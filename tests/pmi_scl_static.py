#!/usr/bin/env python3
from pathlib import Path

root = Path(__file__).resolve().parents[1]
interpreter = (root / "src/waifucad/scl/interpreter.d").read_text()
store = (root / "src/waifucad/sections/pmi/store.d").read_text()
context = (root / "src/waifucad/journal/backend_api.d").read_text()
grammar = (root / "src/waifucad/scl/GRAMMAR.md").read_text()
example = (root / "examples/scripts/pmi_journal.wcs").read_text()

for command in ("pmi_add", "pmi_text", "pmi_visible", "pmi_delete"):
    assert f'"{command}"' in interpreter, command
    assert command in grammar, command

for method in ("findByName", "setText", "setVisible", "removeByName"):
    assert method in store, method

assert "PmiStore* pmi" in context
assert "pmi_add(:note" in example
print("PMI SCL/journal static contract: OK")


