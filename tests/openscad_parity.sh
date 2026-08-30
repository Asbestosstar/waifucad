#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT"

python3 - <<'PY'
import json
from pathlib import Path

parity = json.loads(Path('config/openscad_parity.json').read_text())
items = {(item['category'], item['openscad']) for item in parity['capabilities']}
required = {
    ('syntax','variable assignment'), ('syntax','ternary ?:'), ('syntax','function'), ('syntax','module'), ('syntax','include'), ('syntax','use'),
    ('constants','undef'), ('constants','PI'),
    ('2D','circle'), ('2D','square'), ('2D','polygon'), ('2D','text'), ('2D','import DXF/SVG'), ('2D','projection'),
    ('3D','sphere'), ('3D','cube'), ('3D','cylinder'), ('3D','cylinder r1/r2'), ('3D','polyhedron'), ('3D','import STL/OFF/AMF/3MF'),
    ('3D','linear_extrude'), ('3D','rotate_extrude'), ('3D','surface DAT/PNG'),
    ('transformations','translate'), ('transformations','rotate Euler'), ('transformations','rotate axis-angle'), ('transformations','scale'),
    ('transformations','resize'), ('transformations','mirror'), ('transformations','multmatrix'), ('transformations','color'),
    ('transformations','offset'), ('transformations','hull'), ('transformations','minkowski'),
    ('booleans','union'), ('booleans','difference'), ('booleans','intersection'),
    ('flow control','for'), ('flow control','intersection_for'), ('flow control','if'), ('flow control','let'),
    ('type tests','is_undef'), ('type tests','is_bool'), ('type tests','is_num'), ('type tests','is_string'), ('type tests','is_list'), ('type tests','is_function'),
    ('other','echo'), ('other','render'), ('other','children'), ('other','assert'),
    ('functions','concat'), ('functions','lookup'), ('functions','str'), ('functions','chr'), ('functions','ord'), ('functions','search'),
    ('functions','version'), ('functions','version_num'), ('functions','parent_module'),
    ('mathematical','abs'), ('mathematical','sign'), ('mathematical','sin'), ('mathematical','cos'), ('mathematical','tan'),
    ('mathematical','acos'), ('mathematical','asin'), ('mathematical','atan'), ('mathematical','atan2'), ('mathematical','floor'),
    ('mathematical','round'), ('mathematical','ceil'), ('mathematical','ln'), ('mathematical','len'), ('mathematical','log'),
    ('mathematical','pow'), ('mathematical','sqrt'), ('mathematical','exp'), ('mathematical','rands'), ('mathematical','min'),
    ('mathematical','max'), ('mathematical','norm'), ('mathematical','cross'),
}
missing = sorted(required - items)
if missing:
    raise SystemExit(f'missing OpenSCAD parity records: {missing}')

source = Path('src/waifucad/scl/interpreter.d').read_text()
for command in [
    'sketch', 'sketch_line', 'sketch_arc', 'dumb_body', 'circle', 'square', 'polygon', 'text',
    'sphere', 'sphere_d', 'cube', 'cylinder', 'cylinder_d', 'frustum', 'frustum_d', 'polyhedron', 'linear_extrude', 'rotate_extrude',
    'translate', 'rotate_axis', 'scale', 'resize', 'mirror', 'multmatrix', 'colour', 'offset', 'offset_r',
    'hull', 'minkowski', 'union', 'difference', 'intersection', 'module', 'function', 'call_function',
    'range', 'for', 'intersection_for', 'if', 'let', 'type_test', 'lookup', 'rands', 'cross', 'norm'
]:
    if f'"{command}".ptr' not in source:
        raise SystemExit(f'interpreter command missing: {command}')

roles = Path('src/waifucad/kernel/types.d').read_text()
for role in ['preferredParametric', 'sketchGeometry', 'directParametric', 'roughCurve', 'dumbBody']:
    if role not in roles:
        raise SystemExit(f'modelling role missing: {role}')

# Important semantic commitments beyond command-name presence.
for fragment in [
    'int executeUseFile',
    '"--children".ptr',
    'context.runtime.parentCall',
    'code > 0x10FFFFu',
    'code >= 0xD800u',
]:
    if fragment not in source:
        raise SystemExit(f'OpenSCAD semantic support missing: {fragment}')

if any(item.get('layer') == 'compatibility' for item in parity['capabilities']):
    raise SystemExit('parity manifest still contains compatibility-only entries')

print(f"OpenSCAD parity manifest: {len(parity['capabilities'])} mapped capabilities")
PY

echo "OpenSCAD parity/model-policy checks passed."



