# Boots Nerves from the microSD card with the U-Boot that is already on the
# C100's eMMC (OKdo's L4T U-Boot finds this script through distro boot).
# The eMMC is not modified.

setenv kernel_addr_r 0x84000000
setenv fdt_addr_r 0x83000000

load ${devtype} ${devnum}:${distro_bootpart} ${kernel_addr_r} Image
load ${devtype} ${devnum}:${distro_bootpart} ${fdt_addr_r} tegra210-p3448-0002-okdo-c100.dtb

# The rootfs refers to the boot medium as mmcblk0 (root filesystem,
# application partition, U-Boot environment). Make that the microSD card.
fdt addr ${fdt_addr_r}
fdt resize 4096
fdt set /aliases mmc0 "/mmc@700b0400"
fdt set /aliases mmc1 "/mmc@700b0600"

setenv bootargs console=tty1 console=ttyS0,115200n8 root=/dev/mmcblk0p2 rootfstype=squashfs rootwait
booti ${kernel_addr_r} - ${fdt_addr_r}
