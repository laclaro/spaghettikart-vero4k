#!/bin/sh
# Makes the Vero sysroot usable from the build host. Runs inside the image only.
# usage: prepare-sysroot.sh <sysroot> <dir with extra cmake package configs>
set -eu

S="$1"
EXTRA_CMAKE="$2"
ARCHLIB="$S/usr/lib/arm-linux-gnueabihf"

# Absolute symlinks (e.g. usr/lib/.../libm.so -> /lib/.../libm.so.6) would point into
# the build host's filesystem. Re-target them inside the sysroot as relative links.
find "$S" -type l -lname '/*' | while read -r link; do
    ln -sfnr "$S$(readlink "$link")" "$link"
done

# The Vero's SDL2 (RetroPie 2.0.20+1mali build) ships an autotools-generated config
# with a hard-coded prefix of /usr.
sed -i 's|^set(prefix "/usr")|set(prefix "${CMAKE_SYSROOT}/usr")|' \
    "$ARCHLIB/cmake/SDL2/sdl2-config.cmake"

# libzip's package config verifies its tools exist, but usr/bin is not part of the
# sysroot tarball. They are never run (they are armhf binaries anyway), so stubs suffice.
mkdir -p "$S/usr/bin"
for tool in zipcmp zipmerge ziptool; do
    [ -e "$S/usr/bin/$tool" ] || touch "$S/usr/bin/$tool"
done

# Bullseye's tinyxml2 has no CMake package, and nlohmann_json's lives in
# /usr/lib/cmake (not part of the sysroot tarball).
cp -r "$EXTRA_CMAKE"/* "$ARCHLIB/cmake/"

# Sanity checks for what the build relies on.
for f in \
    "$S/lib/ld-linux-armhf.so.3" \
    "$ARCHLIB/libc.so" \
    "$ARCHLIB/libSDL2.so" \
    "$ARCHLIB/libtinyxml2.so" \
    "$S/usr/include/nlohmann/json.hpp" \
    "$S/opt/vero3/lib/libGLESv2.so" \
    "$S/opt/vero3/lib/libEGL.so" \
    "$S/opt/vero3/lib/libMali.so"
do
    [ -e "$f" ] || { echo "prepare-sysroot: missing $f" >&2; exit 1; }
done
echo "prepare-sysroot: ok"
