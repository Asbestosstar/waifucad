#!/usr/bin/env python3
import json
from pathlib import Path

root = Path(__file__).resolve().parents[1]
config = json.loads((root / "config/openscad_interchange.json").read_text())
assert config["policy"]["import_result"] == "dumb_mesh_body"
assert config["policy"]["reconstruct_parametric_history"] is False
assert set(config["import"]["engines"]) == {"auto", "internal", "external"}
assert {"auto", "manifold", "cgal"}.issubset(config["import"]["backends"])
assert {"named_feature", "all_dumb_bodies", "all_bodies"}.issubset(config["export"]["scopes"])

interpreter = (root / "src/waifucad/scl/interpreter.d").read_text()
assert '"scad_import".ptr' in interpreter
assert '"scad_export".ptr' in interpreter

model = (root / "src/waifucad/kernel/model.d").read_text()
types = (root / "src/waifucad/kernel/types.d").read_text()
assert "MeshArena dumbMeshes" in model
assert "addDumbMeshFeature" in model
assert "uint meshId" in types

exporter = (root / "src/waifucad/interchange/openscad/exporter.d").read_text()
assert "polyhedron(points=[" in exporter
assert "wc-body-begin" in exporter
assert "ExactGeometryStatus.exact" in exporter
assert "meshFromPolyhedronPayload" in exporter

importer = (root / "src/waifucad/interchange/openscad/importer.d").read_text()
assert "--export-format=off" in importer
assert "--backend=manifold" in importer
assert "--backend=cgal" in importer
assert "OPENSCADPATH=" in importer
assert " -d " in importer and " -m " in importer
assert "tmpnam" not in importer
assert "makeSecureTemporaryFile" in importer

print("OpenSCAD interchange static contract passed.")


