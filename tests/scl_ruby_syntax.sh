#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT"
. ./build/compiler.sh
DC_BIN=$(pick_compiler)
DC_KIND=$(compiler_kind "$DC_BIN")
FLAGS=$(betterc_flags "$DC_KIND")
mkdir -p build/tests
SOURCES='src/waifucad/core/platform_bits.d
src/waifucad/scl/tokenise.d
src/waifucad/scl/ruby_syntax.d
tests/scl_ruby_syntax.d'
case "$DC_KIND" in
    ldc)
        # shellcheck disable=SC2086
        "$DC_BIN" $FLAGS $SOURCES -of=build/tests/scl_ruby_syntax
        ;;
    gdc)
        # shellcheck disable=SC2086
        "$DC_BIN" $FLAGS $SOURCES -o build/tests/scl_ruby_syntax
        ;;
esac
./build/tests/scl_ruby_syntax
printf 'Ruby-style SCL syntax test passed.\n'


