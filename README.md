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
| `tools/make-deb.sh` | Packs `output/` as `dist/spaghettikart-vero_<version>_armhf.deb` (run by `build.sh`) |
| `tools/make-source-archive.py` | Packs sources and mirrors of all dependencies for offline builds |
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

2. **Build image.** The `Dockerfile` here builds the compiler environment: `debian:bullseye-slim` with the
   armhf cross compiler (gcc 10.2.1, the same as on the Vero), CMake, and the sysroot from step 1. It holds no
   game sources; `build.sh` mounts them when it runs. Build it once (it only needs the tarball, `docker/` and
   the toolchain file; see `.dockerignore`):

   ```sh
   docker build --network host -t spaghettikart-vero-build .
   ```

3. **Sources.** Clone SpaghettiKart into `source/SpaghettiKart` and check out the commit the patches are made
   for, which `patches/BASE` names. The submodules then come at the matching commits (libultraship at the
   one in `patches/BASE` as well):

   ```sh
   git clone https://github.com/HarbourMasters/SpaghettiKart source/SpaghettiKart
   git -C source/SpaghettiKart checkout "$(awk '$1 == "SpaghettiKart" { print $2 }' patches/BASE)"
   git -C source/SpaghettiKart submodule update --init --recursive libultraship torch
   ```

   `build.sh` does not check out anything itself. On a different commit, e.g. a newer upstream `main`, it
   stops with an error; `./build.sh --force` tries to apply the patches anyway, which may fail or need
   changes to the patches.

4. **Build.** `build.sh` runs everything in the build image: it checks the sources against `patches/BASE`,
   applies the patches, cross-compiles the game, packs its resources, and collects the result in `output/`
   and as a Debian package in `dist/`.

   ```sh
   ./build.sh
   ```

   `output/` then holds:
   - `Spaghettify`, the game (stripped; debug info in `Spaghettify.debug`). `Spaghettify.deps.txt` lists the
     libraries it needs; it finds the Mali driver through its RUNPATH `/opt/vero3/lib`.
   - `spaghetti.o2r`, the port's own resources: shaders, fonts and menu graphics.
   - `config.yml`, `yamls/` and `meta/`, the extraction recipes for making `mk64.o2r` from a ROM.
   - the launcher files from `vero/`, and the Kodi add-on in `kodi/`.

   `dist/spaghettikart-vero_<version>_armhf.deb` holds the same as a Debian package.

The game data `mk64.o2r` is not built here. `spaghetti.o2r` cannot replace it: the game's textures, models,
tracks and sounds all come from `mk64.o2r`, which you generate from your own ROM. Copy it to the Vero (see
below).

## Installing on the Vero

The game data `mk64.o2r` goes into `~/spaghettikart`, which also holds the settings, saves, logs and
`spaghettikart.conf`; the launcher creates the folder on first start. Without `mk64.o2r` the launcher does not
start the game.

```sh
scp mk64.o2r osmc@<vero>:spaghettikart/
```

Runtime packages on the Vero: `libsdl2-2.0-0` (the mali build), `libzip4`, `libtinyxml2-8`, `libspdlog1`,
`libfmt7`, `libasound2`, `libudev1` and the OSMC Vero userland with the Mali driver. The `-dev` packages are
only needed for the sysroot.

### Debian package

The package installs the program to `/opt/spaghettikart` and depends on the runtime packages, apart from the
Mali driver, which no Debian package provides:

```sh
scp dist/spaghettikart-vero_*_armhf.deb osmc@<vero>:
ssh osmc@<vero> 'sudo apt install ./spaghettikart-vero_*_armhf.deb'
```

Uninstall with `sudo apt remove spaghettikart-vero`; `~/spaghettikart` stays.

Moving from a manual install to the package: the game prefers files in `~/spaghettikart` over the installed
ones, so delete the program files there and keep `mk64.o2r`, `spaghettify.cfg.json`, the `.sav` files, `logs/`
and `spaghettikart.conf`:

```sh
cd ~/spaghettikart && rm -rf Spaghettify Spaghettify.debug Spaghettify.deps.txt spaghetti.o2r config.yml \
    yamls meta gamecontrollerdb.txt spaghettikart-*.sh spaghettikart-asound.conf kodi
```

The launcher log warns when a leftover `spaghetti.o2r` or `gamecontrollerdb.txt` is in use.

### Manual install

After building copy output to one directory `~/spaghettikart` on vero:

```sh
rsync -av --exclude build.log output/ osmc@<vero>:spaghettikart/
```

## Starting from Kodi

### Kodi launcher add-on

The add-on `script.launch.spaghettikart` puts SpaghettiKart into Kodi's **Games** and **Programs** menus. It
starts `/opt/spaghettikart/spaghettikart-launch.sh` if the package is installed, otherwise
`~/spaghettikart/spaghettikart-launch.sh`.

Install it from its zip with *Settings → Add-ons → Install from zip file* (needs *Settings → System → Add-ons →
Unknown sources*); Kodi then enables it itself. The package installs the zip as
`/opt/spaghettikart/kodi/script.launch.spaghettikart.zip`; a manual install has it in
`~/spaghettikart/kodi/`.

Alternatively copy the add-on folder into Kodi's add-ons:

```sh
rsync -av output/kodi/script.launch.spaghettikart osmc@<vero>:.kodi/addons/
ssh osmc@<vero> 'sudo systemctl restart mediacenter'
```

Kodi 21 registers add-ons copied in by hand but keeps them disabled, and disabled add-ons do not appear in the
menus: enable it under *Add-ons → My add-ons → Disabled add-ons → SpaghettiKart → Enable*.

Its icon (`icon.png`, 512×512) is the top of `banner.jpg`, which serves as the poster. If the game cannot be
started, the add-on shows the launcher's message as a notification.

### Launcher script details

- `spaghettikart-launch.sh` runs as the calling user (from Kodi, or over SSH as `osmc`, without sudo). It first
  checks for `~/spaghettikart/mk64.o2r`: without it the game would offer to extract the data from a ROM, which
  needs dialogs the Vero cannot show, and quit. Kodi then keeps running. Otherwise it starts a transient systemd
  unit and returns: anything Kodi starts would be killed together with Kodi. The unit's `ExecStopPost` restarts
  Kodi even if the game crashes. It needs passwordless `sudo` for `systemd-run`, which OSMC's `osmc` user has.
- `spaghettikart-run.sh` runs in that unit as root. It stops Kodi, sets HDMI to 1080p60 (other modes stayed
  black), and runs the game as the calling user with the `input` group added, so that controllers can be
  read without a login session. The program files are next to the script, the data in `~/spaghettikart`.
- Sound goes exclusively to `hdmi:CARD=AMLMESONAUDIO,DEV=0`, converted to 48 kHz by `spaghettikart-asound.conf`
  (loaded through `ALSA_CONFIG_PATH`). TVs stay silent at the game's own 26800 Hz, and ALSA's default device
  goes through PulseAudio, which the unit cannot reach.

Logs: `~/spaghettikart/logs/launcher.log` and `~/spaghettikart/logs/Spaghetti Kart.log`.

### Local settings

Settings in `~/spaghettikart/spaghettikart.conf` (shell syntax) survive updates of the scripts:

| Setting | Default | Meaning |
| --- | --- | --- |
| `AUDIODEV` | `spaghettikart` | ALSA device; `plug:dmix` glitches more |
| `DISPLAY_MODE` | `1080p60hz` | HDMI mode set before the game starts |
| `AUDIO_SAMPLES` | `1024` | SDL audio device buffer; 512 underruns on the Vero |
| `FRAME_STATS` | `0` | `1` logs fps and audio queue levels every 5 s |
| `XPAD_IDS` | `2dc8:310a` | USB gamepads (`vendor:product`, space-separated) handed to the `xpad` driver |

## Game controls

### Gamepad controllers

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
- `gamecontrollerdb.txt` is the [SDL controller database](https://github.com/mdqinc/SDL_GameControllerDB):
  SDL 2.0.20 predates controllers such as the 8BitDo Ultimate 2C.
- With `gControllers.AutoAssignPorts` set to `1`, the n-th gamepad drives player n (see
  [Game settings](#game-settings)).
- To have the gamepad recognized from boot (in Kodi's game add-ons and other emulators too), load `xpad` at boot
  and add the ID whenever the module loads:
  ```sh
  echo xpad | sudo tee /etc/modules-load.d/xpad.conf
  echo 'install xpad /sbin/modprobe --ignore-install xpad $CMDLINE_OPTS && echo 2dc8 310a > /sys/bus/usb/drivers/xpad/new_id' \
      | sudo tee /etc/modprobe.d/xpad-8bitdo.conf
  ```
  After a reboot, `cat /sys/bus/usb/drivers/xpad/new_id` lists `2dc8 310a` and the gamepad appears as soon as the
  controller connects. The launcher's own step then does nothing. To undo, delete the two files.
  Use this step instead of adding the IDs to `XPAD_IDS` of spaghettikart if you want to use the controller also
  in other games on vero.

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

## Game settings

The Mali-450 cannot hold 30 fps in races at 1080p on the Vero 4K+. Recommended values in `spaghettify.cfg.json` (under `CVars`),
set with the game closed:

| CVar | Value | Why |
| --- | --- | --- |
| `gInternalResolution` | `0.75` | Renders 1440×810 and scales up; 1.0 costs about 15–20 % fps |
| `gTextureFilter` | `1` | Linear filtering; the N64-style 3-point filter needs several texture reads per pixel |
| `gMSAAValue` | `1` | 4× works on the Mali (GL_EXT_multisampled_render_to_texture), but costs 1–2 fps for little visible gain |
| `gControllers.AutoAssignPorts` | `1` | The n-th gamepad drives player n; otherwise all gamepads drive player 1 |
| `gControlNav` | `1` | The gamepad's Back/Select button opens the game menu, operated with D-pad and A (settings, and a power button to quit) |
| `gQuitComboSeconds` | `1` (default) | Holding Start + Back/Select this long quits the game; `0` turns it off |

You may easily set values from the shell with python. For example, to open the menu with the gamepad:

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
- `stb_image.h` is downloaded only once, and a failed download stops the build

**SpaghettiKart**
- GLES2 versions of the game's shader templates
- Yes/No prompts answer Yes when SDL cannot show a message box (instead of exiting)
- Extra audio updates when the game runs below 30 fps; `SPAGHETTIKART_AUDIO_SAMPLES` and
  `SPAGHETTIKART_FRAME_STATS` environment variables
- Quitting with Start + Back/Select held (`gQuitComboSeconds`); the menu toggle no longer repeats while a button
  is held
- `sse2neon.h` pinned to a commit instead of `master`; it and `semver.hpp` are downloaded only once, and a failed
  download stops the build (CMake otherwise leaves an empty file and carries on)

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

## Building in years to come

Everything the build depends on is pinned: the upstream commits in `patches/BASE` and the submodule commits they
record, the FetchContent tags and commits in upstream's CMake files, the `debian:bullseye-slim` image by digest,
CMake 3.27.9, and Debian bullseye from `archive.debian.org`, which does not change any more. What can still
disappear are the repositories on GitHub and the Debian archive. Two things guard against that:

**Source archive.** After a successful `./build.sh`:

```sh
tools/make-source-archive.py      # writes spaghettikart-vero-src-YYYYMMDD.tar.gz (about 70 MiB)
```

It holds this folder's committed files, SpaghettiKart, libultraship and Torch at their base commits (shallow
git repositories; SpaghettiKart back to its last tag, for the version string), `mirrors/` with a minimal copy
of every repository CMake clones during the build, and `downloads/` with the single headers it downloads.
`build.sh` redirects the clones to the mirrors (`mirrors/gitconfig`) and seeds the headers. To build from it:

```sh
tar -xzf spaghettikart-vero-src-YYYYMMDD.tar.gz && cd spaghettikart-vero
cp /path/to/vero-armhf-sysroot.tar.gz .
docker build --network host -t spaghettikart-vero-build .     # or docker load, see below
./build.sh --offline
```

`--offline` runs the build container without network, which proves nothing is fetched.

**Build image.** `docker build` still downloads Debian packages and CMake. Keep the finished image:

```sh
docker save spaghettikart-vero-build | gzip > spaghettikart-vero-build-image.tar.gz
docker load < spaghettikart-vero-build-image.tar.gz
```

**The Vero side.** The sysroot tarball needs a Vero with OSMC's bullseye userland. Keep a copy of
`vero-armhf-sysroot.tar.gz` along with the image.

**What may be shared.** The source archive holds only code that is public on GitHub, each part under its own
licence, plus this folder; no game data and no Vero files. The build image and the sysroot contain the Vero's
libraries, including OSMC's proprietary Mali driver: keep them private. `output/` holds the game binary and
the port's own `spaghetti.o2r`, but no Mali driver and no game data. `mk64.o2r` and the ROM are never
shared; everybody makes their own.
