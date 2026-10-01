#!/usr/bin/env python3
"""Static wiring checks for the undo/redo transaction log."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
read = lambda rel: (ROOT / rel).read_text()

build = read("build.sh")
undo = read("src/waifucad/journal/undo.d")
interpreter = read("src/waifucad/scl/interpreter.d")
api = read("src/waifucad/journal/backend_api.d")
gtk = read("native/gui/gtk4/wc_gtk4.c")
cocoa = read("native/gui/cocoa/wc_cocoa.m")

assert "src/waifucad/journal/undo.d" in build, "undo.d missing from build.sh"
assert "UndoStack* undo;" in api, "ScriptContext lacks the undo log"
for symbol in ("struct UndoStack", "void begin(", "void end(", "UndoStatus undo(", "UndoStatus redo("):
    assert symbol in undo, f"undo.d lacks {symbol}"
for command in ("undo_enable", "undo_disable", "undo_clear", '"undo"', '"redo"'):
    assert command in interpreter, f"interpreter lacks {command}"
assert "Undo (planned)" not in gtk and "Redo (planned)" not in gtk, "GTK4 undo/redo still planned"
assert "Undo (planned)" not in cocoa and "Redo (planned)" not in cocoa, "Cocoa undo/redo still planned"
for source in (gtk, cocoa):
    assert "WC_MENU_UNDO" in source and "WC_MENU_REDO" in source
print("undo/redo static checks passed")
