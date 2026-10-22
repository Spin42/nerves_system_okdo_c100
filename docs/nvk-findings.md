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
- `patches/mesa3d/` carries two open Mesa MRs, 0001 !45355 (tegra: unwrap
  framebuffer surfaces, fixes the kmscube crash) and 0002 !45402 (nvk: map
  sync range, only wrong on Tegra), and our NAK work for Maxwell:
  - 0003 operand reuse flags on FFMA/FADD/FMUL chains;
  - 0004 plain branches instead of SSY/SYNC and PBK/PCNT for uniform
    control flow;
  - 0005 jump threading on pre-Volta GPUs;
  - 0006 GPR bank-aware register allocation on SM50-SM62;
  - 0007 int→f16 conversion through f32 (GM20B has no `I2F.F16`);
  - 0008 HADD2/HMUL2/HFMA2/HSET2/HSETP2 for SM53, SM60, SM62;
  - 0009 `shaderFloat16` on those GPUs;
  - 0010 pairing of independent scalar f16 ops into packed ops;
  - 0011 unrolling of single-block loops with a constant trip count;
  - 0012 integer multiplies from XMAD (32-bit: three XMADs, 16-bit: one,
    32x32->64: four XMADs and two PRMTs).
- vulkan-loader and vulkan-tools (`vulkaninfo`) 1.4.317.

## Status

- `vulkaninfo`: `NVK GM20B`, Vulkan 1.3.354, integrated GPU.
- kmscube (GLES, `tegra` + nouveau gallium) renders on DP at 45–60 fps.
  One `nv50cal_space: -110` (push buffer space timeout) appeared during a
  300-frame run without visible effect.

## Measured with vkpeak (GPU 921.6 MHz, EMC 1600 MHz)

Same vkpeak build as on L4T (nihui/vkpeak b98fe11, ncnn c189d88).
Raw output in `nvk-reference/`.

| | Mesa 26.1.8 | with 0003-0012 | NVIDIA L4T | patched / NVIDIA |
|---|---|---|---|---|
| fp32 scalar | 111 GFLOPS | 222.7 | 226.4 | 98 % |
| fp32 vec4 | 134 GFLOPS | 221.0 | 225.7 | 98 % |
| fp16 scalar | 0 (not exposed) | 415.7 | 416.6 | 100 % |
| fp16 vec4 | 0 (not exposed) | 439.1 | 321.7 | 136 % |
| fp64 scalar | 7.25 GFLOPS | 7.26 | 7.15 | 102 % |
| int32 scalar | 1.83 GIOPS | 76.1 | 76.6 | 99 % |
| int32 vec4 | 1.83 GIOPS | 76.3 | 75.8 | 101 % |
| int16 scalar | 1.83 GIOPS | 223.4 | 76.1 | 294 % |
| int16 vec4 | 1.83 GIOPS | 227.3 | 75.8 | 300 % |
| int64 scalar | 0.61 GIOPS | 17.2 | 15.7 | 110 % |
| int64 vec4 | 0.49 GIOPS | 14.5 | 14.2 | 102 % |
| int8 dot product | 71 GIOPS (emulated) | 72.2 | 0 | – |
| copy device to device | 10.3 GB/s | 10.3 | 1.2 (EMC 204 MHz) | – |

fp16 vec4 and int16 beat NVIDIA's driver: NAK fills both halves of every
HFMA2, and a 16-bit multiply-add is one XMAD where NVIDIA's rate implies
three instructions.

The Jetson Nano's GM20B has one SM: 128 lanes, 4 schedulers. 226 GFLOPS
is 3.83 warp instructions per clock out of 4. The clock is the same on
both drivers (nouveau's `pstate` reads back 921 MHz under load).

Why stock NAK reached half of peak on fp32:

- Every loop iteration paid for SSY/SYNC, PBK/PCNT/BRK/CONT, two empty
  branch blocks and NOP padding: 31 issue slots per 16 FFMAs (0004, 0005
  bring it to 21).
- The register allocator put the three operands of most FFMAs in the same
  GPR bank, which costs extra issue cycles (0006).
- Occupancy, the yield bit and dispatch overhead were ruled out by
  measurement.

The remaining loop overhead (iadd, isetp, branch, NOP) is spread over up
to eight unrolled iterations by 0011. Stock NAK used `IMUL`/`IMAD`, which
are slow variable-latency ops on Maxwell, for every integer multiply.

## Correctness

- `scripts/dev/gpucheck.cpp` (built against ncnn like vkpeak) runs the
  int32, int16, int64 (unsigned widening, full 64x64, signed widening),
  fp32 and fp16 multiply-add chains for 4096 invocations at loop counts 1
  to 100, which covers every unroll factor, and compares with a CPU
  reference: exact for integers, one ulp for fp32 with denormals flushed
  as NAK does, per-op rounding within one ulp for fp16. Everything passes
  on the patched driver. The only fp32 mismatch (12 values at the
  denormal boundary) is bit-identical on stock Mesa.
- New SM53 encodings are checked with NVIDIA's `nvdisasm -b SM53` (CUDA
  12.6 still disassembles Maxwell). nvdisasm also decodes `I2F.F16`, which
  GM20B rejects, so the hardware has the last word.
- ncnn's layer tests (GPU against CPU) are run on the board with
  `OMP_NUM_THREADS=1`, the GPU capped at 768 MHz and a thermal guard that
  pauses a test above 70 °C until it is back below 55 °C. On the patched
  driver 178 of 179 pass with no GPU traps; the other is the atan2 case
  below. `test_squeezenet` loads its model from `../../examples`, so the
  squeezenet_v1.1 files must be copied there next to the tests.
- `test_binaryop_atan2_special` fails the same way on stock and patched
  NVK: atan2(0, 0) gives 3π/4 where ncnn expects C's 0. GLSL and SPIR-V
  leave atan(y, x) undefined when both are 0, so this is a test
  assumption, not a driver bug.

What is left: int8 dot products are emulated (no DP4A before SM61),
fp16 min/max go through f32 (no HMNMX2 before SM80), and memory bandwidth
is untested beyond vkpeak's copies.

## Platform issues found

- The VDD_GPU PWM regulator's `regulator-min-microvolt` and
  `regulator-max-microvolt` define its duty-cycle calibration. Raising the
  minimum from 710000 to 1000000 does not create a physical 1 V floor:
  it relabels 0% duty as 1 V and changes every voltage request. Retain the
  original 710000..1320000 range. Earlier voltage comparisons made with
  the 1 V override cannot be treated as measurements of rail voltage.
- With that calibration restored, GM20B clock initialization leaves the
  regulator reporting 710000 uV until the first frequency transition. On the
  test board, requesting 307.2 MHz raised the reported voltage to 819800
  uV; returning to 76.8 MHz retained it. The speedo-2 table minimum is
  818750 uV. Patch 0007 requests the initial state's voltage before PLL
  programming. This fixes the missing clock-initialization request.
  ACR/PMU initialization precedes clock initialization, so this does not
  establish the cause of the earlier PMU timeout.
- With native power management restored, a separate intermittent
  `INJECTED_BUNDLE_ERROR` trap was captured during golden-context bundle
  injection with FE_GO_IDLE_TIMEOUT enabled. Patch 0008 defers restoring
  that timeout until injection and a GR idle wait finish, following
  NVIDIA's Tegra sequence. The clean image with 0007/0008 and the fuse
  backports passed thirty warm reboots, three bounded frequency transitions
  and thirty integer-compute cases. Cold power cycles remain untested.
  [Boot evidence and reproduction](nvk-reference/nouveau-boots-20261022/README.md).
- nouveau builds the GPU's golden context on the first graphics channel.
  With the EMC at 1600 MHz that times out in FECS
  (`gf100_gr_fecs_bind_pointer`, `gr: init failed, -16`) and leaves the
  GPU unusable until reboot; at 204 MHz it works, and 1600 MHz is fine
  afterwards. `c100-limits` therefore opens a first channel (with
  `vulkaninfo`) before raising the EMC. Root cause not known.
- `rmmod nouveau` oopses in `nvkm_mmu_dtor` on this GPU, so nouveau
  cannot be reloaded at runtime.

## Power

- Micro-USB (5 V 2 A) is not enough for sustained GPU load: soctherm OC1
  alarms and throttling, and 4.81 V at idle after a long run.
- On the barrel jack (jumper fitted), a 5.0 V supply gave 4.48 V at 0.7 A
  and continuous OC1 alarms, with the USB 3 controller reloading its
  firmware every 2 s. At 5.2 V the input reads 4.96 V and the alarms
  only come in short bursts at large load steps (GPU 76.8 to 921.6 MHz),
  never during sustained load.
- L4T leaves the INA3221 alert limits at their maximum, so OC1 does not
  come from the INA3221. L4T configures OC1 exactly like our DTS and does
  not log OC events.
