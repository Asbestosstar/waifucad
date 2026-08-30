#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT"
CC_BIN=${CC:-cc}
THREAD_CFLAGS_VALUE=${THREAD_CFLAGS:--pthread}
THREAD_LDFLAGS_VALUE=${THREAD_LDFLAGS:--lpthread}
mkdir -p build/obj
# shellcheck disable=SC2086
"$CC_BIN" $THREAD_CFLAGS_VALUE -std=c11 -Wall -Wextra -pedantic \
    -Inative/threads native/threads/wc_threads_posix.c tests/thread_pool_c.c \
    $THREAD_LDFLAGS_VALUE -o build/obj/thread_pool_test
./build/obj/thread_pool_test



