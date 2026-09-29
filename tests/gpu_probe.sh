#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT"
. ./build/compiler.sh
CC_BIN=$(pick_c_compiler)
mkdir -p build/tests

# The GPU probe is an optional dependency: when the host cannot link dlopen,
# the stub probe is built instead and must report the feature as unavailable.
eval "$(detect_libdl)"

if [ "$WC_HAVE_DLOPEN" = 1 ]; then
    PROBE_SRC=native/graphics/wc_gpu_probe.c
else
    PROBE_SRC=native/graphics/wc_gpu_probe_stub.c
fi
# shellcheck disable=SC2086
"${CC:-cc}" ${CFLAGS:-} -std=c11 -Wall -Wextra \
    -Inative/graphics tests/gpu_probe.c "$PROBE_SRC" \
    $LIBDL_RAW -o build/tests/gpu_probe
./build/tests/gpu_probe

if [ "$WC_HAVE_DLOPEN" != 1 ]; then
    summary=$(./build/tests/gpu_probe)
    case "$summary" in
        *"unavailable"*) ;;
        *) echo "stub probe did not report itself unavailable" >&2; exit 1 ;;
    esac
    printf 'GPU probe stub test passed (no dlopen on this host).\n'
    exit 0
fi

# /opt Mesa scan: build a fake /opt with two versioned Mesa trees, only the
# newer one shipping a Vulkan (lavapipe) ICD, plus one tree with no Vulkan
# drivers at all. The probe must pick the Vulkan-capable version and say so.
FAKE_OPT=build/tests/fake-opt
rm -rf "$FAKE_OPT"
mkdir -p "$FAKE_OPT/mesa-24.0/share" \
         "$FAKE_OPT/mesa-25.1/share/vulkan/icd.d" \
         "$FAKE_OPT/mesa-novulkan/share"
echo '{"ICD":{"library_path":"libvulkan_lvp.so"}}' \
    > "$FAKE_OPT/mesa-25.1/share/vulkan/icd.d/lvp_icd.x86_64.json"

opt_summary=$(WC_OPT_MESA_ROOT="$FAKE_OPT" ./build/tests/gpu_probe)
printf '%s\n' "$opt_summary"
case "$opt_summary" in
    *"/opt Mesa="*"mesa-25.1"*"Vulkan"*) ;;
    *) echo "probe did not report the Vulkan-capable /opt Mesa tree" >&2; exit 1 ;;
esac

# A Mesa tree without Vulkan drivers must never qualify as Vulkan-capable.
NOVK="$FAKE_OPT-novk"
rm -rf "$NOVK"
mkdir -p "$NOVK/mesa-99.0/share"
novk_summary=$(WC_OPT_MESA_ROOT="$NOVK" ./build/tests/gpu_probe)
case "$novk_summary" in
    *"/opt Mesa present (no Vulkan drivers)"*) ;;
    *) echo "probe mishandled an /opt Mesa tree without Vulkan drivers" >&2; exit 1 ;;
esac
printf 'GPU probe test passed.\n'
