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
if [ "${WC_DEBUG:-0}" = 1 ]; then
    # Debug symbols (and no optimisation) so a crash can be located with gdb/dbx.
    BASE_FLAGS="$BASE_FLAGS -g"
fi
mkdir -p bin build/obj

# Probe optional system libraries (see build/compiler.sh). Nothing here is a
# hard dependency: PNG output is handwritten, Vulkan is dlopened, and even
# libm/libdl/pthreads are probed so minimal hosts keep building.
eval "$(detect_libm)"
if [ "$WC_HAVE_LIBM" != 1 ]; then
    echo "libm is required but no link spelling worked on this host." >&2
    exit 2
fi
eval "$(detect_libdl)"
# shellcheck disable=SC2086
LIBM_D_FLAGS=$(d_link_flags "$DC_KIND" $LIBM_RAW)
# shellcheck disable=SC2086
LIBDL_D_FLAGS=$(d_link_flags "$DC_KIND" $LIBDL_RAW)

# Threading. WC_THREAD_IMPL=auto (default) probes for POSIX threads and falls
# back to the serial shim; an explicit THREAD_LDFLAGS keeps the historical
# override contract and implies posix with those flags.
THREAD_IMPL=${WC_THREAD_IMPL:-auto}
case "$THREAD_IMPL" in
    auto)
        if [ -n "${THREAD_LDFLAGS:-}" ]; then
            THREAD_IMPL=posix
            THREAD_CFLAGS_VALUE=$(thread_cflags)
            THREAD_LINK_FLAGS=$(thread_d_link_flags "$DC_KIND")
        else
            eval "$(detect_posix_threads)"
            if [ "$WC_HAVE_PTHREAD" = 1 ]; then
                THREAD_IMPL=posix
                THREAD_CFLAGS_VALUE=$PTHREAD_CFLAGS_RAW
                # shellcheck disable=SC2086
                THREAD_LINK_FLAGS=$(d_link_flags "$DC_KIND" $PTHREAD_LDFLAGS_RAW)
            else
                THREAD_IMPL=single
                THREAD_CFLAGS_VALUE=
                THREAD_LINK_FLAGS=
            fi
        fi
        ;;
    posix)
        THREAD_CFLAGS_VALUE=$(thread_cflags)
        THREAD_LINK_FLAGS=$(thread_d_link_flags "$DC_KIND")
        ;;
    single)
        THREAD_CFLAGS_VALUE=
        THREAD_LINK_FLAGS=
        ;;
    *)
        echo "Unknown WC_THREAD_IMPL '$THREAD_IMPL' (expected auto, posix or single)." >&2
        exit 2
        ;;
esac

# GPU probing dlopens Vulkan at runtime; hosts without dynamic loading get a
# stub that reports no GPU probe support instead of failing the build.
GPU_PROBE_IMPL=${WC_GPU_PROBE_IMPL:-auto}
case "$GPU_PROBE_IMPL" in
    auto)
        if [ "$WC_HAVE_DLOPEN" = 1 ]; then GPU_PROBE_IMPL=dlopen; else GPU_PROBE_IMPL=stub; fi
        ;;
    dlopen)
        if [ "$WC_HAVE_DLOPEN" != 1 ]; then
            echo "WC_GPU_PROBE_IMPL=dlopen requested but this host cannot link dlopen." >&2
            exit 2
        fi
        ;;
    stub) ;;
    *)
        echo "Unknown WC_GPU_PROBE_IMPL '$GPU_PROBE_IMPL' (expected auto, dlopen or stub)." >&2
        exit 2
        ;;
esac

# DMD -betterC needs the druntime memset-fill shims; ldc/gdc get nothing.
SHIM_OBJS=$(betterc_shim_objects "$DC_KIND" build/obj)

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
src/waifucad/brep/inertia.d
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
src/waifucad/journal/undo.d
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
src/waifucad/gui/registry.d
src/waifucad/gui/selector.d
src/waifucad/gui/theme.d
src/waifucad/gui/navigation.d
src/waifucad/gui/ribbon_host.d
src/waifucad/gui/ribbon_actions.d
src/waifucad/gui/ribbon_search.d
src/waifucad/gui/feature_dialogues.d
src/waifucad/gui/command_console.d
src/waifucad/graphics/api.d
src/waifucad/graphics/registry.d
src/waifucad/graphics/selector.d
src/waifucad/render/png.d
src/waifucad/render/softshot.d
src/waifucad/render/raytrace.d'



build_native_gpu_probe() {
    case "$GPU_PROBE_IMPL" in
        dlopen) gpu_probe_source=native/graphics/wc_gpu_probe.c ;;
        stub) gpu_probe_source=native/graphics/wc_gpu_probe_stub.c ;;
    esac
    "$CC_BIN" ${CFLAGS:-} -std=c11 -Wall -Wextra -fPIC \
        -Inative/graphics -c "$gpu_probe_source" -o build/obj/wc_gpu_probe.o
}

build_native_gtk4() {
    build_native_gpu_probe
    GTK4_LINK_FLAGS=
    detect_gtk4
    if [ "${GTK4_FORCE_STUB:-0}" = 1 ]; then
        WC_HAVE_GTK4=0
        GTK4_WHY="linking against GTK4 failed (see the linker errors above)"
    fi
    if [ "$WC_HAVE_GTK4" = 1 ]; then
        # shellcheck disable=SC2086
        "$CC_BIN" ${CFLAGS:-} -std=c11 -Wall -Wextra -fPIC $GTK4_CFLAGS_RAW \
            -Inative/gui/gtk4 -Inative/graphics \
            -c native/gui/gtk4/wc_gtk4.c -o build/obj/wc_gtk4.o
        # shellcheck disable=SC2086
        GTK4_LINK_FLAGS=$(d_link_flags "$DC_KIND" $GTK4_LIBS_RAW)
        echo "GTK4 native frontend: enabled ($GTK4_VERSION via $GTK4_METHOD)"
    else
        "$CC_BIN" ${CFLAGS:-} -std=c11 -Wall -Wextra -fPIC \
            -Inative/gui/gtk4 -c native/gui/gtk4/wc_gtk4_stub.c -o build/obj/wc_gtk4.o
        echo "GTK4 native frontend: disabled (GTK4 not found${GTK4_WHY:+: $GTK4_WHY})" >&2
        echo "  Set WC_GTK4_PREFIX=/path (containing include/gtk-4.0), PKG_CONFIG_PATH, or GTK4_CFLAGS and GTK4_LIBS." >&2
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
    case "$THREAD_IMPL" in
        posix) thread_source=native/threads/wc_threads_posix.c; thread_cflags_value=$THREAD_CFLAGS_VALUE ;;
        single) thread_source=native/threads/wc_threads_single.c; thread_cflags_value= ;;
        *) echo "Unknown WC_THREAD_IMPL '$THREAD_IMPL' (expected posix or single)." >&2; exit 2 ;;
    esac
    # shellcheck disable=SC2086
    "$CC_BIN" ${CFLAGS:-} $thread_cflags_value -std=c11 -Wall -Wextra \
        -Inative/threads -c "$thread_source" -o build/obj/wc_threads.o
}

# gdc compiles one object per module, several at a time (see gdc_compile_objects
# in build/compiler.sh), and the shared COMMON objects are built once for both
# the batch and GUI executables. WC_JOBS overrides the parallel job count and
# WC_GDC_SPLIT=0 restores the historical single-command build.
GDC_COMMON_OBJS=
GDC_COMMON_BUILT=0
GDC_SPLIT=${WC_GDC_SPLIT:-1}

gdc_build_common() {
    if [ "$GDC_COMMON_BUILT" = 1 ]; then
        return
    fi
    GDC_EXTRA_FLAGS=
    # shellcheck disable=SC2086
    gdc_compile_objects build/obj/d $COMMON
    GDC_COMMON_OBJS=$GDC_OBJS
    GDC_COMMON_BUILT=1
}

# gdc_link_app OUTPUT SOURCES... -- LINK-INPUTS...: compile the app sources, link
# them with the shared COMMON objects and the extra link inputs.
gdc_link_app() {
    output="$1"
    shift
    app_flags=${GDC_EXTRA_FLAGS:-}
    app_sources=
    while [ "$#" -gt 0 ] && [ "$1" != -- ]; do
        app_sources="$app_sources $1"
        shift
    done
    shift
    gdc_build_common
    GDC_EXTRA_FLAGS=$app_flags
    # shellcheck disable=SC2086
    gdc_compile_objects build/obj/d $app_sources
    app_objs=$GDC_OBJS
    # shellcheck disable=SC2086
    "$DC_BIN" $BASE_FLAGS ${DFLAGS:-} $GDC_COMMON_OBJS $app_objs "$@" -o "$output"
}

build_one() {
    output="$1"
    main="$2"
    shift 2
    # shellcheck disable=SC2086
    case "$DC_KIND" in
        ldc|dmd) "$DC_BIN" $BASE_FLAGS ${DFLAGS:-} "$@" $COMMON "$main" build/obj/wc_threads.o build/obj/wc_temp.o $SHIM_OBJS ${LDFLAGS:-} $THREAD_LINK_FLAGS $LIBM_D_FLAGS -of="$output" ;;
        gdc)
            if [ "$GDC_SPLIT" = 1 ]; then
                GDC_EXTRA_FLAGS="$*"
                gdc_link_app "$output" "$main" -- build/obj/wc_threads.o build/obj/wc_temp.o ${LDFLAGS:-} $THREAD_LINK_FLAGS $LIBM_D_FLAGS
            else
                "$DC_BIN" $BASE_FLAGS ${DFLAGS:-} "$@" $COMMON "$main" build/obj/wc_threads.o build/obj/wc_temp.o ${LDFLAGS:-} $THREAD_LINK_FLAGS $LIBM_D_FLAGS -o "$output"
            fi
            ;;
    esac
}

link_gtk4_gui() {
    case "$DC_KIND" in
        ldc|dmd)
            # shellcheck disable=SC2086
            "$DC_BIN" $BASE_FLAGS ${DFLAGS:-} \
                $COMMON \
                src/waifucad/gui/frontends/common/frontend.d \
                src/waifucad/gui/frontends/gtk4/frontend.d \
                src/apps/waifucad_gui.d \
                build/obj/wc_threads.o build/obj/wc_temp.o \
                build/obj/wc_gtk4.o build/obj/wc_gpu_probe.o $SHIM_OBJS \
                ${LDFLAGS:-} $THREAD_LINK_FLAGS $GTK4_LINK_FLAGS $LIBDL_D_FLAGS $LIBM_D_FLAGS \
                -of=bin/waifucad-gui
            ;;
        gdc)
            if [ "$GDC_SPLIT" = 1 ]; then
                GDC_EXTRA_FLAGS=
                # shellcheck disable=SC2086
                gdc_link_app bin/waifucad-gui \
                    src/waifucad/gui/frontends/common/frontend.d \
                    src/waifucad/gui/frontends/gtk4/frontend.d \
                    src/apps/waifucad_gui.d \
                    -- build/obj/wc_threads.o build/obj/wc_temp.o \
                    build/obj/wc_gtk4.o build/obj/wc_gpu_probe.o \
                    ${LDFLAGS:-} $THREAD_LINK_FLAGS $GTK4_LINK_FLAGS $LIBDL_RAW $LIBM_RAW
            else
            # shellcheck disable=SC2086
            "$DC_BIN" $BASE_FLAGS ${DFLAGS:-} \
                $COMMON \
                src/waifucad/gui/frontends/common/frontend.d \
                src/waifucad/gui/frontends/gtk4/frontend.d \
                src/apps/waifucad_gui.d \
                build/obj/wc_threads.o build/obj/wc_temp.o \
                build/obj/wc_gtk4.o build/obj/wc_gpu_probe.o \
                ${LDFLAGS:-} $THREAD_LINK_FLAGS $GTK4_LINK_FLAGS $LIBDL_RAW $LIBM_RAW \
                -o bin/waifucad-gui
            fi
            ;;
    esac
}

build_gui() {
    gui_target_os=$(detect_target_os)
    if [ "$gui_target_os" = macos ]; then
        # macOS uses the native Cocoa/AppKit front-end. GTK4 is not probed,
        # required or linked on this path.
        build_native_cocoa
        # dlopen/libm link spellings come from the probes, so macOS (libSystem
        # folds both in) and minimal Linux hosts both link without hand-edits.
        case "$DC_KIND" in
            ldc|dmd)
                # shellcheck disable=SC2086
                "$DC_BIN" $BASE_FLAGS ${DFLAGS:-} $(version_flag "$DC_KIND" WaifuCadGuiCocoa) \
                    $COMMON \
                    src/waifucad/gui/frontends/common/frontend.d \
                    src/waifucad/gui/frontends/cocoa/frontend.d \
                    src/apps/waifucad_gui.d \
                    build/obj/wc_threads.o build/obj/wc_temp.o \
                    build/obj/wc_cocoa.o build/obj/wc_gpu_probe.o $SHIM_OBJS \
                    ${LDFLAGS:-} $THREAD_LINK_FLAGS $COCOA_LINK_FLAGS $LIBDL_D_FLAGS $LIBM_D_FLAGS \
                    -of=bin/waifucad-gui
                ;;
            gdc)
                if [ "$GDC_SPLIT" = 1 ]; then
                    GDC_EXTRA_FLAGS=$(version_flag "$DC_KIND" WaifuCadGuiCocoa)
                    # shellcheck disable=SC2086
                    gdc_link_app bin/waifucad-gui \
                        src/waifucad/gui/frontends/common/frontend.d \
                        src/waifucad/gui/frontends/cocoa/frontend.d \
                        src/apps/waifucad_gui.d \
                        -- build/obj/wc_threads.o build/obj/wc_temp.o \
                        build/obj/wc_cocoa.o build/obj/wc_gpu_probe.o \
                        ${LDFLAGS:-} $THREAD_LINK_FLAGS $COCOA_LINK_FLAGS $LIBDL_RAW $LIBM_RAW
                else
                # shellcheck disable=SC2086
                "$DC_BIN" $BASE_FLAGS ${DFLAGS:-} $(version_flag "$DC_KIND" WaifuCadGuiCocoa) \
                    $COMMON \
                    src/waifucad/gui/frontends/common/frontend.d \
                    src/waifucad/gui/frontends/cocoa/frontend.d \
                    src/apps/waifucad_gui.d \
                    build/obj/wc_threads.o build/obj/wc_temp.o \
                    build/obj/wc_cocoa.o build/obj/wc_gpu_probe.o \
                    ${LDFLAGS:-} $THREAD_LINK_FLAGS $COCOA_LINK_FLAGS $LIBDL_RAW $LIBM_RAW \
                    -o bin/waifucad-gui
                fi
                ;;
        esac
        return
    fi
    build_native_gtk4
    if [ "$WC_HAVE_GTK4" = 1 ]; then
        # A GTK4 install that compiles but does not link (missing or unversioned
        # libraries, dependencies in unlisted directories) must not stop the
        # build: report the linker errors and relink against the stub frontend.
        # Set WC_GTK4_REQUIRED=1 to make that a hard failure instead.
        if ! link_gtk4_gui; then
            if [ "${WC_GTK4_REQUIRED:-0}" = 1 ]; then
                echo "Linking the GTK4 frontend failed and WC_GTK4_REQUIRED=1 is set." >&2
                exit 1
            fi
            echo "WARNING: linking against GTK4 failed; building the GUI without the GTK4 frontend." >&2
            echo "  GTK4 flags used: $GTK4_LINK_FLAGS" >&2
            echo "  Fix them with GTK4_CFLAGS/GTK4_LIBS (or WC_GTK4_PREFIX) and rebuild." >&2
            GTK4_FORCE_STUB=1
            build_native_gtk4
            link_gtk4_gui
        fi
    else
        link_gtk4_gui
    fi
}

build_native_threads
build_native_temp_files

# A binary that was built but dies at start-up is worth saying so loudly: the
# build host is often not the place anyone looks first (e.g. SIGILL on SPARC).
verify_batch_starts() {
    if [ "${WC_SKIP_SELFTEST:-0}" = 1 ] || [ ! -x bin/waifucad-batch ]; then
        return 0
    fi
    selftest_rc=0
    ./bin/waifucad-batch --help >/dev/null 2>&1 || selftest_rc=$?
    case "$selftest_rc" in
        126|127) ;; # cross-compiled or not runnable here
        0) echo "Self-test: bin/waifucad-batch --help ran successfully." ;;
        *)
            if [ "$selftest_rc" -gt 128 ]; then
                echo "WARNING: bin/waifucad-batch was killed by signal $((selftest_rc - 128)) on start-up (SIGILL is 4, SIGSEGV is 11, SIGBUS is 10)." >&2
                echo "  Rebuild with WC_DEBUG=1 ./build.sh batch and run it under gdb or dbx to find the faulting instruction." >&2
            else
                echo "WARNING: bin/waifucad-batch --help exited with status $selftest_rc." >&2
            fi
            ;;
    esac
}

case "$MODE" in
    batch)
        build_one bin/waifucad-batch src/apps/waifucad_batch.d
        verify_batch_starts
        ;;
    gui)
        build_gui
        ;;
    all)
        build_one bin/waifucad-batch src/apps/waifucad_batch.d
        build_gui
        verify_batch_starts
        ;;
    *)
        echo "Usage: ./build.sh [batch|gui|all|clean]" >&2
        exit 2
        ;;
esac
