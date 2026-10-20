#!/bin/bash
# Run vkpeak on L4T with default clocks and with jetson_clocks, recording
# tegrastats alongside. Run as the normal user; uses sudo for clocks.
set -u
PASS=${1:?password}
V=$HOME/vkpeak/build/vkpeak
OUT=/tmp/vkpeak-results
rm -rf $OUT && mkdir -p $OUT

run() { # run <label>
	# Clocks and power are only reported to root
	echo "$PASS" | sudo -S tegrastats --interval 500 --logfile $OUT/tegrastats-$1.txt --start 2>/dev/null
	$V 0 > $OUT/vkpeak-$1.txt 2>&1
	echo "$PASS" | sudo -S tegrastats --stop 2>/dev/null
}

run default
echo "$PASS" | sudo -S jetson_clocks --store /tmp/jetson_clocks.conf 2>/dev/null
echo "$PASS" | sudo -S jetson_clocks 2>/dev/null
echo "$PASS" | sudo -S jetson_clocks --show > $OUT/jetson_clocks-max.txt 2>/dev/null
run max
echo "$PASS" | sudo -S jetson_clocks --restore /tmp/jetson_clocks.conf 2>/dev/null
tar czf $OUT.tar.gz -C /tmp vkpeak-results && ls -la $OUT.tar.gz
