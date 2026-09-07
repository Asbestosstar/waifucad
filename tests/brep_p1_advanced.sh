#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT"
. ./build/compiler.sh
DC_BIN=$(pick_compiler)
DC_KIND=$(compiler_kind "$DC_BIN")
FLAGS=$(betterc_flags "$DC_KIND")
CC_BIN=$(pick_c_compiler)
THREAD_CFLAGS_VALUE=$(thread_cflags)
THREAD_LINK_FLAGS=$(thread_d_link_flags "$DC_KIND")
mkdir -p build/tests
# shellcheck disable=SC2086
"$CC_BIN" $THREAD_CFLAGS_VALUE -std=c11 -Wall -Wextra -Inative/threads -c native/threads/wc_threads_posix.c -o build/tests/brep_p1_advanced_threads.o
SOURCES='src/waifucad/core/platform_bits.d
src/waifucad/core/fixed_string.d
src/waifucad/core/jobs.d
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
src/waifucad/mesh/types.d
src/waifucad/mesh/tessellate.d
src/waifucad/mesh/tessellate_brep.d
src/waifucad/interchange/openscad/options.d
tests/brep_p1_advanced.d'
case "$DC_KIND" in
  ldc) # shellcheck disable=SC2086
       "$DC_BIN" $FLAGS $SOURCES build/tests/brep_p1_advanced_threads.o $THREAD_LINK_FLAGS -of=build/tests/brep_p1_advanced ;;
  gdc) # shellcheck disable=SC2086
       "$DC_BIN" $FLAGS $SOURCES build/tests/brep_p1_advanced_threads.o $THREAD_LINK_FLAGS -o build/tests/brep_p1_advanced ;;
esac
./build/tests/brep_p1_advanced
printf 'WaifuBRep P1 advanced geometry test passed.\n'

