#!/usr/bin/env python3
"""Validate WaifuCAD's 64-bit-only architecture and target manifests."""
import json
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parent.parent
arch_data = json.loads((ROOT / "config/architectures.json").read_text())
target_data = json.loads((ROOT / "config/targets.json").read_text())

if arch_data.get("requiredAddressBits") != 64:
    raise SystemExit("requiredAddressBits must be 64")

architectures = {}
for arch in arch_data.get("architectures", []):
    ident = arch.get("id")
    if not ident or ident in architectures:
        raise SystemExit(f"invalid or duplicate architecture id: {ident!r}")
    if arch.get("bits") != 64:
        raise SystemExit(f"architecture {ident} is not 64-bit")
    architectures[ident] = arch

if "riscv64" not in architectures:
    raise SystemExit("riscv64 architecture is required")

for target in target_data.get("targets", []):
    ident = target.get("id", "<unnamed>")
    if target.get("bits") != 64:
        raise SystemExit(f"target {ident} is not 64-bit")
    arch = target.get("arch")
    if arch not in architectures:
        raise SystemExit(f"target {ident} uses undeclared architecture {arch!r}")

forbidden = {"rv32", "riscv32", "wasm32", "x86_32", "aarch32", "i386", "i486", "i586", "i686"}
for arch_id in architectures:
    if arch_id.lower() in forbidden:
        raise SystemExit(f"forbidden 32-bit architecture id present: {arch_id}")
for target in target_data.get("targets", []):
    if str(target.get("arch", "")).lower() in forbidden:
        raise SystemExit(f"target {target.get('id', '<unnamed>')} uses a forbidden 32-bit architecture")

print(f"Validated {len(architectures)} 64-bit architectures and {len(target_data.get('targets', []))} 64-bit targets.")


