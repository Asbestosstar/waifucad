#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT"
. ./build/compiler.sh
DC_BIN=$(pick_compiler)
DC_KIND=$(compiler_kind "$DC_BIN")
CC_BIN=$(pick_c_compiler)
FLAGS=$(betterc_flags "$DC_KIND")
THREAD_CFLAGS_VALUE=$(thread_cflags)
THREAD_LINK_FLAGS=$(thread_d_link_flags "$DC_KIND")
mkdir -p build/tests
# shellcheck disable=SC2086
"$CC_BIN" $THREAD_CFLAGS_VALUE -std=c11 -Wall -Wextra -Inative/threads -c native/threads/wc_threads_posix.c -o build/tests/sketch_solver_threads.o
SOURCES='src/waifucad/core/platform_bits.d
src/waifucad/core/fixed_string.d
src/waifucad/core/jobs.d
src/waifucad/brep/types.d
src/waifucad/mesh/types.d
src/waifucad/kernel/types.d
src/waifucad/kernel/expressions.d
src/waifucad/kernel/model.d
src/waifucad/kernel/sketch_solver.d
src/waifucad/kernel/sketch_nonlinear.d
tests/sketch_solver_p1.d'
case "$DC_KIND" in
  ldc) # shellcheck disable=SC2086
       "$DC_BIN" $FLAGS $SOURCES build/tests/sketch_solver_threads.o $THREAD_LINK_FLAGS -of=build/tests/sketch_solver_p1 ;;
  gdc) # shellcheck disable=SC2086
       "$DC_BIN" $FLAGS $SOURCES build/tests/sketch_solver_threads.o $THREAD_LINK_FLAGS -o build/tests/sketch_solver_p1 ;;
esac
./build/tests/sketch_solver_p1
printf 'P1 sketch solver diagnostics/tangent/symmetry test passed.\n'

