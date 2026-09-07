#!/bin/bash
set -euo pipefail
TARGET=${1:-/Users/macbook/git/waifucad}
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
if [ ! -d "$TARGET/native/gui/cocoa" ]; then
  echo "WaifuCAD tree not found at: $TARGET" >&2
  exit 2
fi
FILES=(
  AGENTS.MD
  HANDOFF_PROMPT.md
  docs/GUI.md
  native/gui/cocoa/wc_cocoa.m
  src/waifucad/gui/frontends/cocoa/frontend.d
  src/waifucad/gui/frontends/gtk4/frontend.d
  src/waifucad/kernel/datums.d
  src/waifucad/scl/GRAMMAR.md
  src/waifucad/scl/interpreter.d
  tests/cocoa_empty_csys_alignment.py
  tests/cocoa_feature_picker_static.py
  tests/sketch_direct_support_static.py
  tests/cocoa_frontend_static.py
  tests/cocoa_face_selection_static.py
)
for f in "${FILES[@]}"; do
  mkdir -p "$TARGET/$(dirname "$f")"
  cp "$HERE/$f" "$TARGET/$f"
done
cd "$TARGET"
python3 tests/cocoa_empty_csys_alignment.py
python3 tests/cocoa_feature_picker_static.py
python3 tests/sketch_direct_support_static.py
python3 tests/cocoa_frontend_static.py
python3 tests/cocoa_face_selection_static.py
python3 tests/gui_body_bounds_default.py
python3 tests/d_parser_hazards.py
python3 tests/d_semantic_compat.py
python3 tests/p1_modelling_kernel_static.py
python3 tests/objective_c_context_static.py
bash tests/cocoa_native_syntax.sh
bash make_todos.sh
rm -f build/obj/wc_cocoa.o bin/waifucad-gui
bash build.sh gui
printf '\nInstalled Cocoa v7. Start with:\n  %s/bin/waifucad-gui\n' "$TARGET"
