#!/usr/bin/env python3
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
profiles=(ROOT/'src/waifucad/kernel/profiles.d').read_text()
advanced=(ROOT/'src/waifucad/brep/advanced.d').read_text()
backend=(ROOT/'src/waifucad/kernel/waifubrep_backend.d').read_text()
types=(ROOT/'src/waifucad/brep/types.d').read_text()
for token in ['ProfileRegionKind : ubyte { none, polygon, circle, mixed }','resolveSketchMixedLoop','arcSegment','BRepProfileSegment']:
    assert token in profiles, token
for token in ['makeProfilePrism','addCircleArcEdge','addCylinderFace','one unambiguous outer loop']:
    assert token in advanced, token
assert 'ProfileRegionKind.mixed' in backend and 'makeProfilePrism' in backend
assert 'BRepProfileSegmentKind' in types
print('Mixed line/arc exact extrusion static validation passed.')

