#!/usr/bin/env python3
from pathlib import Path
import re
root=Path(__file__).resolve().parents[1]
scripts=sorted(path for path in root.rglob("*.wcs") if "build" not in path.parts)
assert scripts,"no .wcs scripts found"
call=re.compile(r"^[A-Za-z_][A-Za-z0-9_]*\s*\(.*\)\s*$")
assignment=re.compile(r"^[A-Za-z_$][A-Za-z0-9_$]*\s*=\s*.+$")
flow=re.compile(r"^(?:if\b.*\bthen\b.*\bend|for\b.*\bin\b.*\bdo\b.*\bend)\s*$")
violations=[]
for path in scripts:
    for lineno,raw in enumerate(path.read_text().splitlines(),1):
        line=raw.strip()
        if not line or line.startswith("#"): continue
        if call.match(line) or assignment.match(line) or flow.match(line): continue
        violations.append(f"{path.relative_to(root)}:{lineno}: {line}")
if violations: raise SystemExit("Non-Ruby-like source found under .wcs:\n  "+"\n  ".join(violations))
legacy=sorted((root/"examples"/"scripts"/"legacy").glob("*.scl"))
assert legacy,"legacy .scl compatibility examples missing"
print(f"WCS extension policy: OK ({len(scripts)} Ruby-like .wcs, {len(legacy)} legacy .scl)")

