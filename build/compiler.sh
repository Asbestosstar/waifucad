#!/bin/sh
# Compiler flag normalisation for WaifuCAD. Keep platform-specific spelling here.
set -eu

pick_compiler() {
    if [ -n "${DC:-}" ]; then
        printf '%s\n' "$DC"
        return
    fi
    if command -v ldc2 >/dev/null 2>&1; then
        printf '%s\n' ldc2
        return
    fi
    if command -v gdc >/dev/null 2>&1; then
        printf '%s\n' gdc
        return
    fi
    if command -v dmd >/dev/null 2>&1; then
        printf '%s\n' dmd
        return
    fi
    echo "No supported D compiler found. Set DC=ldc2, DC=gdc or DC=dmd." >&2
    exit 2
}

pick_c_compiler() {
    if [ -n "${CC:-}" ]; then
        printf '%s\n' "$CC"
        return
    fi
    if command -v cc >/dev/null 2>&1; then
        printf '%s\n' cc
        return
    fi
    if command -v gcc >/dev/null 2>&1; then
        printf '%s\n' gcc
        return
    fi
    if command -v clang >/dev/null 2>&1; then
        printf '%s\n' clang
        return
    fi
    echo "No C compiler found. Set CC to a compiler that can build the native thread shim." >&2
    exit 2
}

compiler_kind() {
    if [ -n "${DC_KIND:-}" ]; then
        case "$DC_KIND" in
            ldc|gdc|dmd) printf '%s\n' "$DC_KIND"; return ;;
            *) echo "DC_KIND must be 'ldc', 'gdc' or 'dmd'." >&2; exit 2 ;;
        esac
    fi
    case "$(basename "$1")" in
        ldc2|ldmd2) printf '%s\n' ldc ;;
        gdc*) printf '%s\n' gdc ;;
        dmd|dmd2) printf '%s\n' dmd ;;
        *) echo "Unsupported compiler '$1'. Set DC_KIND=ldc, DC_KIND=gdc or DC_KIND=dmd for a port-specific compiler name." >&2; exit 2 ;;
    esac
}

betterc_flags() {
    case "$1" in
        ldc) printf '%s\n' '-betterC -wi -I=src' ;;
        gdc) printf '%s\n' '-fno-druntime -Wall -Isrc' ;;
        dmd) printf '%s\n' '-betterC -wi -I=src' ;;
    esac
}

# DMD's -betterC code generator lowers array/struct fills to druntime memset
# helpers (_memsetDouble, _memset32, ...), but -betterC links no druntime.
# native/runtime/wc_betterc_shims.c provides them in plain C. LDC and GDC emit
# their own inline fills and need nothing. Echoes the object path (dmd) or
# nothing (ldc/gdc).
betterc_shim_objects() {
    kind="$1"
    dir="$2"
    if [ "$kind" != dmd ]; then
        return
    fi
    mkdir -p "$dir"
    cc_bin=$(pick_c_compiler)
    "$cc_bin" ${CFLAGS:-} -std=c11 -O2 -Wall -Wextra \
        -c native/runtime/wc_betterc_shims.c -o "$dir/wc_betterc_shims.o"
    printf '%s\n' "$dir/wc_betterc_shims.o"
}

# --- Optional dependency probing -------------------------------------------
#
# WaifuCAD has no required third-party libraries: PNG output is written by
# src/waifucad/render/png.d directly, and Vulkan/GTK4 are discovered at
# runtime. The only system libraries referenced at link time are libm, libdl
# and POSIX threads, and even those are optional on modern systems (glibc
# 2.34+ folds libdl/libpthread into libc). Probing instead of assuming keeps
# the build working on minimal and non-glibc hosts.
#
# The detectors print eval-able assignment lines (WC_HAVE_*=..., *_RAW=...)
# because command substitution would run them in a subshell and lose plain
# global variables.

WC_PROBE_DIR=build/probes

# probe_c_links <source-file> [flags...]: compile AND link, quietly.
probe_c_links() {
    src="$1"
    shift
    mkdir -p "$WC_PROBE_DIR"
    # shellcheck disable=SC2086
    "$CC_BIN" ${CFLAGS:-} -std=c11 -Werror "$src" "$@" -o "$WC_PROBE_DIR/probe.bin" >/dev/null 2>&1
}

detect_libm() {
    mkdir -p "$WC_PROBE_DIR"
    cat > "$WC_PROBE_DIR/libm.c" <<'EOF'
#include <math.h>
int main(int argc, char** argv) {
    (void)argv;
    volatile double x = (double)argc + 0.25;
    return (int)(sqrt(x) + cos(x) + sin(x));
}
EOF
    if probe_c_links "$WC_PROBE_DIR/libm.c"; then
        printf 'WC_HAVE_LIBM=1\nLIBM_RAW=%s\n' "''"
    elif probe_c_links "$WC_PROBE_DIR/libm.c" -lm; then
        printf 'WC_HAVE_LIBM=1\nLIBM_RAW=%s\n' "'-lm'"
    else
        printf 'WC_HAVE_LIBM=0\nLIBM_RAW=%s\n' "''"
    fi
}

detect_libdl() {
    mkdir -p "$WC_PROBE_DIR"
    cat > "$WC_PROBE_DIR/libdl.c" <<'EOF'
#define _POSIX_C_SOURCE 200809L
#include <dlfcn.h>
int main(void) {
    void* h = dlopen("libwaifucad_probe_nonexistent.so", RTLD_LAZY);
    if (h == (void*)0) return 0;
    return dlsym(h, "waifucad_probe") != (void*)0;
}
EOF
    if probe_c_links "$WC_PROBE_DIR/libdl.c"; then
        printf 'WC_HAVE_DLOPEN=1\nLIBDL_RAW=%s\n' "''"
    elif probe_c_links "$WC_PROBE_DIR/libdl.c" -ldl; then
        printf 'WC_HAVE_DLOPEN=1\nLIBDL_RAW=%s\n' "'-ldl'"
    else
        printf 'WC_HAVE_DLOPEN=0\nLIBDL_RAW=%s\n' "''"
    fi
}

detect_posix_threads() {
    mkdir -p "$WC_PROBE_DIR"
    cat > "$WC_PROBE_DIR/pthread.c" <<'EOF'
#define _POSIX_C_SOURCE 200809L
#include <pthread.h>
static void* worker(void* p) { return p; }
int main(void) {
    pthread_t t;
    if (pthread_create(&t, (pthread_attr_t*)0, worker, (void*)0) != 0) return 1;
    return pthread_join(t, (void**)0);
}
EOF
    if probe_c_links "$WC_PROBE_DIR/pthread.c" -pthread -lpthread; then
        printf 'WC_HAVE_PTHREAD=1\nPTHREAD_CFLAGS_RAW=%s\nPTHREAD_LDFLAGS_RAW=%s\n' "'-pthread'" "'-lpthread'"
    elif probe_c_links "$WC_PROBE_DIR/pthread.c" -pthread; then
        printf 'WC_HAVE_PTHREAD=1\nPTHREAD_CFLAGS_RAW=%s\nPTHREAD_LDFLAGS_RAW=%s\n' "'-pthread'" "''"
    elif probe_c_links "$WC_PROBE_DIR/pthread.c"; then
        printf 'WC_HAVE_PTHREAD=1\nPTHREAD_CFLAGS_RAW=%s\nPTHREAD_LDFLAGS_RAW=%s\n' "''" "''"
    else
        printf 'WC_HAVE_PTHREAD=0\nPTHREAD_CFLAGS_RAW=%s\nPTHREAD_LDFLAGS_RAW=%s\n' "''" "''"
    fi
}

# POSIX threads are the first native multicore bridge. Historical targets may
# override both values without touching the D source, for example:
#   THREAD_CFLAGS='-D_REENTRANT' THREAD_LDFLAGS='-lpthread' ./build.sh batch
thread_cflags() {
    printf '%s\n' "${THREAD_CFLAGS:--pthread}"
}

thread_ldflags() {
    # The D link step needs the pthread library, not the GCC/Clang compile-driver
    # switch.  In particular, ldc2 rejects a raw `-pthread` argument.
    printf '%s\n' "${THREAD_LDFLAGS:--lpthread}"
}

# Convert raw C link flags to the spelling the D compiler driver wants:
#   ldc: -L=<flag>   dmd: -L<flag>   gdc: pass through
# A raw -pthread is a compile-driver switch, meaningless to a linker, so it
# becomes the library form -lpthread before wrapping.
d_link_flags() {
    kind="$1"
    shift
    out=
    for flag in "$@"; do
        case "$flag" in
            -pthread) flag=-lpthread ;;
        esac
        case "$kind" in
            ldc)
                case "$flag" in
                    -L=*) converted="$flag" ;;
                    *) converted="-L=$flag" ;;
                esac
                ;;
            dmd) converted="-L$flag" ;;
            gdc) converted="$flag" ;;
        esac
        if [ -n "$out" ]; then
            out="$out $converted"
        else
            out="$converted"
        fi
    done
    printf '%s\n' "$out"
}

thread_d_link_flags() {
    # shellcheck disable=SC2046
    d_link_flags "$1" $(thread_ldflags)
}

version_flag() {
    kind="$1"
    ident="$2"
    case "$kind" in
        ldc) printf '%s\n' "-d-version=$ident" ;;
        gdc) printf '%s\n' "-fversion=$ident" ;;
        dmd) printf '%s\n' "-version=$ident" ;;
    esac
}

# --- Parallel builds ----------------------------------------------------------
#
# gdc has no built-in multi-threaded or incremental driver: handing it every
# source in one command compiles the whole program on a single core, which is
# painfully slow on SPARC and other many-slow-core hosts. build.sh therefore
# compiles gdc modules one object per module and runs several compilers at once.
# ldc and dmd keep their single-command path.

# detect_job_count: WC_JOBS wins; otherwise the online processor count capped at
# 16 (each gdc job can take a few hundred MiB). Works on Solaris, Linux, BSD, macOS.
detect_job_count() {
    jobs_value=${WC_JOBS:-}
    case "$jobs_value" in
        ''|*[!0-9]*|0) jobs_value= ;;
        *) printf '%s\n' "$jobs_value"; return ;;
    esac
    jobs_value=$(getconf _NPROCESSORS_ONLN 2>/dev/null || true)
    case "$jobs_value" in ''|*[!0-9]*) jobs_value= ;; esac
    if [ -z "$jobs_value" ] && command -v nproc >/dev/null 2>&1; then
        jobs_value=$(nproc 2>/dev/null || true)
    fi
    case "$jobs_value" in ''|*[!0-9]*) jobs_value= ;; esac
    if [ -z "$jobs_value" ] && command -v psrinfo >/dev/null 2>&1; then
        jobs_value=$(psrinfo 2>/dev/null | wc -l | tr -d ' ')
    fi
    case "$jobs_value" in ''|*[!0-9]*) jobs_value= ;; esac
    if [ -z "$jobs_value" ] && command -v sysctl >/dev/null 2>&1; then
        jobs_value=$(sysctl -n hw.ncpu 2>/dev/null || true)
    fi
    case "$jobs_value" in ''|*[!0-9]*|0) jobs_value=1 ;; esac
    if [ "$jobs_value" -gt 16 ]; then
        jobs_value=16
    fi
    printf '%s\n' "$jobs_value"
}

# gdc_compile_objects OBJDIR SOURCE...: compile every D source to its own object
# in OBJDIR, up to detect_job_count compilers at a time. Needs DC_BIN, BASE_FLAGS
# and optionally DFLAGS / GDC_EXTRA_FLAGS. Sets GDC_OBJS to the object list.
gdc_compile_objects() {
    gco_dir="$1"
    shift
    mkdir -p "$gco_dir"
    gco_jobs=$(detect_job_count)
    gco_total=$#
    GDC_OBJS=
    gco_pids=
    gco_running=0
    gco_failed=0
    gco_logs=
    echo "gdc: compiling $gco_total modules with $gco_jobs parallel job(s)"
    for gco_src in "$@"; do
        gco_name=$(printf '%s' "${gco_src%.d}" | tr '/' '_')
        gco_obj="$gco_dir/$gco_name.o"
        gco_log="$gco_dir/$gco_name.log"
        GDC_OBJS="$GDC_OBJS $gco_obj"
        gco_logs="$gco_logs $gco_log"
        rm -f "$gco_obj" "$gco_log"
        (
            # shellcheck disable=SC2086
            "$DC_BIN" $BASE_FLAGS ${DFLAGS:-} ${GDC_EXTRA_FLAGS:-} -c "$gco_src" -o "$gco_obj" > "$gco_log" 2>&1
        ) &
        gco_pids="$gco_pids $!"
        gco_running=$((gco_running + 1))
        if [ "$gco_running" -ge "$gco_jobs" ]; then
            gco_first=${gco_pids# }
            gco_first=${gco_first%% *}
            gco_pids=${gco_pids#" $gco_first"}
            wait "$gco_first" || gco_failed=1
            gco_running=$((gco_running - 1))
        fi
    done
    for gco_pid in $gco_pids; do
        wait "$gco_pid" || gco_failed=1
    done
    for gco_log in $gco_logs; do
        if [ -s "$gco_log" ]; then
            cat "$gco_log" >&2
        fi
    done
    if [ "$gco_failed" != 0 ]; then
        echo "gdc: one or more modules failed to compile (see messages above)." >&2
        exit 1
    fi
}

# --- GTK4 discovery -------------------------------------------------------------
#
# pkg-config is the preferred route, but historical hosts (Solaris, minimal
# distributions) often have GTK4 headers and libraries under /usr/include/gtk-4.0
# and /usr/lib without a working gtk4.pc, a pkg-config binary, or a PKG_CONFIG_PATH
# that reaches them. detect_gtk4 tries, in order:
#   1. GTK4_CFLAGS / GTK4_LIBS from the environment (explicit override);
#   2. pkg-config, then pkg-config again with the standard pkgconfig directories
#      under the usual prefixes (WC_GTK4_PREFIX first) added to PKG_CONFIG_PATH;
#   3. a header/library scan of those prefixes that assembles the flags by hand.
# It sets WC_HAVE_GTK4, GTK4_CFLAGS_RAW, GTK4_LIBS_RAW, GTK4_VERSION, GTK4_METHOD
# and, on failure, GTK4_WHY.

gtk4_prefixes() {
    # shellcheck disable=SC2086
    printf '%s\n' ${WC_GTK4_PREFIX:-} /usr /usr/local /opt/csw /opt/local /usr/gnu /opt/gtk4 /opt/gnome /opt/homebrew
}

# 64-bit library directories first: WaifuCAD never links 32-bit libraries.
gtk4_libsubs() {
    printf '%s\n' lib/64 lib/sparcv9 lib/amd64 lib/64-bit lib64 "lib/$(uname -m 2>/dev/null || echo unknown)-linux-gnu" lib
}

gtk4_pkgconfig_dirs() {
    gpd_out=
    for gpd_prefix in $(gtk4_prefixes); do
        gpd_found=0
        for gpd_sub in $(gtk4_libsubs) share; do
            if [ -f "$gpd_prefix/$gpd_sub/pkgconfig/gtk4.pc" ]; then
                gpd_found=1
            fi
        done
        if [ "$gpd_found" = 1 ]; then
            for gpd_sub in $(gtk4_libsubs) share; do
                if [ -d "$gpd_prefix/$gpd_sub/pkgconfig" ]; then
                    gpd_out="${gpd_out:+$gpd_out:}$gpd_prefix/$gpd_sub/pkgconfig"
                fi
            done
        fi
    done
    printf '%s\n' "$gpd_out"
}

gtk4_probe_compiles() {
    mkdir -p "$WC_PROBE_DIR"
    cat > "$WC_PROBE_DIR/gtk4.c" <<'EOP'
#include <gtk/gtk.h>
int main(void) { return GTK_MAJOR_VERSION == 4 ? 0 : 1; }
EOP
    # shellcheck disable=SC2086
    "$CC_BIN" ${CFLAGS:-} -std=c11 $1 -c "$WC_PROBE_DIR/gtk4.c" -o "$WC_PROBE_DIR/gtk4.o" >"$WC_PROBE_DIR/gtk4.log" 2>&1
}

detect_gtk4() {
    WC_HAVE_GTK4=0
    GTK4_CFLAGS_RAW=
    GTK4_LIBS_RAW=
    GTK4_VERSION=unknown
    GTK4_METHOD=
    GTK4_WHY=

    if [ -n "${GTK4_CFLAGS:-}" ]; then
        WC_HAVE_GTK4=1
        GTK4_CFLAGS_RAW=$GTK4_CFLAGS
        GTK4_LIBS_RAW=${GTK4_LIBS:--lgtk-4}
        GTK4_METHOD="GTK4_CFLAGS/GTK4_LIBS override"
        return 0
    fi

    dg_pc=
    for dg_candidate in pkg-config pkgconf; do
        if command -v "$dg_candidate" >/dev/null 2>&1; then
            dg_pc=$dg_candidate
            break
        fi
    done

    if [ -n "$dg_pc" ]; then
        if ! "$dg_pc" --exists gtk4 >/dev/null 2>&1; then
            dg_extra=$(gtk4_pkgconfig_dirs)
            if [ -n "$dg_extra" ]; then
                dg_old_set=${PKG_CONFIG_PATH+set}
                dg_old=${PKG_CONFIG_PATH:-}
                PKG_CONFIG_PATH="$dg_extra${dg_old:+:$dg_old}"
                export PKG_CONFIG_PATH
                if ! "$dg_pc" --exists gtk4 >/dev/null 2>&1; then
                    GTK4_WHY=$("$dg_pc" --print-errors --exists gtk4 2>&1 | tr '\n' ' ' || true)
                    if [ -n "$dg_old_set" ]; then PKG_CONFIG_PATH=$dg_old; else unset PKG_CONFIG_PATH; fi
                fi
            fi
        fi
        if "$dg_pc" --exists gtk4 >/dev/null 2>&1; then
            GTK4_CFLAGS_RAW=$("$dg_pc" --cflags gtk4)
            GTK4_LIBS_RAW=$("$dg_pc" --libs gtk4)
            GTK4_VERSION=$("$dg_pc" --modversion gtk4)
            GTK4_METHOD=$dg_pc
            WC_HAVE_GTK4=1
            return 0
        fi
        if [ -z "$GTK4_WHY" ]; then
            GTK4_WHY=$("$dg_pc" --print-errors --exists gtk4 2>&1 | tr '\n' ' ' || true)
        fi
    else
        GTK4_WHY="no pkg-config or pkgconf in PATH"
    fi

    # Header/library scan.
    for dg_prefix in $(gtk4_prefixes); do
        [ -f "$dg_prefix/include/gtk-4.0/gtk/gtk.h" ] || continue
        dg_libdir=
        for dg_sub in $(gtk4_libsubs); do
            for dg_lib in "$dg_prefix/$dg_sub"/libgtk-4.so*; do
                if [ -e "$dg_lib" ]; then
                    dg_libdir="$dg_prefix/$dg_sub"
                    break 2
                fi
            done
        done
        if [ -z "$dg_libdir" ]; then
            GTK4_WHY="$GTK4_WHY; found $dg_prefix/include/gtk-4.0 but no 64-bit libgtk-4.so under $dg_prefix"
            continue
        fi

        dg_cflags="-I$dg_prefix/include/gtk-4.0"
        for dg_inc in glib-2.0 pango-1.0 harfbuzz cairo gdk-pixbuf-2.0 graphene-1.0 fribidi freetype2 libpng16 pixman-1; do
            if [ -d "$dg_prefix/include/$dg_inc" ]; then
                dg_cflags="$dg_cflags -I$dg_prefix/include/$dg_inc"
            fi
        done
        # glibconfig.h and graphene-config.h live in per-ABI directories.
        for dg_sub in $(gtk4_libsubs); do
            for dg_cfg in glib-2.0/include graphene-1.0/include; do
                if [ -d "$dg_prefix/$dg_sub/$dg_cfg" ]; then
                    dg_cflags="$dg_cflags -I$dg_prefix/$dg_sub/$dg_cfg"
                fi
            done
        done
        # Link by -l<name> when the unversioned development symlink exists;
        # otherwise (common on Solaris, where only libfoo.so.1 may be installed)
        # pass the versioned file by path so ld does not fail with "library not
        # found". Missing optional libraries are skipped.
        dg_libs="-L$dg_libdir -Wl,-R,$dg_libdir"
        for dg_name in gtk-4 pangocairo-1.0 pango-1.0 harfbuzz gdk_pixbuf-2.0 cairo-gobject cairo graphene-1.0 gio-2.0 gobject-2.0 glib-2.0; do
            if [ -e "$dg_libdir/lib$dg_name.so" ]; then
                dg_libs="$dg_libs -l$dg_name"
                continue
            fi
            for dg_lib in "$dg_libdir/lib$dg_name.so".*; do
                if [ -e "$dg_lib" ]; then
                    dg_libs="$dg_libs $dg_lib"
                    break
                fi
            done
        done
        if gtk4_probe_compiles "$dg_cflags"; then
            GTK4_CFLAGS_RAW=$dg_cflags
            GTK4_LIBS_RAW=$dg_libs
            GTK4_VERSION="headers in $dg_prefix/include/gtk-4.0"
            GTK4_METHOD="header scan"
            WC_HAVE_GTK4=1
            return 0
        fi
        GTK4_WHY="$GTK4_WHY; headers in $dg_prefix/include/gtk-4.0 did not compile (see $WC_PROBE_DIR/gtk4.log; set GTK4_CFLAGS/GTK4_LIBS to override)"
    done
    return 0
}
