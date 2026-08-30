#!/usr/bin/env python3
"""Catch D parser hazards that previously escaped static validation.

This is intentionally lightweight and does not replace compiling with LDC/GDC.
It prevents known WaifuCAD mistakes: reserved identifiers/module components and
implicit adjacent string literal concatenation rejected by current D compilers.
"""
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "src"
RESERVED_IDENTIFIER_HAZARDS = {"body", "scope", "debug", "package"}
D_KEYWORDS = set("""
abstract alias align asm assert auto body bool break byte case cast catch cdouble
cent cfloat char class const continue creal dchar debug default delegate delete
deprecated do double else enum export extern false final finally float for foreach
foreach_reverse function goto idouble if ifloat immutable import in inout int
interface invariant ireal is lazy long macro mixin module new nothrow null out
override package pragma private protected public pure real ref return scope shared
short static struct super switch synchronized template this throw true try typedef
typeid typeof ubyte uint ulong union unittest ushort version void volatile wchar
while with
""".split())


def mask_non_code(text: str) -> str:
    # Preserve newlines so line numbers remain meaningful.
    def keep_lines(match: re.Match[str]) -> str:
        return "".join("\n" if ch == "\n" else " " for ch in match.group(0))
    text = re.sub(r"/\*.*?\*/", keep_lines, text, flags=re.S)
    text = re.sub(r"//[^\n]*", keep_lines, text)
    text = re.sub(r'"(?:\\.|[^"\\])*"', keep_lines, text)
    text = re.sub(r"'(?:\\.|[^'\\])*'", keep_lines, text)
    return text


errors: list[str] = []
for path in sorted(SRC.rglob("*.d")):
    original = path.read_text(encoding="utf-8", errors="replace")
    lines = original.splitlines()

    # D disallows keyword components in module/package names, e.g. .debug.
    module_match = re.search(r"^\s*module\s+([A-Za-z_][\w.]*)\s*;", original, re.M)
    if module_match:
        for component in module_match.group(1).split("."):
            if component in D_KEYWORDS:
                line = original.count("\n", 0, module_match.start()) + 1
                errors.append(f"{path.relative_to(ROOT)}:{line}: keyword '{component}' in module name")

    code = mask_non_code(original)
    for hazard in RESERVED_IDENTIFIER_HAZARDS:
        for match in re.finditer(rf"\b{re.escape(hazard)}\b", code):
            line = code.count("\n", 0, match.start()) + 1
            errors.append(f"{path.relative_to(ROOT)}:{line}: reserved word '{hazard}' appears in code")

    # Catch D keywords used as declaration identifiers without rejecting legal
    # storage-class uses such as `foreach (ref entry; values)`.  `auto ref =`
    # is particularly easy to write when porting C/C++ geometry code.
    declaration_types = r"auto|bool|byte|char|double|float|int|long|real|short|ubyte|uint|ulong|ushort|wchar|dchar|size_t|BRepId|BRepVec3"
    for keyword in D_KEYWORDS:
        for match in re.finditer(rf"\b(?:{declaration_types})\s+({re.escape(keyword)})\b(?=\s*(?:=|;|,|\[))", code):
            line = code.count("\n", 0, match.start(1)) + 1
            errors.append(f"{path.relative_to(ROOT)}:{line}: D keyword '{keyword}' used as declaration identifier")

    # Current D compilers reject C-style implicit concatenation of adjacent
    # string literals. Require an explicit ~ between lines.
    for i in range(len(lines) - 1):
        left = lines[i].strip()
        right = lines[i + 1].strip()
        if re.search(r'"\s*$', left) and re.match(r'^"', right):
            errors.append(f"{path.relative_to(ROOT)}:{i + 1}: adjacent string literals require '~'")

if errors:
    print("D parser-hazard validation failed:", file=sys.stderr)
    for error in errors:
        print(f"  {error}", file=sys.stderr)
    raise SystemExit(1)

print("D parser-hazard validation passed.")


