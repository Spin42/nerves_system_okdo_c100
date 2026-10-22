#!/usr/bin/env bash
# Rebuild, upload, confirm the new firmware, then trace N boots.
set -uo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/env.sh"
bash "$script_dir/rebuild-dtb.sh" || exit 1
bash "$script_dir/wait-upload.sh"
bash "$script_dir/confirm-fw.sh"
rm -f "$log_dir"/boot-*.log
bash "$script_dir/trace-boots.sh" "${1:-10}"
grep -h "c100-limits: pll\|GPCPLL\|gr: init failed\|cannot initialize" "$log_dir"/boot-*.log | cut -c1-160
