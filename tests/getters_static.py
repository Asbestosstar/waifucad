#!/usr/bin/env python3
"""Validate the read-only SCL/WCS AI inspection surface without a D compiler."""
from pathlib import Path
import json
import re

ROOT = Path(__file__).resolve().parents[1]
source = (ROOT / "src/waifucad/scl/getters.d").read_text()
interpreter = (ROOT / "src/waifucad/scl/interpreter.d").read_text()
build = (ROOT / "build.sh").read_text()
ruby = (ROOT / "src/waifucad/scl/ruby_syntax.d").read_text()
docs = (ROOT / "docs/AI_MODEL_INSPECTION.md").read_text()
schema = json.loads((ROOT / "config/scl_getters.json").read_text())

commands = set(re.findall(r'"(get_[a-z0-9_]+)"\.ptr', source))
schema_commands = {entry["command"] for entry in schema["commands"]}
doc_commands = set(re.findall(r'`(get_[a-z0-9_]+)\b', docs))

required = {
    "get_model_name", "get_parameter_count", "get_parameter_name", "get_parameter_value",
    "get_parameter_dependant_name", "get_feature_count", "get_feature_name", "get_feature_kind",
    "get_feature_role", "get_feature_operand_count", "get_feature_operand_kind",
    "get_feature_operand_name", "get_feature_dependant_name", "get_feature_geometry_status",
    "get_feature_bounds_source", "get_feature_bounds", "get_feature_volume",
    "get_feature_surface_area", "get_feature_centre_of_mass", "get_feature_exact_topology_counts",
    "get_feature_mesh_vertex_count", "get_feature_mesh_triangle_count", "get_pmi_count",
    "get_pmi_name", "get_pmi_kind", "get_pmi_text", "get_pmi_feature_name",
    "get_feature_persistent_body_id", "get_feature_face_persistent_id", "get_topology_kind",
    "get_topology_vertex_point", "get_topology_face_surface_kind",
}
missing = required - commands
assert not missing, f"missing required getters: {sorted(missing)}"
assert len(commands) >= 60, f"getter surface unexpectedly small: {len(commands)}"
assert commands == schema_commands, f"schema/source mismatch: source-only={sorted(commands-schema_commands)} schema-only={sorted(schema_commands-commands)}"
assert commands <= doc_commands, f"undocumented getters: {sorted(commands-doc_commands)}"
assert schema["read_only"] is True and schema["journalled"] is False
assert schema["enumeration_index_base"] == 0
assert schema["persistent_topology_indices"] is False
assert schema["persistent_topology_ids"] is True
assert "src/waifucad/scl/getters.d" in build
assert "isGetterName(tokens.values[2])" in ruby
assert "Internally getters keep the deterministic SCL `COMMAND OUT ...` ABI" in ruby
assert all(entry["wcs"].startswith("out = get_") for entry in schema["commands"])

# Getter dispatch must occur before journal.record so AI reads do not enter the semantic journal.
get_pos = interpreter.index("executeGetter(context, tokens)")
journal_pos = interpreter.index("context.journal.record(originalLine)")
assert get_pos < journal_pos, "getter dispatch must precede journal recording"

wcs = (ROOT / "examples/scripts/model_getters.wcs").read_text()
scl = (ROOT / "examples/scripts/legacy/model_getters.scl").read_text()
assert "base_kind = get_feature_kind(:base)" in wcs
assert "get_feature_kind base_kind base" in scl
assert "base_volume = get_feature_volume(:base)" in wcs

model = (ROOT / "src/waifucad/kernel/model.d").read_text()
assert "previewBounds[i] = BoundingBox.init;" in model
assert "previewErrors[i] = 0;" in model
assert "resolveIndex(context" in source, "getter enumeration must accept runtime numeric indices"

print(f"SCL/WCS getter static validation passed ({len(commands)} getters).")

