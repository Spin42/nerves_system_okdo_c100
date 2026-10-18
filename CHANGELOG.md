# Changelog

## v0.1.0

Initial release.

* Mainline Linux 6.18.57 with an OKdo C100 device tree (eMMC module, carrier
  microSD on SDMMC3) and backported nouveau devfreq for the Tegra GPU
* Mainline U-Boot 2026.07 installed by fwup into NVIDIA's LNX partition; no
  NVIDIA flashing tools needed
* A/B firmware updates on the eMMC alongside NVIDIA's boot firmware partitions
* OpenGL ES and EGL/GBM through Mesa's nouveau and tegra drivers
* `nerves_system_br` 1.35.2, Buildroot 2026.08, GCC 15.3
