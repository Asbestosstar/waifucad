#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
MODE=${1:-all}
shift || true
# solaris build entry point. Port status is tracked in config/targets.json.
WC_TARGET_OS=solaris
WC_TARGET_BITS=64
WC_THREAD_IMPL=${WC_THREAD_IMPL:-posix}
export WC_TARGET_OS WC_TARGET_BITS WC_THREAD_IMPL
exec "$ROOT/build.sh" "$MODE" "$@"



