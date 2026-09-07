#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
cd "$ROOT"
. ./build/compiler.sh

MODE=${1:-all}
TARGET_BITS=${WC_TARGET_BITS:-64}
if [ "$TARGET_BITS" != 64 ]; then
    echo "WaifuCAD is 64-bit-only; WC_TARGET_BITS must be 64." >&2
    exit 2
fi
if [ "$MODE" = clean ]; then
    rm -rf bin build/obj
    exit 0
fi

DC_BIN=$(pick_compiler)
DC_KIND=$(compiler_kind "$DC_BIN")
CC_BIN=$(pick_c_compiler)
BASE_FLAGS=$(betterc_flags "$DC_KIND")
THREAD_CFLAGS_VALUE=$(thread_cflags)
THREAD_LINK_FLAGS=
if [ "${WC_THREAD_IMPL:-posix}" = posix ]; then
    THREAD_LINK_FLAGS=$(thread_d_link_flags "$DC_KIND")
fi
mkdir -p bin build/obj

# The base source list is intentionally explicit so historical make implementations
# do not need recursive glob support.
COMMON='src/waifucad/core/platform_bits.d
src/waifucad/core/fixed_string.d
src/waifucad/core/log.d
src/waifucad/core/jobs.d
src/waifucad/brep/types.d
src/waifucad/brep/builder.d
src/waifucad/brep/geometry.d
src/waifucad/brep/intersections.d
src/waifucad/brep/classification.d
src/waifucad/brep/advanced.d
src/waifucad/brep/transform.d
src/waifucad/brep/tolerance.d
src/waifucad/brep/naming.d
src/waifucad/brep/properties.d
src/waifucad/brep/euler.d
src/waifucad/brep/kernel.d
src/waifucad/brep/validate.d
src/waifucad/brep/dump.d
src/waifucad/mesh/types.d
src/waifucad/mesh/off_io.d
src/waifucad/mesh/payload_io.d
src/waifucad/mesh/tessellate.d
src/waifucad/mesh/tessellate_brep.d
src/waifucad/interchange/openscad/options.d
src/waifucad/interchange/openscad/roundtrip.d
src/waifucad/interchange/openscad/importer.d
src/waifucad/interchange/openscad/exporter.d
src/waifucad/kernel/types.d
src/waifucad/kernel/expressions.d
src/waifucad/kernel/datums.d
src/waifucad/kernel/profiles.d
src/waifucad/kernel/sketch_solver.d
src/waifucad/kernel/sketch_nonlinear.d
src/waifucad/kernel/model.d
src/waifucad/kernel/backend_api.d
src/waifucad/kernel/builtin_preview.d
src/waifucad/kernel/waifubrep_backend.d
src/waifucad/journal/journal.d
src/waifucad/journal/backend_api.d
src/waifucad/journal/script_runtime.d
src/waifucad/journal/backends/scl/backend.d
src/waifucad/scl/runtime_ops.d
src/waifucad/scl/tokenise.d
src/waifucad/scl/ruby_syntax.d
src/waifucad/scl/getters.d
src/waifucad/scl/interpreter.d
src/waifucad/scl/repl.d
src/waifucad/sections/api.d
src/waifucad/sections/ribbon.d
src/waifucad/sections/modelling/section.d
src/waifucad/sections/pmi/types.d
src/waifucad/sections/pmi/store.d
src/waifucad/sections/pmi/section.d
src/waifucad/sections/registry.d
src/waifucad/sections/context.d
src/waifucad/mods/api.d
src/waifucad/scripts/runner.d
src/waifucad/ai/protocol.d
src/waifucad/platform/capabilities.d
src/waifucad/platform/target.d
src/waifucad/platform/temp_files.d
src/waifucad/gui/api.d
src/waifucad/gui/selector.d
src/waifucad/gui/theme.d
src/waifucad/gui/navigation.d
src/waifucad/gui/ribbon_host.d
src/waifucad/gui/ribbon_actions.d
src/waifucad/gui/feature_dialogues.d
src/waifucad/gui/command_console.d
src/waifucad/graphics/api.d
src/waifucad/graphics/selector.d'



gtk4_d_link_flags() {
    gtk_libs=$(pkg-config --libs gtk4)
    if [ "$DC_KIND" = gdc ]; then
        printf '%s\n' "$gtk_libs"
        return
    fi
    result=
    for flag in $gtk_libs; do
        case "$flag" in
            -pthread) result="$result -L-lpthread" ;;
            -L*|-l*|-Wl,*) result="$result -L=$flag" ;;
            *) result="$result $flag" ;;
        esac
    done
    printf '%s\n' "$result"
}

build_native_gpu_probe() {
    "$CC_BIN" ${CFLAGS:-} -std=c11 -Wall -Wextra -fPIC \
        -Inative/graphics -c native/graphics/wc_gpu_probe.c -o build/obj/wc_gpu_probe.o
}

build_native_gtk4() {
    build_native_gpu_probe
    GTK4_LINK_FLAGS=
    if command -v pkg-config >/dev/null 2>&1 && pkg-config --exists gtk4; then
        gtk_cflags=$(pkg-config --cflags gtk4)
        # shellcheck disable=SC2086
        "$CC_BIN" ${CFLAGS:-} -std=c11 -Wall -Wextra -fPIC $gtk_cflags \
            -Inative/gui/gtk4 -Inative/graphics \
            -c native/gui/gtk4/wc_gtk4.c -o build/obj/wc_gtk4.o
        GTK4_LINK_FLAGS=$(gtk4_d_link_flags)
        echo "GTK4 native frontend: enabled ($(pkg-config --modversion gtk4))"
    else
        "$CC_BIN" ${CFLAGS:-} -std=c11 -Wall -Wextra -fPIC \
            -Inative/gui/gtk4 -c native/gui/gtk4/wc_gtk4_stub.c -o build/obj/wc_gtk4.o
        echo "GTK4 native frontend: disabled (pkg-config gtk4 not found)" >&2
    fi
}

build_native_temp_files() {
    "$CC_BIN" ${CFLAGS:-} -std=c11 -Wall -Wextra \
        -Inative/files -c native/files/wc_temp_posix.c -o build/obj/wc_temp.o
}

# Resolve the GUI front-end target OS. An explicit WC_TARGET_OS (set by the
# build/os/ entry points and arch helpers) wins; otherwise the build host
# decides. macOS selects the native Cocoa front-end and never probes GTK4.
detect_target_os() {
    if [ -n "${WC_TARGET_OS:-}" ]; then
        printf '%s\n' "$WC_TARGET_OS"
        return
    fi
    case "$(uname -s)" in
        Darwin) printf 'macos\n' ;;
        Linux)  printf 'linux\n' ;;
        *)      printf 'unknown\n' ;;
    esac
}

build_native_cocoa() {
    build_native_gpu_probe
    COCOA_LINK_FLAGS=
    if [ -f native/gui/cocoa/wc_cocoa.m ] && [ "$(uname -s)" = Darwin ]; then
        # shellcheck disable=SC2086
        "$CC_BIN" ${CFLAGS:-} -fPIC -fobjc-arc \
            -Inative/gui/cocoa -Inative/graphics \
            -c native/gui/cocoa/wc_cocoa.m -o build/obj/wc_cocoa.o
        case "$DC_KIND" in
            gdc) COCOA_LINK_FLAGS="-framework Cocoa -framework Metal -framework QuartzCore" ;;
            *) COCOA_LINK_FLAGS="-L=-framework -L=Cocoa -L=-framework -L=Metal -L=-framework -L=QuartzCore" ;;
        esac
        echo "Cocoa native frontend: enabled (AppKit/Metal bridge)"
    else
        "$CC_BIN" ${CFLAGS:-} -std=c11 -Wall -Wextra -fPIC \
            -Inative/gui/cocoa -c native/gui/cocoa/wc_cocoa_stub.c -o build/obj/wc_cocoa.o
        echo "Cocoa native frontend: stub (build on macOS for the AppKit/Metal bridge)" >&2
    fi
}

build_native_threads() {
    impl=${WC_THREAD_IMPL:-posix}
    case "$impl" in
        posix) thread_source=native/threads/wc_threads_posix.c; thread_cflags_value=$THREAD_CFLAGS_VALUE ;;
        single) thread_source=native/threads/wc_threads_single.c; thread_cflags_value= ;;
        *) echo "Unknown WC_THREAD_IMPL '$impl' (expected posix or single)." >&2; exit 2 ;;
    esac
    # shellcheck disable=SC2086
    "$CC_BIN" ${CFLAGS:-} $thread_cflags_value -std=c11 -Wall -Wextra \
        -Inative/threads -c "$thread_source" -o build/obj/wc_threads.o
}

build_one() {
    output="$1"
    main="$2"
    shift 2
    # shellcheck disable=SC2086
    case "$DC_KIND" in
        ldc) "$DC_BIN" $BASE_FLAGS ${DFLAGS:-} "$@" $COMMON "$main" build/obj/wc_threads.o build/obj/wc_temp.o ${LDFLAGS:-} $THREAD_LINK_FLAGS -of="$output" ;;
        gdc) "$DC_BIN" $BASE_FLAGS ${DFLAGS:-} "$@" $COMMON "$main" build/obj/wc_threads.o build/obj/wc_temp.o ${LDFLAGS:-} $THREAD_LINK_FLAGS -o "$output" ;;
    esac
}

build_gui() {
    gui_target_os=$(detect_target_os)
    if [ "$gui_target_os" = macos ]; then
        # macOS uses the native Cocoa/AppKit front-end. GTK4 is not probed,
        # required or linked on this path.
        build_native_cocoa
        # dlopen lives in libSystem on macOS; only a non-Darwin build host
        # exercising this path (for example Linux CI) needs the libdl shim.
        # LDC needs linker flags wrapped as -L=..., GDC passes them through.
        cocoa_dl_flag_ldc='-L=-ldl'
        cocoa_dl_flag_gdc='-ldl'
        if [ "$(uname -s)" = Darwin ]; then
            cocoa_dl_flag_ldc=
            cocoa_dl_flag_gdc=
        fi
        case "$DC_KIND" in
            ldc)
                # shellcheck disable=SC2086
                "$DC_BIN" $BASE_FLAGS ${DFLAGS:-} -d-version=WaifuCadGuiCocoa \
                    $COMMON \
                    src/waifucad/gui/frontends/cocoa/frontend.d \
                    src/apps/waifucad_gui.d \
                    build/obj/wc_threads.o build/obj/wc_temp.o \
                    build/obj/wc_cocoa.o build/obj/wc_gpu_probe.o \
                    ${LDFLAGS:-} $THREAD_LINK_FLAGS $COCOA_LINK_FLAGS $cocoa_dl_flag_ldc -L=-lm \
                    -of=bin/waifucad-gui
                ;;
            gdc)
                # shellcheck disable=SC2086
                "$DC_BIN" $BASE_FLAGS ${DFLAGS:-} -fversion=WaifuCadGuiCocoa \
                    $COMMON \
                    src/waifucad/gui/frontends/cocoa/frontend.d \
                    src/apps/waifucad_gui.d \
                    build/obj/wc_threads.o build/obj/wc_temp.o \
                    build/obj/wc_cocoa.o build/obj/wc_gpu_probe.o \
                    ${LDFLAGS:-} $THREAD_LINK_FLAGS $COCOA_LINK_FLAGS $cocoa_dl_flag_gdc -lm \
                    -o bin/waifucad-gui
                ;;
        esac
        return
    fi
    build_native_gtk4
    case "$DC_KIND" in
        ldc)
            # shellcheck disable=SC2086
            "$DC_BIN" $BASE_FLAGS ${DFLAGS:-} \
                $COMMON \
                src/waifucad/gui/frontends/gtk4/frontend.d \
                src/apps/waifucad_gui.d \
                build/obj/wc_threads.o build/obj/wc_temp.o \
                build/obj/wc_gtk4.o build/obj/wc_gpu_probe.o \
                ${LDFLAGS:-} $THREAD_LINK_FLAGS $GTK4_LINK_FLAGS -L=-ldl -L=-lm \
                -of=bin/waifucad-gui
            ;;
        gdc)
            # shellcheck disable=SC2086
            "$DC_BIN" $BASE_FLAGS ${DFLAGS:-} \
                $COMMON \
                src/waifucad/gui/frontends/gtk4/frontend.d \
                src/apps/waifucad_gui.d \
                build/obj/wc_threads.o build/obj/wc_temp.o \
                build/obj/wc_gtk4.o build/obj/wc_gpu_probe.o \
                ${LDFLAGS:-} $THREAD_LINK_FLAGS $GTK4_LINK_FLAGS -ldl -lm \
                -o bin/waifucad-gui
            ;;
    esac
}

build_native_threads
build_native_temp_files

case "$MODE" in
    batch)
        build_one bin/waifucad-batch src/apps/waifucad_batch.d
        ;;
    gui)
        build_gui
        ;;
    all)
        build_one bin/waifucad-batch src/apps/waifucad_batch.d
        build_gui
        ;;
    *)
        echo "Usage: ./build.sh [batch|gui|all|clean]" >&2
        exit 2
        ;;
esac




