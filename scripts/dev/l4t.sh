#!/bin/bash
# Run a command on the L4T install over SSH with password auth.
# Usage: L4T_HOST=192.168.0.31 L4T_PASS=... scripts/dev/l4t.sh <command...>
#        scripts/dev/l4t.sh --put <local> <remote> | --get <remote> <local>
set -euo pipefail
HOST=${L4T_HOST:-192.168.0.31}
USER_=${L4T_USER:-marc}
export SSHPASS=${L4T_PASS:?set L4T_PASS}
OPTS=(-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR
      -o PreferredAuthentications=password -o PubkeyAuthentication=no)
case "${1:-}" in
	--put) sshpass -e scp "${OPTS[@]}" "$2" "$USER_@$HOST:$3" ;;
	--get) sshpass -e scp "${OPTS[@]}" "$USER_@$HOST:$2" "$3" ;;
	*) sshpass -e ssh "${OPTS[@]}" "$USER_@$HOST" "$@" ;;
esac
