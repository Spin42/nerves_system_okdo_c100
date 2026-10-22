# Shared settings for the board scripts; sourced, not executed.
script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
repo_dir=$(cd -- "$script_dir/../.." && pwd)
board=${C100_BOARD:-192.168.0.31}
app_dir=${C100_APP_DIR:-$repo_dir/../hello_c100}
artifact=${C100_SYSTEM_ARTIFACT:-$repo_dir/.nerves/artifacts/nerves_system_okdo_c100-portable-0.1.0}
log_dir=${C100_BOOT_LOG_DIR:-/tmp/c100-boots}
mkdir -p "$log_dir"
ssh_board() { ssh -o BatchMode=yes -o LogLevel=ERROR -o ConnectTimeout=5 "$board" "$@"; }
wait_board() {
  local i
  for i in $(seq 1 "${1:-60}"); do
    timeout 6 ssh -o BatchMode=yes -o LogLevel=ERROR -o ConnectTimeout=4 "$board" ':ok' > /dev/null 2>&1 && return 0
    sleep 5
  done
  return 1
}
