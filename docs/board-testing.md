# Board testing guide: controlling the OKdo C100 and running tests on it

This guide collects how the board is reached, flashed, rebooted, inspected
and boot-tested from the host, followed by the dated checkpoints of the GPU
and stereo work in reverse chronological order. The companion
[nouveau GM20B notes](nouveau-gm20b.md) cover the GPU bring-up itself and the
[boot guide](booting.md) the first installation on a microSD card.

## NVIDIA parity reached, 2026-10-23: resume here

The user set the goal "at least match NVIDIA's SGBM FPS" on 2026-10-22 and it
is met with byte-identical output. Resident-input graph throughput on boot
`2e0cb4b9-6f3d-452b-b2d9-be6ee28dcd6d` (validated slot B, EMC 1600 MHz, normal
governors, installed NVK unchanged, zero GPU errors and zero new kernel
messages in every run R45–R72):

| Variant | VGA FPS | 720p FPS |
| --- | ---: | ---: |
| Frozen NVIDIA target | 45.796 | 15.594 |
| `cost-fused` (previous best) | 34.02 | 11.39 |
| `lean7` (retained) | **49.59** | **17.27** |

The complete four-context 200-pair Elixir loop gives 47.11 FPS (`lean7`) and
48.45 FPS for the same graph exported by the production exporter, versus
30.95 FPS for the previous retained control; all 50 reference maps match
byte-for-byte (R70, R72). The changes are shader restructuring (packed Census
comparisons, one-candidate-per-term recurrence, cheaper selection), a row-tiled
layout for byte volumes and interleaved features, and a cost-fused six-dispatch
graph. Those shaders are now the `~/Projects/nx_stereo` library
(`NxStereo.sgm/3`, an `NxIREE.Vulkan.Pipeline`); the benchmark directory they
were developed in, `nx_iree/bench/stereo/census/` with `VIDEO_FUSION=cost`, is
in nx_iree's history up to commit cae4115. The report is
`~/Projects/nx_iree/docs/reference/stereo-nvidia-20261022/optimization-round.md`,
section "Second round". Experiment sources, scripts, NAK listings, ablations,
logs and per-variant snapshots are in
`~/.cache/stereo-bench/nvidia-parity-20261022/lean/` (board side
`/root/nxiree/nvidia-parity-20261022/`, models `lean*-{vga,720}.vmfb`, runs
`r45`–`r72`), with a checksummed copy under
`~/.local/share/c100-gpu/experiments/stereo-tracing-20261022/lean/`.

Useful scripts in that directory: `check.sh` (host oracle matrix, 16 cases),
`check-prod.sh` (same through the production exporter), `build-vga.sh` /
`build-720.sh` (frozen IREE 3.11 board models), `run-board.sh <results>
"<variants>" [vga|720]` (guarded board correctness + timing), `run-timing.sh`
(timing only, for ablations), `run-elixir.sh` (200-pair Elixir comparison),
`profile*.sh` (quiet Tracy stage captures). The host NAK compile-only shim
(`NOUVEAU_CHIPSET=0x12b`, `LD_PRELOAD` of the drm-shim, `probe-host`) gives
instruction and register counts without the board; see `nak/`.

At 960x540 the resident graph gives 29.2-29.7 FPS (R73/R75) but the Elixir
loop only 21 FPS with two contexts (R76/R77), because per-frame transient
allocation costs about 38 ms at that size (R78: 13.9 FPS without IREE's caching
allocator). The next step for a 30 FPS loop at that size is a pooled transient
allocator in the 3.13 Elixir runtime, plus a few percent from the untouched
consistency/median stages. Inputs are `/root/nxiree/qhd-input` and
`/root/nxiree/nvidia-parity-20261022/qhd/`; runners `qhd.exs`, `qhd-elixir.exs`.

No flash, reboot, driver, runtime, governor or voltage change was made. The
board remains on the same boot with no benchmark children. Consistency and
median (0.77 + 0.96 ms at VGA) are the only stages still slower than NVIDIA's.

## Stopped checkpoint, 2026-10-22: resume here

Optimization was paused here at the user's request. No new
experiment was started after that request. The already-running R44 finished
successfully. NVIDIA parity remains **unachieved**; do not mark the goal complete.
No flash, reboot, commit, push, installed driver/runtime replacement, governor
or voltage change was made in these final experiments.

Latest resident-input graph measurements (not camera-to-output FPS):

| Variant / run | VGA FPS | 720p FPS | Status |
| --- | ---: | ---: | --- |
| Frozen NVIDIA target | 45.796 | 15.5942 | Reference |
| Retained generic branchless loads | 31.6247 | 10.9931 | Existing source |
| First-horizontal-path cost producer, R40 / R42 | 34.2377 / 34.2054 | 11.3299 (R43) | Private candidate only |
| Vertical cost producer + separate selector, R44 | 31.8376 | Untested | Slower; reject |

R42 paired control was 31.6214 FPS; R43 paired control was 11.0302 FPS.
R44 paired first-horizontal producer was 34.1242 FPS. All board output checks
passed, with zero GPU errors and zero new kernel messages. Both new variants
passed 16 independent host-oracle cases (D64/D128 and BLOCK4/8/16, four frames
each). The faster candidate has **not** had the full 200-pair Elixir comparison
and has **not** been promoted into the generic exporter or production shaders.

`cost-fused` computes raw matching costs inside the existing forward horizontal
scan, stores those costs alongside its path, then lets reverse-horizontal and
vertical/selection stages consume them. It adds a packed cost buffer (19.66 MB
at VGA) and uses six dispatches. Algorithm and quality settings remain classic
48-bit Census, D64, three paths, P1=8, P2=64, uniqueness=1.0526315789473684,
f32 subpixel, projected consistency and median. The experimental exporter
explicitly supports the three-path vertical-fusion case only.

`cost-vertical` instead emits costs and a vertical path using the existing
shared feature tile, runs both horizontal paths, and runs the modern branchless
selector over independent pixels. It adds another path buffer and loses to
`cost-fused`; no profile, 720p run or further tuning was performed for it.

Evidence and reproducible private sources/scripts:

- Cache: `~/.cache/stereo-bench/nvidia-parity-20261022/{cost-fused,cost-vertical}`.
- Durable copy: `~/.local/share/c100-gpu/experiments/stereo-tracing-20261022/`,
  including sources, build/check scripts, models, R40–R44 logs, board result
  directories, GPU trace, final-state snapshot and `SHA256SUMS`.
- Detailed report: `~/Projects/nx_iree/docs/reference/stereo-nvidia-20261022/optimization-round.md`.
- Board models: `/root/nxiree/nvidia-parity-20261022/models/cost-fused-{vga,720}.vmfb`
  and `cost-vertical-vga.vmfb`; isolated experiments, not installed defaults.

Useful next steps, only when optimization resumes:

1. Recheck board identity/defaults and existing processes using
   `/root/nxiree/nvidia-parity-20261022/tracy/final-state.exs` over Elixir SSH.
2. Validate `cost-fused` through the existing full Elixir harness before retaining
   it: adapt cache `run-elixir.exs` with a fresh results directory and upload
   `cost-fused-elixir-vga.bin`. Use 200 prepared pairs / 50 distinct reference
   maps. Do not compare resident-only FPS with end-to-end Elixir FPS.
3. Further speed is still required: roughly 34% at VGA and 38% at 720p relative
   to the best private result. R41 corrected GPU stages are 3.6827 ms Census,
   7.5997 forward+cost, 4.3087 reverse, 10.6208 vertical+selection, 0.7692
   consistency, 0.9611 median. Focus remains aggregation; unfusing selection
   alone did not win.
4. One untested compiler lead is Maxwell operand-reuse flags across integer
   instructions. See `cost-tiled/next-leads.txt` for pinned MaxAs references.
   This is a hypothesis, not demonstrated stalls or promised speed. A private
   experiment must prove that only reuse-control bits change, preserving
   registers, instructions, scheduling, scoreboards, cache flags and code size.
   Do not repeat the already-rejected register-bank or scheduler experiments.

At the final check, Nerves remains on boot
`2e0cb4b9-6f3d-452b-b2d9-be6ee28dcd6d`, validated slot B, EMC 1600 MHz,
normal CPU/GPU governors, one BEAM, no active benchmark children, scoped
environment restored and no GPU errors. Installed NVK SHA256 remains
`48885fd37aa46790352387032a2584ceaba2e909b59d081d528c475b83c5c930`.
No OS switch is needed to resume. The earlier checkpoints below are historical;
this section supersedes their pending/unimplemented descriptions.

Latest diagnostic follow-up: the user spotted three CPU `perf: interrupt took
too long` messages during R30's first Tracy capture. They concern average
profiling-handler time (2.5–4us), and reduced the kernel's sampling-rate cap
to50250. They are not GPU clock throttling. Earlier GPU-only guard output
missed them. Use process-scoped `TRACY_NO_SYS_TRACE=1` for future GPU traces:
R34 verified GPU zones still work, zero perf handles in12 monitored samples,
and identical before/after kernel logs. Do not reset the kernel sysctl or
clear dmesg. The private benchmark runner now prints all new kernel messages.
Uninstrumented FPS measurements remain the performance authority.

Private packed-cost reuse with the existing shared-memory tile now gives
32.13/32.30FPS VGA versus31.59/31.68 control, with20 host-oracle cases and
board checks passing. It adds19.66MB and is not yet retained in production;
the gain is too small to close the45.80FPS NVIDIA target. Artifacts:
`~/.cache/stereo-bench/nvidia-parity-20261022/{irq-review,cost-volume,cost-tiled}`,
also copied into the durable experiment archive named below. No new kernel
messages during the paired tests; installed stack unchanged. Next concrete
algorithmic lead: fuse cost production into the first horizontal scan instead
of its separate4.99ms producer. This is unimplemented/unmeasured.

Latest profiling checkpoint (2026-10-22): board is back in Nerves, boot
`2e0cb4b9-6f3d-452b-b2d9-be6ee28dcd6d`, validated slot B, EMC1600MHz,
normal CPU/GPU governors, zero GPU errors and unchanged installed NVK.
Matched IREE3.11 stage traces on both operating systems put most of the
remaining gap inside horizontal and vertical GPU aggregation. Peak compute
and bulk-copy throughput are similar. NVK's reported timestampPeriod=1 is
wrong on this board: an independent query probe measures about1.627604ns,
matching NVIDIA's reported period; correct NVK trace durations accordingly.
This correction changes timing units, not FPS. Two private 48→40-register
shader variants pass correctness but do not improve throughput. An isolated
readonly-cache bypass also loses performance (31.769→25.6152FPS), mostly
by slowing median filtering. Bypassing only the final instruction scheduler
also loses (28.0281 versus31.5139FPS), with both aggregation stages slower.
None of these candidates is retained; all output checks pass.
Sources, traces, results and checksums are archived under
`~/.local/share/c100-gpu/experiments/stereo-tracing-20261022/`.
The full comparison and rejected experiments are recorded in sibling
`nx_iree/docs/reference/stereo-nvidia-20261022/optimization-round.md`.
No further OS switch is currently needed. A more specific dependency or
throughput model is needed before another scheduling experiment; the
NVIDIA parity goal remains open.

Latest L4T checkpoint: the eMMC preboot configuration now preserves CBoot's
trained EMC tables, restoring actual1600MHz RAM. It retains the SD-first
boot target and stock SD command; no shared U-Boot binary, saved environment
or SD files were changed. Board backup for rollback is
`/var/backups/c100-l4t-emc-20261022T184950Z/u-boot-preboot.scr`.
The dedicated source/build/install/regression tools and details are in
sibling `c100_gpu/docs/l4t-emc.md`. Unattended L4T boot and all four
correctness/four timing probes pass with zero GPU errors. Same D64 graph:
45.80FPS VGA,15.59FPS720p, resident inputs without camera/network/readback.
The user has now returned to Nerves from SD. Boot
`a1415b28-a332-4bfe-9652-7069b9fc2819`, kernel6.18.57, validated slotB,
Mesa26.1.8/NVK, actual EMC1600MHz and a fresh GPU log with zero errors
verify the SD boot path. Normal CPU/GPU governors and caps are unchanged.

Parity optimization follow-up: generic branchless feature loading in
`nx_iree/bench/stereo/census/paths.comp` gives 31.6247 FPS VGA / 10.9931 FPS
720p resident graph throughput. A separate IREE 3.13 Elixir comparison with
four contexts and 200 prepared pairs gives 31.0400 versus 29.8512 FPS;
all 50 distinct maps match the saved reference byte-for-byte. Twenty host
oracle cases pass and all current board probes report zero GPU errors.
No firmware/default runtime/default driver change. Full evidence and rejected
experiments: `nx_iree/docs/reference/stereo-nvidia-20261022/optimization-round.md`.
Earlier packed DP and Maxwell LOP3 experiments did not close the gap;
see the later profiling checkpoint above for the current investigation.

The exact L4T comparison stack is frozen in
`~/.local/share/c100-gpu/baselines/l4t-sgm-20261022/`, with native tools,
models, fixtures, reference outputs, source/build snapshots, SHA256SUMS and
manifest.json containing all argv. See sibling `c100_gpu/docs/l4t-sgm-baseline.md`.
The Nerves comparison now passes all four numeric checks and four timings:
30.686FPS VGA /10.689FPS720p serial,30.746/10.627FPS async4. All12 staged
artifact hashes match. The unpatched frozen3.11 tool first failed numeric
output; an isolated build with only the two existing generic mapped-buffer
flush/invalidation backports restores correctness. Keep this runtime
compatibility delta explicit; the L4T artifacts remain untouched. All EMC
samples are1600MHz, GPU reaches921.6MHz, and zero new GPU errors occur.
Nerves bundle: `~/.local/share/c100-gpu/baselines/nerves-sgm-20261022/`.
Report: sibling `nx_iree/docs/reference/stereo-nvidia-20261022/README.md`.
A separate3.13 VGA profile spends81.3% of GPU time in aggregation/selection;
its optional caching wrapper fails a mapped allocation, so native allocation
remains the working3.13 control. No firmware/default runtime was replaced.
The old Elixir whole-loop rates are a different metric; these short clean
probes do not resolve the historical intermittent load failure.

Latest coexistence test: at 320×136/D64, 1,000-pair runs with normal CPU/GPU
governors give GPU 150–152 FPS versus CPU 3WAY 51–52 FPS while two OpenSSL-backed
workers use about two CPU cores in the main BEAM. No performance governor
is selected. See `~/Projects/nx_iree/docs/reference/stereo-concurrency-20261022/README.md`.
The scoped CPU-load helper and updated runners are in
`/root/nxiree/sgm-concurrency-tools`; existing final runtime/model are reused.
Every run adds zero GPU errors to the same 23-error baseline. This is prepared
replay, not live-camera acceptance; `/dev/video*` currently lists no devices.

Latest stereo result: the generic fused/mappable pipeline reaches 121–140
whole-loop FPS at 320×136/D64 with the bounded CPU-performance diagnostic,
versus 85–89 CPU FPS under the same policy; normal CPU schedutil gives about
101–104 GPU FPS. See `~/Projects/nx_iree/docs/reference/stereo-fused-20261022/README.md`.
The corrected runtime is isolated at `/root/nxiree/sgm-final-mappable-runtime`;
tools in `/root/nxiree/sgm-final-tools` include `cpu_performance_probe.exs`.
That probe restores the CPU governor after success and guard timeout. It is
not a boot default. No firmware or default native-library install occurred.
The earlier native load failure remains open; all recent diagnostics retain
its 23-error baseline and add zero new errors.

Latest runtime note: rapid native profiling exposed `nv50cal_space: -110`
on the accepted boot, despite process exit 0. This is an unresolved load
failure, separate from boot acceptance. The dedicated `c100_gpu` child
harness now requires `scripts/board_gpu_log.exs` alongside it, monitors
kernel errors while running, and refuses already contaminated logs.
`C100_GPU_DIAGNOSTIC=1` explicitly retains a baseline for bounded investigation
and produces `BOARD_DIAGNOSTIC_PASS`, never clean acceptance. Every new
error still stops the child. Preserve and investigate failure logs; do not
clear dmesg to obtain a passing result. See the latest update in the
[nouveau notes](nouveau-gm20b.md) and `~/Projects/nx_iree/docs/reference/stereo-graph-20261022/README.md`.

## Updated boot harness, 2026-10-22

Use `scripts/board/trace-native-boots.sh` for the restored native GPU
configuration. It uses relative script paths, preserves logs in a new
directory, checks the firmware UUID and slot validation, and stops at the
first timeout, graphics trap, or power-management mismatch. It never uploads.

```sh
C100_BOARD=192.168.0.31 C100_BOOT_LOG_DIR=/tmp/c100-boots \
  bash scripts/board/trace-native-boots.sh 30 run-1 FIRMWARE_UUID
```

Replace `FIRMWARE_UUID` with the uploaded image's `meta-uuid`, obtained with
`fwup -m -i hello_c100.fw --metadata-key meta-uuid`. Confirm the upload has
booted and validated before starting. The harness expects no Nouveau config
override or debug command-line flag, `simple_ondemand`, a 921.6 MHz cap,
and a reported GPU voltage of at least 818750 uV. These are Nano-specific
acceptance checks, not a generic Tegra test.

The earlier scripts described below still contain historical scratch paths.
The 0003/0004 generators recreate retired workarounds; do not run them as
part of the current build. Current active GPU patches are 0001, 0002,
0005, 0006, 0007, and 0008. The board's `nerves_bootargs` is now the plain value
without `nouveau.debug`; the older command line below is historical.

Accepted firmware UUID: `1ffb5cb3-94bd-54a7-f1e2-ec9661ce6746`, currently
on validated slot B. It passed thirty warm reboots plus scaling/compute
checks. Evidence: `docs/nvk-reference/nouveau-boots-20261022/README.md`.

The unchanged `c100-limits` script now belongs to `package/c100-gpu`, enabled
by `BR2_PACKAGE_C100_GPU`. It installs at the same `/usr/sbin/c100-limits`
path used by erlinit. This source packaging move has not been flashed.
Portable Vulkan/Elixir work is in `~/Projects/nx_iree`; C100-specific tuning
and test tools are in the dedicated `~/Projects/c100_gpu` library.

You are taking over hands-on work on an OKdo Nano C100 (Jetson Nano module
P3448-0002, Tegra210) running a Nerves firmware built from this repository.
This file explains how to reach the board, change its firmware, reboot it,
read its state, and run repeatable boot tests. The companion file
`nouveau-gm20b.md` describes the current investigation.

## 1. The board and the host

- Board IP: `192.168.0.31` (DHCP; if it stops answering after a reboot, ask the
  user whether it got a new address).
- Host: this Fedora machine, user `marc`. Work happens in the system repo
  worktree `/var/home/marc/Projects/nerves_system_okdo_c100/.claude/worktrees/base-system`
  (branch `worktree-base-system`, no remote).
- The test firmware app is `~/Projects/hello_c100`. Its `mix.exs` takes the
  system from that worktree by path (`nerves_system_okdo_c100`, `path: ...`).
- The microSD card has two systems the user can choose between: the Nerves
  firmware (default) and NVIDIA's Ubuntu (L4T). Only the user can switch to
  Ubuntu or power-cycle the board.

## 2. Talking to Nerves over SSH

SSH uses the host's key (`~/.ssh/id_*.pub` is baked into the firmware). The
remote side is not a Unix shell: each command is an **Elixir expression**
evaluated in the running IEx, and its output is what it prints. End with
`:ok` so the return value does not clutter the output.

```sh
ssh -o BatchMode=yes -o LogLevel=ERROR 192.168.0.31 'IO.puts(File.read!("/proc/version")); :ok'
```

Common patterns:

```elixir
# Kernel log, filtered
{d, _} = System.cmd("dmesg", []); d |> String.split("\n") |> Enum.filter(&(&1 =~ ~r/nouveau|c100-limits/)) |> Enum.join("\n") |> IO.puts(); :ok

# Read / write sysfs and debugfs
IO.puts(File.read!("/sys/class/devfreq/57000000.gpu/cur_freq")); :ok
File.write("/sys/kernel/debug/emc/min_rate", "204000000")

# Run a binary
{o, rc} = System.cmd("/root/regread", ~w(0x57137000 0x57137100)); IO.puts(o); :ok

# Firmware slot state
IO.inspect(Nerves.Runtime.KV.get_all() |> Map.take(~w(nerves_fw_active nerves_fw_validated))); :ok

# Reboot (the SSH call then hangs until timeout; wrap it in `timeout 15`)
Nerves.Runtime.reboot()
```

Notes:
- Quote the whole expression in single quotes on the host; use double quotes
  inside Elixir.
- `System.cmd` raises `:enoent` for binaries that do not exist; the rootfs is
  BusyBox (no `tr`, no `uptime`).
- debugfs is mounted by `/usr/sbin/c100-limits` at boot.
- Files can be copied with `sftp` (the board runs the SFTP subsystem):
  `printf 'put local /root/remote\n' | sftp -q -o BatchMode=yes -b - 192.168.0.31`.
- `~/.ssh/known_hosts` holds the Nerves host key. Do not add another key for
  this IP there.

Useful places on the board:
- GPU devfreq: `/sys/class/devfreq/57000000.gpu/{cur_freq,max_freq,governor}`.
- GPU rail: the `/sys/class/regulator/regulator.*` whose `name` is `VDD_GPU`
  (`microvolts`).
- EMC: `/sys/kernel/debug/clk/emc/clk_rate`, `/sys/kernel/debug/emc/min_rate`.
- Clocks: `/sys/kernel/debug/clk/<name>/{clk_rate,clk_enable_count}`.
- nouveau module options: `/sys/module/nouveau/parameters/config`.
- Device tree: `/proc/device-tree/...` (for example
  `/proc/device-tree/gpu@57000000/clock-names`).
- `/root/regread ADDR...`: static aarch64 `/dev/mem` 32-bit reader (source
  `scripts/board/regread.c`; `scripts/board/regdump.sh` builds and runs it). GPU
  MMIO is at 0x57000000.

## 3. Building and installing firmware

Build chain: kernel/Buildroot changes go into the system worktree, then the
Buildroot output is rebuilt, then hello_c100 is rebuilt against it.

- Buildroot output: `.nerves/artifacts/nerves_system_okdo_c100-portable-0.1.0/`
  in the worktree. The kernel tree is `build/linux-6.18.57/` inside it, with
  all `linux/*.patch` already applied. Edits made there directly are picked up
  by `make linux-rebuild` (handy for quick experiments; turn them into a
  patch in `linux/` afterwards).
- Toolchain: `.nerves/artifacts/nerves_system_okdo_c100-portable-0.1.0/host/bin/aarch64-nerves-linux-gnu-gcc`.

Steps (as scripts in `scripts/board/`, configured through the environment
variables listed in its README):
1. `rebuild-dtb.sh`: in the artifact dir, `make linux-rebuild` then `make`
   (also picks up DTS changes in `linux/` and `rootfs_overlay/`), then runs
   `build-app.sh`.
2. `build-app.sh`: `MIX_TARGET=okdo_c100 mix firmware` in the application
   directory (`C100_APP_DIR`, by default the sibling `hello_c100`); the image
   is at `_build/okdo_c100_dev/nerves/images/<app>.fw`.
3. `upload-app.sh`: `mix upload <board>`. This writes the **inactive** A/B
   slot and reboots into it.
4. `confirm-fw.sh`: waits for the board and prints the active slot and
   `nerves_fw_validated`.

**A/B trap:** after an upload the board must come up and be validated
(`nerves_fw_validated` = 1; autovalidate is on) before any further reboot.
If it reboots before that, U-Boot falls back to the previous slot and you end
up testing the old firmware. Always run `confirm-fw.sh` after an upload, and
check the active slot changed (a ↔ b).

`wait-upload.sh` waits for SSH **and then uploads**; do not use it just to
wait for the board.

The later stereo replay experiment uses the separate runtime
`/root/nxiree/sgm-serving-runtime` and runner
`/root/nxiree/sgm-serving-tools/serving.exs`; it does not replace default
libraries. Reproduce through
`~/.cache/stereo-bench/serving-20261022/board_control.exs` on the host, passing
`2 alley 20 100` (CPU workers, clip, repetitions, scheduled pairs/s).
The controller reuses the existing guard and restores environment/stops the
CPU helper in `after`. Evidence and limitations are in
`~/Projects/nx_iree/docs/reference/stereo-serving-20261022/README.md`.

## 4. Kernel command line

The kernel command line comes from the U-Boot environment variable
`nerves_bootargs`, which firmware updates do not rewrite. It currently is:

```
console=tty1 console=ttyS0,115200n8 rootfstype=squashfs rootwait nouveau.debug=gr=debug,pmu=debug,privring=debug,bus=debug
```

The `nouveau.debug=...` part is for the investigation; restore the plain
value when done (via `fw_setenv` on the board, for example
`System.cmd("fw_setenv", ["nerves_bootargs", "..."])`). Settings that must
ship with the firmware belong in the rootfs instead
(`rootfs_overlay/etc/modprobe.d/nouveau.conf` sets `nouveau config=...`).

## 5. Boot testing

The failure under study is intermittent, so tests are series of reboots.

- `run-series.sh N`: rebuild (`rebuild-dtb.sh`), upload, confirm, delete old
  traces, then `trace-boots.sh N`, then grep the traces for errors.
- `trace-boots.sh N`: for each boot: reboot via SSH, wait ~45 s, wait for SSH,
  wait 20 s more for `c100-limits`, then save the nouveau/c100-limits dmesg
  lines to `traces/boot-<n>.log` and print `boot n: ok|FAILED`.
  - A boot is **ok** when the log contains `c100-limits: first channel open`
    (a Vulkan device was created).
  - It **stops at the first failed boot**: one failure rejects the
    configuration under test. Do not wait for a full series to finish.
  - About 3.7 minutes per boot.
- To accept a configuration, ask for a long clean series (30+ boots); the
  previous best configuration still failed about 1 boot in 7.
- `trace-boots-low.sh`: same, but drops the EMC and GPU clocks before each
  reboot (used to test state carried over a warm reboot).

Traces go to `C100_BOOT_LOG_DIR` (default `/tmp/c100-boots`).

What a failing boot looks like in the trace:

```
nouveau 57000000.gpu: pmu:hpq: timeout waiting for queue ready   (or: waiting for reply)
nouveau 57000000.gpu: gr: init failed, -110
c100-limits: vulkaninfo failed, GPU and EMC left at boot clocks
```

## 6. Kernel patches

The nouveau patches in `linux/` are 0001/0002 (upstream reclocking and
devfreq support for Tegra), 0005/0006 (Sasha Levin's fuse-clock series v2,
patches 5/6 and 6/6, backported to 6.18; the source mboxes are in
`docs/nvk-reference/fuse-clock-series-v2/`) and our own 0007/0008 (initial
voltage request, idle timeout during bundle injection). To change one, edit
the file in the Buildroot kernel tree, run `make linux-rebuild` through
`rebuild-dtb.sh`, and regenerate the patch with `git diff` against the
pristine tree before committing it.

## 7. Ubuntu (L4T) on the same board

Only when the user has booted it. User `marc`; the password is given by the
user and must only be passed through the `SSHPASS` environment variable, never
written to a file:

```sh
SSHPASS=... scripts/board/l4t-ssh.sh 'uname -a'
```

`l4t-ssh.sh` keeps the Ubuntu host key in a separate known_hosts file (edit
its path); never put it in `~/.ssh/known_hosts`.

## 8. Sandbox constraints

The session's sandbox rejects shell commands it cannot verify in this
worktree: loops, `$(...)`, variables in option positions, compound `cd`
commands. Put such logic in a script file and run `bash script.sh`. Long
runs (boot series) go in the background; one series of 20 boots is about 75
minutes.

## 9. Safety

- The power supply was replaced and is fine under load, but keep GPU loads
  light during boot tests.
- A GPU that wedges may only recover after a full power-off, which only the
  user can do. All boot tests so far are warm reboots.
- Never flash, reboot or change the U-Boot environment without saying so; the
  user may be using the board.
- Git rules: author `Marc Lainez <marc.lainez@gmail.com>`, no `Signed-off-by`
  or `Co-Authored-By`, an `Assisted-by: <AGENT>:<MODEL>` trailer, English,
  short imperative subjects, no session links. Never push to main or force-push.

## Latest native VGA replay checkpoint

Portable sources/evidence are in sibling `nx_iree`, report
`docs/reference/stereo-vga30-20261022/README.md`:31.30prepared-pairFPS at
640x480/D64, plus paced30Hz rawgray TCP replay using four ordinary Nx.Serving
contexts.1200pairs idle and600pairs with two CPU workers pass every hash;
latency~124ms median is the four-context throughput tradeoff. Two-context
idle replay only26.8FPS, so use VIDEO_CONCURRENCY=4 for the measured baseline.
GPU/CPU governors, limits, firmware and default native libraries unchanged.
No CPU floor or artificial load required. All diagnostics addzeroGPUerrors;
the historical23-error load failure remains unresolved. Stop new tests at
first GPU error. Camera capture and standard Evision GPU SGBM remain open.

Runtime `/root/nxiree/sgm-serving-runtime`; model
`/root/nxiree/sgm-vga30-tools/selectopsrefine.bin`; network runner and expected
manifest in the same tools directory. Host controls/source snapshots are
under `~/.cache/stereo-bench/vga30-20261022/controls`. Run stream-network.sh
from sibling `nx_iree`, overriding NETWORK_BUNDLE, VIDEO_EXPECTED,
VIDEO_CONCURRENCY=4, VIDEO_FPS=30 and a unique VIDEO_TAG; it uses script-relative
controller paths. Source clip remains
`~/.cache/stereo-bench/network60-20261022/stereo640-60.gray` (50pairs looped).
This is directly resized original Sintel data, not cameras;4:3 aspect changes
are disclosed in the report. No pyramid/ROI work was done.
