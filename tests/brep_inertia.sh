#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT"
. ./build/compiler.sh
DC_BIN=$(pick_compiler)
DC_KIND=$(compiler_kind "$DC_BIN")
FLAGS=$(betterc_flags "$DC_KIND")
SHIM_OBJS=$(betterc_shim_objects "$DC_KIND" build/obj)
mkdir -p build/tests
SOURCES='src/waifucad/core/platform_bits.d
src/waifucad/brep/types.d
src/waifucad/brep/builder.d
src/waifucad/brep/geometry.d
src/waifucad/brep/properties.d
src/waifucad/brep/inertia.d
src/waifucad/brep/euler.d
src/waifucad/brep/naming.d
src/waifucad/brep/kernel.d
src/waifucad/brep/advanced.d
src/waifucad/brep/intersections.d
src/waifucad/brep/classification.d
src/waifucad/brep/tolerance.d
src/waifucad/brep/validate.d
tests/brep_inertia.d'
case "$DC_KIND" in
    ldc|dmd)
        # shellcheck disable=SC2086
        "$DC_BIN" $FLAGS $SOURCES $SHIM_OBJS -of=build/tests/brep_inertia
        ;;
    gdc)
        # shellcheck disable=SC2086
        "$DC_BIN" $FLAGS $SOURCES -o build/tests/brep_inertia
        ;;
esac
./build/tests/brep_inertia

# End-to-end: the SCL getters expose the same exact numbers.
./build.sh batch
./bin/waifucad-batch --script tests/brep_inertia.wcs > build/tests/brep_inertia_scl.txt
grep -Fqx '[1500000,5550000,6750000,0,0,0]' build/tests/brep_inertia_scl.txt
grep -Fqx '[1500000,5550000,6750000]' build/tests/brep_inertia_scl.txt
grep -Fqx '[1,0,0,0,1,0,0,0,1]' build/tests/brep_inertia_scl.txt

# A missing feature must fail with the getter error, not silently zero.
cat > build/tests/brep_inertia_missing.wcs <<'EOS'
model(:m)
box(:b, 1, 1, 1)
recompute()
i = get_feature_inertia(:i, :missing_feature)
EOS
if ./bin/waifucad-batch --script build/tests/brep_inertia_missing.wcs >/dev/null 2>&1; then
    echo 'get_feature_inertia on a missing feature did not fail' >&2
    exit 1
fi
printf 'WaifuBRep inertia test passed.\n'
