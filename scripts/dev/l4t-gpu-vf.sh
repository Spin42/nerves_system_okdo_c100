#!/bin/bash
# Measure NVIDIA's GPU voltage at each devfreq step on L4T (R32). Changes
# only runtime sysfs settings and restores them at the end. Run as root.
set -u
DF=/sys/devices/57000000.gpu/devfreq/57000000.gpu
G=/sys/devices/57000000.gpu
DBG=/sys/kernel/debug/57000000.gpu
mount | grep -q debugfs || mount -t debugfs none /sys/kernel/debug

old_gov=$(cat $DF/governor)
old_min=$(cat $DF/min_freq)
old_max=$(cat $DF/max_freq)
old_rg=$(cat $G/railgate_enable)

echo 0 > $G/railgate_enable
echo userspace > $DF/governor
printf "%10s %10s %8s\n" "req_hz" "rate_hz" "mV"
for f in $(cat $DF/available_frequencies); do
	echo "$f" > $DF/max_freq
	echo "$f" > $DF/min_freq
	echo "$f" > $DF/userspace/set_freq 2>/dev/null
	sleep 0.3
	printf "%10s %10s %8s\n" "$f" "$(cat $DF/cur_freq)" "$(cat $DBG/voltage)"
done

echo "$old_min" > $DF/min_freq
echo "$old_max" > $DF/max_freq
echo "$old_gov" > $DF/governor
echo "$old_rg" > $G/railgate_enable
echo "restored: governor=$(cat $DF/governor) min=$(cat $DF/min_freq) max=$(cat $DF/max_freq) railgate=$(cat $G/railgate_enable)"
