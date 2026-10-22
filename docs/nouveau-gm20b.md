# Nouveau GM20B notes: GPU bring-up on the OKdo C100 (Jetson Nano)

These notes record the investigation of nouveau's intermittent GPU
initialization failure on this board, the accepted configuration, and the
GPU compute work that followed, as dated checkpoints in reverse chronological
order. The [board testing guide](board-testing.md) explains how to reach and
test the board.

## NVIDIA parity checkpoint, 2026-10-23

Read **board-testing.md, "NVIDIA parity reached"** first. The
Census SGBM graph now runs at 49.59 FPS VGA / 17.27 FPS 720p on NVK (frozen
NVIDIA 45.80 / 15.59), byte-identical, with zero GPU errors and no driver,
firmware, runtime or clock change. The gain came from shader restructuring
and a row-tiled volume layout, not from compiler or driver work; the earlier
compiler leads (reuse flags, LOP3/IADD3) were not needed. Boot
`2e0cb4b9-6f3d-452b-b2d9-be6ee28dcd6d`, validated slot B. No boot series was
run; this is a performance checkpoint, not a stability claim.

## Stop checkpoint after optimization experiments, 2026-10-22

Optimization was paused here at the user's request.
Read **board-testing.md, “Stopped checkpoint”** first: it contains
current board state, exact artifacts, remaining checks and resume steps.
Best private resident graph: **34.24 FPS VGA / 11.33 FPS 720p**, versus frozen
NVIDIA **45.80 / 15.59**. This candidate emits matching costs during the forward
horizontal path; it preserves reference output but is not yet promoted or
validated through the full Elixir 200-pair loop. Existing retained source is
still about31.62 /10.99 FPS. The later vertical-producer/separate-selector
candidate completed before stopping and lost:31.84 versus34.12 FPS.

The user's observed `perf: interrupt took too long` messages came during CPU
sampling in the first Tracy capture; the GPU-only guard missed them. Future
GPU captures use `TRACY_NO_SYS_TRACE=1`; verification retained GPU zones with
zero sampled perf handles and identical before/after dmesg. Ordinary FPS uses
the uninstrumented runtime. The benchmark runner now reports all new kernel
lines; R40/R42/R43/R44 report zero. Leave the sampling sysctl and dmesg intact.

Final checked boot is `2e0cb4b9-6f3d-452b-b2d9-be6ee28dcd6d`, Nerves validated
slot B, EMC1600MHz, original governors and unchanged installed NVK. No active
benchmark children or GPU errors. No reboot series was performed here; these
results do **not** establish a new 30-boot stability claim. Stop any future
series at its first failure. No firmware/driver/runtime installation occurred.
Full report: `~/Projects/nx_iree/docs/reference/stereo-nvidia-20261022/optimization-round.md`.
Archive: `~/.local/share/c100-gpu/experiments/stereo-tracing-20261022/`.

## Latest Nerves/L4T comparison checkpoint, 2026-10-22

The user returned to Nerves from SD after the dedicated C100 eMMC boot fix.
Boot `a1415b28-a332-4bfe-9652-7069b9fc2819`, kernel6.18.57, validated slotB,
Mesa26.1.8/NVK and EMC1600MHz verify the preserved SD boot path. Fresh GPU
log has zero errors throughout the bounded comparison. This does not resolve
the historical intermittent load failure described below.

Same D64 resident-input graph: Nerves30.686FPS VGA /10.689FPS720p, versus
L4T45.796/15.594FPS at full-speed RAM. Async4 gives no material gain. All
four numeric checks pass before four timings. The frozen IREE3.11 tool first
failed output on NVK; an isolated build with only the existing generic mapped
input flush and source-invalidation fixes restores correctness. All model/
input hashes match; the frozen L4T bundle stays untouched. Explicitly retain
this runtime compatibility delta when comparing OS results. No firmware,
default runtime, governor or voltage setting changed in this comparison.

A separate3.13 VGA profile attributes81.3% of active GPU time to aggregation
and selection. Its optional caching wrapper fails mapped allocation, while
the native allocator passes output checks. Keep those profile timings apart
from the cached3.11 comparison. Report and complete caveats:
`~/Projects/nx_iree/docs/reference/stereo-nvidia-20261022/README.md`.
Durable Nerves bundle: `~/.local/share/c100-gpu/baselines/nerves-sgm-20261022/`.
Matching NVIDIA alone would still leave720p at15.6FPS;720p30 needs further
GPU execution gains beyond that measured driver/stack gap.

The first optimization round retains only generic branchless feature loading:
31.6247 FPS VGA / 10.9931 FPS 720p resident graph, plus a separate complete
Elixir VGA comparison of 31.0400 versus 29.8512 FPS over 200 prepared pairs.
All 50 distinct maps remain byte-identical and 20 host oracle cases pass.
Current vkpeak reproduces 222.47 GFLOPS / 76.07 integer GIOPS / 10.19 GB/s
copy payload throughput. Allocation tracing rules out repeated native
allocations; coherent memory selection and global-load scheduling estimates
give no improvement. A packed DP prototype reduces registers but loses FPS
with current NAK, so it is rejected. Missing Maxwell LOP3/IADD3 lowering is
a research lead, not an implemented driver change. Full round:
`~/Projects/nx_iree/docs/reference/stereo-nvidia-20261022/optimization-round.md`.
Zero GPU errors throughout; no boot series, flash, default driver/runtime,
clock/governor or voltage changes occurred.

## Takeover update, 2026-10-22

Acceptance clarification: CPU parity is insufficient; require a worthwhile
GPU throughput advantage at comparable quality while preserving Elixir CPU
capacity. New IREE calibrated dispatch capture identifies ~7.26 ms of warmed
device work, of which paths/selection consume ~88% (4.12/2.29 ms). These are
implementation timings, not a hardware limit. Two/four contexts plateau
near 66 FPS and add latency. Missing read-cache flags and path spills are
not supported explanations. Ordinary allocation/readback NIFs can block BEAM
schedulers; generic dirty-I/O registrations improve heartbeat p95 from
~12.4 to ~2.4 ms under two-context load, but do not improve FPS. Target NIF
experiment is isolated at `/root/nxiree/sgm-pipeline-dirty-runtime`; the normal
target library is untouched. Full updated host suite: 809 passed. C100 guard
now optionally owns native tool PIDs directly from `C100_GPU_COMMAND_FILE`
and accepts a bounded `C100_GPU_TIMEOUT_MS`; native capture, deadline kill
and original Elixir path are manually verified. All runs add zero GPU errors
to the retained 23. See
`~/Projects/nx_iree/docs/reference/stereo-saturation-20261022/README.md`.

Latest stereo result: OpenCV's winner scatter adapted to row-local shared
memory replaces the projected consistency gather. Complete three-path GPU
throughput is now 61–69 FPS in bounded diagnostics; paired gains are 9–20%.
All 100 downloaded outputs are byte-identical to the preceding projected
matcher, and D64/D128 fixture/edge checks pass on NVK/RADV. CPU 3WAY still
leads at 94–101 FPS. Generic `IREETensor::upload` now reuses IREE's existing
allocator-aware mapped generator with the earlier flush fix. In an isolated
target runtime it saves about 1–1.4 ms of uploads per frame, without a
consistent additional total-FPS gain. The board's working native library
was not overwritten, no policy changed, and all guarded runs add zero GPU
errors to the retained 23-error baseline. Full host regression: 808 passed,
one shader-tool test skipped then passed separately with explicit tools.
See `~/Projects/nx_iree/docs/reference/stereo-shared-20261022/README.md`.

Latest follow-up: generic `NxIREE.Vulkan.export_pipeline/4` composes the
existing shaders into one invocation and raises three-path throughput to
48.93/49.38 FPS; all 100 board predictions remain byte-identical. The
composed projected selector gives 49.13/53.18 FPS at comparable measured
quality. CPU 3WAY still leads at 100.78/93.71 FPS. Full NxIREE suite passes
809 checks. See `~/Projects/nx_iree/docs/reference/stereo-graph-20261022/README.md`.

A rapid native median-stage benchmark exposed 23 `nv50cal_space: -110`
messages on the accepted boot. The old test regex missed them despite
tool exit 0; that profiling run is rejected. The C100 harness now includes
`board_gpu_log.exs`, refuses existing errors by default, monitors live logs,
and stops on each new error. Explicit diagnostic mode records the old
baseline and reports `BOARD_DIAGNOSTIC_PASS` only; the later graph tests
had zero new errors. This runtime stress failure is unresolved, separate
from the earlier 30/30 warm-boot result. Do not declare full load stability.
The same investigation confirmed a missing flush in IREE's mapped CLI
input generator; patch 0003 fixes that with fail/pass native toggle proof.
NxIREE uploads already flush. No target NIF/driver/firmware was replaced.

User direction is standard Evision/OpenCV GPU integration with minimal
custom code. A real board probe establishes that UMat works through standard
keyword calls (cvtColor returns UMat), while positional guards reject it.
OpenCL is compiled in but haveOpenCL/useOpenCL are false without a device
runtime. Evaluate existing OpenCV OpenCL kernels over clvk/Vulkan, keeping
intermediates resident; StereoSGBM itself still forces CPU Mat and needs a
verified GPU matcher extension. Source evidence and board probe:
`~/Projects/nx_iree/docs/reference/evision-acceleration-20261022/README.md`.
No reboot or power-policy change occurred; slot B remains validated.

Host integration follow-up: unchanged Evision 1.0.0/OpenCV 5.0.0 now executes
cvtColor, resize, medianBlur and remap through clvk/Vulkan on RX 7800 XT.
All four pipelines dispatch, their fixture outputs match CPU byte-for-byte,
and inputs remain unchanged. clvk must use its supported in-process compiler
(`CLVK_CLSPV_ONLINE_COMPILER=1`): the external compiler exits 0 but its wait
fails with ECHILD inside BEAM, causing silent OpenCV CPU fallback. Red/green
logs and a reusable UMat chain benchmark are in the Evision report above.
The small host chain is slower than CPU; no stereo speedup is claimed.
Evision copies UMat inputs between calls. Generic copy/pipeline integration,
a GPU SGBM extension and ARM64 clvk packaging remain outstanding. No board
load, firmware, native library or policy changed in this host investigation.

Current direction: the production stereo pipeline must use the GPU and beat
optimized CPU OpenCV at comparable quality, leaving the CPU for Elixir. Prefer
existing libraries and upstream GPU code, packaged through Buildroot or a
dedicated Elixir library, with minimal custom integration. Generic GPU work
must also run on the host discrete GPU; C100 policy belongs in `c100_gpu` or
the system package. CPU fallback results do not meet this goal.

An isolated Evision 1.0.0 / OpenCV 5.0.0 CPU comparison processed the same
50 Sintel pairs at 320×136 / D=64: SGBM 25.58 FPS, HH 15.64 FPS, HH4 63.65 FPS
and 3WAY 100.78 FPS. This uses ARM NEON/pthreads, not CUDA or Vulkan. Modes and
right-consistency workloads differ from the current 10.39 FPS Vulkan matcher;
match quality and workload before claiming a GPU speedup. No production
Evision dependency, firmware or power policy was changed. The survey and
parameter-verified results are in
`~/Projects/nx_iree/docs/reference/stereo-library-survey-20261022/README.md`.

A subsequent generic Vulkan Census experiment adapts licensed libSGM kernels
(upstream itself remains CUDA-only). Classic Census, upstream path caches,
fused accumulation/selection and register-only selection now reach
28.03 FPS on alley_1 and 29.00 FPS on a second sequence, temple_2. Common
bad1-or-rejected is 4.360% / 2.397%, versus CPU 3WAY 4.434% / 2.284% at
100.78 / 93.71 FPS. Quality metrics are close but do not all favor GPU.
A three-direction GPU tradeoff reaches 38.57 / 36.08 FPS, with worse alley
bad1-or-rejected (4.849%). The performance goal is not complete, and this
is not an accepted production package. D=64/128 and 3/4/8-path fixtures pass
on NVK and RADV; all 100 host/board predictions agree within 3.9e-6 pixels.
See `~/Projects/nx_iree/docs/reference/stereo-census-reuse-20261022/README.md`
for source provenance, quality, native IREE timing, remaining bottlenecks
and reproduction. Eight-path aggregation takes about 16 ms, while fused
selection still takes 9–10 ms even with only three paths. Candidate next
work is OpenCV-style right-map construction and generic IREE graph submission.
Firmware, boot/slot state, power policy and target native runtime remain
unchanged. No reboot or firmware upload occurred during these benchmarks.

The configuration below describes the earlier investigation. The accepted
configuration restores the native NA PLL, `simple_ondemand`, and the parent
710000..1320000 regulator range. Patches 0003/0004 and the modprobe override
are removed from the active build. Fuse patches 0005/0006 remain; new 0007
requests the initial performance state's voltage before PLL initialization.
Patch 0008 keeps the frontend idle timeout disabled through initialization
bundle injection and restores it after GR becomes idle.
The GPU cap remains 921.6 MHz and is applied before the first channel.
The U-Boot command line has been restored without `nouveau.debug`.

Two concrete defects were found:

- The supposed 1 V floor changed PWM calibration. The regulator driver
  uses the DT minimum/maximum as duty-cycle endpoints, so it reported 1 V
  at 0% duty, where the original mapping gives approximately 710 mV.
  Previous voltage conclusions using that override are invalid.
- GM20B directly programmed its initial clock without requesting the
  corresponding voltage. With the correct calibration, sysfs reported
  710000 uV until a frequency transition; patch 0007 produces 819800 uV at
  startup on this board. This is a PWM-derived reading, not a voltmeter
  measurement. PMU/ACR initialization occurs earlier than clock init.

Before 0008, the clean native candidate was rejected at warm boot 13:
twelve passed, then `INJECTED_BUNDLE_ERROR` recurred. Failure-only
instrumentation reproduced it at boot 10, during golden-context bundle
injection with FE_GO_IDLE_TIMEOUT enabled. Both series stopped immediately.
NVIDIA's driver keeps this timeout disabled through injection; Nouveau
restored it before injection. Patch 0008 corrects that ordering.

The clean final image, UUID `1ffb5cb3-94bd-54a7-f1e2-ec9661ce6746`, passed
its upload boot and **30/30 distinct warm reboots**, followed by frequency
transitions at 307.2, 614.4 and 921.6 MHz and thirty integer-compute cases.
No GPU timeout or trap appeared. It returned to 76.8 MHz / 819800 uV with
`simple_ondemand`. Board is left on validated slot B, last boot ID
`6f672cb9-e70d-433c-8894-7231f93bf6b7`. All temporary kernel diagnostics,
test IDs and debug boot arguments are removed. Changes are uncommitted.

This meets the warm-boot acceptance criterion; cold power cycles remain
untested. The precise cause of the earlier PMU timeout is not isolated by
these combined changes. See
`docs/nvk-reference/nouveau-boots-20261022/README.md` for full evidence,
reproduction commands, limitations and retained failure logs.
The acceptance harness stops on the first timeout, graphics trap, wrong
firmware, unvalidated slot, or incorrect power-management state.

GPU work has continued in `~/Projects/nx_iree` with portable Vulkan tests
on both the C100 and host AMD discrete GPU. Device-specific tuning and
board tools live in the dedicated `~/Projects/c100_gpu` library. The unchanged
boot policy script now installs from `package/c100-gpu`; its Buildroot target
and running board hashes match. This packaging change has not been flashed.
See `~/Projects/nx_iree/docs/stereo-path.md` for the allocator fix, recurrence
benchmark and compiler work. Full stereo SGBM and NVIDIA-equivalent
performance are still outstanding.
The compiler copy-elision repair now passes on RADV and NVK, with normal
exports preserving caller inputs. It requires a host source compiler build;
the ordinary downloaded wheel does not contain it. C100 memory headroom
improved, but normal-devfreq latency remains variable. One controlled
921.6 MHz comparison confirmed a speed gain and restored the normal minimum
afterward; the board remains at 76.8 MHz idle with `simple_ondemand`.

Further portable optimization now keeps an entire SGM line in one Vulkan
dispatch, imported through generic `NxIREE.Vulkan.export/4`. The application
shaders are in `nx_iree/bench/stereo`; no stereo/device-specific logic was
added to the compiler or runtime. At the accepted 921.6 MHz cap, the large
direction's median fell from 109.407 ms to 11.138 ms including readback;
GPU-completing invocation alone is 3.402 ms median. All final variants pass
exact results on C100 and host AMD, including boundary/overflow regressions.
The controlled comparison restored normal devfreq. No firmware, boot state,
voltage policy or target runtime binary changed. This is not full SGBM FPS.
See `nx_iree/docs/reference/stereo-kernels-20261022/` for evidence.

A first complete stereo-sequence benchmark now lives in
`nx_iree/bench/stereo/video`: grayscale 3×3 block SAD, eight SGM directions
per view, uniqueness/subpixel selection and left–right consistency.
It ran all 50 Sintel alley_1 clean frames at 320×136 / 64 disparities:
5.928 FPS on C100 normal devfreq, 5.900 FPS at the accepted 921.6 MHz cap,
155.20 FPS on host RADV. This is processing FPS including upload/readback,
excluding decoding/disk I/O; it lacks OpenCV's exact cost and speckle cleanup.
Independent scalar fixtures pass, host/board disparity agrees within 4e-6,
and no GPU errors occurred. The fixed-cap comparison restored normal
devfreq and left the same boot/firmware/runtime in place. See
`nx_iree/docs/reference/stereo-video-20261022/README.md` for quality metrics,
preview video, reproducible commands and remaining performance bottlenecks.

Further optimization preserves the same disparity results: a coalesced
selector plus four independent scan lines per workgroup reaches 7.876 FPS
with normal devfreq (7.859 FPS at the held accepted cap), versus 5.928 FPS
initially. The portable exporter accepts `VIDEO_LINES_PER_GROUP=4`; keep
the default of 1 on the tested host AMD, where four is slower. The final
host variant reaches 172.45 FPS. A generic streaming benchmark measured
11.37 GB/s through the C100 runtime. The earlier s32-layout traffic model gives
about 20 FPS at that measured rate or 46 FPS at the published bandwidth;
neither is a guaranteed SGM speed. See
`nx_iree/docs/reference/stereo-efficiency-20261022/README.md`.

The next portable implementation packs two exact 16-bit scores per u32 and
selects disparity inside the final path. Export with `VIDEO_STORAGE=packed16
VIDEO_FUSE_SELECT=1`, plus `VIDEO_LINES_PER_GROUP=4` on C100 (1 on AMD).
C100 now measures 10.13 FPS, repeated at 10.45 and 10.15 FPS under normal
devfreq; the previous s32 version repeated at 8.05 FPS. Host reaches
216.94 FPS. All 50 disparity maps and rejection masks are bit-identical to
the original. Full CPU intermediate oracles pass at D=3,33,65,128, including
odd padding, chunk boundaries and maximum-SAD inputs. Packing preserves the
invalid scores through an explicit encoding; grayscale 0..255 is enforced.
The volume-traffic model falls from 0.557 to 0.256 GB/pair. At an assumed
20 GB/s that is 12.8 ms of volume streaming alone; measured total is about
99 ms, primarily path aggregation/selection. This is not a predicted FPS.
Explicit next-pixel prefetch regressed to 9.75 FPS and was removed. No
firmware, voltage, clock policy, native runtime or NIF changed for this work.

The generic export decoder now preloads `Nx.Type` for cold unsigned exports;
only that Elixir BEAM was updated in `/root/nxiree-stereo`, with the prior
BEAM backed up. Native runtime/NIF, firmware and boot are unchanged. The
board harness supports an optional success marker for generic benchmarks.

## Goal

Make nouveau bring up the GM20B GPU reliably on every boot of the Nerves
system for the OKdo C100 (Jetson Nano module P3448-0002, Tegra210, speedo id
2). On a failing boot, the first graphics channel (created by `vulkaninfo`
from `/usr/sbin/c100-limits` shortly after boot) fails with:

```
nouveau 57000000.gpu: pmu:hpq: timeout waiting for reply
nouveau 57000000.gpu: gr: init failed, -110
```

The GPU is then unusable until the next boot. The failure rate is currently
about 14% of warm reboots (7 of the last 50), down from 20-50% originally.
The target is 0 in 30+ boots.

## Repository and build

- System repo worktree: `/var/home/marc/Projects/nerves_system_okdo_c100/.claude/worktrees/base-system`,
  branch `worktree-base-system` (no remote). Main branch `main`.
- Kernel patches live in `linux/` (applied by Buildroot), DTS in
  `linux/tegra210-p3448-0002-okdo-c100.dts`, rootfs overlay in `rootfs_overlay/`.
- Kernel: mainline 6.18.57. Buildroot build tree:
  `.nerves/artifacts/nerves_system_okdo_c100-portable-0.1.0/`, kernel sources at
  `build/linux-6.18.57/` inside it (patches already applied there; edits there
  are picked up by `make linux-rebuild`).
- Test firmware app: `~/Projects/hello_c100` (built against this system).
- Nouveau patches in `linux/`:
  - `0001-drm-nouveau-Support-reclocking-on-gp10b.patch` (upstream, Aaron Kling)
  - `0002-drm-nouveau-Support-devfreq-for-Tegra.patch` (upstream, Aaron Kling)
  - `0003-drm-nouveau-gm20b-Add-an-option-to-disable-the-NA-PLL.patch` (ours):
    `NvNaPll=0` selects the speedo-0 (non noise-aware) clock path and the
    matching non-NA voltage table.
  - `0004-drm-nouveau-Start-Tegra-devfreq-without-load-polling.patch` (ours):
    devfreq registers with the `userspace` governor, and the PMU idle
    counters are set up on the first load sample instead of at clk init.
- `rootfs_overlay/etc/modprobe.d/nouveau.conf`: `options nouveau config=NvNaPll=0`
  (verified applied: `/sys/module/nouveau/parameters/config`).
- DTS sets a VDD_GPU floor: `regulator-vdd-gpu { regulator-min-microvolt = <1000000>; }`.
- `c100-limits`: waits for the render node, runs `vulkaninfo` (first channel),
  then sets devfreq `max_freq=921600000`, governor `performance`, and EMC
  `min_rate=1600000000`. Logs to `/dev/kmsg` (`c100-limits: first channel open`
  marks a good boot).

Recent commits: `801a814` VDD floor, `f881ac7` NvNaPll option, `41a42d3`
devfreq change + c100-limits.

## Board access

- Nerves at `192.168.0.31`, SSH with key, the shell is an Elixir IEx eval:
  `ssh 192.168.0.31 'IO.puts(File.read!("/proc/version")); :ok'`.
  Use `System.cmd("dmesg", [])` for the kernel log. Busybox has no `tr`.
- Upload firmware: `mix upload` from hello_c100 writes the inactive A/B slot.
  The new slot must be validated before the next reboot, or U-Boot falls back
  to the old slot; check `Nerves.Runtime.KV.get_all()` for `nerves_fw_active` /
  `nerves_fw_validated` after each upload.
- U-Boot env `nerves_bootargs` currently contains
  `nouveau.debug=gr=debug,pmu=debug,privring=debug,bus=debug` for diagnosis;
  restore the plain value when done.
- The board can also boot NVIDIA's Ubuntu (L4T, nvgpu driver) — ask the user;
  credentials are given by the user out of band, never store them in files.
  Keep its SSH host key out of `~/.ssh/known_hosts` (that holds the Nerves key).
- `/root/regread` on the board: static aarch64 /dev/mem 32-bit reader
  (`/root/regread 0x57137000 ...`), GPU MMIO base 0x57000000.
- Serial console exists but `/dev/ttyUSB0` was not readable from the sandbox.
- Power: the user has a good PSU now. Keep GPU stress light. Every test so far
  used warm reboots (`Nerves.Runtime.reboot()`); cold power cycles need the user.

## Test harness

The scripts live in `scripts/board/` (see its README for the environment
variables); `regread.c` builds with the system toolchain through `regdump.sh`.
- `run-series.sh N`: `make linux-rebuild` + `make` + build hello_c100, upload,
  confirm active/validated, then `trace-boots.sh N`.
- `trace-boots.sh N`: reboot N times; each boot's nouveau/c100-limits dmesg
  lines go to `../traces/boot-<n>.log`; prints ok/FAILED per boot.
- `mk-0003v4.py`, `mk-0004.py`: regenerate patches 0003/0004 from pristine
  copies in `../kernel-orig/` and apply them to the build tree.
- One series of 20 boots takes about 75 minutes.

The sandbox rejects compound shell commands (loops, `$(...)`, variables in
sed) in this worktree; put them in a script file and run `bash script.sh`.

## Measured results (warm reboots)

| Configuration | Failed boots |
|---|---|
| Stock NA clock, devfreq simple_ondemand, VDD floor | 20-50% across many series |
| NA + various PLL fixes (SEL_VCO wait/retry, nvgpu divider handling, DFS-before-IDDQ, coeff 0 at lock, async switch) | 2/10 to 5/10 each |
| Non-NA (`NvNaPll=0`), devfreq ondemand, floor | 6/20 |
| NA, devfreq disabled entirely, floor | 5/20 |
| Non-NA, devfreq disabled entirely, floor | 0/10 (GPU stuck at 76.8 MHz) |
| Non-NA, devfreq userspace, **no** floor | 11/20 |
| Non-NA, devfreq userspace, floor | 2/20 |
| Non-NA, devfreq userspace + lazy counter init, floor (committed) | 5/30 (first 14 clean) |

Ruled out (each by a 8-20 boot series): PSU, soctherm OC throttling (levels
NONE), EMC DRAM tables (removed: 3/10), previous boot's clock state (clocks
lowered before reboot: 3/10), privring resets, NvGrResetWar, devfreq
transitions, GPU clock height.

Observations:
- In NA mode, failing boots show GPCPLL locked (CFG bit17) but SEL_VCO
  (0x137100 bit0) refusing to switch out of bypass, with register state
  identical to good boots.
- With non-NA, failures are PMU queue timeouts during the first GR init.
- With `NvNaPll=0` nouveau sets 1161 mV at 921.6 MHz (L4T: 1057.6 mV in NA
  mode). Stable but ~100 mV high; needs a decision.
- Firmware: linux-firmware `nvidia/gm20b` (PMU image dated 2016-03-01).

## Latest: fuse-clock backport (uncommitted)

Sasha Levin's series "Keep the fuse clock enabled while the Tegra GPU is
powered" (v2, 2026-10-16, linux-tegra patchwork; mboxes in
`docs/nvk-reference/fuse-clock-series-v2/`) is backported as `linux/0005-*.patch` (DT,
unchanged) and `linux/0006-*.patch` (nouveau, rebased onto 6.18). On the
board the GPU node lists `fuse` and the fuse clock is enabled (count 1,
19.2 MHz). With it, on top of the committed configuration, boot 2 of a new
series still failed with `pmu:hpq: timeout waiting for queue ready`. So it is
not sufficient alone; whether it reduces the rate is unknown.

A trace observation from a separate review: on all five failed boots of the
previous 30-boot series the PMU command queue head read back as `0xbad00100`
(a PRI error value), on none of the 25 good boots; nouveau uses that value
unchecked. WPR init had completed on those boots.

Research findings (other systems):
- 6.18.y stable commit 020ecb16e578 ("soc/tegra: fuse: speedo-tegra210:
  Update speedo IDs") gives the Nano `gpu_speedo_id = 2`; before it, the Nano
  was speedo 0 (legacy PLL, 950 mV vmin, non-NA CVB table). Earlier working
  mainline setups ran speedo 0. Forcing speedo 0 entirely is untested
  (`NvNaPll=0` covers clk and volt tables but not the 950 mV vmin).
- Aaron Kling's LineageOS 6.18 kernel (`LineageOS/android_kernel_nvidia_kernel`,
  branch `lineage-24.0_6.18`) carries no nouveau fixes beyond our 0001/0002.
- Mesa CI's Nano power-cycled the board before every job (never warm reboots).
- Mainline never re-clamps the GPU (`GPU_RG_CNTRL`, PMC 0x7000e400+0x2d4) or
  asserts its reset on power down, so a warm reboot may leave GPU state that
  a cold boot would not.
- `774b73428e6e` ("drm/nouveau: Use write-combined maps for coherent") fixes
  an NVK SIGBUS on Tegra; probably not in 6.18.57. Unrelated to this failure.

## Earlier investigation's open questions (historical)

1. **Check what other systems do.** Nobody has yet compared with other
   mainline nouveau users on Tegra210: Aaron Kling's kernel trees
   (webgeek1234 / Kaz205; LineageOS tegra210 on mainline), postmarketOS
   `nvidia-p3450`, switchroot / Linux on Switch (Tegra X1), Fedora/Armbian
   mainline images; nouveau issue tracker and dri-devel threads on
   `pmu:hpq: timeout` / `gr: init failed` for gm20b; NVIDIA (Thierry Reding,
   Jon Hunter) Tegra210 GPU powergate / PMC / regulator patches. Look for
   GM20B/Tegra210 GPU patches beyond 6.18 and DT settings for VDD_GPU.
2. **Cold boots.** Ask the user to power-cycle ~10 times; compare with warm
   reboots. If cold boots are clean, the cause is state surviving a warm
   reset (rail stays powered) and the fix belongs in shutdown/probe reset.
3. **PMU side.** Instrument nouveau's PMU boot (ACR/secure boot, hpq queue
   init) on failing boots: falcon state, mailbox, PRI errors (0x9080..),
   and whether the PMU actually runs (vs GR init timing).
4. **Voltage decision** for `NvNaPll=0` (non-NA table vs NA table).
5. Afterwards: restore `nerves_bootargs`, update docs (`docs/nvk-findings.md`)
   and the memory notes.

## GPU stereo follow-up, 2026-10-22

The portable libSGM-derived Vulkan pipeline in `~/Projects/nx_iree` now has
a conditional throughput lead at 320×136/D64: 121–140 whole-loop GPU FPS
versus 85–89 for four-thread CPU OpenCV 3WAY with matched temporary CPU
performance governor. Normal CPU schedutil gives about 101–104 GPU FPS.
All 100 downloaded predictions remain byte-identical to the earlier matcher.
CPU use is roughly 0.6 cores for GPU submission/readback versus 3.5 for CPU
matching. This is short-run evidence, not production or NVIDIA-equivalent
acceptance. Standard Evision GPU SGBM integration remains open.

The retained changes fuse vertical aggregation/selection, express wide
feature/cost accesses, and reuse IREE's opt-in mappable external-resource
policy. The first mapped C100 fixture failed; the harness stopped immediately.
IREE's non-coherent mapped readback lacked source invalidation. Generic
patch 0005 fixes it; the same fixtures then pass. Patch 0004 also serializes
IREE profile metadata for concurrent contexts. Native red/green regressions
cover both fixes. No custom allocator or executor was added.

Reproduction and evidence are in
`~/Projects/nx_iree/docs/reference/stereo-fused-20261022/README.md`.
The corrected runtime is isolated in `/root/nxiree/sgm-final-mappable-runtime`,
model `/root/nxiree/sgm-final-mappable.bin`, harness `/root/nxiree/sgm-final-tools`.
The dedicated C100 CPU probe restores the governor in `after`, including
an intentionally tested guard timeout. Final CPU governor is schedutil.
Default board native libraries, firmware, GPU/EMC limits and voltage were
not changed; no reboot or firmware upload occurred.

Boot ID remains `6f672cb9-e70d-433c-8894-7231f93bf6b7`, validated slot B,
firmware `1ffb5cb3-94bd-54a7-f1e2-ec9661ce6746`. Every completed diagnostic
adds zero GPU errors, retaining the 23 historical `nv50cal_space: -110`
messages. That earlier rapid native-submission failure remains unresolved;
these timings do not establish clean driver acceptance. Continue to stop
any actual boot/load series at its first failure.

## CPU coexistence follow-up

Latest coexistence follow-up: 1,000-pair normal-governor runs at 320×136/D64
reach GPU 150–152 FPS versus CPU 3WAY 51–52 FPS with two independent CPU workers
using about two cores. GPU child CPU use is about 0.71 cores; no native library,
GPU algorithm, clock-limit or boot-policy change was needed. All repeats agree
and all 400 downloaded maps match previous validated output. The CPU-load
wrapper uses existing OTP/OpenSSL and stops its workers on guard failure,
including a verified injected timeout. Evidence and reproduction:
`~/Projects/nx_iree/docs/reference/stereo-concurrency-20261022/README.md`.
The historical 23-error GPU baseline remains; no new errors occur. Live-camera
pacing/capture and standard Evision GPU SGBM integration remain open.

## Nx.Serving replay follow-up

`~/Projects/nx_iree` now wraps loaded exports with existing Nx.Serving streams.
Generic reshape/squeeze use independent IREE buffer views instead of invoking
the compiler; red/green regressions, 817 passing host cases and RADV checks
cover the integration. C100 runtime is isolated under
`/root/nxiree/sgm-serving-runtime`, runner in `/root/nxiree/sgm-serving-tools`.
Default libraries and firmware are preserved.

With two existing OTP/OpenSSL CPU workers and normal governors, one context
processes 1,000 scheduled 320×136/D64 pairs in about 10.001 seconds on each
clip. Matcher CPU use is 0.64–0.67 cores. Readback latency p95 is 21–24 ms;
scheduled latency reaches 51–56 ms. An idle-CPU 100-pair control only reaches
79 FPS, so this does not prove arbitrary-workload 100 Hz or camera deadlines.
All 200 downloaded C100 maps equal earlier output. Every completed run adds
zero GPU errors; the historical 23-error baseline remains unresolved.

Evidence: `~/Projects/nx_iree/docs/reference/stereo-serving-20261022/README.md`.
Controller/data: `~/.cache/stereo-bench/serving-20261022/`. Background workers
are stopped and the helper unloaded after each callback. No governor, limit,
voltage, U-Boot, firmware or reboot change occurs. Continue to stop actual
boot/load series at the first failure. Idle/bursty CPU pacing, live cameras,
stability and standard Evision GPU integration remain open.

## Rules for this repo

- Commit author `Marc Lainez <marc.lainez@gmail.com>`; no `Signed-off-by`, no
  `Co-Authored-By`; add `Assisted-by: <AGENT>:<MODEL>` when an AI helped.
  Strip `Signed-off-by` from imported patches.
- English only; imperative subject <= 72 chars; body only for a non-obvious
  why; no process narration; no session links anywhere.
- Code comments state present facts, no history.
- Never push to main, never force-push.

## Native VGA follow-up

Current narrowed target is 640x480 per eye at sustained 30 FPS, without
pyramid or ROI work. Prepared-pair GPU throughput is now31.30FPS over200pairs
with two contexts/two CPU workers, versus23.90FPS baseline. Retained portable
changes are upstream libSGM's duplicated-column tile, GLSL mix candidate
selection and bounded branch-free f32 refinement. All50downloaded maps
are byte-identical to validated reference;20 independent host CPU fixture
cases cover D128, block4/16 and eight-path edge groups. No quality or
precision reduction. CPU OpenCV3WAY VGA controls are8.03FPS loaded and
13.49FPS idle; algorithms differ. Prepared GPU matcher CPU use~0.31cores.

Network replay now sustains30Hz with four ordinary Nx.Serving contexts:
1200pairs/39.999seconds with otherwise idle CPUs, and600pairs/20.003seconds
with two CPU workers. Every input/output hash passes, no frames dropped.
Matcher CPU use~1.19/~0.91cores; processingp50~124/~121ms. Four-context
latency is the explicit tradeoff. Two contexts only sustain30Hz with the
loaded CPU control; idle two-context throughput is26.8FPS with growing
backlog. Three contexts reach29.88completionFPS over1200pairs, insufficient.
The solution retains normal governors without artificial CPU load or a CPU
frequency floor. All board limits/policy are unchanged. Live-camera capture,
rectification, clean driver-load acceptance and Evision GPU API remain open.

Evidence, rejected experiments, GPU traces and ground-truth quality:
`~/Projects/nx_iree/docs/reference/stereo-vga30-20261022/README.md`.
Isolated model `/root/nxiree/sgm-vga30-tools/selectopsrefine.bin`, serving runtime
unchanged. No firmware, clock/voltage limit or production library change.
Historical23errors remain; every completed diagnostic addszero. One compiler
IR capture hit its timeout and was retried with file capture; debug env was
restored. Final compiler capture shows vertical selector731->522instructions
and34->5reconvergence setups versus duplicated-tile control; still48GPR,
40warps/SM maximum and zero spills. An isolated Mesa integer-bank variant
gave no meaningful gain and was rejected; exact original build source is
restored. Stop actual boot/load tests at first failure. Reproduction
controllers are retained under `~/.cache/stereo-bench/vga30-20261022/controls`.
