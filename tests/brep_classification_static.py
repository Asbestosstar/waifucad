#!/usr/bin/env python3
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
s=(ROOT/'src/waifucad/brep/classification.d').read_text()
b=(ROOT/'build.sh').read_text()
for token in ['BRepTrimClassification','BRepPointClassification','classifyPointOnPlanarFace','intersectLineTrimmedPlanarFace','classifyPointInPlanarSolid','BRepCurveKind.line']:
    assert token in s, token
assert 'curved/NURBS faces return unknown' in s
assert 'src/waifucad/brep/classification.d' in b
print('BRep planar trim/classification static validation passed.')

