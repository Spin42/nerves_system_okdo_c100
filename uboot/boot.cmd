# Installed as boot.scr in the microSD card's boot partition next to this
# system's u-boot.bin. When the U-Boot in the eMMC LNX partition is not this
# system's (for example OKdo's), its distro boot runs this script, which starts
# this system's U-Boot. That U-Boot then finds the Nerves environment on the
# card and boots Nerves from it.

load ${devtype} ${devnum}:${distro_bootpart} ${kernel_addr_r} u-boot.bin
booti ${kernel_addr_r} - ${fdtcontroladdr}
