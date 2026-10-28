#!/bin/bash
# Runs SpaghettiKart with Kodi stopped and restarts Kodi when the game exits or crashes.
# Started as root by spaghettikart-launch.sh; the game itself runs as GAME_USER (default: osmc).
# Output goes to logs/launcher.log next to the game; the game's own log is "logs/Spaghetti Kart.log".
set -u

DIR="$(cd "$(dirname "$0")" && pwd)"
if [ "$(id -u)" -ne 0 ]; then
    echo "Start SpaghettiKart with spaghettikart-launch.sh (this script must run as root)." >&2
    exit 1
fi
GAME_USER="${GAME_USER:-osmc}"
# Optional local settings (AUDIODEV=..., DISPLAY_MODE=...), kept across updates of this script.
if [ -f "$DIR/spaghettikart.conf" ]; then
    # shellcheck source=/dev/null
    . "$DIR/spaghettikart.conf"
fi
GAME_HOME="$(getent passwd "$GAME_USER" | cut -d: -f6)"
# ALSA's "default" device on OSMC goes through PulseAudio, which the game cannot reach from this
# service (no user session). Play to the HDMI output exclusively, converted to 48 kHz ("spaghettikart",
# defined in spaghettikart-asound.conf); MPD and Raspotify cannot play while the game runs. To share the
# output with them instead, set AUDIODEV=plug:dmix (glitches more often in races).
AUDIODEV="${AUDIODEV:-spaghettikart}"
# Kodi can leave the HDMI output in a mode the TV does not show (seen: 480p60hz, black screen), and the game
# just uses whatever mode it finds. Kodi sets its own mode again when it restarts.
DISPLAY_MODE="${DISPLAY_MODE:-1080p60hz}"
# Audio device buffer in samples at 26800 Hz (game default 512 = 19 ms underruns on the Vero; 1024 = 38 ms).
AUDIO_SAMPLES="${AUDIO_SAMPLES:-1024}"
# FRAME_STATS=1 logs fps and audio queue levels every 5 s to "logs/Spaghetti Kart.log" (for tuning).
FRAME_STATS="${FRAME_STATS:-0}"
# USB gamepads (vendor:product) the kernel's xpad driver should take on. The Vero's 4.9 kernel does not know
# the 8BitDo Ultimate 2C dongle; without xpad only its keyboard/mouse interface works (enough for Kodi, not for
# the game).
XPAD_IDS="${XPAD_IDS:-2dc8:310a}"

install -d -o "$GAME_USER" -g "$(id -gn "$GAME_USER")" "$DIR/logs"
exec >"$DIR/logs/launcher.log" 2>&1
echo "=== $(date '+%F %T') launching SpaghettiKart as $GAME_USER"

restart_kodi() {
    echo "=== $(date '+%F %T') starting mediacenter"
    systemctl start mediacenter
}
trap restart_kodi EXIT
trap 'exit 143' TERM INT HUP

systemctl stop mediacenter
# Give the Mali driver, framebuffer and input devices a moment to be released.
for _ in $(seq 1 20); do
    pgrep -x kodi.bin >/dev/null || break
    sleep 0.5
done

mode="$(cat /sys/class/display/mode)"
if [ "$mode" != "$DISPLAY_MODE" ]; then
    echo "display mode: $mode -> $DISPLAY_MODE"
    echo "$DISPLAY_MODE" >/sys/class/display/mode
else
    echo "display mode: $mode"
fi

cd "$DIR" || exit 1
# If the audio device cannot be opened once, the game saves the silent "null" backend and stays silent after
# the device is fixed; always start with SDL audio.
[ -f spaghettify.cfg.json ] && runuser -u "$GAME_USER" -- sed -i 's/"AudioBackend": "null"/"AudioBackend": "sdl"/' spaghettify.cfg.json
echo "audio device: $AUDIODEV, buffer $AUDIO_SAMPLES samples; pulseaudio: $(pgrep -a pulseaudio || echo 'not running')"
# Teach xpad the IDs (lasts until reboot; an ID it already has is refused, which is fine). Dongles connected
# now are probed at once, later ones when they appear.
if modprobe xpad; then
    for id in $XPAD_IDS; do
        echo "${id%:*} ${id#*:}" >/sys/bus/usb/drivers/xpad/new_id 2>/dev/null && echo "xpad: added $id"
    done
fi
# Controllers are read from /dev/input/event*, which only the "input" group may open; Kodi gets access through
# its login session, the game does not have one. Run with the user's groups plus "input" (runuser -G
# replaces the group list, and without -g the first -G group would become the primary group).
supp_groups=()
for g in $(id -Gn "$GAME_USER") input; do
    getent group "$g" >/dev/null && supp_groups+=(-G "$g")
done
echo "groups: ${supp_groups[*]}; controllers: $(grep -h '^N: Name=' /proc/bus/input/devices | cut -d'"' -f2 | paste -sd, -)"
# SHIP_HOME keeps config, saves, mods/ and logs/ in the game folder regardless of the working directory.
runuser -u "$GAME_USER" -g "$(id -gn "$GAME_USER")" "${supp_groups[@]}" -- env \
    HOME="$GAME_HOME" \
    SHIP_HOME="$DIR" \
    SDL_VIDEODRIVER=mali \
    SDL_AUDIODRIVER=alsa \
    AUDIODEV="$AUDIODEV" \
    SPAGHETTIKART_AUDIO_SAMPLES="$AUDIO_SAMPLES" \
    SPAGHETTIKART_FRAME_STATS="$FRAME_STATS" \
    ALSA_CONFIG_PATH="$DIR/spaghettikart-asound.conf" \
    ./Spaghettify
echo "=== $(date '+%F %T') game exited with status $?"
