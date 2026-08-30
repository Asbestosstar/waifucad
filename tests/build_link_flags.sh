#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT"
mkdir -p build/tests build/obj
LOG=build/tests/fake-ldc-args.txt
FAKE=build/tests/fake-ldc2.sh
rm -f "$LOG" "$FAKE"
cat > "$FAKE" <<'EOF'
#!/bin/sh
printf '%s\n' "$@" >> "${WC_FAKE_LDC_LOG:?}"
exit 0
EOF
chmod +x "$FAKE"

WC_FAKE_LDC_LOG="$ROOT/$LOG" \
DC="$ROOT/$FAKE" DC_KIND=ldc \
THREAD_CFLAGS=-pthread THREAD_LDFLAGS=-lpthread \
./build.sh batch

if grep -Fx -- '-pthread' "$LOG" >/dev/null 2>&1; then
    echo 'build.sh passed raw -pthread to ldc2' >&2
    exit 1
fi
grep -Fx -- '-L=-lpthread' "$LOG" >/dev/null
printf 'LDC pthread linker flag regression test passed.\n'



