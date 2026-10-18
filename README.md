# OKdo Nano C100

This is the base Nerves System configuration for the [OKdo Nano
C100](https://www.okdo.com/), a carrier board with the NVIDIA Jetson Nano
production module (P3448-0002, 16 GB eMMC).

| Feature              | Description                                        |
| -------------------- | -------------------------------------------------- |
| CPU                  | 1.43 GHz quad-core Cortex-A57 (Tegra X1 / T210)    |
| GPU                  | 128-core Maxwell (GM20B), OpenGL ES via Mesa       |
| Memory               | 4 GB LPDDR4                                        |
| Storage              | 16 GB eMMC (Nerves), microSD as `/dev/mmcblk1`     |
| Linux kernel         | 6.18 (mainline)                                    |
| Bootloader           | U-Boot 2026.07 (mainline), chain-loaded by cboot   |
| IEx terminal         | UART `ttyS0` (115200 8N1)                          |
| GPIO, I2C, SPI       | Yes - [Elixir Circuits](https://github.com/elixir-circuits) |
| Ethernet             | Yes - Realtek RTL8111 over PCIe                    |
| Display              | HDMI and DisplayPort                               |
| USB                  | USB 3.0 host                                       |

## Using

The most common way of using this Nerves System is create a project with `mix
nerves.new` and to export `MIX_TARGET=okdo_c100`. See the [Getting started
guide](https://hexdocs.pm/nerves/getting-started.html#creating-a-new-nerves-app)
for more information.

If you need custom modifications to this system for your device, clone this
repository and update as described in [Making custom
systems](https://hexdocs.pm/nerves/customizing-systems.html).

## How it boots

NVIDIA's boot firmware (BCT, nvtboot, TOS, cboot) stays on the module and is
never modified. It lives in the eMMC boot partitions and in a few partitions at
the end of the eMMC user area. cboot loads U-Boot from the `LNX` partition.
This system replaces that U-Boot with mainline U-Boot, which then runs the
Nerves A/B logic and boots Linux from the active root filesystem.

```text
eMMC user area
+------------------------------------+ 0
| Protective MBR + GPT               |
+------------------------------------+ 2 MiB
| U-Boot environment (Nerves A/B)    |
+------------------------------------+ 4 MiB
| p1: rootfs A (squashfs, 1 GiB)     |  /boot holds Image, dtb, extlinux
| p2: rootfs B (squashfs, 1 GiB)     |
| p3: application data (f2fs, 12 GiB)|
+------------------------------------+ 2 MiB + 14 GiB
| p4..p16: NVIDIA partitions         |  LNX and LNX-1 hold U-Boot
+------------------------------------+
```

The NVIDIA partitions keep the names, offsets and sizes from L4T R32.7's
layout for this module, so cboot finds `LNX` as before.

## Installing Nerves on the eMMC

No NVIDIA tools are needed. The board's existing U-Boot exposes the eMMC to
your computer over USB, and `fwup` writes Nerves, including the new U-Boot.

You need:

* a C100 with its factory firmware or one flashed with
  [c100-bootupd](https://github.com/LetsOKdo/c100-bootupd), which provides
  NVIDIA's boot chain with the configuration for the module's DRAM
* a 3.3 V USB serial adapter on the debug UART (115200 8N1)
* a USB cable from your computer to the C100's USB device port

Then:

1. Build your firmware with `mix firmware`.
2. Power on the C100 and press a key on the serial console to stop U-Boot.
3. Expose the eMMC over USB:

   ```text
   ums 0 mmc 0
   ```

4. On your computer, find the new disk (for example `/dev/sdX`) and check that
   its layout matches what this system expects:

   ```sh
   sudo deps/nerves_system_okdo_c100/scripts/check-emmc-layout.sh /dev/sdX
   ```

   Stop here if it reports a mismatch: that board was flashed with a
   different layout and installing would overwrite other data.

5. Write the firmware:

   ```sh
   mix burn -d /dev/sdX
   ```

6. Press Ctrl+C on the serial console to leave `ums`, then type `reset`.

The same steps reinstall a board that already runs Nerves, since this
system's U-Boot also has `ums`. A full install erases the application data
partition.

## Firmware updates

`mix upload` and NervesHub update the inactive root filesystem and switch to it
on the next boot, with automatic rollback if the new firmware is not
validated. Updates do not rewrite U-Boot; a full install does.

## GPU

The GM20B GPU is driven by nouveau and Mesa's `tegra` and `nouveau` Gallium
drivers. The display controller is `/dev/dri/card0` (tegra-drm) and the
GPU render node is provided by nouveau. To check OpenGL ES with a display on
HDMI:

```elixir
cmd("kmscube")
```

GPU clock scaling is handled by devfreq; see
`/sys/class/devfreq/57000000.gpu/`.

## Known limitations

* The kernel has no memory controller (EMC) frequency tables, so the DRAM runs
  at the frequency set by NVIDIA's boot firmware.
* Nerves boots from the eMMC only. The microSD card is available to
  applications as `/dev/mmcblk1`.
* If NVIDIA's boot firmware itself is damaged, the board has to be recovered
  over USB recovery mode (RCM), which this system does not provide tools for.
