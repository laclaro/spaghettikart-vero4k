#!/bin/sh
# Regenerates patches/ from the vero4k branches in source/SpaghettiKart and its libultraship submodule, and records
# the upstream commits they apply to in patches/BASE (read by build.sh).
# usage: tools/update-patches.sh [spaghettikart-base]   (default: the merge base of vero4k and origin/main)
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SK="$ROOT/source/SpaghettiKart"
LUS="$SK/libultraship"
BRANCH=vero4k

SK_BASE="$(git -C "$SK" rev-parse "${1:-$(git -C "$SK" merge-base "$BRANCH" origin/main)}")"
# libultraship's base is the submodule commit that the SpaghettiKart base pins.
LUS_BASE="$(git -C "$SK" ls-tree "$SK_BASE" libultraship | awk '{print $3}')"
git -C "$LUS" merge-base --is-ancestor "$LUS_BASE" "$BRANCH" ||
    { echo "libultraship $BRANCH is not based on $LUS_BASE (pinned by SpaghettiKart $SK_BASE)" >&2; exit 1; }

rm -f "$ROOT"/patches/SpaghettiKart/*.patch "$ROOT"/patches/libultraship/*.patch
# The libultraship gitlink is left out: the libultraship series carries those changes.
git -C "$SK" format-patch -q -o "$ROOT/patches/SpaghettiKart" "$SK_BASE..$BRANCH" -- . ':(exclude)libultraship'
git -C "$LUS" format-patch -q -o "$ROOT/patches/libultraship" "$LUS_BASE..$BRANCH"

cat >"$ROOT/patches/BASE" <<END
# Upstream commits the patch series apply to (written by tools/update-patches.sh, checked by build.sh).
SpaghettiKart $SK_BASE https://github.com/HarbourMasters/SpaghettiKart
libultraship $LUS_BASE https://github.com/Kenix3/libultraship
END
echo "patches for SpaghettiKart $SK_BASE, libultraship $LUS_BASE:"
ls "$ROOT"/patches/*/
