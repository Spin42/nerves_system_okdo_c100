#!/usr/bin/env bash
# Build the application firmware for the C100 without burning it.
set -euo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/env.sh"
cd "$app_dir"
export MIX_TARGET=okdo_c100
mix deps.get > /dev/null
mix firmware 2>&1 | tail -5
ls -la --time-style=+%m-%d_%H:%M _build/okdo_c100_dev/nerves/images/*.fw
