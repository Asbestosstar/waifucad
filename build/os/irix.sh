#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
MODE=${1:-all}
shift || true
# irix build entry point. Port status is tracked in config/targets.json.
WC_TARGET_OS=irix
WC_TARGET_BITS=64
WC_THREAD_IMPL=${WC_THREAD_IMPL:-posix}
export WC_TARGET_OS WC_TARGET_BITS WC_THREAD_IMPL
THREAD_CFLAGS=${THREAD_CFLAGS:--D_REENTRANT}
THREAD_LDFLAGS=${THREAD_LDFLAGS:--lpthread}
export THREAD_CFLAGS THREAD_LDFLAGS
exec "$ROOT/build.sh" "$MODE" "$@"



