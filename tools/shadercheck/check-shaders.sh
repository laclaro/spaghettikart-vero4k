#!/bin/sh
# Validates the GLES2 (GLSL ES 1.00) expansion of SpaghettiKart's OpenGL shader templates.
# Expands both copies of default.shader.glsl (the game's assets/ copy, which is what runs, and libultraship's) for
# COUNT colour-combiner configurations with the prism engine, then checks each with glslangValidator.
# Runs in a throwaway container from the build image; needs a configured build/vero (for prism's sources).
# usage: tools/shadercheck/check-shaders.sh [count]   (default 400)
set -eu

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
COUNT="${1:-400}"
IMAGE="${IMAGE:-spaghettikart-vero-build}"
OUT="$ROOT/build/shadercheck"
GL="$ROOT/source/SpaghettiKart/libultraship/src/fast/backends/gfx_opengl.cpp"

[ -d "$ROOT/build/vero/_deps/prism-src" ] || { echo "run ./build.sh first (prism is fetched at configure time)" >&2; exit 1; }

# The combiner formula code is taken from the current renderer so the check never drifts from it.
rm -rf "$OUT" && mkdir -p "$OUT"
sed -n '/^#define RAND_NOISE/,/^std::optional<std::string> opengl_include_fs/p' "$GL" | sed '$d' > "$OUT/formula.inc"

docker run --rm --network host \
    -v "$HERE:/src:ro" -v "$OUT:/out" -v "$ROOT:/work:ro" \
    -e COUNT="$COUNT" -e HOST_IDS="$(id -u):$(id -g)" \
    "$IMAGE" \
    bash -euc '
        trap "chown -R \"$HOST_IDS\" /out" EXIT
        apt-get -o Acquire::Check-Valid-Until=false update -qq >/dev/null
        apt-get install -y -qq --no-install-recommends glslang-tools libspdlog-dev >/dev/null 2>&1
        P=/work/build/vero/_deps/prism-src/src
        g++ -std=c++20 -O1 -w -DSPDLOG_FMT_EXTERNAL -I$P -I/out -o /tmp/shadergen /src/shadergen.cpp \
            $P/prism/processor.cpp $P/prism/ast.cpp $P/prism/lexer.cpp $P/prism/utils/gv.cpp \
            -x c $P/prism/utils/invoke.c -lspdlog -lfmt
        status=0
        for t in game:/work/source/SpaghettiKart/assets/shaders/opengl \
                 libultraship:/work/source/SpaghettiKart/libultraship/src/fast/shaders/opengl; do
            name=${t%%:*}; dir=${t#*:}; d=/out/$name; mkdir -p $d
            /tmp/shadergen $dir/default.shader.glsl $d "$COUNT" >/dev/null
            fail=0
            for f in $d/*.vert $d/*.frag; do
                glslangValidator $f > $f.log 2>&1 || fail=$((fail + 1))
            done
            echo "$name: $(ls $d/*.vert | wc -l) shader pairs, glslang failures: $fail"
            [ $fail -eq 0 ] || status=1
        done
        [ $status -eq 0 ] || grep -h ERROR /out/*/*.log | sort | uniq -c | sort -rn | head -20
        exit $status
    '
