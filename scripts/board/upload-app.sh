#!/usr/bin/env bash
# Upload the application firmware to the board's inactive slot and reboot into it.
set -euo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/env.sh"
cd "$app_dir"
export MIX_TARGET=okdo_c100
mix upload "$board" 2>&1 | tail -8
