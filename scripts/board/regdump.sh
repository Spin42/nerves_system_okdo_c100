#!/usr/bin/env bash
# Build regread for the board, copy it over and dump GPU and SoC registers.
# Usage: regdump.sh <label>
set -euo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/env.sh"
label=${1:?label required}
[ -f "$log_dir/regread" ] || "$artifact/host/bin/aarch64-nerves-linux-gnu-gcc" -O2 -static -o "$log_dir/regread" "$script_dir/regread.c"
printf 'put %s /root/regread\n' "$log_dir/regread" | sftp -q -o BatchMode=yes -o LogLevel=ERROR -b - "$board" > /dev/null
# Host side first (BOOT0, PMC_ENABLE), then GPU clocks/therm, PRI timeout
# latch, SoC CAR/PMC, MC hot-reset and error state
REGS="0x57000000 0x57000200 0x57009080 0x57009084 0x57009088 0x57137000 0x57137004 0x57137100 0x57137250 0x57137010 0x57137014 0x57020160 0x57020200 0x60006280 0x6000628c 0x7000e6d4 0x70019970 0x70019974 0x70019000 0x70019008 0x7001900c 0x70019010 0x70019aac"
timeout 40 ssh -o BatchMode=yes -o LogLevel=ERROR "$board" "File.chmod!(\"/root/regread\", 0o755); {o, rc} = System.cmd(\"/root/regread\", ~w($REGS), stderr_to_stdout: true); IO.puts(o); IO.puts(\"rc #{rc}\"); {d, _} = System.cmd(\"dmesg\", []); IO.puts(d |> String.split(\"\\n\") |> Enum.filter(&(&1 =~ ~r/gr: init failed|first channel open/)) |> Enum.join(\"\\n\")); :ok" > "$log_dir/regdump-$label.txt" 2>&1
cat "$log_dir/regdump-$label.txt"
