#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT"
. ./build/compiler.sh
CC_BIN=$(pick_c_compiler)
mkdir -p build/tests build/obj
LOG="$ROOT/build/tests/fake-ldc-gui-args.txt"
FAKE="$ROOT/build/tests/fake-ldc2-gui.sh"
rm -f "$LOG" "$FAKE"
cat > "$FAKE" <<'EOS'
#!/bin/sh
printf '%s\n' "$@" >> "${WC_FAKE_LDC_LOG:?}"
exit 0
EOS
chmod +x "$FAKE"

# The probed system-library flags must reach ldc2 through -L=<flag>, never as
# raw -l flags. What exactly is probed depends on the host: glibc 2.34+ folds
# libdl/libpthread into libc, so LIBDL_RAW may legitimately be empty.
eval "$(detect_libm)"
eval "$(detect_libdl)"

WC_FAKE_LDC_LOG="$LOG" \
DC="$FAKE" DC_KIND=ldc \
THREAD_CFLAGS=-pthread THREAD_LDFLAGS=-lpthread \
./build.sh gui >/dev/null

for flag in $LIBM_RAW $LIBDL_RAW; do
    if ! grep -Fx -- "-L=$flag" "$LOG" >/dev/null; then
        echo "build.sh did not pass -L=$flag to ldc2" >&2
        exit 1
    fi
    if grep -Fx -- "$flag" "$LOG" >/dev/null 2>&1; then
        echo "build.sh passed raw $flag to ldc2" >&2
        exit 1
    fi
done

# libm is the one unconditional dependency: the probe must always succeed.
# (Its flag list may still be empty on platforms where maths lives in libc.)
[ "$WC_HAVE_LIBM" = 1 ]

printf 'GTK4 GUI LDC linker flag regression test passed.\n'
