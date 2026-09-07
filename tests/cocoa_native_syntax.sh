#!/bin/sh
# Cocoa native shim syntax check. The scaffold stub is plain C11 and must
# compile on every host so the macOS GUI target also builds headlessly in
# cross/CI layouts. The functional Objective-C bridge (wc_cocoa.m) is
# syntax-checked only where a macOS SDK toolchain exists.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT"

CC_BIN=${CC:-cc}
"$CC_BIN" -std=c11 -fsyntax-only -Wall -Wextra -Wno-unused-parameter \
    -Inative/gui/cocoa \
    native/gui/cocoa/wc_cocoa_stub.c

if [ -f native/gui/cocoa/wc_cocoa.m ] && [ "$(uname -s)" = Darwin ]; then
    "$CC_BIN" -fsyntax-only -Wall -Wextra -fobjc-arc \
        -Inative/gui/cocoa -Inative/graphics \
        native/gui/cocoa/wc_cocoa.m
    echo 'Cocoa native Objective-C syntax check passed.'
elif [ -f native/gui/cocoa/wc_cocoa.m ]; then
    echo 'Cocoa native C stub syntax check passed (Objective-C bridge needs the macOS SDK; skipped on this host).'
else
    echo 'Cocoa native C stub syntax check passed (Objective-C bridge not present; macOS-only check skipped).'
fi
