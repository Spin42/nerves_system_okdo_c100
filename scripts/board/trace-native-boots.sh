#!/usr/bin/env bash
set -euo pipefail
board=${C100_BOARD:-192.168.0.31}
count=${1:?boot count required}
label=${2:?unique series label required}
marker=FIRMWARE_UUID=${3:?expected firmware UUID required}
[[ "$count" =~ ^[1-9][0-9]*$ ]] || { printf 'Boot count must be positive\n'; exit 2; }
[[ "$3" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]] || { printf 'Invalid firmware UUID\n'; exit 2; }
scratch=${C100_BOOT_LOG_DIR:-/tmp/c100-boots}
script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
mkdir -p "$scratch"
mkdir "$scratch/$label"
for (( n=1; n<=count; n++ )); do
  state=$(timeout 15 ssh -o BatchMode=yes -o LogLevel=ERROR -o ConnectTimeout=5 "$board" 'kv = Nerves.Runtime.KV.get_all(); IO.puts("VALIDATED=" <> kv["nerves_fw_validated"]); IO.puts("BOOT_ID=" <> String.trim(File.read!("/proc/sys/kernel/random/boot_id"))); :ok')
  grep -q 'VALIDATED=1' <<< "$state" || { printf 'Refusing reboot of unvalidated slot\n'; exit 2; }
  old_boot=$(sed -n 's/^BOOT_ID=//p' <<< "$state" | tr -d '\r')
  [[ -n "$old_boot" ]] || exit 2
  printf 'Reboot %d/%d from %s\n' "$n" "$count" "$old_boot"
  timeout 15 ssh -o BatchMode=yes -o LogLevel=ERROR -o ConnectTimeout=5 "$board" 'Nerves.Runtime.reboot()' > "$scratch/$label/reboot-$n.log" 2>&1 || true
  sleep 10
  bash "$script_dir/observe-native-boot.sh" "$old_boot" "$scratch/$label/boot-$n.log" "$marker"
done
