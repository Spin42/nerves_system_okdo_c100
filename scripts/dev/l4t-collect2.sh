#!/bin/bash
# Second L4T collection pass: DVFS, thermal and over-current, PMC pads,
# nvgpu and display debugfs. Read-only except for $OUT. Run as root:
#   sudo bash l4t-collect2.sh /tmp/l4t-intel2
set -u
OUT=${1:-/tmp/l4t-intel2}
rm -rf "$OUT" && mkdir -p "$OUT"
cd "$OUT" || exit 1
mount | grep -q debugfs || mount -t debugfs none /sys/kernel/debug
D=/sys/kernel/debug

# Dump every readable small file under a debugfs directory
dumpdir() { # dumpdir <out-file> <dir> [maxdepth]
	local f=$1 dir=$2 depth=${3:-3}
	[ -d "$dir" ] || { echo "missing: $dir" > "$f"; return; }
	find "$dir" -maxdepth "$depth" -type f -readable 2>/dev/null | sort | while read -r p; do
		case "$p" in *regdump*|*trace*|*/mem|*/firmware*) continue ;; esac
		echo "== $p"
		timeout 2 head -c 4000 "$p" 2>&1
		echo
	done > "$f"
}

find $D -maxdepth 2 2>/dev/null | sort > debugfs-tree.txt

# DVFS and voltage/frequency tables
dumpdir dvfs.txt $D/tegra_dvfs 2
dumpdir clock-dvfs.txt $D/clock 1
for c in gbus emc cpu_g cclk_g dfll_cpu sor0 sor1 dpaux dpaux1; do
	dumpdir "clk-$c.txt" "$D/clk/$c" 1
done

# Thermal, throttling and over-current
dumpdir soctherm.txt $D/soctherm 2
dumpdir thermal-sys.txt /sys/class/thermal 2
run_oc() { dmesg | grep -iE 'oc|over.?current|alarm|throttl|edp' | grep -viE 'socket|clock|block|loc|doc|proc' | tail -100; }
run_oc > oc-dmesg.txt
dumpdir edp.txt $D/edp 2

# PMC I/O pads and power gating
dumpdir pmc.txt $D/pmc 2
dumpdir io-pads.txt $D/tegra_io_pad 2
cat $D/powergate 2>&1 > powergate.txt

# GPU (nvgpu) debugfs
dumpdir nvgpu-debugfs.txt $D/gpu.0 1
dumpdir nvgpu-clk.txt $D/gpu.0/clocks 2

# Display controllers, SOR and DPAUX
for d in $D/tegradc.* $D/tegra_hdmi* $D/tegra_dp* $D/sor* $D/dpaux*; do
	[ -e "$d" ] && dumpdir "display-$(basename "$d").txt" "$d" 2
done

# Power monitor configuration
for d in /sys/bus/i2c/drivers/ina3221x/*; do
	[ -d "$d" ] && dumpdir "ina3221-$(basename "$d").txt" "$d" 2
done

# Files from the first pass that were not copied
lsusb -t > usb-tree.txt 2>&1
lsusb -v > usb-verbose.txt 2>&1
lspci -nnkvv > pci.txt 2>&1
cat /proc/interrupts > interrupts.txt
ip -d link > net-links.txt 2>&1
cat /sys/kernel/debug/clk/clk_summary > /dev/null 2>&1

cd .. && tar czf "$OUT.tar.gz" "$(basename "$OUT")" && ls -la "$OUT.tar.gz"
