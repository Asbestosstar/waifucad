#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT"
if ! command -v openscad >/dev/null 2>&1; then
    echo "OpenSCAD CLI probe skipped (openscad not installed)."
    exit 0
fi
mkdir -p build/tests
OUT=build/tests/openscad-probe.off
LOG=build/tests/openscad-probe.log
rm -f "$OUT" "$LOG"
# Keep backend automatic: older stable OpenSCAD versions do not know --backend,
# whereas current versions do. The WaifuCAD importer's auto mode behaves likewise.
openscad --export-format=off -o "$OUT" examples/openscad/external_import_demo.scad >"$LOG" 2>&1
head -c 3 "$OUT" | grep -q '^OFF$'
test -s "$OUT"
echo "OpenSCAD CLI/OFF bridge probe passed."



