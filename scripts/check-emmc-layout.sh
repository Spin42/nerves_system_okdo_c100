#!/usr/bin/env bash
#
# Check that an OKdo C100 eMMC (exposed to this computer with U-Boot's
# `ums 0 mmc 0`) has NVIDIA's partitions where fwup.conf expects them.
#
# fwup's complete task rewrites the GPT and writes U-Boot to LNX and LNX-1 by
# absolute offset. If a board was flashed with a different L4T layout (for
# example a different ROOTFSSIZE), those offsets would land on other data.
#
# Usage: sudo scripts/check-emmc-layout.sh /dev/sdX

set -euo pipefail

if [ $# -ne 1 ]; then
    echo "Usage: $0 /dev/sdX" >&2
    exit 2
fi
dev=$1

# name start size (512-byte sectors). A size of "-" means "to the end of the
# disk". Entries marked optional are in NVIDIA's GPT but not in the one fwup
# writes, so they are only checked when present.
expected="DTB 29364224 2048
TOS 29366272 12288
EKS 29378560 160
LNX 29378720 131040
DTB-1 29509760 2048
TOS-1 29511808 12288
EKS-1 29524096 160
LNX-1 29524256 131040
BMP 29655296 384 optional
RP4 29655680 512
recovery 29656192 129024 optional
recovery-dtb 29785216 1024 optional
kernel-bootctrl 29786240 512
kernel-bootctrl_b 29786752 512
RECROOTFS 29787264 614400 optional
UDA 30401664 - optional"

actual=$(sfdisk --json "$dev" | python3 -I -c '
import json, sys
t = json.load(sys.stdin)["partitiontable"]
if t.get("label") != "gpt":
    sys.exit("not a GPT disk")
for p in t["partitions"]:
    print(p.get("name", ""), p["start"], p["size"])
')

status=0
while read -r name start size optional; do
    line=$(awk -v n="$name" '$1 == n' <<<"$actual")
    if [ -z "$line" ]; then
        if [ -n "$optional" ]; then
            echo "absent   $name (not needed)"
        else
            echo "MISSING  $name"
            status=1
        fi
        continue
    fi
    read -r _ astart asize <<<"$line"
    if [ "$astart" != "$start" ] || { [ "$size" != "-" ] && [ "$asize" != "$size" ]; }; then
        echo "MISMATCH $name: expected start=$start size=$size, found start=$astart size=$asize"
        status=1
    else
        echo "ok       $name"
    fi
done <<<"$expected"

if [ $status -eq 0 ]; then
    echo "Layout matches. It is safe to install Nerves on $dev."
else
    echo "Layout differs from what fwup.conf expects. Do not install." >&2
fi
exit $status
