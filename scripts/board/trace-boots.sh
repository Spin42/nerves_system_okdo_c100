#!/usr/bin/env bash
# Reboot N times, open a first Vulkan channel and save each boot's nouveau
# kernel log.
# A boot is ok when the first Vulkan channel opened; the first failed boot
# rejects the configuration under test.
set -uo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/env.sh"
N=${1:-5}
for n in $(seq 1 "$N"); do
  timeout 15 ssh -o BatchMode=yes -o LogLevel=ERROR "$board" 'Nerves.Runtime.reboot()' > /dev/null 2>&1
  sleep 45
  wait_board 30
  timeout 30 ssh -o BatchMode=yes -o LogLevel=ERROR "$board" '{_, rc} = System.cmd("vulkaninfo", ["--summary"], env: [{"NVK_I_WANT_A_BROKEN_VULKAN_DRIVER", "1"}], stderr_to_stdout: true); IO.puts(if rc == 0, do: "first channel open", else: "first channel failed"); {d, _} = System.cmd("dmesg", []); d |> String.split("\n") |> Enum.filter(&(&1 =~ ~r/nouveau|Kernel command line/)) |> Enum.join("\n") |> IO.puts(); :ok' > "$log_dir/boot-$n.log" 2>&1
  outcome=$(grep -c "first channel open" "$log_dir/boot-$n.log")
  echo "boot $n: $( [ "$outcome" -gt 0 ] && echo ok || echo FAILED ), $(wc -l < "$log_dir/boot-$n.log") nouveau lines"
  [ "$outcome" -gt 0 ] || exit 1
done
