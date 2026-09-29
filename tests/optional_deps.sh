#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT"
. ./build/compiler.sh
CC_BIN=$(pick_c_compiler)

# Every third-party dependency is optional: the build must succeed with the
# stub GPU probe and the single-threaded scheduler, and the batch binary must
# still run (screenshots included) on such a host.

# Detectors must print eval-able assignments and probe libm successfully on
# any supported host (libm is the one dependency we always require).
eval "$(detect_libm)"
[ "$WC_HAVE_LIBM" = 1 ]

eval "$(detect_libdl)"
case "$WC_HAVE_DLOPEN" in 0|1) ;; *) echo 'WC_HAVE_DLOPEN not 0/1' >&2; exit 1 ;; esac

eval "$(detect_posix_threads)"
case "$WC_HAVE_PTHREAD" in 0|1) ;; *) echo 'WC_HAVE_PTHREAD not 0/1' >&2; exit 1 ;; esac

# Minimal-deps build: no dynamic loading, no POSIX threads.
rm -f bin/waifucad-batch
WC_GPU_PROBE_IMPL=stub WC_THREAD_IMPL=single ./build.sh batch
[ -x bin/waifucad-batch ]
./bin/waifucad-batch --command 'box(:deps_box, 4, 3, 2)' --dump-model \
    | grep -q 'deps_box.*brep=exact'

# PNG output must not depend on zlib either (stored deflate, in-tree writer).
mkdir -p build/tests
./bin/waifucad-batch --command 'box(:deps_png, 4, 3, 2)' \
    --screenshot build/tests/optional_deps.png --size 128x96 > /dev/null
python3 tests/png_validate.py build/tests/optional_deps.png

# Forcing dlopen on a host without dynamic loading support must be a clear
# build error, not a confusing linker failure. (Skipped when the host can
# link dlopen; the point is the guard exists.)
if [ "$WC_HAVE_DLOPEN" != 1 ]; then
    if WC_GPU_PROBE_IMPL=dlopen ./build.sh batch > /dev/null 2>&1; then
        echo 'WC_GPU_PROBE_IMPL=dlopen succeeded without dlopen support' >&2
        exit 1
    fi
fi

# Restore the default (auto) build for the rest of the test battery.
./build.sh batch
printf 'Optional dependency test passed.\n'
