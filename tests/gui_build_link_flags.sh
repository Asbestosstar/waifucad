#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT"
mkdir -p build/tests build/obj
LOG=build/tests/fake-ldc-gui-args.txt
FAKE=build/tests/fake-ldc2-gui.sh
rm -f "$LOG" "$FAKE"
cat > "$FAKE" <<'EOS'
#!/bin/sh
printf '%s\n' "$@" >> "${WC_FAKE_LDC_LOG:?}"
exit 0
EOS
chmod +x "$FAKE"
WC_FAKE_LDC_LOG="$ROOT/$LOG" \
DC="$ROOT/$FAKE" DC_KIND=ldc \
THREAD_CFLAGS=-pthread THREAD_LDFLAGS=-lpthread \
./build.sh gui >/dev/null

grep -Fx -- '-L=-ldl' "$LOG" >/dev/null
grep -Fx -- '-L=-lm' "$LOG" >/dev/null
if grep -Fx -- '-ldl' "$LOG" >/dev/null 2>&1; then
    echo 'build.sh passed raw -ldl to ldc2' >&2
    exit 1
fi
if grep -Fx -- '-lm' "$LOG" >/dev/null 2>&1; then
    echo 'build.sh passed raw -lm to ldc2' >&2
    exit 1
fi
printf 'GTK4 GUI LDC linker flag regression test passed.\n'
