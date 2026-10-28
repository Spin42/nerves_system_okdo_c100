# Changelog

## Unreleased

* Two Raspberry Pi Camera Module 3 (IMX708) on the CSI connectors, captured
  as raw Bayer through V4L2: the Raspberry Pi kernel's IMX708 driver, and
  patches to `tegra-video` for subdevice nodes, format pass-through on the
  CSI channels, media bus code filtering and frame start timestamps
* CMA pool raised from 32 to 256 MiB for the capture buffers

## v0.1.0

Initial release.

* Mainline Linux 6.18.57 with an OKdo C100 device tree (eMMC module, carrier
  microSD on SDMMC3)
* Mainline U-Boot 2026.07 running the Nerves A/B logic on microSD or eMMC;
  as on the Raspberry Pi, each slot has its own boot partition with the
  kernel and device tree next to its root filesystem
* `mix burn` installs on a microSD card, booted through the board's existing
  U-Boot; `mix burn --task emmc` installs on the eMMC (exposed with U-Boot's
  `ums`) next to NVIDIA's boot firmware, with no NVIDIA flashing tools
* GPU through nouveau with devfreq: OpenGL ES and EGL/GBM through Mesa's
  nouveau and tegra drivers, Vulkan 1.3 through NVK
* CPU (1479 MHz) and GPU (921.6 MHz) limited to the module's validated
  maxima; DRAM at 1600 MHz
* `nerves_system_br` 1.35.3, Buildroot 2026.08.1, GCC 15.3
