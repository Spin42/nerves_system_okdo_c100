# Changelog

## v0.1.0

Initial release.

* nouveau runs the GM20B on its native clock path with the fuse clock kept
  enabled, the initial voltage requested before PLL programming and the
  frontend idle timeout disabled during golden-context setup; the GPU came
  up on thirty consecutive warm reboots
* The device tree keeps the CPU at 1479 MHz and the GPU at 921.6 MHz, the
  module's validated maxima, and runs the DRAM at 1600 MHz from nouveau's
  probe; no userspace startup script is needed

* Mainline Linux 6.18.57 with an OKdo C100 device tree (eMMC module, carrier
  microSD on SDMMC3) and backported nouveau devfreq for the Tegra GPU
* Mainline U-Boot 2026.07 running the Nerves A/B logic on microSD or eMMC
* `mix burn` installs on a microSD card, booted through the board's existing
  U-Boot; `mix burn --task emmc` installs on the eMMC (exposed with U-Boot's
  `ums`) next to NVIDIA's boot firmware, with no NVIDIA flashing tools
* OpenGL ES and EGL/GBM through Mesa's nouveau and tegra drivers
* `nerves_system_br` 1.35.2, Buildroot 2026.08, GCC 15.3
