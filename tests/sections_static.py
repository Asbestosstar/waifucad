#!/usr/bin/env python3
import json
from pathlib import Path

root = Path(__file__).resolve().parents[1]
sections = json.loads((root / "config/sections.json").read_text())
assert sections["default_section"] == "modelling"
assert sections["global_ribbon_tabs"] == ["sections", "mods"]
assert sections["home_ribbon_groups"] == ["scripts"]
ids = [item["id"] for item in sections["sections"]]
assert ids[0] == "modelling"
assert "pmi" in ids and "assembly" in ids
assert "sketch" not in ids
assert next(x for x in sections["sections"] if x["id"] == "pmi")["implemented_ribbon"] is True

loads = json.loads((root / "config/assembly_load_options.json").read_text())
policies = {x["id"] for x in loads["document_level_policies"]}
assert {"fully_loaded", "lightweight", "structure_only", "partial", "load_on_demand"} <= policies
states = set(loads["occurrence_states"])
assert {"fully_loaded", "lightweight", "structure_only", "deferred", "unloaded", "suppressed"} <= states
assert loads["rules"]["suppressed_is_not_unloaded"] is True

registry = (root / "src/waifucad/sections/registry.d").read_text()
assert '"modelling".ptr' in registry
assert '"pmi".ptr' in registry
assert '"sketch".ptr' not in registry
assert "modellingSectionRibbon" in registry and "pmiSectionRibbon" in registry

context = (root / "src/waifucad/sections/context.d").read_text()
assert 'findBuiltInSection("modelling".ptr)' in context
assert "activate(const(char)* id)" in context

pmi = (root / "src/waifucad/sections/pmi/section.d").read_text()
for tab in ("pmi.home", "pmi.dimensions", "pmi.gdt", "pmi.notes", "pmi.exchange"):
    assert f'"{tab}".ptr' in pmi
for command in ("pmi.linear_dimension", "pmi.datum_feature", "pmi.feature_control_frame", "pmi.surface_texture", "pmi.weld_symbol"):
    assert f'"{command}".ptr' in pmi

modelling = (root / "src/waifucad/sections/modelling/section.d").read_text()
assert '"modelling.sketch".ptr' in modelling
assert '"modelling.extrude".ptr' in modelling
assert '"modelling.import_openscad".ptr' in modelling
for command in ("modelling.datum_plane", "modelling.datum_axis", "modelling.datum_csys"):
    assert f'"{command}".ptr' in modelling
for key in ("command.datum_plane", "command.datum_axis", "command.datum_csys"):
    assert key in json.loads((root / "assets/locales/en_GB.json").read_text())
assert '"modelling.datum_plane".ptr, "command.datum_plane".ptr, "cmd_datum_plane".ptr, "modelling.surface".ptr, "group.datum".ptr, cast(uint)RibbonCommandFlags.requiresDocument' in modelling
assert '"modelling.datum_axis".ptr, "command.datum_axis".ptr, "cmd_datum_axis".ptr, "modelling.surface".ptr, "group.datum".ptr, cast(uint)RibbonCommandFlags.requiresDocument' in modelling

agents = (root / "AGENTS.MD").read_text()
assert "fully loaded, lightweight, structure-only, partial and load-on-demand" in agents
assert "Keep `modelling` as the default Section" in agents

print("Sections/PMI/assembly planning static contract passed.")


