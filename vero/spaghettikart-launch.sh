#!/bin/sh
# Entry point for Kodi launcher add-ons, Kodi favourites (System.Exec) or an SSH shell.
#
# Anything Kodi starts lives in mediacenter.service's cgroup and would be killed when Kodi is
# stopped, so the real work is handed to a transient systemd unit and this script returns at once.
# ExecStopPost restarts Kodi even if the runner itself is killed.
set -eu

DIR="$(cd "$(dirname "$0")" && pwd)"
UNIT=spaghettikart

if systemctl is-active --quiet "$UNIT"; then
    echo "SpaghettiKart is already running" >&2
    exit 0
fi

# Clear a failed instance from an earlier run so the unit name can be reused.
sudo -n systemctl reset-failed "$UNIT" 2>/dev/null || true

exec sudo -n systemd-run \
    --unit="$UNIT" \
    --collect \
    --description="SpaghettiKart (Kodi stopped)" \
    --property=ExecStopPost="/bin/systemctl start mediacenter" \
    --setenv=GAME_USER="$(id -un)" \
    "$DIR/spaghettikart-run.sh"
