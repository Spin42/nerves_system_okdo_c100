# GPU compute on the C100: inventory and investigation plan

## Current direction, 2026-10-22

The active stack is `~/Projects/nx_iree`: Nx/Elixir, host AOT compilation
through IREE, and a runtime-only Vulkan deployment on the C100. It already
supports cross compilation and has run matmul and DistilBERT on this board;
the older inventory below predates that work.

The target is full-performance stereo SGBM without CUDA. Vulkan runtime
and compiler work must remain generic and is also tested on the host AMD
discrete GPU. Device-specific performance tuning is separate. Exact image
size, disparity range, FPS and OpenCV compatibility remain to be defined.

Device-specific code must live in a dedicated Buildroot package or Elixir
library. `~/Projects/c100_gpu` now owns the C100/Maxwell tuning, target
capability list and board harness. Shared allocator/compiler changes remain
in IREE/nx_iree.
The system's `package/c100-gpu` installs `/usr/sbin/c100-limits`; erlinit
invokes it from the board configuration. Moving the script out of the
overlay does not change its accepted clock policy or initialization sequence.

Normal devfreq (76.8–921.6 MHz) is restored; accepted firmware passed 30/30
warm reboots. See `nvk-reference/nouveau-boots-20261022/README.md`.
The initial directional SGM recurrence exposed an IREE TLSF slab-reuse
bug on both GPUs. A shared allocator fix now passes repeated exact-output
tests on the host and C100. Results, patch and reproduction are in
`~/Projects/nx_iree/docs/stereo-path.md`; the matcher itself is now
`~/Projects/nx_stereo`.
An additional generic compiler repair removes per-step full-volume copies.
It passes on both GPUs; the host source compiler build is selected explicitly
with `NX_IREE_COMPILER_DIR`. C100 normal-devfreq latency remains variable.
An explicit comparison at the existing 921.6 MHz cap showed a speed gain,
then restored the normal minimum; it is not the default power policy.

The running Mesa 26.1.8 NVK driver reports `shaderFloat16`, `shaderInt8`,
`shaderInt16`, `shaderInt64`, and 8/16-bit storage support. This supersedes
the older FP16 inventory below; advertised support does not establish
half-precision throughput. The captured `vulkaninfo` evidence is in
`~/Projects/nx_iree/docs/reference/stereo-path-20261022/c100-gpu-features.log`.

The remaining sections are the earlier inventory and investigation plan.

Goal: use the Jetson Nano's GM20B GPU for real AI work from Elixir/Nx, as
close as possible to what CUDA offers, on mainline Linux + Mesa.

## What the hardware can do

| | CUDA / NVIDIA driver (L4T) | NVK (Mesa 26.1) today |
|---|---|---|
| Peak fp32 | ~235 GFLOPS (128 cores × 2 × 921.6 MHz) | same hardware, GPU clock up to 998.4 MHz via devfreq |
| Peak fp16 | ~470 GFLOPS (sm_53 has native half2) | not exposed: NVK sets `shaderFloat16` only for sm ≥ 70 |
| 16-bit storage | yes | yes (`storageBuffer16BitAccess`) |
| Tensor cores, int8 dot | no | no (`KHR_shader_integer_dot_product` advertised, not accelerated) |
| Vulkan | 1.2 (to be confirmed on the board) | 1.3 on Maxwell-B, non-conformant, needs `NVK_I_WANT_A_BROKEN_VULKAN_DRIVER=1` |
| Memory | 4 GB LPDDR4 shared with the CPU, 25.6 GB/s | same |

The single highest-value upstream item is fp16 arithmetic for sm_53 in
Mesa's NAK compiler: it doubles the compute ceiling and is what makes
CUDA's 470 GFLOPS figure.

## Platform status (verified 2026-10-20)

- GPU devfreq works (backported from 6.19): 76.8 to 998.4 MHz,
  `simple_ondemand`.
- The nouveau fix NVK needs on Tegra ("Use write-combined maps for
  coherent", 774b73428e6e) is already in 6.18.57.
- Kernel cache-flush ioctl for VM_BIND (nouveau #453) is only needed for
  32-bit userspace; not needed here.
- GL: kmscube crash in `nvc0_validate_fb` is Mesa !45355 ("tegra: unwrap
  framebuffer and clear surfaces"), open, posted for Jetson Nano.
- Tegra fixes worth carrying on Mesa 26.1: !45355, !45402 (map sync range).
  Stay on 26.1: 26.2 has a Tegra tiling regression (#15943).
- EMC (memory) DVFS: needs the Tegra210 EMC interconnect series (v7, not
  merged) plus the EMC tables from cboot.

## Reusable software

In ~/Projects:

- `nx_opencl`: Nx backend + defn compiler on OpenCL, proven on rusticl
  (FP3). Its kernels could run on rusticl (nouveau or zink) or clvk.
- `nx_eigen` (Hex): CPU fallback.
- `nerves_ai`: llama.cpp / whisper.cpp / Evision adapters. The ggml
  cross-build scripts in `spikes/llm_stt/` are the starting point for a
  `GGML_VULKAN` build.
- FP3 system git history (9aebfbe, e899db0): Buildroot plumbing to enable
  rusticl for a driver Buildroot does not allowlist; rusticl costs about
  177 MB (LLVM, clang, libclc).
- `cblast_binaries`: CLBlast, an OpenCL GEMM source.

Upstream, ranked for "Nx on this GPU, closest to CUDA":

1. `nx_vulkan` (borodark, Hex 0.3.0): `Nx.Backend` in Rust/vulkano with a
   fusion compiler; tested on a Jetson Nano with the L4T Vulkan driver.
2. Tuned engines through NIFs: ggml-vulkan (llama.cpp, whisper.cpp; needs
   Vulkan 1.2 + 16-bit storage, fp16 compute optional) and ncnn (Vulkan
   1.0; ~4x CPU on the Nano with the NVIDIA driver).
3. `nx_iree` (elixir-nx): whole-graph AOT like XLA, compile on the host,
   small runtime on the device. Dormant since 2024, no aarch64 Linux build,
   IREE needs Vulkan 1.3 (NVK only).
4. Ortex with ONNX Runtime's WebGPU EP: needs Ortex work.
5. OpenCL on Vulkan (rusticl on zink, clvk): only useful for nx_opencl or
   CLBlast.

## Intel to gather on the original OS (L4T on the eMMC)

The NVIDIA driver is the reference: what it exposes is the target for NVK,
and its numbers are the baseline. Boot it by removing the microSD card.

1. Software versions: `/etc/nv_tegra_release`, `uname -a`, installed
   CUDA/cuDNN/TensorRT/Vulkan packages, the Vulkan ICD JSON.
2. `vulkaninfo` (full JSON): API version, features (fp16, 16-bit storage,
   subgroups, int8), limits (shared memory, workgroup sizes), memory heaps
   and types.
3. CUDA `deviceQuery`, `bandwidthTest`: SM clocks, shared memory, measured
   memory bandwidth.
4. Peak throughput with the NVIDIA driver: vkpeak (Vulkan fp32/fp16/int)
   and a CUDA fp16 GEMM, as the ceilings NVK should reach.
5. Clocks and power: GPU frequency table and max, EMC rate actually used
   (`/sys/kernel/debug/clk/emc/clk_rate`), nvpmodel modes, INA3221 rail
   power under GPU load (the `soctherm: OC ALARM` question).
6. Live device tree (`dtc -I fs /proc/device-tree`): EMC tables written by
   cboot, HDMI/DP (does the C100 have DP?), GPIO hogs, regulators, fan,
   anything mainline lacks.
7. Runtime state: GPIO (`/sys/kernel/debug/gpio`), pinmux, regulator
   summary, `/proc/iomem` carveouts (VPR), nvgpu sysfs knobs (railgate,
   ELPG, clock gating), loaded GPU firmware versions vs linux-firmware.
8. If Elixir can be installed: the `nx_vulkan` test suite and benchmarks on
   the NVIDIA driver, as the baseline for the same suite on NVK.
