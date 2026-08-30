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
src/waifucad/brep/types.d
src/waifucad/brep/builder.d
src/waifucad/brep/geometry.d
src/waifucad/brep/naming.d
src/waifucad/brep/euler.d
src/waifucad/brep/kernel.d
src/waifucad/brep/advanced.d
src/waifucad/brep/intersections.d
src/waifucad/brep/classification.d
src/waifucad/brep/tolerance.d
src/waifucad/brep/validate.d
tests/brep_p1_advanced.d'
case "$DC_KIND" in
  ldc) # shellcheck disable=SC2086
       "$DC_BIN" $FLAGS $SOURCES -of=build/tests/brep_p1_advanced ;;
  gdc) # shellcheck disable=SC2086
       "$DC_BIN" $FLAGS $SOURCES -o build/tests/brep_p1_advanced ;;
esac
./build/tests/brep_p1_advanced
printf 'WaifuBRep P1 advanced geometry test passed.\n'

