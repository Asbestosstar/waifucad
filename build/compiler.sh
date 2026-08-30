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
    echo "No supported D compiler found. Set DC=ldc2 or DC=gdc." >&2
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
            ldc|gdc) printf '%s\n' "$DC_KIND"; return ;;
            *) echo "DC_KIND must be 'ldc' or 'gdc'." >&2; exit 2 ;;
        esac
    fi
    case "$(basename "$1")" in
        ldc2|ldmd2) printf '%s\n' ldc ;;
        gdc*) printf '%s\n' gdc ;;
        *) echo "Unsupported compiler '$1'. Set DC_KIND=ldc or DC_KIND=gdc for a port-specific compiler name." >&2; exit 2 ;;
    esac
}

betterc_flags() {
    case "$1" in
        ldc) printf '%s\n' '-betterC -wi -I=src' ;;
        gdc) printf '%s\n' '-fno-druntime -Wall -Isrc' ;;
    esac
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

thread_d_link_flags() {
    kind="$1"
    raw=$(thread_ldflags)
    case "$kind" in
        ldc)
            # LDC's -L=<flag> forwards a flag to its linker invocation.  Keep
            # this conversion here so build.sh never passes raw -pthread-like
            # C-driver switches to ldc2.
            out=
            for flag in $raw; do
                case "$flag" in
                    -L=*) converted="$flag" ;;
                    *) converted="-L=$flag" ;;
                esac
                if [ -n "$out" ]; then
                    out="$out $converted"
                else
                    out="$converted"
                fi
            done
            printf '%s\n' "$out"
            ;;
        gdc)
            printf '%s\n' "$raw"
            ;;
    esac
}

version_flag() {
    kind="$1"
    ident="$2"
    case "$kind" in
        ldc) printf '%s\n' "-d-version=$ident" ;;
        gdc) printf '%s\n' "-fversion=$ident" ;;
    esac
}



