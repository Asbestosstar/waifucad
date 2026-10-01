#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT"
. ./build/compiler.sh
DC_BIN=$(pick_compiler)
DC_KIND=$(compiler_kind "$DC_BIN")
CC_BIN=$(pick_c_compiler)
SHIM_OBJS=$(betterc_shim_objects "$DC_KIND" build/obj)
FLAGS=$(betterc_flags "$DC_KIND")
mkdir -p build/obj build/tests

eval "$(detect_libm)"
if [ "$WC_HAVE_LIBM" != 1 ]; then
    echo "libm is required but no link spelling worked on this host." >&2
    exit 2
fi
# shellcheck disable=SC2086
LIBM_D_FLAGS=$(d_link_flags "$DC_KIND" $LIBM_RAW)

# The searcher lives behind the common GUI front-end, so the test links the
# same COMMON list as the real targets (extracted from build.sh to stay in
# sync) plus the front-end module itself.
COMMON=$(sed -n "/^COMMON='/,/' *$/p" build.sh | grep '\.d' | sed "s/^COMMON='//" | tr -d "'")

# frontends/common/frontend.d references the temp-file and job-pool C shims
# that build.sh normally compiles; rebuild them here like build.sh does.
if [ ! -f build/obj/wc_threads.o ]; then
    THREAD_IMPL=${WC_THREAD_IMPL:-auto}
    case "$THREAD_IMPL" in
        auto|posix)
            "$CC_BIN" -std=c11 -Wall -Wextra -fPIC \
                -Inative/threads -c native/threads/wc_threads_posix.c -o build/obj/wc_threads.o
            ;;
        single)
            "$CC_BIN" -std=c11 -Wall -Wextra -fPIC \
                -Inative/threads -c native/threads/wc_threads_single.c -o build/obj/wc_threads.o
            ;;
    esac
fi
if [ ! -f build/obj/wc_temp.o ]; then
    "$CC_BIN" -std=c11 -Wall -Wextra \
        -Inative/files -c native/files/wc_temp_posix.c -o build/obj/wc_temp.o
fi

# shellcheck disable=SC2086
case "$DC_KIND" in
    ldc|dmd)
        "$DC_BIN" $FLAGS $COMMON \
            src/waifucad/gui/frontends/common/frontend.d \
            tests/ribbon_search.d \
            build/obj/wc_threads.o build/obj/wc_temp.o $SHIM_OBJS \
            $LIBM_D_FLAGS -of=build/tests/ribbon_search
        ;;
    gdc)
        "$DC_BIN" $FLAGS $COMMON \
            src/waifucad/gui/frontends/common/frontend.d \
            tests/ribbon_search.d \
            build/obj/wc_threads.o build/obj/wc_temp.o \
            $LIBM_RAW -o build/tests/ribbon_search
        ;;
esac
./build/tests/ribbon_search
printf 'Ribbon search test passed.\n'
