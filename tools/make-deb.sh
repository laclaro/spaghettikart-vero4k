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
NAME=spaghettikart-vero
PREFIX=/opt/spaghettikart

# Version: upstream's tag and commit (as in the game's own version string), then the number of commits in this
# folder as Debian revision, so that changes to the launcher alone also give a newer package.
describe="$(git -C "$ROOT/source/SpaghettiKart" describe --tags)"   # e.g. 1.0.0-64-g7246554d4
upstream="$(echo "$describe" | sed -E 's/^v//; s/-([0-9]+)-g([0-9a-f]+)$/+\1.g\2/')"
revision="$(git -C "$ROOT" rev-list --count HEAD 2>/dev/null || echo 1)"
VERSION="$upstream-$revision"

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
chmod -R u=rwX,go=rX "$pkg"
chmod 755 "$pkg$PREFIX/Spaghettify" "$pkg$PREFIX/spaghettikart-launch.sh" "$pkg$PREFIX/spaghettikart-run.sh"

# libGLESv2 is the Mali driver from OSMC's Vero userland (/opt/vero3/lib), not a Debian package. SDL 2.0.20 is
# OSMC's mali build; Debian bullseye's own SDL (2.0.14) has no mali video driver.
cat >"$pkg/DEBIAN/control" <<EOF
Package: $NAME
Version: $VERSION
Architecture: armhf
Maintainer: spaghettikart-cross <noreply@localhost>
Installed-Size: $(du -sk "$pkg$PREFIX" | cut -f1)
Depends: libc6 (>= 2.31), libstdc++6 (>= 10), libgcc-s1, libsdl2-2.0-0 (>= 2.0.20), libzip4, libtinyxml2-8,
 libspdlog1, libfmt7, libasound2, sudo, systemd, util-linux, kmod
Section: games
Priority: optional
Homepage: https://github.com/HarbourMasters/SpaghettiKart
Description: SpaghettiKart (Mario Kart 64 PC port) for the Vero 4K+
 Built for OSMC on the Vero 4K+ (armhf, Mali-450, OpenGL ES 2.0), started from
 Kodi: the launcher stops Kodi while the game runs and restarts it afterwards.
 .
 Installs to $PREFIX. The game data (mk64.o2r, made from your own ROM) is not
 included; copy it to ~/spaghettikart. Install the Kodi add-on from
 $PREFIX/kodi/script.launch.spaghettikart.zip.
EOF

mkdir -p "$DIST"
deb="$DIST/${NAME}_${VERSION}_armhf.deb"
dpkg-deb --root-owner-group -Zxz --build "$pkg" "$deb" >/dev/null
echo "package: $deb"
