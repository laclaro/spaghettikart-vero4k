# SpaghettiKart for the Vero 4K+

Cross-build and Kodi launcher for [SpaghettiKart](https://github.com/HarbourMasters/SpaghettiKart) on a
Vero 4K+ running OSMC:

- Amlogic S905D, arm64 kernel (`4.9.269-62-osmc`) with a 32-bit **armhf** userspace (Debian bullseye: glibc 2.31,
  libstdc++ 10.2.1)
- **Mali-450** GPU: OpenGL ES 2.0 / GLSL ES 1.00 only, driver in `/opt/vero3/lib`
- SDL 2.0.20+1mali (mali-fbdev video, no message boxes)

Upstream needs OpenGL 3 or GLES 3, so the game and its engine (libultraship) are patched for GLES 2.0 and for
the Vero's slow GPU.

## Layout

| Path | Contents |
| --- | --- |
| `Dockerfile`, `docker/`, `toolchain/vero-armhf.cmake` | Build image: bullseye cross compiler (gcc 10.2.1) with the Vero's own libraries as sysroot |
| `build.sh` | Applies `patches/`, configures and builds in the image, collects everything in `output/` |
| `patches/` | The Vero changes as patch series, generated from the `vero4k` branches; `BASE` names the upstream commits they apply to |
| `vero/` | Files installed next to the game on the Vero: launcher, ALSA config, controller mappings, Kodi add-on |
| `tools/shadercheck/` | Validates the GLES2 shader templates with glslang |
| `tools/update-patches.sh` | Regenerates `patches/` and `patches/BASE` from the `vero4k` branches |
| `source/SpaghettiKart` | Upstream checkout (not tracked here), with `vero4k` branches in it and in `libultraship` |

## Building

1. **Sysroot from the Vero.** Install the build dependencies on the Vero (`libsdl2-dev`, `libzip-dev`,
   `libtinyxml2-dev`, `libspdlog-dev`, `nlohmann-json3-dev`, `libpng-dev`, `libgles-dev`, `libegl-dev`, …),
   then pack its libraries and headers:

   ```sh
   sudo tar --numeric-owner -czf ~/vero-armhf-sysroot.tar.gz -C / \
       lib/ld-linux-armhf.so.3 lib/arm-linux-gnueabihf \
       usr/include usr/lib/arm-linux-gnueabihf opt/vero3/lib
   ```

   Copy `vero-armhf-sysroot.tar.gz` into this folder.

2. **Build image** (needs only the tarball, `docker/` and the toolchain file; see `.dockerignore`):

   ```sh
   docker build --network host -t spaghettikart-vero-build .
   ```

3. **Sources.** Clone SpaghettiKart with submodules into `source/SpaghettiKart`. Either check out its `vero4k`
   branch (and `vero4k` in `libultraship`), or stay on upstream `main` and let `build.sh` apply `patches/`.

4. **Build:**

   ```sh
   ./build.sh
   ```

   `output/` then holds the stripped `Spaghettify` (debug info in `Spaghettify.debug`), `spaghetti.o2r`,
   `config.yml`, `yamls/`, `meta/` and the files from `vero/`. `Spaghettify.deps.txt` lists the needed
   libraries; the binary finds the Mali driver through its RUNPATH `/opt/vero3/lib`.

The game data `mk64.o2r` is not built here. Generate it from your own ROM and copy it to the Vero.

## Installing on the Vero

```sh
rsync -av --exclude build.log output/ osmc@<vero>:spaghettikart/
scp mk64.o2r osmc@<vero>:spaghettikart/
```

Runtime packages on the Vero: `libsdl2-2.0-0` (the mali build), `libzip4`, `libtinyxml2-8`, `libspdlog1`,
`libfmt7`, `libasound2`, `libudev1` and the OSMC Vero userland with the Mali driver. The `-dev` packages are
only needed for the sysroot.

## Starting from Kodi

The add-on in `vero/kodi/script.launch.spaghettikart` (copied to `output/kodi/`) puts SpaghettiKart into Kodi's
**Games** and **Programs** menus. Install it once:

```sh
rsync -av output/kodi/script.launch.spaghettikart osmc@<vero>:.kodi/addons/
ssh osmc@<vero> 'sudo systemctl restart mediacenter'
```

Kodi 21 registers add-ons copied in by hand but keeps them disabled, and disabled add-ons do not appear in the
menus: enable it under *Add-ons → My add-ons → Disabled add-ons → SpaghettiKart → Enable*. Alternatively install
`output/kodi/script.launch.spaghettikart.zip` with *Settings → Add-ons → Install from zip file* (needs *Settings → System →
Add-ons → Unknown sources*); Kodi then enables it itself. Its icon (`icon.png`, 512×512) is the top of
`banner.jpg`, which serves as the poster.

Alternatively point a Kodi favourite (`System.Exec`) or a launcher add-on at
`~/spaghettikart/spaghettikart-launch.sh`, or run it over SSH as `osmc`, without sudo. It needs passwordless
`sudo` for `systemd-run`, which OSMC's `osmc` user has.

- `spaghettikart-launch.sh` starts a transient systemd unit and returns. Anything Kodi starts would be killed
  together with Kodi; the unit's `ExecStopPost` restarts Kodi even if the game crashes.
- `spaghettikart-run.sh` runs in that unit as root. It stops Kodi, sets HDMI to 1080p60 (other modes stayed
  black), and runs the game as the calling user with the `input` group added, so that controllers can be
  read without a login session.
- Sound goes exclusively to `hdmi:CARD=AMLMESONAUDIO,DEV=0`, converted to 48 kHz by `spaghettikart-asound.conf`
  (loaded through `ALSA_CONFIG_PATH`). TVs stay silent at the game's own 26800 Hz, and ALSA's default device
  goes through PulseAudio, which the unit cannot reach.
- `gamecontrollerdb.txt` is the [SDL controller database](https://github.com/mdqinc/SDL_GameControllerDB):
  SDL 2.0.20 predates controllers such as the 8BitDo Ultimate 2C.
- Tested controllers: two 8BitDo Ultimate 2C Wireless on their 2.4 GHz dongles (USB `2dc8:310a`). The Vero's
  kernel `4.9.269-62-osmc` has the `xpad` module (Xbox 360 protocol) but does not know this dongle, so only its
  keyboard/mouse interface works out of the box: enough for Kodi, not for the game. The launcher therefore loads
  `xpad` and adds the IDs in `XPAD_IDS` to it, the same as
  ```sh
  sudo modprobe xpad
  echo 2dc8 310a | sudo tee /sys/bus/usb/drivers/xpad/new_id
  ```
  This lasts until reboot. The dongle then has two input devices: interface 0 is the gamepad, named
  "Generic X-Box pad" (handlers `js0`, `eventN`); interface 1, named "8BitDo 8BitDo Ultimate 2C Wireless
  Controller", is the keyboard/mouse device. Check with `grep -B1 -A5 -iE "x-box|8bitdo" /proc/bus/input/devices`.
  Without a connected controller the dongle reports itself as `8BitDo IDLE` (USB `2dc8:301c`) and creates no
  gamepad.
- The game reads the gamepad from `/dev/input/event*`, which needs the `input` group (added by the launcher).
- To have the gamepad recognized from boot (in Kodi's game add-ons and other emulators too), load `xpad` at boot
  and add the ID whenever the module loads:
  ```sh
  echo xpad | sudo tee /etc/modules-load.d/xpad.conf
  echo 'install xpad /sbin/modprobe --ignore-install xpad $CMDLINE_OPTS && echo 2dc8 310a > /sys/bus/usb/drivers/xpad/new_id' \
      | sudo tee /etc/modprobe.d/xpad-8bitdo.conf
  ```
  After a reboot, `cat /sys/bus/usb/drivers/xpad/new_id` lists `2dc8 310a` and the gamepad appears as soon as the
  controller connects. The launcher's own step then does nothing. To undo, delete the two files.

Logs: `~/spaghettikart/logs/launcher.log` and `~/spaghettikart/logs/Spaghetti Kart.log`.

### Quitting the game

Hold **Start + Back/Select** on any gamepad for one second (on the 8BitDo Ultimate 2C, Back/Select is the small
left button in the middle). The game exits, and the launcher's systemd unit restarts Kodi within a few seconds.
`gQuitComboSeconds` sets the hold time; `0` turns the combo off.

The game itself has no quit option. The other way out is the port's settings menu, which the gamepad can only open
with `gControlNav` set to `1` (see [Game settings](#game-settings)):

1. Press **Back/Select**. The settings menu opens over the game; the same button closes it.
2. Move with the **D-pad** to the red **power button** at the top right of the menu header and press **A**.

Pressing Back/Select while Start is held does not open the menu, so the combo does not flash it. With a keyboard,
Esc opens and closes the menu. If the game hangs, stop it over SSH with `sudo systemctl stop spaghettikart`; Kodi
restarts as well.

### Local settings

Settings in `~/spaghettikart/spaghettikart.conf` (shell syntax) survive updates of the scripts:

| Setting | Default | Meaning |
| --- | --- | --- |
| `AUDIODEV` | `spaghettikart` | ALSA device; `plug:dmix` glitches more |
| `DISPLAY_MODE` | `1080p60hz` | HDMI mode set before the game starts |
| `AUDIO_SAMPLES` | `1024` | SDL audio device buffer; 512 underruns on the Vero |
| `FRAME_STATS` | `0` | `1` logs fps and audio queue levels every 5 s |
| `XPAD_IDS` | `2dc8:310a` | USB gamepads (`vendor:product`, space-separated) handed to the `xpad` driver |

## Game settings

The Mali-450 cannot hold 30 fps in races at 1080p. Recommended values in `spaghettify.cfg.json` (under `CVars`),
set with the game closed:

| CVar | Value | Why |
| --- | --- | --- |
| `gInternalResolution` | `0.75` | Renders 1440×810 and scales up; 1.0 costs about 15–20 % fps |
| `gTextureFilter` | `1` | Linear filtering; the N64-style 3-point filter needs several texture reads per pixel |
| `gMSAAValue` | `1` | 4× works on the Mali (GL_EXT_multisampled_render_to_texture), but costs 1–2 fps for little visible gain |
| `gControllers.AutoAssignPorts` | `1` | The n-th gamepad drives player n; otherwise all gamepads drive player 1 |
| `gControlNav` | `1` | The gamepad's Back/Select button opens the game menu, operated with D-pad and A (settings, and a power button to quit) |
| `gQuitComboSeconds` | `1` (default) | Holding Start + Back/Select this long quits the game; `0` turns it off |

For example, to open the menu with the gamepad:

```sh
cd ~/spaghettikart && python3 - <<'EOF'
import json; p='spaghettify.cfg.json'; c=json.load(open(p))
c.setdefault('CVars',{})['gControlNav']=1
json.dump(c,open(p,'w'),indent=4)
EOF
```

Most of these can also be changed in the game's settings menu. The game rewrites the file when it exits, so edit it
only while the game is not running.

Races run at about 17–21 fps. Sound stays continuous anyway, because the game generates extra audio when its
queue runs low.

## What the patches change

**libultraship**
- OpenGL ES 2.0 renderer (`USE_OPENGLES2`): GLSL ES 1.00 shaders, unsized texture formats, packed depth/stencil,
  no VAOs or depth readback, framebuffer copies as textured quads instead of `glBlitFramebuffer`
- MSAA through `GL_EXT_multisampled_render_to_texture` where available
- Diagnostics for silent GLES2 failures (framebuffer status, GL errors, render target changes)
- `gControllers.AutoAssignPorts`, and `libdl` linked on all platforms (glibc < 2.34)

**SpaghettiKart**
- GLES2 versions of the game's shader templates
- Yes/No prompts answer Yes when SDL cannot show a message box (instead of exiting)
- Extra audio updates when the game runs below 30 fps; `SPAGHETTIKART_AUDIO_SAMPLES` and
  `SPAGHETTIKART_FRAME_STATS` environment variables

`patches/BASE` names the upstream commits the series apply to (SpaghettiKart, and the libultraship commit it
pins). `build.sh` checks the checkout first: at exactly those commits it applies the patches, a branch containing
them (such as `vero4k`) is built as it is, anything else stops with an error. `./build.sh --force` tries to apply
the patches anyway, e.g. on a newer upstream. To build from scratch:

```sh
git clone --recurse-submodules https://github.com/HarbourMasters/SpaghettiKart source/SpaghettiKart
git -C source/SpaghettiKart checkout <SpaghettiKart commit from patches/BASE>
git -C source/SpaghettiKart submodule update --init --recursive
./build.sh
```

After changing the `vero4k` branches, regenerate `patches/` and `patches/BASE`:

```sh
tools/update-patches.sh
```

When applying the series by hand with `git am`, use `--keep-cr`: the shader templates have CRLF line endings.

## Checking the shaders

```sh
tools/shadercheck/check-shaders.sh        # after ./build.sh; expands 400 configurations per template
```
