#!/bin/bash
# Show the EMC (DRAM) clock state on L4T. Run as root.
mount | grep -q debugfs || mount -t debugfs none /sys/kernel/debug
echo "clk emc rate: $(cat /sys/kernel/debug/clk/emc/clk_rate)"
for f in /sys/kernel/debug/tegra_bwmgr/*; do
	[ -f "$f" ] && echo "== $f" && head -c 1500 "$f"
done
for f in /sys/kernel/debug/tegra_emc/*; do
	[ -f "$f" ] && echo "== $f" && head -c 1500 "$f"
done
