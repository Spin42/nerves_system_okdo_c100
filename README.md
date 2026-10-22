# OKdo Nano C100

This is the base Nerves System configuration for the [OKdo Nano
C100](https://www.okdo.com/), a carrier board with the NVIDIA Jetson Nano
production module (P3448-0002, 16 GB eMMC).

| Feature              | Description                                        |
| -------------------- | -------------------------------------------------- |
| CPU                  | 1.43 GHz quad-core Cortex-A57 (Tegra X1 / T210)    |
| GPU                  | 128-core Maxwell (GM20B), OpenGL ES via Mesa       |
| Memory               | 4 GB LPDDR4                                        |
| Storage              | microSD (default) or 16 GB eMMC                    |
| Linux kernel         | 6.18 (mainline)                                    |
| Bootloader           | U-Boot 2026.07 (mainline)                          |
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

## Installing on a microSD card

```sh
mix firmware
mix burn
```

Put the card in the C100 and power it on. Nothing on the eMMC is modified.
The step-by-step guide, what to expect on the console and how to update over
the network are in [docs/booting.md](docs/booting.md).

## How it boots

NVIDIA's boot firmware (BCT, nvtboot, TOS, cboot) stays on the module and is
never modified. cboot always loads a U-Boot from the eMMC `LNX` partition.
Nerves runs with this system's mainline U-Boot, which handles the Nerves A/B
logic and boots Linux from the active root filesystem:

* **microSD card**: the U-Boot in `LNX` is whatever the board shipped with
  (for example OKdo's). Its distro boot finds `boot.scr` in the card's boot
  partition, which starts this system's U-Boot from the same partition.
* **eMMC**: the eMMC install puts this system's U-Boot into `LNX`, so cboot
  starts it directly.

This system's U-Boot keeps its environment on the microSD card when the card
holds a Nerves installation, and on the eMMC otherwise. A Nerves microSD card
therefore takes precedence over a Nerves eMMC installation.

The microSD card and the eMMC use the same Nerves partitions, so firmware
updates work the same on both:

```text
+------------------------------------+ 0
| Protective MBR + GPT               |
+------------------------------------+ 2 MiB
| U-Boot environment (Nerves A/B)    |
| p1: boot (FAT)                     |  boot.scr, u-boot.bin
+------------------------------------+ 4 MiB
| p2: rootfs A (squashfs, 1 GiB)     |  /boot holds Image and the dtb
| p3: rootfs B (squashfs, 1 GiB)     |
| p4: application data (f2fs)        |  fills the card; 12 GiB on the eMMC
+------------------------------------+
| eMMC only: p5..p16 NVIDIA          |  LNX and LNX-1 hold U-Boot
+------------------------------------+
```

On the eMMC, Nerves takes the region that NVIDIA's layout uses for the L4T root
filesystem (`APP`). The NVIDIA partitions keep the names, offsets and sizes
from L4T R32.7's layout for this module, so cboot finds `LNX` as before.

In Linux, `/dev/mmcblk0` is the eMMC and `/dev/mmcblk1` the microSD card.
`/dev/rootdisk0` refers to whichever one Nerves booted from.

## Installing on the eMMC

No NVIDIA tools are needed. U-Boot exposes the eMMC to your computer over USB,
and `fwup` writes Nerves, including this system's U-Boot.

You need:

* a C100 with its factory firmware or one flashed with
  [c100-bootupd](https://github.com/LetsOKdo/c100-bootupd), which provides
  NVIDIA's boot chain with the configuration for the module's DRAM
* a 3.3 V USB serial adapter on the debug UART (115200 8N1)
* a USB cable from your computer to the C100's USB device port

Then:

1. Build your firmware with `mix firmware`.
2. Remove any microSD card, power on the C100 and press a key on the serial
   console to stop U-Boot.
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

5. Write the firmware with the `emmc` task:

   ```sh
   mix burn -d /dev/sdX --task emmc
   ```

6. Press Ctrl+C on the serial console to leave `ums`, then type `reset`.

The same steps reinstall a board that already runs Nerves from the eMMC. An
install erases the application data partition.

## Firmware updates

`mix upload` and NervesHub update the inactive root filesystem on the device
Nerves booted from and switch to it on the next boot, with automatic rollback
if the new firmware is not validated. Updates do not rewrite U-Boot; an install
does.

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

* The kernel has no memory controller (EMC) frequency tables, so the DRAM
  stays at the frequency set by NVIDIA's boot firmware (1600 MHz on the
  tested boards; `/sys/kernel/debug/clk/emc/clk_rate` shows it).
* GPU initialization was validated over thirty consecutive warm reboots with
  the nouveau patches in `linux/`; cold power cycles were not tested in
  series. See [docs/nouveau-gm20b.md](docs/nouveau-gm20b.md).
* If NVIDIA's boot firmware itself is damaged, the board has to be recovered
  over USB recovery mode (RCM), which this system does not provide tools for.

## Documentation

* [docs/booting.md](docs/booting.md): booting from a Nerves microSD card.
* [docs/board-testing.md](docs/board-testing.md): reaching, flashing and
  boot-testing a board from the host, with the `scripts/board/` helpers.
* [docs/nouveau-gm20b.md](docs/nouveau-gm20b.md): GPU bring-up notes and the
  accepted power-management configuration.
* [docs/gpu-compute.md](docs/gpu-compute.md), [docs/nvk-findings.md](docs/nvk-findings.md),
  [docs/l4t-findings.md](docs/l4t-findings.md): GPU compute investigation and
  what L4T configures that this system has to match.
