#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT"
mkdir -p build/tests
CC_BIN=${CC:-cc}
"$CC_BIN" ${CFLAGS:-} -std=c11 -Wall -Wextra \
    -Inative/graphics tests/gpu_probe.c native/graphics/wc_gpu_probe.c \
    -ldl -o build/tests/gpu_probe
./build/tests/gpu_probe
