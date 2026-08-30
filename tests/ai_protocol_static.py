#!/usr/bin/env python3
"""Static guard for the provider-neutral AI C ABI and inspection boundary."""
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
text = (ROOT / "src/waifucad/ai/protocol.d").read_text()
arch = (ROOT / "docs/ARCHITECTURE.md").read_text()

for required in (
    "struct AiRequestV1", "struct AiResponseV1", "struct AiProviderV1",
    "extern(C) alias AiInvokeV1Fn", "extern(C) alias AiReleaseResponseV1Fn",
    "enum AiCapability : ulong", "inspectDocument", "proposeScl", "validateScl",
    "executeScl", "captureViewport", "providerSupports",
):
    assert required in text, f"AI protocol missing {required}"

# Raw kernel/model pointers must never cross this provider boundary.
assert not re.search(r"\b(?:Model|BRepArena|Feature|Parameter)\s*\*", text), "raw model/kernel pointer leaked into AI ABI"
assert "read-only SCL/WCS getter" in text
assert "AI code does not receive raw model pointers" in arch
print("Provider-neutral AI protocol static validation passed.")

