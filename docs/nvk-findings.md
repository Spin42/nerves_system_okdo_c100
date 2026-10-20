# NVK on the C100

Mesa 26.1.8 NVK on Linux 6.18.57 nouveau, GM20B (sm_53). The device is
only exposed with `NVK_I_WANT_A_BROKEN_VULKAN_DRIVER=1`, which erlinit
sets for the Erlang VM and everything it starts.

## How it is built

- `patches/buildroot/0001-...` adds `BR2_PACKAGE_MESA3D_VULKAN_DRIVER_NOUVEAU`
  to Buildroot 2026.08 (nothing upstream has it yet), a `host-cbindgen`
  package, offline Rust crates for meson, and the host-mesa3d `cpp_rtti`
  fix. NVK needs no LLVM on the target: its CL shaders are compiled at
  build time by the host `mesa_clc`.
- `patches/mesa3d/` carries two open Mesa MRs: !45355 (tegra: unwrap
  framebuffer surfaces, fixes the kmscube crash) and !45402 (nvk: map
  sync range, only wrong on Tegra).
- vulkan-loader and vulkan-tools (`vulkaninfo`) 1.4.317.

## Status

- `vulkaninfo`: `NVK GM20B`, Vulkan 1.3.354, integrated GPU.
- kmscube (GLES, `tegra` + nouveau gallium) renders on DP at 45–60 fps.
  One `nv50cal_space: -110` (push buffer space timeout) appeared during a
  300-frame run without visible effect.

## Measured with vkpeak (GPU 921.6 MHz, EMC 1600 MHz)

Same vkpeak build as on L4T (nihui/vkpeak b98fe11, ncnn c189d88).
Raw output in `nvk-reference/`.

| | NVK | NVIDIA L4T | NVK / NVIDIA |
|---|---|---|---|
| fp32 scalar | 111 GFLOPS | 226 | 49 % |
| fp32 vec4 | 134 GFLOPS | 226 | 59 % |
| fp16 scalar, vec4 | 0 (not exposed) | 417, 322 | – |
| fp64 | 7.25 GFLOPS | 7.15 | 101 % |
| int32 | 1.83 GIOPS | 77 | 2 % |
| int16 | 0 (not exposed) | 76 | – |
| int8 dot product | 71 GIOPS (emulated) | 0 | – |
| copy device to device | 10.3 GB/s | 1.2 (EMC 204 MHz) | – |

fp64 matches, so clocks and the platform are equal and the gaps are in
the NAK shader compiler for Maxwell. Pinning the GPU at 921.6 MHz gives
the same numbers as `simple_ondemand`.

Upstream work, in order of value for AI workloads:

1. fp32 at half of peak: instruction scheduling (control codes, dual
   issue, register reuse) for sm_50.
2. fp16: `shaderFloat16` is gated at sm ≥ 70 (`nvk_physical_device.c`);
   sm_53 has HADD2/HMUL2/HFMA2, which NAK does not emit for sm_5x.
3. int32 at 2 % of NVIDIA: integer multiply on Maxwell is an XMAD
   sequence; NAK's lowering is about 40× slower than NVIDIA's.
4. `shaderInt16` not exposed.

## Platform issues found

- nouveau builds the GPU's golden context on the first graphics channel.
  With the EMC at 1600 MHz that times out in FECS
  (`gf100_gr_fecs_bind_pointer`, `gr: init failed, -16`) and leaves the
  GPU unusable until reboot; at 204 MHz it works, and 1600 MHz is fine
  afterwards. `c100-limits` therefore opens a first channel (with
  `vulkaninfo`) before raising the EMC. Root cause not known.
- `rmmod nouveau` oopses in `nvkm_mmu_dtor` on this GPU, so nouveau
  cannot be reloaded at runtime.
