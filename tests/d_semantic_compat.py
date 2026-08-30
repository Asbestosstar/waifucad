#!/usr/bin/env python3
"""Catch known D/LDC semantic portability mistakes before compilation."""
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "src"
errors: list[str] = []

for path in sorted(SRC.rglob("*.d")):
    text = path.read_text(encoding="utf-8", errors="replace")
    rel = path.relative_to(ROOT)

    # D's size_t is a built-in alias made available through object.d.  Phobos/
    # druntime versions do not consistently export it from core.stdc.stddef.
    if re.search(r"^\s*import\s+core\.stdc\.stddef\s*:\s*[^;]*\bsize_t\b", text, re.M):
        errors.append(f"{rel}: import size_t from D/object, not core.stdc.stddef")


    # core.stdc.stdlib strtod/strtoul use inout(char) for both the input and
    # end-pointer.  With const input text, the end pointer must also be const.
    if ("strtod" in text or "strtoul" in text) and re.search(r"\bchar\s*\*\s*end\s*=\s*null\s*;", text):
        errors.append(f"{rel}: strtod/strtoul end pointer must be const(char)* for const input")

    # Conditional expressions sourced from const aggregate members can also
    # infer a const-qualified value under LDC.  Locals that are normalised or
    # otherwise reassigned must use an explicit mutable value type.
    if rel == "src/waifucad/brep/advanced.d":
        if re.search(r"\bauto\s+reference\s*=\s*segments\[0\]", text):
            errors.append(f"{rel}: mutable BRep vector `reference` must use explicit BRepVec3 type")

    # Reading through const(char)* with `auto` can infer a const-qualified
    # scalar under LDC. If that local is subsequently rewritten (as in the
    # Ruby punctuation lexer), give it an explicit mutable `char` type.
    if rel.as_posix() == "src/waifucad/scl/ruby_syntax.d":
        if re.search(r"\bauto\s+value\s*=\s*input\s*\[\s*i\s*\]\s*;", text):
            errors.append(f"{rel}: mutable lexer scalar must be `char value = input[i]`, not auto")

    # In a D struct member function, `this` is the struct lvalue, not a pointer.
    if re.search(r"\*this\s*=\s*[A-Za-z_][A-Za-z0-9_]*\.init\s*;", text):
        errors.append(f"{rel}: assign struct defaults with `this = Type.init`, not `*this = ...`")


    # Model expression recursion is a free helper taking Model*. Inside a
    # struct member function, pass &this rather than the Model lvalue itself.
    if rel.as_posix() == "src/waifucad/kernel/model.d":
        if re.search(r"\bevaluateParameterRecursive\(\s*this\s*,", text):
            errors.append(f"{rel}: evaluateParameterRecursive expects Model*; pass &this")
        if "WC_EXPRESSION_UNKNOWN_NAME" in text and not re.search(
            r"import\s+waifucad\.kernel\.expressions\s*:[^;]*\bWC_EXPRESSION_UNKNOWN_NAME\b", text
        ):
            errors.append(f"{rel}: WC_EXPRESSION_UNKNOWN_NAME is used but not selectively imported")

    # EntityId is intentionally selectively imported into BetterC modules.
    # Catch the interpreter regression where a new EntityId local was added
    # without extending the waifucad.kernel.types import list.
    if rel.as_posix() == "src/waifucad/scl/interpreter.d":
        if re.search(r"\bEntityId\b", text) and not re.search(
            r"import\s+waifucad\.kernel\.types\s*:[^;]*\bEntityId\b", text
        ):
            errors.append(f"{rel}: EntityId is used but not selectively imported")

    # Prefix const on pointer fields can make the pointer itself immutable under
    # D's transitive qualifier rules.  Use const(T)* when the pointee is const
    # but the field must be reassignable (e.g. active Section context).
    if re.search(r"^\s*const\s+SectionDescriptorV1\s*\*\s*active\s*;", text, re.M):
        errors.append(f"{rel}: SectionContext.active must be const(SectionDescriptorV1)*")

    # Ribbon tables contain pointers. Making the aggregate transitively
    # immutable can reject otherwise valid const-pointer initialisers in LDC.
    if "RibbonTabDescriptorV1" in text or "RibbonCommandDescriptorV1" in text:
        if re.search(r"\bimmutable\s+Ribbon(?:Tab|Command)DescriptorV1", text):
            errors.append(f"{rel}: ribbon descriptor tables must be __gshared const, not immutable")

if errors:
    print("D semantic compatibility validation failed:", file=sys.stderr)
    for error in errors:
        print(f"  {error}", file=sys.stderr)
    raise SystemExit(1)

print("D semantic compatibility validation passed.")


