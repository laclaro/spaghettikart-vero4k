# Starts SpaghettiKart through its launcher. The launcher hands the game to a systemd unit that stops Kodi,
# so it returns at once; Kodi is restarted by that unit when the game exits.
import os
import subprocess

import xbmcgui

LAUNCHER = os.path.expanduser("~/spaghettikart/spaghettikart-launch.sh")


def notify(message):
    xbmcgui.Dialog().notification("SpaghettiKart", message, xbmcgui.NOTIFICATION_ERROR, 8000)


if not os.access(LAUNCHER, os.X_OK):
    notify("Launcher not found: " + LAUNCHER)
else:
    try:
        result = subprocess.run([LAUNCHER], capture_output=True, text=True, timeout=30)
        if result.returncode != 0:
            notify((result.stderr or result.stdout).strip() or "Launcher failed ({})".format(result.returncode))
    except subprocess.TimeoutExpired:
        notify("Launcher did not return")
