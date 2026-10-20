// Check NVK compute results against a CPU reference for the integer and
// float multiply-add chains that vkpeak times.

#include <cmath>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <string>
#include <vector>

#include "command.h"
#include "gpu.h"
#include "mat.h"
#include "pipeline.h"

static const int N = 4096;
static const int LOCAL = 32;

struct Case
{
    const char* name;
    std::string glsl;
    // reference for invocation gx with local id lx and the loop count
    uint32_t (*ref)(uint32_t gx, uint32_t lx, int loop);
    int tol; // 0 exact, 1 within one f32 ulp, 2 within one f16 ulp
};

#define BODY_HEAD "#version 450\n#extension GL_EXT_shader_explicit_arithmetic_types_int16: require\n#extension GL_EXT_shader_explicit_arithmetic_types_float16: require\n#extension GL_EXT_shader_explicit_arithmetic_types_int64: require\nlayout (constant_id = 0) const int loop = 1;\nlayout (local_size_x = 32) in;\nlayout (binding = 0) writeonly buffer c_blob { uint c_blob_data[]; };\nvoid main() {\nconst uint gx = gl_GlobalInvocationID.x;\nconst uint lx = gl_LocalInvocationID.x;\n"

static uint32_t ref_i32(uint32_t gx, uint32_t lx, int loop)
{
    uint32_t c = gx, a = gx, b = lx;
    for (int i = 0; i < loop * 16; i++) c = a * c + b;
    return c;
}
static uint32_t ref_i32_dual(uint32_t gx, uint32_t lx, int loop)
{
    uint32_t c0 = gx, c1 = lx, a = gx, b = lx;
    for (int i = 0; i < loop * 8; i++) { c0 = a * c0 + b; c1 = a * c1 + b; }
    return c0 + c1;
}
static uint32_t ref_i32_vec4(uint32_t gx, uint32_t lx, int loop)
{
    uint32_t c[4], a[4], b[4];
    const int32_t ao[4] = {0, 1, 2, -3}, bo[4] = {2, 3, 5, -7};
    for (int k = 0; k < 4; k++) { c[k] = gx; a[k] = gx + ao[k]; b[k] = lx + bo[k]; }
    for (int i = 0; i < loop * 16; i++)
        for (int k = 0; k < 4; k++) c[k] = a[k] * c[k] + b[k];
    return (c[0] + c[1]) + (c[2] + c[3]);
}
static uint32_t ref_i16(uint32_t gx, uint32_t lx, int loop)
{
    uint16_t c = (uint16_t)gx, a = (uint16_t)gx, b = (uint16_t)lx;
    for (int i = 0; i < loop * 16; i++) c = (uint16_t)(a * c + b);
    return (uint32_t)(int32_t)(int16_t)c;
}
static uint32_t ref_i16_dual(uint32_t gx, uint32_t lx, int loop)
{
    uint16_t c0 = (uint16_t)gx, c1 = (uint16_t)lx, a = (uint16_t)gx, b = (uint16_t)lx;
    for (int i = 0; i < loop * 8; i++) { c0 = (uint16_t)(a * c0 + b); c1 = (uint16_t)(a * c1 + b); }
    return (uint32_t)(int32_t)(int16_t)(uint16_t)(c0 + c1);
}
static uint32_t ref_i16_vec4(uint32_t gx, uint32_t lx, int loop)
{
    uint16_t c[4], a[4], b[4];
    const int32_t ao[4] = {0, 1, 2, -3}, bo[4] = {2, 3, 5, -7};
    for (int k = 0; k < 4; k++) { c[k] = (uint16_t)gx; a[k] = (uint16_t)(gx + ao[k]); b[k] = (uint16_t)(lx + bo[k]); }
    for (int i = 0; i < loop * 16; i++)
        for (int k = 0; k < 4; k++) c[k] = (uint16_t)(a[k] * c[k] + b[k]);
    uint16_t s = (uint16_t)((uint16_t)(c[0] + c[1]) + (uint16_t)(c[2] + c[3]));
    return (uint32_t)(int32_t)(int16_t)s;
}
// NAK runs f32 with denormals flushed to zero
static float ftz(float x) { return fabsf(x) < 1.17549435e-38f ? copysignf(0.0f, x) : x; }
static uint32_t mix64(uint64_t c) { return (uint32_t)c ^ (uint32_t)(c >> 32); }
static uint32_t ref_i64(uint32_t gx, uint32_t lx, int loop)
{
    uint64_t c = gx, a = gx, b = lx;
    for (int i = 0; i < loop * 16; i++) c = a * c + b;
    return mix64(c);
}
static uint32_t ref_i64_full(uint32_t gx, uint32_t lx, int loop)
{
    uint64_t a = (uint64_t)gx * 0x9E3779B97F4A7C15ull + 0x123456789ull, c = (uint64_t)lx * 0xD1B54A32D192ED03ull, b = a ^ 0x5555ull;
    for (int i = 0; i < loop * 16; i++) c = a * c + b;
    return mix64(c);
}
static uint32_t ref_i64_swide(uint32_t gx, uint32_t lx, int loop)
{
    int32_t x = (int32_t)gx - 2048, y = (int32_t)lx * -77777 + (int32_t)gx;
    int64_t acc = 0;
    for (int i = 0; i < loop; i++) { acc += (int64_t)x * (int64_t)y; y = y * 3 + 1; }
    return mix64((uint64_t)acc);
}
static float f32_a(uint32_t gx) { return 0.5f + (gx % 5) * 0.0625f; }
static float f32_b(uint32_t lx) { return (lx % 7) * 0.125f; }
static uint32_t ref_f32(uint32_t gx, uint32_t lx, int loop)
{
    float c = (float)(gx % 13), a = f32_a(gx), b = f32_b(lx);
    for (int i = 0; i < loop * 16; i++) c = ftz(fmaf(a, c, b));
    uint32_t u;
    memcpy(&u, &c, 4);
    return u;
}
static uint32_t ref_f32_dual(uint32_t gx, uint32_t lx, int loop)
{
    float c0 = (float)(gx % 13), c1 = (float)(lx % 11), a = f32_a(gx), b = f32_b(lx);
    for (int i = 0; i < loop * 8; i++) { c0 = ftz(fmaf(a, c0, b)); c1 = ftz(fmaf(a, c1, b)); }
    float c = ftz(c0 + c1);
    uint32_t u;
    memcpy(&u, &c, 4);
    return u;
}
static uint32_t ref_f16(uint32_t gx, uint32_t lx, int loop)
{
    _Float16 c = (_Float16)(gx % 13), a = (_Float16)f32_a(gx), b = (_Float16)f32_b(lx);
    for (int i = 0; i < loop * 16; i++) c = (_Float16)fmaf((float)a, (float)c, (float)b);
    float f = (float)c;
    uint32_t u;
    memcpy(&u, &f, 4);
    return u;
}
static uint32_t ref_f16_dual(uint32_t gx, uint32_t lx, int loop)
{
    _Float16 c0 = (_Float16)(gx % 13), c1 = (_Float16)(lx % 11), a = (_Float16)f32_a(gx), b = (_Float16)f32_b(lx);
    for (int i = 0; i < loop * 8; i++)
    {
        c0 = (_Float16)fmaf((float)a, (float)c0, (float)b);
        c1 = (_Float16)fmaf((float)a, (float)c1, (float)b);
    }
    float f = (float)(_Float16)((float)c0 + (float)c1);
    uint32_t u;
    memcpy(&u, &f, 4);
    return u;
}

static std::string rep(const char* s, int n)
{
    std::string r;
    for (int i = 0; i < n; i++) r += s;
    return r;
}

int main(int argc, char** argv)
{
    // gpucheck [case-name-prefix]
    const char* only = argc > 1 ? argv[1] : "";
    ncnn::create_gpu_instance();
    ncnn::VulkanDevice* vkdev = ncnn::get_gpu_device(0);
    if (!vkdev)
    {
        fprintf(stderr, "no vulkan device\n");
        return 2;
    }

    const std::string f32ab = "float a = 0.5 + float(gx % 5u) * 0.0625; float b = float(lx % 7u) * 0.125;\n";
    const std::string f16ab = "float16_t a = float16_t(0.5 + float(gx % 5u) * 0.0625); float16_t b = float16_t(float(lx % 7u) * 0.125);\n";
    std::vector<Case> cases = {
        {"int32", BODY_HEAD "int c = int(gx); int a = c; int b = int(lx);\nfor (int i = 0; i < loop; i++) {" + rep("c = a * c + b;", 16) + "}\nc_blob_data[gx] = uint(c); }\n", ref_i32, 0},
        {"int32-dual", BODY_HEAD "int c0 = int(gx); int c1 = int(lx); int a = c0; int b = c1;\nfor (int i = 0; i < loop; i++) {" + rep("c0 = a * c0 + b; c1 = a * c1 + b;", 8) + "}\nc_blob_data[gx] = uint(c0 + c1); }\n", ref_i32_dual, 0},
        {"int32-vec4", BODY_HEAD "ivec4 c = ivec4(gx); ivec4 a = c + ivec4(0,1,2,-3); ivec4 b = ivec4(lx) + ivec4(2,3,5,-7);\nfor (int i = 0; i < loop; i++) {" + rep("c = a * c + b;", 16) + "}\nc_blob_data[gx] = uint((c[0] + c[1]) + (c[2] + c[3])); }\n", ref_i32_vec4, 0},
        {"int16", BODY_HEAD "int16_t c = int16_t(gx); int16_t a = c; int16_t b = int16_t(lx);\nfor (int i = 0; i < loop; i++) {" + rep("c = a * c + b;", 16) + "}\nc_blob_data[gx] = uint(int(c)); }\n", ref_i16, 0},
        {"int16-dual", BODY_HEAD "int16_t c0 = int16_t(gx); int16_t c1 = int16_t(lx); int16_t a = c0; int16_t b = c1;\nfor (int i = 0; i < loop; i++) {" + rep("c0 = a * c0 + b; c1 = a * c1 + b;", 8) + "}\nc_blob_data[gx] = uint(int(int16_t(c0 + c1))); }\n", ref_i16_dual, 0},
        {"int16-vec4", BODY_HEAD "i16vec4 c = i16vec4(gx); i16vec4 a = c + i16vec4(0,1,2,-3); i16vec4 b = i16vec4(lx) + i16vec4(2,3,5,-7);\nfor (int i = 0; i < loop; i++) {" + rep("c = a * c + b;", 16) + "}\nc_blob_data[gx] = uint(int(int16_t((c[0] + c[1]) + (c[2] + c[3])))); }\n", ref_i16_vec4, 0},
        {"int64", BODY_HEAD "int64_t c = int64_t(gx); int64_t a = c; int64_t b = int64_t(lx);\nfor (int i = 0; i < loop; i++) {" + rep("c = a * c + b;", 16) + "}\nc_blob_data[gx] = uint(c) ^ uint(c >> 32); }\n", ref_i64, 0},
        {"int64-full", BODY_HEAD "uint64_t a = uint64_t(gx) * 0x9E3779B97F4A7C15ul + 0x123456789ul; uint64_t c = uint64_t(lx) * 0xD1B54A32D192ED03ul; uint64_t b = a ^ 0x5555ul;\nfor (int i = 0; i < loop; i++) {" + rep("c = a * c + b;", 16) + "}\nc_blob_data[gx] = uint(c) ^ uint(c >> 32); }\n", ref_i64_full, 0},
        {"int64-swide", BODY_HEAD "int x = int(gx) - 2048; int y = int(lx) * -77777 + int(gx); int64_t acc = 0;\nfor (int i = 0; i < loop; i++) { acc += int64_t(x) * int64_t(y); y = y * 3 + 1; }\nc_blob_data[gx] = uint(acc) ^ uint(acc >> 32); }\n", ref_i64_swide, 0},
        {"fp32", BODY_HEAD "float c = float(gx % 13u); " + f32ab + "for (int i = 0; i < loop; i++) {" + rep("c = fma(a, c, b);", 16) + "}\nc_blob_data[gx] = floatBitsToUint(c); }\n", ref_f32, 1},
        {"fp32-dual", BODY_HEAD "float c0 = float(gx % 13u); float c1 = float(lx % 11u); " + f32ab + "for (int i = 0; i < loop; i++) {" + rep("c0 = fma(a, c0, b); c1 = fma(a, c1, b);", 8) + "}\nc_blob_data[gx] = floatBitsToUint(c0 + c1); }\n", ref_f32_dual, 1},
        {"fp16", BODY_HEAD "float16_t c = float16_t(gx % 13u); " + f16ab + "for (int i = 0; i < loop; i++) {" + rep("c = fma(a, c, b);", 16) + "}\nc_blob_data[gx] = floatBitsToUint(float(c)); }\n", ref_f16, 2},
        {"fp16-dual", BODY_HEAD "float16_t c0 = float16_t(gx % 13u); float16_t c1 = float16_t(lx % 11u); " + f16ab + "for (int i = 0; i < loop; i++) {" + rep("c0 = fma(a, c0, b); c1 = fma(a, c1, b);", 8) + "}\nc_blob_data[gx] = floatBitsToUint(float(c0 + c1)); }\n", ref_f16_dual, 2},
    };
    const int loops[] = {1, 2, 3, 5, 8, 16, 24, 37, 64, 100};

    ncnn::VkAllocator* blob = vkdev->acquire_blob_allocator();
    ncnn::VkAllocator* staging = vkdev->acquire_staging_allocator();
    ncnn::Option opt;
    opt.use_vulkan_compute = true;
    opt.blob_vkallocator = blob;
    opt.workspace_vkallocator = blob;
    opt.staging_vkallocator = staging;

    int failures = 0;
    for (const Case& cs : cases)
    {
        if (strncmp(cs.name, only, strlen(only)) != 0)
            continue;
        std::vector<uint32_t> spirv;
        if (ncnn::compile_spirv_module(cs.glsl.c_str(), (int)cs.glsl.size(), opt, spirv) != 0)
        {
            printf("%-11s compile failed\n", cs.name);
            failures++;
            continue;
        }
        for (int loop : loops)
        {
            std::vector<ncnn::vk_specialization_type> spec(1);
            spec[0].i = loop;
            ncnn::Pipeline pipeline(vkdev);
            pipeline.set_local_size_xyz(LOCAL, 1, 1);
            if (pipeline.create(spirv.data(), spirv.size() * 4, spec) != 0)
            {
                printf("%-11s loop=%-3d pipeline failed\n", cs.name, loop);
                failures++;
                continue;
            }

            ncnn::VkMat c(N, (size_t)4u, 1, blob);
            ncnn::Mat out;
            ncnn::VkCompute cmd(vkdev);
            std::vector<ncnn::VkMat> bindings(1, c);
            std::vector<ncnn::vk_constant_type> constants;
            ncnn::VkMat dispatcher;
            dispatcher.w = N;
            dispatcher.h = 1;
            dispatcher.c = 1;
            cmd.record_pipeline(&pipeline, bindings, constants, dispatcher);
            cmd.record_download(c, out, opt);
            if (cmd.submit_and_wait() != 0)
            {
                printf("%-11s loop=%-3d submit failed\n", cs.name, loop);
                failures++;
                continue;
            }

            const uint32_t* got = (const uint32_t*)out.data;
            int bad = 0, first = -1;
            for (int gx = 0; gx < N; gx++)
            {
                uint32_t want = cs.ref(gx, gx % LOCAL, loop);
                bool ok = got[gx] == want;
                if (!ok && cs.tol == 1)
                    ok = (got[gx] > want ? got[gx] - want : want - got[gx]) <= 1;
                if (!ok && cs.tol == 2)
                {
                    float g, w;
                    memcpy(&g, &got[gx], 4);
                    memcpy(&w, &want, 4);
                    ok = fabsf(g - w) <= fmaxf(fabsf(w), 1.0f) * (1.0f / 1024);
                }
                if (!ok)
                {
                    if (first < 0) first = gx;
                    bad++;
                }
            }
            if (bad)
            {
                printf("%-11s loop=%-3d FAIL %d/%d first gx=%d got 0x%08x want 0x%08x\n", cs.name, loop, bad, N, first,
                       got[first], cs.ref(first, first % LOCAL, loop));
                failures++;
            }
            else
            {
                printf("%-11s loop=%-3d ok\n", cs.name, loop);
            }
        }
    }

    vkdev->reclaim_blob_allocator(blob);
    vkdev->reclaim_staging_allocator(staging);
    ncnn::destroy_gpu_instance();
    printf("%s: %d failing case(s)\n", failures ? "FAILED" : "PASSED", failures);
    return failures ? 1 : 0;
}
