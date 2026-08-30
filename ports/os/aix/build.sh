#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../../.." && pwd)
exec "$ROOT/build/os/aix.sh" "$@"



