#!/bin/sh
# Packs the build in output/ as a Debian package for the Vero 4K+ (armhf), installed to /opt/spaghettikart.
# Called by build.sh inside the build container; works anywhere with dpkg-deb.
# usage: tools/make-deb.sh <output dir> <package dir>
#
# The package holds no game data: mk64.o2r goes into the user's data folder (~/spaghettikart), next to the
# settings, saves and logs, which the launcher creates on first start.
set -eu

OUT="$1"
DIST="$2"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/source/SpaghettiKart"
DEPS="$ROOT/build/vero/_deps"
NAME=spaghettikart-vero
PREFIX=/opt/spaghettikart

# Version: this folder's release tag, with the number of commits since it for builds between releases (1.0.0,
# 1.0.0+2.g1a2b3c4). A source archive has no git history and names its version in VERSION instead. Epoch 1:
# builds before the first release were numbered after SpaghettiKart's version (1.0.0+64.g7246554d4-N), which
# would otherwise sort above 1.0.0.
if ! release="$(git -C "$ROOT" describe --tags --match '[0-9]*' 2>/dev/null)"; then
    release="$(cat "$ROOT/VERSION" 2>/dev/null)" || { echo "make-deb.sh: no release tag and no VERSION file" >&2; exit 1; }
fi
release="$(echo "$release" | sed -E 's/-([0-9]+)-g([0-9a-f]+)$/+\1.g\2/')"
VERSION="1:$release"
GAME_VERSION="$(git -C "$SRC" describe --tags)"   # as in the game's own version string, e.g. 1.0.0-64-g7246554d4

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
pkg="$STAGE/pkg"
mkdir -p "$pkg$PREFIX" "$pkg/DEBIAN" "$pkg/usr/share/doc/$NAME"

for f in Spaghettify spaghetti.o2r config.yml gamecontrollerdb.txt \
    spaghettikart-launch.sh spaghettikart-run.sh spaghettikart-asound.conf; do
    cp "$OUT/$f" "$pkg$PREFIX/"
done
cp -r "$OUT/yamls" "$OUT/meta" "$pkg$PREFIX/"
mkdir "$pkg$PREFIX/kodi"
cp "$OUT/kodi/script.launch.spaghettikart.zip" "$pkg$PREFIX/kodi/"
gzip -9n -c "$ROOT/README.md" >"$pkg/usr/share/doc/$NAME/README.md.gz"

# The game includes code from these projects (compiled in, or as headers); their licences ask for the notices to
# accompany binary copies. The system libraries it links to (SDL, libzip, spdlog, fmt, tinyxml2) bring their own
# copyright files in their packages. A missing licence file stops the build, so a changed dependency is noticed.
notice() {   # notice <name> <url> <licence file> [sed range]
    [ -f "$3" ] || { echo "make-deb.sh: licence file missing: $3" >&2; exit 1; }
    printf '\n%s\n\n%s (%s)\n\n' "------------------------------------------------------------------------------" "$1" "$2"
    if [ $# -ge 4 ]; then sed -n "$4" "$3"; else cat "$3"; fi
}
{
    cat <<EOF
SpaghettiKart for the Vero 4K+

Built from SpaghettiKart (https://github.com/HarbourMasters/SpaghettiKart) with the
patches and launcher from https://github.com/laclaro/spaghettikart-vero4k.
SpaghettiKart's repository carries no licence file. The game data (mk64.o2r) is not
part of this package.

The controller mappings (gamecontrollerdb.txt) come from SDL_GameControllerDB
(https://github.com/mdqinc/SDL_GameControllerDB), under the zlib licence.

Third-party code in the game:
EOF
    notice libultraship https://github.com/Kenix3/libultraship "$SRC/libultraship/LICENSE"
    notice Torch https://github.com/HarbourMasters/Torch "$SRC/torch/LICENSE"
    notice "Dear ImGui" https://github.com/ocornut/imgui "$DEPS/imgui-src/LICENSE.txt"
    notice yaml-cpp https://github.com/jbeder/yaml-cpp "$DEPS/yaml-cpp-src/LICENSE"
    notice prism https://github.com/KiritoDv/prism-processor "$DEPS/prism-src/LICENSE"
    notice thread-pool https://github.com/bshoshany/thread-pool "$DEPS/threadpool-src/LICENSE.txt"
    notice toml++ https://github.com/marzer/tomlplusplus "$DEPS/tomlplusplus-src/LICENSE"
    notice Monocypher https://github.com/LoupVaillant/Monocypher "$DEPS/monocypher-src/LICENCE.md"
    notice dr_libs https://github.com/mackron/dr_libs "$DEPS/dr_libs-src/LICENSE"
    notice tinyxml2 https://github.com/leethomason/tinyxml2 "$DEPS/tinyxml2-src/LICENSE.txt"
    notice stb_image https://github.com/nothings/stb "$DEPS/stb/stb_image.h" '/^This software is available under/,/^ALTERNATIVE B/{/^ALTERNATIVE B/!p}'
    notice sse2neon https://github.com/DLTcollab/sse2neon "$DEPS/sse2neon/sse2neon.h" '/freely redistributable/,/SOFTWARE\./p'
    notice semver https://github.com/Neargye/semver "$DEPS/semver/semver.hpp" '/Licensed under the MIT/,/SOFTWARE\./p'
} >"$pkg/usr/share/doc/$NAME/copyright"
chmod -R u=rwX,go=rX "$pkg"
chmod 755 "$pkg$PREFIX/Spaghettify" "$pkg$PREFIX/spaghettikart-launch.sh" "$pkg$PREFIX/spaghettikart-run.sh"

# libGLESv2 is the Mali driver from OSMC's Vero userland (/opt/vero3/lib), not a Debian package. SDL 2.0.20 is
# OSMC's mali build; Debian bullseye's own SDL (2.0.14) has no mali video driver.
cat >"$pkg/DEBIAN/control" <<EOF
Package: $NAME
Version: $VERSION
Architecture: armhf
Maintainer: Henning Hollermann <laclaro@mail.com>
Installed-Size: $(du -sk "$pkg$PREFIX" | cut -f1)
Depends: libc6 (>= 2.31), libstdc++6 (>= 10), libgcc-s1, libsdl2-2.0-0 (>= 2.0.20), libzip4, libtinyxml2-8,
 libspdlog1, libfmt7, libasound2, sudo, systemd, util-linux, kmod
Section: games
Priority: optional
Homepage: https://github.com/HarbourMasters/SpaghettiKart
Description: SpaghettiKart (Mario Kart 64 PC port) for the Vero 4K+
 Built for OSMC on the Vero 4K+ (armhf, Mali-450, OpenGL ES 2.0), started from
 Kodi: the launcher stops Kodi while the game runs and restarts it afterwards.
 SpaghettiKart version: $GAME_VERSION.
 .
 Installs to $PREFIX. The game data (mk64.o2r, made from your own ROM) is not
 included; copy it to ~/spaghettikart. Install the Kodi add-on from
 $PREFIX/kodi/script.launch.spaghettikart.zip.
EOF

mkdir -p "$DIST"
deb="$DIST/${NAME}_${release}_armhf.deb"   # file names leave out the epoch
dpkg-deb --root-owner-group -Zxz --build "$pkg" "$deb" >/dev/null
echo "package: $deb"
