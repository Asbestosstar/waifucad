#!/bin/sh
set -eu

if ! command -v pkg-config >/dev/null 2>&1 || ! pkg-config --exists gtk4; then
    echo 'GTK4 development headers unavailable; native GTK4 syntax check skipped.'
    exit 0
fi

CC_BIN=${CC:-cc}
"$CC_BIN" -std=c11 -fsyntax-only -Wall -Wextra -Wno-unused-parameter \
    $(pkg-config --cflags gtk4) \
    -Inative/gui/gtk4 -Inative/graphics \
    native/gui/gtk4/wc_gtk4.c

echo 'GTK4 native C syntax check passed.'
