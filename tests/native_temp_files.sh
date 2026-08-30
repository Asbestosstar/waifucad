#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT"
CC_BIN=${CC:-cc}
mkdir -p build/tests
"$CC_BIN" ${CFLAGS:-} -std=c11 -Wall -Wextra -Inative/files \
    native/files/wc_temp_posix.c tests/native_temp_files.c \
    -o build/tests/native_temp_files
build/tests/native_temp_files
