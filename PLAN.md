# nerves_system_okdo_c100 — plan

Target: OKdo Nano C100 = Jetson Nano **production module p3448-0002**
(T210, 4x A57, GM20B Maxwell GPU sm_53, 4 GB LPDDR4 shared, 16 GB eMMC),
on a carrier with the microSD slot wired to **SDMMC3**, no QSPI flash, and
possibly the **PCN211181** Micron DRAM.

Constraints:
- Fresh Nerves system following current conventions (layout of
  `nerves_system_fp3` / `nerves_system_rpi5`: current `nerves_system_br`,
  aarch64 toolchain 15.x, fwup A/B). No fork of `nerves_system_jetson_nano`
  (L4T 4.9, nerves_system_br 1.14, abandoned 2021).
- CPU Nx backend: `nx_eigen`. GPU Nx backend: `nx_opencl` (+ possibly a
  Vulkan backend later).

---

## 0. Bring-up status (2026-10-20, on hardware)

Working on the C100 from a microSD card (`mix burn`), booted by OKdo's
L4T U-Boot chain-loading our mainline U-Boot (`boot.scr`):

- Linux 6.18.57, IEx on UART `ttyS0`, Nerves A/B: first `mix upload`
  switched to slot B and validated.
- eth0 (RTL8111F) with the module's MAC from the EEPROM (U-Boot patch
  0003), usb0 gadget Ethernet, USB 3 host, PMIC watchdog for nerves_heart.
- Hostname `nerves-<last 4 of module serial>` from the module EEPROM.
- HDMI: console framebuffer, hotplug and EDID. Needed the GPIOs L4T drives
  high (PMIC GPIO1 open-drain high, SoC X3 and CC7) in the board DTS.
- GPU: nouveau binds GM20B; EGL/GLES 3.2 (Mesa 26.1.8, renderer `tegra`),
  kmscube renders on HDMI and DP; Vulkan 1.3 through NVK (see
  `docs/nvk-findings.md`).
- DRAM at 1600 MHz from cboot's trained EMC tables; CPU and GPU capped at
  the module's validated maxima (`/usr/sbin/c100-limits`).

Open:

- GPU golden-context init times out with the EMC at 1600 MHz;
  `c100-limits` initialises the GPU at 204 MHz first. Root cause open.
- NAK codegen for sm_53: fp32 at half of NVIDIA's, no fp16, slow int32.
- U-Boot changes only ship with a fresh install (decided); the test card
  got the MAC-patched u-boot.bin by hand.
- An unverified write of U-Boot into LNX under LineageOS's cboot
  soft-bricked the board (Android cboot rejects the image and fails over
  to an incomplete BFS1). Recovered with RCM + c100-bootupd `make flash`.

## 1. Key decision: mainline kernel + Mesa, not L4T + CUDA

| | Mainline 6.18+/7.x + nouveau + Mesa | L4T R32.7.6 (4.9) + nvgpu + CUDA 10.2 |
|---|---|---|
| Kernel | Upstream, maintained, Nerves-friendly | Frozen 4.9, EOL, needs 4.9-headers toolchain (Kobo precedent) |
| GPU API | GLES 3.2 (works), Vulkan via NVK (Tegra WIP), OpenCL via rusticl | CUDA 10.2, cuDNN 8.2, TensorRT 8.2 (ONNX opset ≤ 13), Vulkan 1.2 |
| Reclocking | devfreq for gm20b since ~6.18 | Full DVFS |
| Ready-made NN kernels | None (bring your own: nx_opencl, ncnn, ggml-vulkan) | TensorRT |
| Nx story | `nx_opencl` on rusticl, same path as FP3/Adreno | Model-level serving only (TensorRT NIF) |
| Future | Improves with every Mesa release | Dead end |

**Decision: build on mainline.** L4T is kept only as an optional variant
(section 6), and porting nvgpu to mainline is rejected (section 7).

### Why the driver source does not give us OpenCL/Vulkan
nvgpu/nvmap/nvhost are kernel drivers: memory, channels, firmware, clocks.
OpenCL/Vulkan need a **userspace driver**: a Maxwell ISA compiler plus a
command-stream builder. NVIDIA's (libcuda, ptxas, libnvidia-glcore) is closed.
Writing one on top of nvgpu would mean reinventing Mesa.

Mesa has already done this:
- **NAK** (the Rust shader compiler) has supported Maxwell since Mesa 25.1.
- **NVK** runs on the mainline **nouveau** kernel driver, which already
  drives GM20B (firmware `nvidia/gm20b` in linux-firmware, reclocking via
  devfreq).

So "CUDA-irrelevant GPU compute" = mainline nouveau + Mesa NVK/rusticl. The
work left is closing the **Tegra gaps in NVK**, which is upstream-able and
already in progress:
- mesa#14105 "nvk: Tegra support" (MRs !33959 and !38163 merged; "almost
  passing CTS" with a kernel hack)
- nouveau#452 coherent maps SIGBUS on Tegra
- nouveau#453 cache-flush ioctl for VM_BIND
- mesa#15943 tiling regression on Tegra in 26.2

Existence proof: `mesa-switch` / `nxvk` run NVK + Zink on the same GM20B
(Nintendo Switch, Horizon OS).

Realistic performance ceiling (on paper):
- GPU: 128 cores × 2 × ~0.92 GHz ≈ **235 GFLOPS fp32** (~470 fp16).
- CPU: 4× A57 NEON ≈ 45 GFLOPS.
- Both share 25.6 GB/s LPDDR4. Convolutional vision models gain the most.
  LLM decode is bandwidth-bound and gains little.

---

## 2. Boot chain and storage layout

The early boot chain (BCT incl. PCN211181 DRAM config, nvtboot, TOS, cboot)
stays NVIDIA's and is never rewritten. It is already on every C100 (factory
image or `c100-bootupd`). The kernel never sees DRAM training; DRAM changes
only affect the BCT plus the EMC DVFS tables.

Nerves installs on the **microSD card by default** (`mix burn`) and on the
**eMMC as an explicit task** (`mix burn --task emmc`). No NVIDIA tools are
used for either:
- cboot loads U-Boot from the eMMC `LNX` partition as an **unsigned** Android
  v0 boot image (verified: `scripts/mkbootimg-lnx.py` reproduces the image
  L4T's flasher wrote, byte for byte).
- microSD: the board's existing U-Boot (OKdo's) runs `boot.scr` from the
  card's FAT boot partition, which chain-loads this system's mainline U-Boot
  with `booti` (Tegra arm64 U-Boot has a Linux image header and is PIE).
- eMMC: stop U-Boot, `ums 0 mmc 0`, `check-emmc-layout.sh`, then
  `mix burn --task emmc`, which also writes mainline U-Boot into `LNX` and
  `LNX-1`.
- Mainline U-Boot picks its environment from the microSD card if the card
  holds a valid Nerves environment, else from the eMMC (board patch
  overriding `mmc_get_env_dev()`). fwup sets `devnum` per medium and the
  kernel gets `root=/dev/mmcblk${devnum}p${part}`.

Both media share one layout: env at 2 MiB, p1 boot FAT, p2/p3 rootfs A/B
(squashfs, 1 GiB each), p4 app (f2fs). Userspace uses `/dev/rootdisk0`, so
the same rootfs works from either. On the eMMC Nerves owns NVIDIA's old `APP`
region and the GPT reproduces NVIDIA's partitions after it at their L4T
offsets (without L4T's recovery entries and UDA, to stay within fwup's
16-entry GPT limit); `scripts/check-emmc-layout.sh` refuses boards with a
different layout.

C100 deltas to port (from `~/Projects/c100-bootupd`):

| c100-bootupd | Nerves/mainline equivalent |
|---|---|
| `0001-Enable-sdmmc3.patch` (U-Boot dts + pinmux) | Rebase onto mainline U-Boot `tegra210-p3450-0000.dts` / `board/nvidia/p3450-0000` |
| `0002` preboot script from both mmc | Drop. Nerves U-Boot env runs `sysboot` on extlinux-a/b.conf inside the squashfs |
| `0003`–`0005` pxe_utils overlay hacks | Drop. Use a real board DTS instead of overlays |
| `tegra210-p3448-common-sdmmc3.dts` overlay | New kernel DTS `tegra210-p3448-0002-okdo-c100.dts` (includes p3450 dtsi): enable `mmc@700b0400` (SD, 3.3V-only/high-speed to avoid UHS warm-reset), enable `mmc@700b0600` (eMMC, 8-bit), disable `mmc@700b0000` |
| `tegra210-porg-p3448-emc-a00.dts` (EMC tables) | Mainline Tegra210 EMC driver takes tables from bootloader reserved-memory (2025 work by A. Kling / T. Reding). **Risk item**: verify; without them EMC stays at boot clock |
| `nv_boot_control.conf` (eMMC instead of SPI) | Not needed: Nerves does not do NVIDIA bootloader OTA |

---

## 3. Phases

### Phase 0 — bench baseline (1–2 days)
- Serial console on the 40-pin/UART header; recovery-mode USB.
- Flash factory state with `c100-bootupd` (`make flash`, `make flash-data`);
  boot OKdo's SD image. Record: DRAM vendor (PCN211181 or not), U-Boot
  version, `/proc/device-tree` of the stock boot, eMMC GPT layout
  (`sgdisk -p`), which partition nvtboot loads U-Boot from.

### Phase 1 — minimal Nerves system, mainline (1–2 weeks)
Repo layout modeled on the official `nerves_system_rpi4`/`rpi5` (conventions)
and `nerves_system_mangopi_mq_pro` (U-Boot A/B pattern):
`mix.exs`, `nerves_defconfig`, `linux-6.18.defconfig` (or 7.x),
`uboot/` (defconfig fragment + patches), `fwup.conf`, `fwup-ops.conf`,
`fwup_include/`, `post-build.sh`, `post-createfs.sh`, `rootfs_overlay/`,
`Config.in`, `external.mk`, `package/` (local BR packages), `linux/` (DTS +
patches), `README.md`, `CHANGELOG.md`, `VERSION`.

- `nerves_system_br` latest (1.35.x), `nerves_toolchain_aarch64_nerves_linux_gnu` 15.x.
- Kernel: 6.18 LTS plus the two 6.19 commits that add Tegra GPU devfreq
  (gp10b reclocking, then devfreq). Enable
  `ARCH_TEGRA_210_SOC`, `TEGRA_EMC`, `DRM_TEGRA`, `DRM_NOUVEAU`,
  `NOUVEAU_PLATFORM_DRIVER`, PCIe + `R8169`, XUSB + firmware, `TEGRA_SOCTHERM`,
  `PWM_FAN`, cpufreq. Firmware: `nvidia/tegra210/xusb.bin`, `nvidia/gm20b/*`.
- Board DTS `tegra210-p3448-0002-okdo-c100.dts`, carried as a patch in
  `linux/` (upstream later).
- U-Boot: mainline 2026.07 + SDMMC3 patch, env on eMMC with Nerves A/B logic.
- Done when: IEx over UART + ethernet, `nerves_firmware_ssh`/`mix upload` OTA,
  A/B revert works, `cat /sys/class/devfreq/*/cur_freq` shows EMC/GPU.

### Phase 2 — GPU on Mesa (2–4 weeks, partly upstream work)
- Local BR package override for **Mesa ≥ 26.x** with `nouveau` gallium,
  `nouveau` Vulkan (NVK, needs Rust + NAK), `zink`, `rusticl`
  (+ LLVM/SPIRV-LLVM-Translator/libclc for host + target). Carry Tegra
  patches from open MRs in `package/mesa3d/` until they land.
- Kernel: carry nouveau#452/#453 fixes as patches if still unmerged.
- Validation ladder: `kmscube` / GLES → `vulkaninfo` → dEQP-VK
  `dEQP-VK.compute.*` subset → `clinfo` with `RUSTICL_ENABLE=nouveau` and
  with `zink` → Nx test suite.
- Reclocking check: devfreq governor `performance`, sustained matmul,
  thermals (fan via `pwm-fan`).
- **Go/no-go** for the GPU track: dEQP-VK compute ≥ 95% pass and a stable
  30-minute matmul soak. If NVK is not there yet, fall back to GLES 3.1
  compute shaders for a handful of hot kernels (conv2d, matmul) while
  contributing to the NVK Tegra issues.

### Phase 3 — Nx and Evision on the GPU (3–6 weeks)
- **`nx_opencl` on rusticl** (preferred, zero new backend). Same code path as
  FP3/Adreno, so the work there pays off twice. Watch rusticl-on-nouveau vs
  rusticl-on-zink-on-NVK; benchmark both.
- `nx_eigen` as CPU fallback for ops `NxCL.Backend` does not cover.
- Optional `nx_vulkan`: reuse nx_opencl's OpenCL C kernels compiled to Vulkan
  SPIR-V with **clspv**, run via a small Rust NIF (`ash`). This beats
  rusticl only if rusticl on nouveau proves flaky.
- **Evision**: build OpenCV with OpenCL on (T-API/`UMat` → rusticl) and the
  DNN Vulkan backend (`DNN_BACKEND_VKCOM`). Benchmark YOLO-n ONNX through
  `cv.dnn` CPU vs OpenCL vs Vulkan.
- Model runtimes with Vulkan backends that may beat a hand-rolled backend:
  ncnn (proven on Nano with NVIDIA Vulkan), ggml/llama.cpp Vulkan. Wrap as
  `nerves_ai` adapters if they win.

### Phase 4 — productisation
- Camera: CSI via mainline VI (`tegra-video`), test IMX219.
- NervesHub, `nerves_system_okdo_c100` on Hex.
- Upstream the board DTS (linux-tegra) and the U-Boot SDMMC3 patch.

---

## 4. Answer to "Docker container + custom Nx backend"

On L4T R32 the NVIDIA container runtime **bind-mounts CUDA/cuDNN/TensorRT
from the host** (`/etc/nvidia-container-runtime/host-files-for-container.d/*.csv`).
The host must already run the L4T 4.9 kernel + nvgpu + all NVIDIA libs. A
container therefore buys an Ubuntu 18.04 userspace (Python, etc.), not GPU
access. On mainline there is no CUDA at all, so the container has nothing to
reach.

If the L4T variant (section 6) is ever built, skip Docker and do this instead:
- Unpack the L4T userspace (CUDA 10.2, cuDNN, TensorRT 8.2) into a
  **sidecar squashfs** at system build time; mount it at boot.
- Run a **second BEAM node** under MuonTrap (cgroups, restart policy)
  with a TensorRT NIF. Crash isolation is the real value of the "container".
- The main node calls it through **distributed `Nx.Serving`**
  (`Nx.Serving.batched_run/2` finds remote servings via `:pg`), so the app
  sees a normal serving.
- Do **not** build a remote op-by-op `Nx.Backend`: one RPC per tensor op
  is orders of magnitude too slow. Model-level serving is the right grain.

---

## 5. Risks

| Risk | Mitigation |
|---|---|
| PCN211181 EMC tables on mainline (memory stuck at low clock) | Phase 0 identify DRAM; port EMC table into DT reserved-memory or patch driver; measure with `mbw` |
| NVK Tegra not CTS-clean yet | GLES compute fallback; contribute fixes; pin Mesa commit |
| rusticl on nouveau untested on GM20B | zink-on-NVK path; nx_vulkan via clspv |
| Building Mesa (Rust + LLVM + libclc) in Buildroot | Prebuild Mesa as a Nerves artifact package; host LLVM shared with toolchain |
| Thermal throttling under sustained GPU load | Fan control via `pwm-fan`, soctherm trip points in DTS |
| eMMC GPT shared with NVIDIA partitions | GPT reproduces NVIDIA entries at L4T offsets; `check-emmc-layout.sh` before first install |

---

## 6. Optional variant: L4T 4.9 + CUDA (`nerves_system_okdo_c100_l4t`)
Only if a TensorRT-specific model is a hard requirement.
- Kobo-style setup: aarch64 Nerves toolchain fork with 4.9 headers; L4T
  kernel `tegra-l4t-r32.7.6` + gcc-compat patches; c100-bootupd overlays
  folded into the kernel DTS.
- CUDA kernels compiled on the host with nvcc 10.2 + gcc 8 (meta-tegra
  `kirkstone-l4t-r32.7.x` shows how); NIFs against TensorRT 8.2's C++ API
  build fine with the Nerves gcc 15 (no nvcc involved).
- Section 4 sidecar pattern for Nx.

## 7. Rejected: porting nvgpu to mainline
Source is available (R32.7.6 `public_sources.tbz2`: nvgpu ~278k lines of
which ~32k are Linux glue, nvmap ~21k, nvhost ~58k). The blocker is
userspace, not the kernel: closed libcuda/libnvrm expect the exact R32
ioctl ABI of nvgpu/nvmap/nvhost. nvhost conflicts with mainline host1x
(display). Estimated 1–3 months to `deviceQuery`, with a 50–60% chance of
reaching reliable TensorRT, and a re-port on every kernel bump. No known
prior art. Effort goes into NVK Tegra instead.

---

## References
- c100-bootupd: https://github.com/LetsOKdo/c100-bootupd
- Mainline DTS: https://github.com/torvalds/linux/tree/master/arch/arm64/boot/dts/nvidia
- NVK Tegra: https://gitlab.freedesktop.org/mesa/mesa/-/issues/14105,
  https://gitlab.freedesktop.org/drm/nouveau/-/issues/452
- Mesa CI Jetson Nano job: https://gitlab.freedesktop.org/mesa/mesa/-/blob/main/src/gallium/drivers/nouveau/ci/gitlab-ci.yml
- NVK docs: https://gallo.pages.freedesktop.org/mesa/drivers/nvk.html
- NVK on GM20B (Switch): https://github.com/JohnUzoka/mesa-switch, https://github.com/nx-mod/nxvk
- meta-tegra R32: https://github.com/OE4T/meta-tegra/tree/kirkstone-l4t-r32.7.x
- Container host-file mounts: https://forums.developer.nvidia.com/t/host-libraries-for-nvidia-container-runtime/234752
- PCN211181 + buildroot: https://forums.developer.nvidia.com/t/jetson-nano-with-micron-dram-and-pcn211181-buildroot-and-custom-dtb/339666
- TensorRT 8.2 ONNX ops: https://github.com/onnx/onnx-tensorrt/blob/8.2-GA/docs/operators.md
