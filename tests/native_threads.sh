#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT"
. ./build/compiler.sh
CC_BIN=${CC:-cc}
# POSIX threads are optional: probe first (glibc 2.34+ needs no flags at
# all); explicit THREAD_CFLAGS/THREAD_LDFLAGS overrides keep working.
if [ -n "${THREAD_CFLAGS:-}" ] || [ -n "${THREAD_LDFLAGS:-}" ]; then
    THREAD_CFLAGS_VALUE=${THREAD_CFLAGS:-}
    THREAD_LDFLAGS_VALUE=${THREAD_LDFLAGS:-}
else
    eval "$(detect_posix_threads)"
    if [ "$WC_HAVE_PTHREAD" != 1 ]; then
        printf 'POSIX threads unavailable on this host; skipping native thread pool test.\n'
        exit 0
    fi
    THREAD_CFLAGS_VALUE=$PTHREAD_CFLAGS_RAW
    THREAD_LDFLAGS_VALUE=$PTHREAD_LDFLAGS_RAW
fi
mkdir -p build/obj
# shellcheck disable=SC2086
"$CC_BIN" $THREAD_CFLAGS_VALUE -std=c11 -Wall -Wextra -pedantic \
    -Inative/threads native/threads/wc_threads_posix.c tests/thread_pool_c.c \
    $THREAD_LDFLAGS_VALUE -o build/obj/thread_pool_test
./build/obj/thread_pool_test
