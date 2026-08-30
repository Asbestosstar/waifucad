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
src/waifucad/core/fixed_string.d
src/waifucad/kernel/types.d
src/waifucad/kernel/expressions.d
tests/expression_p1.d'
case "$DC_KIND" in
  ldc) # shellcheck disable=SC2086
       "$DC_BIN" $FLAGS $SOURCES -of=build/tests/expression_p1 ;;
  gdc) # shellcheck disable=SC2086
       "$DC_BIN" $FLAGS $SOURCES -o build/tests/expression_p1 ;;
esac
./build/tests/expression_p1
printf 'P1 expression parameter function test passed.\n'

