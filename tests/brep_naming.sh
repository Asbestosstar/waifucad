#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT"
. ./build/compiler.sh
DC_BIN=$(pick_compiler)
DC_KIND=$(compiler_kind "$DC_BIN")
BASE_FLAGS=$(betterc_flags "$DC_KIND")
mkdir -p build/obj
SOURCES='src/waifucad/brep/types.d src/waifucad/brep/builder.d src/waifucad/brep/geometry.d src/waifucad/brep/naming.d src/waifucad/brep/euler.d src/waifucad/brep/kernel.d tests/brep_naming.d'
# shellcheck disable=SC2086
case "$DC_KIND" in
    ldc) "$DC_BIN" $BASE_FLAGS $SOURCES -of=build/obj/brep_naming_test ;;
    gdc) "$DC_BIN" $BASE_FLAGS $SOURCES -o build/obj/brep_naming_test ;;
esac
./build/obj/brep_naming_test

