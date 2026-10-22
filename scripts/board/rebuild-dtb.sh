#!/usr/bin/env bash
# Rebuild the kernel and the system after a change in linux/, then the
# application firmware.
set -euo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/env.sh"
cd "$artifact"
make linux-rebuild > "$log_dir/linux-rebuild.log" 2>&1
make > "$log_dir/system-build.log" 2>&1
ls -la --time-style=+%H:%M images/*.dtb
bash "$script_dir/build-app.sh" | tail -1
