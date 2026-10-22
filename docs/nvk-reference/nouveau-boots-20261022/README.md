# GM20B native power-management validation — 2026-10-22

Accepted firmware: `1ffb5cb3-94bd-54a7-f1e2-ec9661ce6746`.
Board: OKdo C100 / Tegra210 Nano, speedo 2, kernel 6.18.57.
The upload boot and **30/30 distinct warm reboots passed**. Every measured
boot validated slot B, opened the first Vulkan channel, retained
`simple_ondemand`, a 921600000 Hz cap, and 819800 uV at 76800000 Hz.
No Nouveau timeout, initialization failure, graphics trap or MMIO fault
appeared. Cold power cycles were not tested.

## Changes under test

- Keep fuse-clock patches 0005/0006 and upstream reclocking/devfreq patches
  0001/0002.
- Remove the non-NA PLL override (0003), userspace/lazy-counter workaround
  (0004), forced performance governor, and modified PWM voltage minimum.
- Restore the parent regulator's 710000..1320000 uV calibration. Its
  constraints define PWM duty endpoints; changing the minimum to 1 V
  mislabeled 0% duty and distorted every voltage request.
- Patch 0007 requests the initial performance state's voltage before PLL
  initialization. With the correct calibration but without this request,
  the regulator reported 710000 uV until a clock transition. With the
  patch, startup reports 819800 uV, above the 818750 uV table minimum.
- Patch 0008 keeps FE_GO_IDLE_TIMEOUT disabled through golden-context
  method initialization and bundle injection, waits for GR idle, then
  restores it. NVIDIA's Tegra driver also keeps this timeout disabled
  during bundle injection.
- Apply the GPU frequency cap before opening the first channel. CPU and
  EMC policy are otherwise unchanged. No Nouveau config/debug override.

## Failing evidence and controlled change

The native configuration with 0007 but without 0008 failed at warm boot
13 after twelve passes (`before-timeout-fix-boot-13.log`). Vulkan startup
completed despite `INJECTED_BUNDLE_ERROR`; this was treated as a failure.

Failure-only instrumentation reproduced the trap at boot 10 after nine
passes (`diagnostic-failure-boot-10.log`). The captured state was:

```text
stage=3 bundle=0000c401 data=00000001 golden=1
esr=80000001 info=00010e90 timeout=00000800
pipe=0000c403/00000001/80000008 fe=00200001 pll=00000001
```

Stage 3 is `gf100_gr_icmd`: the fault occurred during golden-context
bundle injection with the timeout enabled. The software bundle marker and
hardware address can differ because injection proceeds concurrently with
the interrupt. ESR_INFO is not decoded here. The retained `0x20` read on
an earlier boot was not proof of a timeout.

`temporary-diagnostics.diff` preserves the instrumentation used to obtain
this evidence; none of it is in the accepted firmware. After removing it
and adding only 0008, the same boot scenario passed thirty times. This
supports the sequencing fix, but an intermittent test is not proof that
every possible boot is reliable. Nor does it isolate the precise cause of
the original PMU timeout: fuse handling and voltage initialization both
changed, and ACR/PMU initialization precedes clock initialization.

## Regression procedure and result

From the system worktree, after upload and slot validation:

```sh
C100_BOOT_LOG_DIR=/tmp/c100-nouveau-20261022 \
  bash handover-scripts/trace-native-boots.sh 30 final-v2 \
  1ffb5cb3-94bd-54a7-f1e2-ec9661ce6746
```

The harness never uploads. It checks boot identity, firmware UUID, slot
validation, power-management state and the complete kernel log. A failure
stops the series before the next reboot. The broadened timeout check also
catches `gf100_gr_wait_idle` failures that initialization may not propagate.

Result: exit 0, 30 distinct boot IDs. Last result:

```text
PASS 6f672cb9-e70d-433c-8894-7231f93bf6b7 .../final-v2/boot-30.log
```

Full logs are in `accepted-boots/`; the upload boot is separately saved.
`earlier-boot-series.tar.gz` retains the preceding diagnostic and rejected
series, and `final-state.log` records the board state after QA.
`patch-check.log` records all active patches applying with fuzz=0 to
pristine kernel files, followed by byte comparisons against the built
sources. The kernel/Buildroot/firmware build, shell syntax checks and
`git diff --check` passed.

## Scaling and compute QA

On boot 30, request each minimum frequency for 500 ms without GPU load,
then restore the original minimum in an Elixir `after` block. The governor
remained `simple_ondemand`; the cap remained 921600000 Hz. PLL lock and
SEL_VCO stayed set. Readings are regulator/PWM-derived, not voltmeter
measurements.

| State | GPU Hz | Reported uV |
|---|---:|---:|
| Initial idle | 76800000 | 819800 |
| Requested minimum | 307200000 | 819800 |
| Requested minimum | 614400000 | 893000 |
| Requested minimum | 921600000 | 1057700 |
| Restored idle | 76800000 | 819800 |

Run `/root/gpucheck int32` with
`NVK_I_WANT_A_BROKEN_VULKAN_DRIVER=1`. This selects three integer kernels
at ten loop counts each, comparing GPU results with CPU references.
`scaling-and-compute.log` records:

```text
PASSED: 0 failing case(s)
GPUCHECK_RC=0 GPUCHECK_CASES=30
KERNEL_GPU_ERRORS=0
QA_PASS
```

The board was left on the accepted, validated slot B, with its original
minimum frequency restored. No further reboot or heavy stress test was
performed. Temporary kernel instrumentation, firmware test IDs, debug
boot arguments and scratch files were removed; patches and evidence remain
uncommitted.
