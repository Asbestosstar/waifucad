#!/bin/sh
# macOS GUI target regression: the Cocoa front-end path must be selected for
# a macOS target, must compile the cocoa front-end with the WaifuCadGuiCocoa
# version identifier, and must never probe, compile or link GTK4.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT"
mkdir -p build/tests build/obj
LOG=build/tests/fake-ldc-cocoa-args.txt
FAKE=build/tests/fake-ldc2-cocoa.sh
rm -f "$LOG" "$FAKE"
cat > "$FAKE" <<'EOS'
#!/bin/sh
printf '%s\n' "$@" >> "${WC_FAKE_LDC_LOG:?}"
exit 0
EOS
chmod +x "$FAKE"
WC_FAKE_LDC_LOG="$ROOT/$LOG" \
DC="$ROOT/$FAKE" DC_KIND=ldc \
WC_TARGET_OS=macos \
THREAD_CFLAGS=-pthread THREAD_LDFLAGS=-lpthread \
./build.sh gui >/dev/null 2>&1

grep -Fx -- '-d-version=WaifuCadGuiCocoa' "$LOG" >/dev/null
grep -Fx -- 'src/waifucad/gui/frontends/cocoa/frontend.d' "$LOG" >/dev/null
grep -Fx -- 'build/obj/wc_cocoa.o' "$LOG" >/dev/null
if grep -F -- 'src/waifucad/gui/frontends/gtk4/frontend.d' "$LOG" >/dev/null 2>&1; then
    echo 'macOS GUI target compiled the GTK4 front-end' >&2
    exit 1
fi
if grep -F -- 'wc_gtk4' "$LOG" >/dev/null 2>&1; then
    echo 'macOS GUI target linked GTK4 native objects' >&2
    exit 1
fi
printf 'Cocoa macOS GUI target selection regression test passed.\n'
