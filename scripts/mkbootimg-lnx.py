#!/usr/bin/env python3
"""Wrap U-Boot in the Android v0 boot image that cboot loads from LNX.

NVIDIA's L4T R32 cboot for Tegra210 chain-loads the "kernel" of the boot
image stored in the LNX eMMC partition. The image is not signed on
non-secure-boot modules, so this produces the same layout as L4T's flash
tooling: 2 KiB pages, kernel at 0x10008000, no ramdisk.

Usage: mkbootimg-lnx.py <u-boot.bin> <boot.img> [name [cmdline]]
"""

import hashlib
import struct
import sys

PAGE_SIZE = 2048
KERNEL_ADDR = 0x10008000
RAMDISK_ADDR = 0x11000000
SECOND_ADDR = 0x10F00000
TAGS_ADDR = 0x10000100


def pad(data):
    return data + b"\0" * (-len(data) % PAGE_SIZE)


def add_nv_header(page, image_size):
    """Add the unsigned-image trailer that L4T's flash tooling places at the
    end of the first page. Only the partition name and image size vary; the
    rest are fixed placeholders for signatures that a non-secure boot does
    not use."""
    magic = struct.pack("<II", 0xBEEFBAB1, 0xFEEDDEAD)
    page[0x5A4:0x5A8] = b"LNX\0"
    page[0x5A8:0x5B0] = struct.pack("<II", image_size, 0)
    page[0x5B0:0x5B8] = magic
    page[0x5B8:0x6B8] = b"\xaa" * 0x100
    page[0x6B8:0x7C8] = b"\xee" * 0x110
    page[0x7D0:0x7E0] = b"\xcc" * 0x10
    page[0x7E0:0x7E8] = struct.pack("<II", image_size, 0)
    page[0x7E8:0x7F8] = magic * 2


def main():
    if len(sys.argv) not in (3, 4, 5):
        sys.exit(__doc__)

    with open(sys.argv[1], "rb") as f:
        kernel = f.read()
    name = sys.argv[3].encode() if len(sys.argv) > 3 else b""
    cmdline = sys.argv[4].encode() if len(sys.argv) > 4 else b""
    if len(name) >= 16 or len(cmdline) >= 512:
        sys.exit("name or cmdline too long")

    # Same digest as AOSP mkbootimg for header version 0
    sha = hashlib.sha1()
    for blob in (kernel, b"", b""):
        sha.update(blob)
        sha.update(struct.pack("<I", len(blob)))

    header = struct.pack(
        "<8s10I16s512s32s1024s",
        b"ANDROID!",
        len(kernel), KERNEL_ADDR,
        0, RAMDISK_ADDR,
        0, SECOND_ADDR,
        TAGS_ADDR,
        PAGE_SIZE,
        0,  # header version
        0,  # os version
        name,
        cmdline,
        sha.digest(),
        b"",
    )

    first_page = bytearray(pad(header))
    body = pad(kernel)
    add_nv_header(first_page, len(first_page) + len(body))

    with open(sys.argv[2], "wb") as f:
        f.write(first_page)
        f.write(body)


if __name__ == "__main__":
    main()
