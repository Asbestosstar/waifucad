#!/usr/bin/env python3
from pathlib import Path

root = Path(__file__).resolve().parents[1]
script = (root / "make_todos.sh").read_text()
assert "*.m|*.mm" in script, "Objective-C sources are missing from make_todos.sh"
assert (root / "native/gui/cocoa/wc_cocoa.m").is_file()
# When todos.txt exists, it must contain the native bridge body, not merely the tree entry.
todos = root / "todos.txt"
if todos.exists():
    text = todos.read_text(errors="replace")
    assert "===== BEGIN FILE: native/gui/cocoa/wc_cocoa.m =====" in text
    assert "int wc_cocoa_run(const WcCocoaWindowConfig *config" in text
print("Objective-C AI-context regression passed.")
