#!/usr/bin/env bash
#
# Make a microSD test firmware from a regular firmware file. The card boots
# with the U-Boot already on the C100's eMMC and leaves the eMMC untouched.
#
# Usage: scripts/make-sd-test-fw.sh <app.fw> <output.fw> [nerves-system-dir]
#
# The system directory defaults to $NERVES_SYSTEM (the built system artifact,
# containing images/). Write the result to a card with `fwup <output.fw>`.

set -euo pipefail

if [ $# -lt 2 ] || [ $# -gt 3 ]; then
    echo "Usage: $0 <app.fw> <output.fw> [nerves-system-dir]" >&2
    exit 2
fi

here=$(cd "$(dirname "$0")" && pwd)
app_fw=$1
out_fw=$2
system=${3:-${NERVES_SYSTEM:?set NERVES_SYSTEM or pass the system directory}}

mkimage=$system/host/bin/mkimage
[ -x "$mkimage" ] || mkimage=mkimage

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

unzip -p "$app_fw" data/rootfs.img > "$work/rootfs.img"
"$mkimage" -A arm64 -T script -C none -d "$here/sd-test/boot.cmd" "$work/boot.scr" > /dev/null

NERVES_SYSTEM=$system ROOTFS=$work/rootfs.img BOOT_SCR=$work/boot.scr \
    fwup -c -f "$here/sd-test/fwup-sd-test.conf" -o "$out_fw"
echo "Wrote $out_fw"
