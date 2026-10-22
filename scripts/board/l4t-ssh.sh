#!/usr/bin/env bash
# Run a command on the board's L4T installation, when the user has booted it.
# The password comes from SSHPASS; the L4T host key is kept apart from the
# Nerves one because both systems answer on the same address.
set -euo pipefail
board=${C100_BOARD:-192.168.0.31}
user=${C100_L4T_USER:-marc}
exec sshpass -e ssh -o UserKnownHostsFile="${C100_L4T_KNOWN_HOSTS:-/tmp/c100-l4t-known-hosts}" \
  -o StrictHostKeyChecking=accept-new -o LogLevel=ERROR -o ConnectTimeout=8 "$user@$board" "$@"
