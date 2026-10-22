#!/usr/bin/env bash
# Wait for the board after an upload and print the active slot, its validation
# and the live device-tree values that identify the firmware under test.
set -euo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/env.sh"
sleep 60
wait_board 30 || { echo "board not reachable"; exit 1; }
sleep 20
timeout 30 ssh -o BatchMode=yes -o LogLevel=ERROR "$board" '
kv = Nerves.Runtime.KV.get_all()
IO.puts("active #{kv["nerves_fw_active"]}, validated #{kv["nerves_fw_validated"]}")
for f <- Path.wildcard("/proc/device-tree/thermal-sensor@700e2000/throttle-cfgs/oc*/nvidia,gpu-throt-level"),
  do: IO.puts("#{f}: #{:binary.decode_unsigned(File.read!(f))}")
:ok' 2>&1
