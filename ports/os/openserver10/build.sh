#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../../.." && pwd)
exec "$ROOT/build/os/openserver10.sh" "$@"



