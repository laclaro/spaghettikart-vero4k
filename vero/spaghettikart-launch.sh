#!/bin/sh
# Entry point for Kodi launcher add-ons, Kodi favourites (System.Exec) or an SSH shell.
#
# Anything Kodi starts lives in mediacenter.service's cgroup and would be killed when Kodi is
# stopped, so the real work is handed to a transient systemd unit and this script returns at once.
# ExecStopPost restarts Kodi even if the runner itself is killed.
set -eu

DIR="$(cd "$(dirname "$0")" && pwd)"
UNIT=spaghettikart
# Settings, saves, logs and the game data; see spaghettikart-run.sh.
DATA_DIR="${DATA_DIR:-$HOME/spaghettikart}"

# Without its data the game would ask to extract it from a ROM, which needs dialogs the Vero cannot show,
# and quit at once. Check here, while Kodi still runs and can show the message.
if [ ! -f "$DATA_DIR/mk64.o2r" ]; then
    echo "Game data missing: copy mk64.o2r to $DATA_DIR" >&2
    exit 1
fi

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
    --setenv=DATA_DIR="$DATA_DIR" \
    "$DIR/spaghettikart-run.sh"
