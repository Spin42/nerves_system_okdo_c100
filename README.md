# OKdo Nano C100

This is the base Nerves System configuration for the [OKdo Nano
C100](https://www.okdo.com/), a carrier board with the NVIDIA Jetson Nano
production module (P3448-0002, 16 GB eMMC).

| Feature              | Description                                        |
| -------------------- | -------------------------------------------------- |
| CPU                  | 1.43 GHz quad-core Cortex-A57 (Tegra X1 / T210)    |
| GPU                  | 128-core Maxwell (GM20B), OpenGL ES and Vulkan via Mesa |
| Memory               | 4 GB LPDDR4                                        |
| Storage              | microSD (default) or 16 GB eMMC                    |
| Linux kernel         | 6.18 (mainline)                                    |
| Bootloader           | U-Boot 2026.07 (mainline)                          |
| IEx terminal         | HDMI/DP with a USB keyboard; UART `ttyS0` (115200 8N1) via `erlinit.config` |
| GPIO, I2C, SPI       | Yes - [Elixir Circuits](https://github.com/elixir-circuits) |
| Ethernet             | Yes - Realtek RTL8111 over PCIe                    |
| Display              | HDMI and DisplayPort                               |
| USB                  | USB 3.0 host                                       |
| Cameras              | Two Raspberry Pi Camera Module 3 (IMX708) on the CSI connectors, raw Bayer over V4L2 |

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
logic. As on the Raspberry Pi, each firmware slot has its own boot partition:
U-Boot loads the kernel and device tree from the active slot's boot partition
and Linux mounts that slot's root filesystem.

* **microSD card**: the U-Boot in `LNX` is whatever the board shipped with
  (for example OKdo's). Its distro boot finds `boot.scr` in the card's
  bootloader partition, which starts this system's U-Boot from the same
  partition.
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
| p5: bootloader (FAT)               |  microSD only: boot.scr, u-boot.bin
+------------------------------------+ 4 MiB
| p1: boot A (FAT, 64 MiB)           |  Image and dtb of slot A
| p2: boot B (FAT, 64 MiB)           |  Image and dtb of slot B
| p3: rootfs A (squashfs, 1 GiB)     |
| p4: rootfs B (squashfs, 1 GiB)     |
| p6: application data (f2fs)        |  fills the card; 11.9 GiB on the eMMC
+------------------------------------+
| eMMC only: p5, p7..p16 NVIDIA      |  LNX and LNX-1 hold U-Boot
+------------------------------------+
```

On the eMMC, Nerves takes the region that NVIDIA's layout uses for the L4T root
filesystem (`APP`). The NVIDIA partitions keep the names, offsets and sizes
from L4T R32.7's layout for this module, so cboot finds `LNX` as before. A GPT
written by fwup holds at most 16 entries, so the boot splash (`BMP`) and L4T's
recovery partitions are left out of the table; their data stays in place.

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

`mix upload` and NervesHub update the inactive slot, its boot partition and
its root filesystem, on the device Nerves booted from and switch to it on the
next boot, with automatic rollback if the new firmware is not validated.
Updates do not rewrite U-Boot; an install does.

## GPU

The GM20B GPU is driven by nouveau. The display controller is
`/dev/dri/card0` (tegra-drm) and the GPU render node is provided by nouveau.

* OpenGL ES 3.2 and EGL/GBM come from Mesa's `tegra` and `nouveau` Gallium
  drivers. To check them with a display on HDMI:

  ```elixir
  cmd("kmscube")
  ```

* Vulkan 1.3 comes from Mesa's NVK driver. NVK only exposes GPUs it is not
  conformant on, such as this one, when `NVK_I_WANT_A_BROKEN_VULKAN_DRIVER=1`
  is set; erlinit sets it for the Erlang VM and everything it starts.
  `vulkaninfo` is included.

The GPU clock scales with load between 76.8 and 921.6 MHz (devfreq,
`/sys/class/devfreq/57000000.gpu/`) and the CPU up to 1479 MHz, the module's
validated maxima. The DRAM runs at 1600 MHz, the rate NVIDIA's boot firmware
trains.

## Cameras

Both camera connectors are described for the Raspberry Pi Camera Module 3
(Sony IMX708): CAM0 on CSI port A and CAM1 on CSI port E, two lanes each.
Mainline Linux has no IMX708 driver, so the Raspberry Pi kernel's driver is
carried in `linux/`, along with patches to the Tegra210 video input driver
(`tegra-video`, in staging):

* device nodes for the sensors and CSI channels (`/dev/v4l-subdev*`), so
  exposure, gain and blanking can be set from user space;
* the CSI channels pass the sensor's format through;
* `VIDIOC_ENUM_FMT` filters by media bus code (`V4L2_CAP_IO_MC`);
* buffers are timestamped at frame start, so the frame timing of the two
  cameras can be compared and aligned by adjusting one sensor's vertical
  blanking;
* buffers can be requested cached (`V4L2_MEMORY_FLAG_NON_COHERENT`), so
  reading a frame on the CPU is not slowed by an uncached mapping.

The Tegra X1's ISP has no open driver, so frames arrive as raw 10-bit Bayer
(`RG10`, one sample per 16 bits), one video node per connector, named
`54080000.vi-output-0` (CAM0) and `54080000.vi-output-4` (CAM1) in
`/sys/class/video4linux/*/name`. Each connector's enable line is a fixed
regulator with a startup delay, which the sensor needs before it answers on
I2C. The CMA pool is 256 MiB for the capture buffers.

## Known limitations

* The DRAM clock does not scale with load; it stays at 1600 MHz.
* GPU initialization was validated over thirty consecutive warm reboots with
  the nouveau patches in `linux/`; cold power cycles were not tested in
  series.
* NAK, Mesa's shader compiler for NVK, is not tuned for Maxwell: fp32 compute
  runs at roughly half the throughput of NVIDIA's driver. The patches in
  `patches/mesa3d/` close part of that gap.
* If NVIDIA's boot firmware itself is damaged, the board has to be recovered
  over USB recovery mode (RCM), which this system does not provide tools for.

## Documentation

* [docs/booting.md](docs/booting.md): booting from a Nerves microSD card.
