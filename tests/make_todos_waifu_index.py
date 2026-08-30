from pathlib import Path
import re
import struct

root = Path(__file__).resolve().parents[1]
script = (root / "make_todos.sh").read_text()
assert "## Waifu PNG index" in script
assert "Path('waifus').rglob('*.png')" in script

# make_todos.sh should already have regenerated PROJECT_TREE.txt before this test.
tree = (root / "PROJECT_TREE.txt").read_text()
assert "## Waifu PNG index" in tree
for path in sorted((root / "waifus").rglob("*.png")):
    with path.open("rb") as handle:
        header = handle.read(24)
    assert header[:8] == b"\x89PNG\r\n\x1a\n"
    width, height = struct.unpack(">II", header[16:24])
    expected = f"- {path.relative_to(root).as_posix()} — {width} × {height}"
    assert expected in tree, expected
print("Waifu PNG project-tree index passed.")
