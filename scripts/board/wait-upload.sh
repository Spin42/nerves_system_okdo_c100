#!/usr/bin/env bash
# Wait until the board answers SSH, then upload the application firmware.
set -euo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/env.sh"
wait_board || { echo "board not reachable"; exit 1; }
bash "$script_dir/upload-app.sh" 2>&1 | tr '\r' '\n' | grep -E "Upgrading|Success|rror" | head -5
