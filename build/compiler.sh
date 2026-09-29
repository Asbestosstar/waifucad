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
