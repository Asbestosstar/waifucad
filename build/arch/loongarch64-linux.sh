#!/bin/sh
# LA64 (LoongArch 64-bit) Linux build helper. This is a research cross-build
# entry point; native loongarch64 Linux can use build/os/linux.sh directly.
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
MODE=${1:-all}
shift || true

TRIPLE=${LOONGARCH64_TRIPLE:-loongarch64-unknown-linux-gnu}
WC_TARGET_OS=linux
WC_TARGET_ARCH=loongarch64
WC_TARGET_BITS=64
WC_THREAD_IMPL=${WC_THREAD_IMPL:-posix}

if [ -n "${LOONGARCH64_DC:-}" ]; then
    DC=$LOONGARCH64_DC
    if [ -n "${LOONGARCH64_DC_KIND:-}" ]; then
        DC_KIND=$LOONGARCH64_DC_KIND
    else
        case "$(basename "$DC")" in
            *gdc*) DC_KIND=gdc ;;
            *) DC_KIND=ldc ;;
        esac
    fi
elif command -v loongarch64-linux-gnu-gdc >/dev/null 2>&1; then
    DC=loongarch64-linux-gnu-gdc
    DC_KIND=gdc
elif command -v ldc2 >/dev/null 2>&1; then
    DC=ldc2
    DC_KIND=ldc
else
    echo "No LA64-capable D compiler found. Set LOONGARCH64_DC and LOONGARCH64_DC_KIND." >&2
    exit 2
fi

if [ -n "${LOONGARCH64_CC:-}" ]; then
    CC=$LOONGARCH64_CC
elif command -v loongarch64-linux-gnu-gcc >/dev/null 2>&1; then
    CC=loongarch64-linux-gnu-gcc
elif command -v clang >/dev/null 2>&1; then
    CC=clang
    CFLAGS="${CFLAGS:-} --target=$TRIPLE"
    LOONGARCH64_LDC_CC_FLAGS="${LOONGARCH64_LDC_CC_FLAGS:-} -Xcc=--target=$TRIPLE"
else
    echo "No LA64-capable C compiler found. Set LOONGARCH64_CC." >&2
    exit 2
fi

case "$DC_KIND" in
    ldc)
        DFLAGS="${DFLAGS:-} -mtriple=$TRIPLE -gcc=$CC ${LOONGARCH64_LDC_CC_FLAGS:-} ${LOONGARCH64_DFLAGS:-}"
        ;;
    gdc)
        DFLAGS="${DFLAGS:-} ${LOONGARCH64_DFLAGS:-}"
        ;;
    *)
        echo "LOONGARCH64_DC_KIND must be ldc or gdc." >&2
        exit 2
        ;;
esac

if [ -n "${LOONGARCH64_SYSROOT:-}" ]; then
    CFLAGS="${CFLAGS:-} --sysroot=$LOONGARCH64_SYSROOT"
    case "$DC_KIND" in
        ldc) DFLAGS="${DFLAGS:-} -Xcc=--sysroot=$LOONGARCH64_SYSROOT" ;;
    esac
fi

export DC DC_KIND CC DFLAGS CFLAGS
export WC_TARGET_OS WC_TARGET_ARCH WC_TARGET_BITS WC_THREAD_IMPL
exec "$ROOT/build.sh" "$MODE" "$@"



