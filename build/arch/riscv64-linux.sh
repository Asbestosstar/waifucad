#!/bin/sh
# RV64-only Linux build helper. This is a research cross-build entry point;
# native riscv64 Linux can use build/os/linux.sh directly.
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
MODE=${1:-all}
shift || true

TRIPLE=${RISCV64_TRIPLE:-riscv64-unknown-linux-gnu}
WC_TARGET_OS=linux
WC_TARGET_ARCH=riscv64
WC_TARGET_BITS=64
WC_THREAD_IMPL=${WC_THREAD_IMPL:-posix}

if [ -n "${RISCV64_DC:-}" ]; then
    DC=$RISCV64_DC
    if [ -n "${RISCV64_DC_KIND:-}" ]; then
        DC_KIND=$RISCV64_DC_KIND
    else
        case "$(basename "$DC")" in
            *gdc*) DC_KIND=gdc ;;
            *) DC_KIND=ldc ;;
        esac
    fi
elif command -v riscv64-linux-gnu-gdc >/dev/null 2>&1; then
    DC=riscv64-linux-gnu-gdc
    DC_KIND=gdc
elif command -v ldc2 >/dev/null 2>&1; then
    DC=ldc2
    DC_KIND=ldc
else
    echo "No RV64-capable D compiler found. Set RISCV64_DC and RISCV64_DC_KIND." >&2
    exit 2
fi

if [ -n "${RISCV64_CC:-}" ]; then
    CC=$RISCV64_CC
elif command -v riscv64-linux-gnu-gcc >/dev/null 2>&1; then
    CC=riscv64-linux-gnu-gcc
elif command -v clang >/dev/null 2>&1; then
    CC=clang
    CFLAGS="${CFLAGS:-} --target=$TRIPLE"
    RISCV64_LDC_CC_FLAGS="${RISCV64_LDC_CC_FLAGS:-} -Xcc=--target=$TRIPLE"
else
    echo "No RV64-capable C compiler found. Set RISCV64_CC." >&2
    exit 2
fi

case "$DC_KIND" in
    ldc)
        DFLAGS="${DFLAGS:-} -mtriple=$TRIPLE -gcc=$CC ${RISCV64_LDC_CC_FLAGS:-} ${RISCV64_DFLAGS:-}"
        ;;
    gdc)
        DFLAGS="${DFLAGS:-} ${RISCV64_DFLAGS:-}"
        ;;
    *)
        echo "RISCV64_DC_KIND must be ldc or gdc." >&2
        exit 2
        ;;
esac

if [ -n "${RISCV64_SYSROOT:-}" ]; then
    CFLAGS="${CFLAGS:-} --sysroot=$RISCV64_SYSROOT"
    case "$DC_KIND" in
        ldc) DFLAGS="${DFLAGS:-} -Xcc=--sysroot=$RISCV64_SYSROOT" ;;
    esac
fi

export DC DC_KIND CC DFLAGS CFLAGS
export WC_TARGET_OS WC_TARGET_ARCH WC_TARGET_BITS WC_THREAD_IMPL
exec "$ROOT/build.sh" "$MODE" "$@"



