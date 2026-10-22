#!/usr/bin/env bash
# Reboot N times and save each boot's nouveau and c100-limits kernel log. Drops the EMC and GPU clocks before each reboot to test state carried over a warm reboot.
# A boot is ok when the first Vulkan channel opened; the first failed boot
# rejects the configuration under test.
set -uo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/env.sh"
N=${1:-5}
for n in $(seq 1 "$N"); do
  timeout 15 ssh -o BatchMode=yes -o LogLevel=ERROR "$board" 'File.write("/sys/kernel/debug/emc/min_rate", "204000000"); File.write("/sys/class/devfreq/57000000.gpu/max_freq", "76800000"); Process.sleep(1000); Nerves.Runtime.reboot()' > /dev/null 2>&1
  sleep 45
  wait_board 30
  sleep 20
  timeout 30 ssh -o BatchMode=yes -o LogLevel=ERROR "$board" '{d, _} = System.cmd("dmesg", []); d |> String.split("\n") |> Enum.filter(&(&1 =~ ~r/nouveau|c100-limits|Kernel command line/)) |> Enum.join("\n") |> IO.puts(); :ok' > "$log_dir/boot-$n.log" 2>&1
  outcome=$(grep -c "first channel open" "$log_dir/boot-$n.log")
  echo "boot $n: $( [ "$outcome" -gt 0 ] && echo ok || echo FAILED ), $(wc -l < "$log_dir/boot-$n.log") nouveau lines"
  [ "$outcome" -gt 0 ] || exit 1
done
