#!/bin/bash
# Third L4T collection pass with this kernel's actual debugfs names.
# Read-only except for $OUT. Run as root:
#   sudo bash l4t-collect3.sh /tmp/l4t-intel3
set -u
OUT=${1:-/tmp/l4t-intel3}
rm -rf "$OUT" && mkdir -p "$OUT"
cd "$OUT" || exit 1
mount | grep -q debugfs || mount -t debugfs none /sys/kernel/debug
D=/sys/kernel/debug

dumpdir() { # dumpdir <out-file> <dir> [maxdepth]; follows symlinks
	local f=$1 dir=$2 depth=${3:-3}
	[ -e "$dir" ] || { echo "missing: $dir" > "$f"; return; }
	find -L "$dir" -maxdepth "$depth" -type f -readable 2>/dev/null | sort | while read -r p; do
		case "$p" in *regdump*|*trace*|*/mem|*/uevent|*/subsystem/*|*/driver/*|*/firmware_node*) continue ;; esac
		echo "== $p"
		timeout 2 head -c 4000 "$p" 2>&1
		echo
	done > "$f"
}

for d in 57000000.gpu 57000000.gpu_scaling gpu.0 tegra-pmc-io-pads pg_domains tegra_throttle \
	tegra_emc tegra_dfll_fcpu opp tegra_sor0 tegra_sor1 tegra_dp1 tegra_hdmi tegra_bwmgr \
	tegra_la_ptsa mc soctherm tegra_dvfs tegra_central_actmon dma-vpr nvmap tegra_host; do
	dumpdir "dbg-$d.txt" "$D/$d" 2
done

dumpdir thermal.txt /sys/class/thermal 2
for d in /sys/bus/i2c/drivers/ina3221x/*-*; do dumpdir "ina3221-$(basename "$d").txt" "$d" 3; done
dumpdir pwm-fan.txt /sys/devices/pwm-fan 1
dumpdir gpu-sysfs-full.txt /sys/devices/57000000.gpu 1
cat /proc/device-tree/chosen/bootargs > chosen-bootargs.txt 2>&1
dmesg | grep -iE 'speedo|iddq|rail|dvfs|cvb|edp|throttl|soctherm|oc[0-9]' > dvfs-dmesg.txt

cd .. && tar czf "$OUT.tar.gz" "$(basename "$OUT")" && ls -la "$OUT.tar.gz"
