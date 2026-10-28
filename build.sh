#!/bin/sh
# Build SpaghettiKart for the Vero 4k+ (armhf, Mali-450 GLES 2.0) inside the spaghettikart-vero-build image.
# usage: ./build.sh [image]
# Build the image first: docker build --network host -t spaghettikart-vero-build .
set -eu

HERE="$(cd "$(dirname "$0")" && pwd)"
IMAGE="${1:-spaghettikart-vero-build}"

docker run --rm --network host \
    -u "$(id -u):$(id -g)" -e HOME=/tmp \
    -v "$HERE:/work" \
    -w /work \
    "$IMAGE" \
    bash -euo pipefail -c '
        SRC=/work/source/SpaghettiKart
        B=/work/build/vero
        OUT=/work/output

        # Local fixes for the 32-bit armhf / Mali GLES2 target, applied once (idempotent).
        for repo in SpaghettiKart libultraship; do
            [ "$repo" = SpaghettiKart ] && dir=$SRC || dir=$SRC/$repo
            for p in /work/patches/$repo/*.patch; do
                [ -e "$p" ] || continue
                if git -C "$dir" apply --reverse --check "$p" 2>/dev/null; then
                    echo "patch already applied: $p"
                else
                    git -C "$dir" apply "$p" && echo "patch applied: $p"
                fi
            done
        done

        cmake -S "$SRC" -B "$B" -GNinja \
            -DCMAKE_TOOLCHAIN_FILE=/opt/toolchain/vero-armhf.cmake \
            -DCMAKE_BUILD_TYPE=Release \
            -DUSE_OPENGLES=ON \
            -DUSE_OPENGLES2=ON
        cmake --build "$B" -j"$(nproc)" -- -k 0 2>&1 | tee "$OUT/build.log"
        # spaghetti.o2r carries the (GLES2-patched) shaders; it is packed by the host-built torch.
        cmake --build "$B" --target GenerateO2R 2>&1 | tee -a "$OUT/build.log"

        cp "$B/Spaghettify" "$B/spaghetti.o2r" "$SRC/config.yml" "$OUT/"
        cp -r "$SRC/yamls" "$SRC/meta" "$OUT/"
        cp /work/vero/spaghettikart-launch.sh /work/vero/spaghettikart-run.sh /work/vero/spaghettikart-asound.conf /work/vero/gamecontrollerdb.txt "$OUT/"
        # Ship a stripped binary; keep the debug info next to it for symbolising crashes.
        arm-linux-gnueabihf-objcopy --only-keep-debug "$OUT/Spaghettify" "$OUT/Spaghettify.debug"
        arm-linux-gnueabihf-strip --strip-all "$OUT/Spaghettify"
        arm-linux-gnueabihf-objcopy --add-gnu-debuglink="$OUT/Spaghettify.debug" "$OUT/Spaghettify"
        arm-linux-gnueabihf-readelf -d "$OUT/Spaghettify" | grep -E "NEEDED|RPATH|RUNPATH" > "$OUT/Spaghettify.deps.txt"
    '
