# SpaghettiKart for the Vero 4K+

Cross-build and Kodi launcher for [SpaghettiKart](https://github.com/HarbourMasters/SpaghettiKart) on a
Vero 4K+ running OSMC:

- Amlogic S905D, arm64 kernel with a 32-bit **armhf** userspace (Debian bullseye: glibc 2.31, libstdc++ 10.2.1)
- **Mali-450** GPU: OpenGL ES 2.0 / GLSL ES 1.00 only, driver in `/opt/vero3/lib`
- SDL 2.0.20+1mali (mali-fbdev video, no message boxes)

Upstream needs OpenGL 3 or GLES 3, so the game and its engine (libultraship) are patched for GLES 2.0 and for
the Vero's slow GPU.

## Layout

| Path | Contents |
| --- | --- |
| `Dockerfile`, `docker/`, `toolchain/vero-armhf.cmake` | Build image: bullseye cross compiler (gcc 10.2.1) with the Vero's own libraries as sysroot |
| `build.sh` | Applies `patches/`, configures and builds in the image, collects everything in `output/` |
| `patches/` | The Vero changes as patch series, generated from the `vero4k` branches |
| `vero/` | Files installed next to the game on the Vero: launcher, ALSA config, controller mappings |
| `tools/shadercheck/` | Validates the GLES2 shader templates with glslang |
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

Point a Kodi launcher add-on or favourite (`System.Exec`) at `~/spaghettikart/spaghettikart-launch.sh`, or run
it over SSH as `osmc`, without sudo. It needs passwordless `sudo` for `systemd-run`, which OSMC's `osmc` user
has.

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

Logs: `~/spaghettikart/logs/launcher.log` and `~/spaghettikart/logs/Spaghetti Kart.log`.

### Local settings

Settings in `~/spaghettikart/spaghettikart.conf` (shell syntax) survive updates of the scripts:

| Setting | Default | Meaning |
| --- | --- | --- |
| `AUDIODEV` | `spaghettikart` | ALSA device; `plug:dmix` shares the output with MPD and Raspotify, but glitches more |
| `DISPLAY_MODE` | `1080p60hz` | HDMI mode set before the game starts |
| `AUDIO_SAMPLES` | `1024` | SDL audio device buffer; 512 underruns on the Vero |
| `FRAME_STATS` | `0` | `1` logs fps and audio queue levels every 5 s |

## Game settings

The Mali-450 cannot hold 30 fps in races at 1080p. Recommended values in `spaghettify.cfg.json` (under `CVars`),
set with the game closed:

| CVar | Value | Why |
| --- | --- | --- |
| `gInternalResolution` | `0.75` | Renders 1440×810 and scales up; 1.0 costs about 15–20 % fps |
| `gTextureFilter` | `1` | Linear filtering; the N64-style 3-point filter needs several texture reads per pixel |
| `gMSAAValue` | `1` | 4× works on the Mali (GL_EXT_multisampled_render_to_texture), but costs 1–2 fps for little visible gain |
| `gControllers.AutoAssignPorts` | `1` | The n-th gamepad drives player n; otherwise all gamepads drive player 1 |

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

To regenerate `patches/` after changing the `vero4k` branches:

```sh
git -C source/SpaghettiKart format-patch -o "$PWD/patches/SpaghettiKart" origin/main..vero4k -- . ':(exclude)libultraship'
git -C source/SpaghettiKart/libultraship format-patch -o "$PWD/patches/libultraship" <upstream-commit>..vero4k
```

Remove the old patch files first. The libultraship series starts at the submodule commit pinned by upstream
`main` (currently `60c9bb71`). When applying the series with `git am`, use `--keep-cr`: the shader templates
have CRLF line endings.

## Checking the shaders

```sh
tools/shadercheck/check-shaders.sh        # after ./build.sh; expands 400 configurations per template
```
