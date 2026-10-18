#!/bin/sh

set -e

FWUP_CONFIG=$NERVES_DEFCONFIG_DIR/fwup.conf

# Wrap U-Boot the way cboot expects to find it in the LNX partition
python3 $NERVES_DEFCONFIG_DIR/scripts/mkbootimg-lnx.py $BINARIES_DIR/u-boot.bin $BINARIES_DIR/boot.img

# Run the common post-image processing for nerves
$BR2_EXTERNAL_NERVES_PATH/board/nerves-common/post-createfs.sh $TARGET_DIR $FWUP_CONFIG
