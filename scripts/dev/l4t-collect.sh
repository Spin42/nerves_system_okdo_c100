#!/bin/bash
# Collect reference information from NVIDIA L4T (R32) on a Jetson Nano.
# Read-only except for files under $OUT. Run as root on the board:
#   sudo bash l4t-collect.sh /tmp/l4t-intel
set -u
OUT=${1:-/tmp/l4t-intel}
rm -rf "$OUT" && mkdir -p "$OUT"
cd "$OUT" || exit 1

run() { # run <file> <command...>
	local f=$1; shift
	{ echo "\$ $*"; "$@"; } > "$f" 2>&1
}

mount | grep -q debugfs || mount -t debugfs none /sys/kernel/debug

# Software
run versions.txt sh -c 'uname -a; cat /etc/nv_tegra_release; cat /etc/os-release; cat /proc/cmdline'
run packages.txt sh -c "dpkg -l | grep -iE 'nvidia|cuda|cudnn|tensorrt|vulkan|vpi|visionworks|opencv|libnv'"
run vulkan-icd.txt sh -c 'ls -la /etc/vulkan/icd.d /usr/share/vulkan/icd.d 2>&1; cat /etc/vulkan/icd.d/*.json /usr/share/vulkan/icd.d/*.json 2>/dev/null; command -v vulkaninfo'
run cuda.txt sh -c 'ls -la /usr/local | grep -i cuda; ls /usr/local/cuda/samples 2>&1 | head; /usr/local/cuda/bin/nvcc --version 2>&1'
command -v vulkaninfo > /dev/null && vulkaninfo > vulkaninfo.txt 2>&1

# Power mode and clocks
run nvpmodel.txt sh -c 'nvpmodel -q --verbose; cat /etc/nvpmodel.conf'
run jetson_clocks.txt jetson_clocks --show
run gpu-devfreq.txt sh -c 'for f in /sys/devices/57000000.gpu/devfreq/57000000.gpu/*; do [ -f "$f" ] && echo "$f: $(cat "$f" 2>&1)"; done'
run gpu-sysfs.txt sh -c 'for f in /sys/devices/57000000.gpu/*; do [ -f "$f" ] && [ -r "$f" ] && echo "$f: $(head -c 400 "$f" 2>&1 | tr "\n" " ")"; done'
run clk-summary.txt cat /sys/kernel/debug/clk/clk_summary
run clk-rates.txt sh -c 'for c in gbus gpu emc sclk cpu cclk_g host1x vic03 nvenc nvdec nvjpg; do d=/sys/kernel/debug/clk/$c; [ -d "$d" ] && echo "$c rate=$(cat $d/clk_rate 2>/dev/null) max=$(cat $d/clk_max_rate 2>/dev/null)"; done; ls /sys/kernel/debug/clk | head -400'
run emc.txt sh -c 'ls /sys/kernel/debug/tegra_emc 2>&1; for f in /sys/kernel/debug/tegra_emc/*; do [ -f "$f" ] && echo "== $f" && head -c 2000 "$f"; done; cat /sys/kernel/debug/bwmgr/bwmgr 2>&1'

# Power rails
run power-rails.txt sh -c 'for d in /sys/bus/i2c/drivers/ina3221x/*/iio:device*; do for f in "$d"/rail_name_* "$d"/in_power*_input "$d"/in_current*_input "$d"/in_voltage*_input; do [ -f "$f" ] && echo "$f: $(cat "$f")"; done; done'
timeout 6 tegrastats --interval 1000 > tegrastats.txt 2>&1

# Hardware state
mkdir -p devicetree && cp -r /proc/device-tree/. devicetree/ 2>/dev/null
command -v dtc > /dev/null && dtc -q -I fs -O dts /proc/device-tree > live.dts 2>&1
run gpio.txt cat /sys/kernel/debug/gpio
run pinctrl.txt sh -c 'for f in /sys/kernel/debug/pinctrl/*/pinconf-groups /sys/kernel/debug/pinctrl/*/pinmux-pins; do echo "== $f"; cat "$f"; done; cat /sys/kernel/debug/tegra_pinctrl_reg 2>/dev/null'
run regulators.txt sh -c 'cat /sys/kernel/debug/regulator/regulator_summary 2>/dev/null || ls /sys/class/regulator'
run iomem.txt cat /proc/iomem
run interrupts.txt cat /proc/interrupts
run modules.txt lsmod
run firmware.txt sh -c 'find /lib/firmware -iname "*gm20b*" -o -iname "*tegra21x*" -o -iname "*xusb*" | xargs -r ls -la; find /lib/firmware \( -path "*gm20b*" -o -path "*tegra21x*" \) -type f -exec sha256sum {} +'
run usb-pci.txt sh -c 'lsusb; lspci -nnk'
run net.txt sh -c 'ip -br addr; ip -br link'
run dmesg.txt dmesg
run cpuinfo.txt sh -c 'cat /proc/cpuinfo; cat /proc/meminfo'

cd .. && tar czf "$OUT.tar.gz" "$(basename "$OUT")" && ls -la "$OUT.tar.gz"
