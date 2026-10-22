# What L4T does that our system needs to match

Measured on the C100 under NVIDIA L4T R32.7.6 (kernel 4.9.337-tegra, MAXN)
on 2026-10-20. Raw data is in `docs/l4t-reference/` (collected with
`scripts/dev/l4t-collect*.sh`, `l4t-gpu-vf.sh` and `vkfeatures.py`).

## Patches for our Nerves system

### Kernel device tree (`linux/tegra210-p3448-0002-okdo-c100.dts`)

1. **soctherm over-current inputs.** L4T configures OC1 and OC3 as
   active-low (`throttle-cfgs/oc1`, `oc3`: `nvidia,polarity-active-low`,
   alarm filter 0x4dd1e0, count threshold 1 and 15, GPU throttle level
   3/2, CPU 75 %). Mainline has no OC configuration, which is why it
   reports `soctherm: OC ALARM 0x1` every second. Add equivalent
   `throttle-cfgs` entries (check the mainline soctherm binding for the
   property names).
2. **INA3221 power monitor.** `host1x/i2c@546c0000`, address 0x40,
   channels 0 POM_5V_IN, 1 POM_5V_GPU, 2 POM_5V_CPU, 5 mΩ shunts. Mainline
   has no node; add a `ti,ina3221` node (hwmon driver `SENSORS_INA3221`).
3. **DisplayPort.** L4T drives the monitor on DP (`DP-0 connected
   1920x1080`, 4 lanes, link training passes). Both hot-plug pads are
   muxed to function `dp` with input enabled: `dp_hpd0_pcc6` (DP) and
   `hdmi_int_dp_hpd_pcc1` (HDMI). Mainline's p3450 DTS sets neither and
   relies on the boot firmware. Compare with mainline's live pinmux
   before patching; likely add a pinmux hog for `dp_hpd0_pcc6`.
4. **GPU maximum clock.** NVIDIA's GPU table for this chip (GPU speedo
   ID 2) stops at 921.6 MHz, at 1046 mV against a 1068 mV nominal
   maximum. nouveau's gm20b table also offers 998.4 MHz, which would need
   about 1090 mV. Cap devfreq at 921.6 MHz.

| MHz | 76.8 | 153.6–460.8 | 537.6 | 614.4 | 691.2 | 768.0 | 844.8 | 921.6 |
|---|---|---|---|---|---|---|---|---|
| mV | 832 | 810–821 | 842 | 875 | 917 | 960 | 1003 | 1046 |

### Memory clock (EMC)

5. cboot trains the DRAM for 204 MHz and 1600 MHz (plus derated tables)
   and writes the tables into the kernel device tree (`emc-table@204000`,
   `emc-table@1600000`, `emc-table-derated@*` in `live.dts`). L4T idles at
   204 MHz and scales to 1600 MHz. Mainline needs the Tegra210 EMC
   interconnect series (v7, not merged) and a way to hand these tables
   over: our U-Boot is chain-loaded from OKdo's and never sees cboot's
   device tree, which OKdo's U-Boot holds at 0x83100000.
6. With `c100-bootupd`'s EMC overlay missing, the 4.9 kernel hangs at
   boot; the overlay replaces cboot's EMC node with tables for the
   PCN211181 DRAM.
7. **With that overlay, L4T never leaves 204 MHz.** The bandwidth manager
   requests 1600 MHz (`tegra_bwmgr/emc_min_rate` 1600000000, CPU and
   display floors at 1600 MHz) but `emc_rate` stays at 204000000 and
   `tegra_emc/stats` shows no time at 1600 MHz and no transitions, even
   with `jetson_clocks`. The DRAM is the Micron part (MR5 = 0xFF), i.e.
   the PCN211181 module. Likely cause: OKdo's U-Boot deletes cboot's EMC
   node, which carries the tables cboot has just trained, and the
   overlay's untrained tables (`13_1600000_12_V9.8.7_V1.6`, rev 7) do not
   switch. Memory bandwidth is then about 1/8 of 25.6 GB/s.
   Check the EMC rate on mainline (`/sys/kernel/debug/clk/emc/clk_rate`)
   before trusting any memory-bound benchmark; for 1600 MHz, mainline
   needs cboot's trained tables, not the overlay's.

8. **Mainline also runs the DRAM at 204 MHz** (`clk/emc/clk_rate`
   204000000 with `pll_m`/`pll_mb` at 1600 MHz): cboot leaves it there and
   `tegra210-emc` fails with `failed to get nominal EMC table: -19`. Memory
   bandwidth is about 1/8 of what the board can do. This is the single
   biggest performance issue.
9. **cboot already provides the trained tables in mainline's format.**
   cboot's kernel DT (`l4t-reference/cboot/cboot-kernel.dts`, saved at
   OKdo's U-Boot prompt from `fdt_addr` = 0x83100000) has
   `reserved-memory/emc-table@83400000` ("nominal") and
   `emc-table@83410000` ("derated"), each 64 KiB,
   `compatible = "nvidia,tegra210-emc-table"`, referenced from the EMC
   node as `memory-region-names = "nominal", "derated"`.
   - Each holds two entries, 204 MHz (pllp_out0) and 1600 MHz (pllm_ud),
     revision 7, stride 0x1340.
   - Mainline's `struct tegra210_emc_timing` is 0x1340 bytes with `rate`
     at 0x40 and `clock_src` at 0x4c: the same layout. Mainline counts
     entries until `revision == 0`.
   - The 128 KiB region was byte-identical at OKdo's U-Boot prompt and at
     ours after loading the kernel and DTB (dump in
     `l4t-reference/cboot/emc-tables-0x83400000.bin`), and at the same
     address on two boots.
   - Fix: declare both regions in our DTS (`reserved-memory`, same
     addresses, `nvidia,tegra210-emc-table`) and add `memory-region` and
     `memory-region-names` to `external-memory-controller@7001b000`.
     Move `ramdisk_addr_r` (0x83400000 in `uboot/uboot.env`) out of the
     way. Then something has to request 1600 MHz: check
     `tegra210-emc` debugfs, or carry the EMC interconnect series.

### Follow-up: L4T's 204 MHz blocker confirmed, 2026-10-22

The stereo comparison's read-only inspection confirms the immediate reason
for item7: the active Micron/strap0 1600MHz table has `nvidia,trained=0`.
R32.7.6 `drivers/memory/tegra/tegra210-emc.c:1580` rejects requests above
204MHz when that field is zero. MAXN already requests1600MHz (EMC min/max
1600000000, current204000000), so another power-mode request is insufficient.

OKdo's `c100-bootupd` patch0005 deletes the existing EMC node before applying
the static PCN211181 overlay. The earlier CBoot snapshot in
`l4t-reference/cboot/cboot-kernel.dts` has the matching1600MHz Micron table
trained=1 and nonzero training values; the active replacement has zeroes.
This strongly identifies loss of CBoot training data in the C100 boot path.
The current extlinux entry has no FDT line, so removing one is not a remedy.
Preserve the trained node/data and necessary SDMMC3 support; do not fake the
training flag or bypass the clock driver's validation. No boot changes have
been made or tested at the diagnosis checkpoint. Nerves already ran this
hardware at actual1600MHz.

The subsequent dedicated `c100_gpu` eMMC boot-script fix is now installed:
it retains CBoot's trained EMC node and the SDMMC3 overlay, preserving the
existing SD-first target and Nerves chain-loader without flashing U-Boot.
A one-shot and an unattended L4T boot reach1600MHz. The unchanged D64 graph
improves from17.02 to45.80FPS at640x480, and5.68 to15.59FPS at1280x720
(resident inputs; camera/network/readback excluded). Four output checks
and four timing probes pass with zero GPU errors. CPU/GPU governors/caps
are unchanged. The user subsequently booted Nerves from SD, bootID
`a1415b28-a332-4bfe-9652-7069b9fc2819`, validated slotB, EMC1600MHz,
fresh GPU log with zero errors. This verifies preservation of the SD boot
path. Source, rollback and limitations: sibling `c100_gpu/docs/l4t-emc.md`.

The unchanged D64 resident graph on Nerves/NVK now measures30.686FPS VGA
and10.689FPS720p, versus45.796/15.594 on L4T. Four numeric checks and four
timings pass with no GPU errors. IREE3.11 requires the two existing generic
host-cache maintenance fixes on NVK; the isolated backport leaves models,
shaders, inputs and allocator unchanged. The L4T baseline is untouched.
The report records this runtime delta and the separate3.13 profiling results.

The comparison, raw evidence and upstream links are recorded in sibling
`nx_iree/docs/reference/stereo-nvidia-20261022/README.md`.

### CPU

10. Mainline (`cpufreq-dt`) offers up to 1555.5 MHz; NVIDIA caps the
    Nano at 1479 MHz (DFLL, 1092 mV thermal cap). Cap at 1479 MHz.
    Mainline GPU voltages are 8–18 mV above NVIDIA's for the same clock
    (`l4t-reference/mainline-gpu-vf-table.txt`), and 998.4 MHz needs
    1100 mV, above the 1068 mV nominal maximum.

### Mesa (Vulkan targets for NVK)

11. NVIDIA's driver (Vulkan 1.2.131) enables on this GPU:
   `shaderFloat16 = 1`, `shaderInt8 = 1`, 8/16-bit storage, subgroup size
   32 with basic, vote, arithmetic, ballot, shuffle, shuffle_relative,
   clustered, quad and partitioned (NV) operations in compute,
   fp16 round-to-nearest-even. Limits: 48 KiB compute shared memory, 1536
   invocations per workgroup, 3.86 GiB + 400 MiB heaps. NVK on sm_53 does
   not expose `shaderFloat16`; that is the main gap.

### Measured with NVIDIA's Vulkan driver (vkpeak, GPU at 921.6 MHz)

| | Measured | Theoretical |
|---|---|---|
| fp32 | 226 GFLOPS | 236 |
| fp16 scalar | 417 GFLOPS | 472 |
| fp16 vec4 | 322 GFLOPS | |
| int32, int16 | 77 GIOPS | |
| fp64 | 7.2 GFLOPS | |
| int8 dot product, matrix ops | 0 | no hardware |

Board power under this load: about 7.0 W at the 5 V input, 4.7 W on the
GPU rail, GPU at 51.5 °C. Default and pinned clocks give the same results.
vkpeak's copy rates (1.2 GB/s) are not a bandwidth measurement, and the
DRAM was at 204 MHz (item 7). Raw output in `l4t-reference/vkpeak/`.

### Reference values

- Speedo: CPU 9, SoC 0, GPU 2 (IDDQ CPU 1672, SoC 1928, GPU 2165).
- CPU 102–1479 MHz (DFLL), EMC 204–1600 MHz, GPU 76.8–921.6 MHz.
- Idle power: ~1.5 W at the 5 V input, 0 W on the GPU rail.
- GPU PLL in NA (noise-aware) mode, ADC offset 617.9 mV, slope 10.714 mV.

## Booting L4T on the eMMC after an RCM reflash

`flash.sh -r` rewrites the rootfs without c100-bootupd's extra files.
To boot it again without NVIDIA tools (done here from Nerves on the SD
card, which sees the eMMC as `mmcblk0`):

1. Copy c100-bootupd's `flash-data` files into `mmcblk0p1`: the two
   overlays to `/boot`, `nv_boot_control.conf` and `.service` to `/etc`,
   `u-boot-preboot.scr` to `/`.
2. In `/boot/extlinux/extlinux.conf`, change `root=/dev/mmcblk0p1` to
   `root=/dev/mmcblk1p1`: with the SDMMC3 overlay loaded, the SD slot
   becomes `mmcblk0` and the eMMC `mmcblk1`.
