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

### Mesa (Vulkan targets for NVK)

7. NVIDIA's driver (Vulkan 1.2.131) enables on this GPU:
   `shaderFloat16 = 1`, `shaderInt8 = 1`, 8/16-bit storage, subgroup size
   32 with basic, vote, arithmetic, ballot, shuffle, shuffle_relative,
   clustered, quad and partitioned (NV) operations in compute,
   fp16 round-to-nearest-even. Limits: 48 KiB compute shared memory, 1536
   invocations per workgroup, 3.86 GiB + 400 MiB heaps. NVK on sm_53 does
   not expose `shaderFloat16`; that is the main gap.

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
