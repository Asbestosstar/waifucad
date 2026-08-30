#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
MODE=${1:-batch}
case "$MODE" in
    batch|clean) ;;
    *) echo "WebAssembly bootstrap currently builds the 64-bit Memory64 batch executable only." >&2; exit 2 ;;
esac

if [ "$MODE" = clean ]; then
    exec "$ROOT/build.sh" clean
fi

if [ -z "${WASM64_SYSROOT:-}" ]; then
    echo "Set WASM64_SYSROOT to a WASI sysroot built for wasm64/Memory64." >&2
    echo "WaifuCAD deliberately refuses a normal wasm32 WASI sysroot." >&2
    exit 2
fi
if [ -z "${WASI_SDK_PATH:-}" ] && [ -z "${WASM64_CC:-}" ]; then
    echo "Set WASI_SDK_PATH or WASM64_CC for a wasm64-capable Clang." >&2
    exit 2
fi
if ! command -v "${DC:-ldc2}" >/dev/null 2>&1; then
    echo "LDC (or another explicitly configured wasm64-capable D compiler) is required." >&2
    exit 2
fi

WASM_ABI=${WASM_ABI:-wasip1}
case "$WASM_ABI" in
    wasip1) WASM_TRIPLE=wasm64-unknown-wasip1 ;;
    wasip2) WASM_TRIPLE=wasm64-unknown-wasip2 ;;
    *) echo "WASM_ABI must be wasip1 or wasip2." >&2; exit 2 ;;
esac

DC=${DC:-ldc2}
if [ -n "${WASM64_CC:-}" ]; then
    CC=$WASM64_CC
else
    CC="$WASI_SDK_PATH/bin/clang"
fi
WC_TARGET_OS=webassembly
WC_TARGET_ARCH=wasm64
WC_TARGET_BITS=64
WC_THREAD_IMPL=single
CFLAGS="${CFLAGS:-} --target=$WASM_TRIPLE --sysroot=$WASM64_SYSROOT"
DFLAGS="${DFLAGS:-} -mtriple=$WASM_TRIPLE ${WASM64_DFLAGS:-}"
LDFLAGS="${LDFLAGS:-} ${WASM64_LDFLAGS:-}"
DC_KIND=${DC_KIND:-ldc}
export DC DC_KIND CC WC_TARGET_OS WC_TARGET_ARCH WC_TARGET_BITS WC_THREAD_IMPL CFLAGS DFLAGS LDFLAGS

"$ROOT/build.sh" batch
mv -f "$ROOT/bin/waifucad-batch" "$ROOT/bin/waifucad-batch-wasm64-$WASM_ABI.wasm"
printf 'Built %s\n' "$ROOT/bin/waifucad-batch-wasm64-$WASM_ABI.wasm"



