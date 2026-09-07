#!/usr/bin/env python3
from pathlib import Path

root = Path(__file__).resolve().parents[1]
interp = (root / 'src/waifucad/scl/interpreter.d').read_text()
datums = (root / 'src/waifucad/kernel/datums.d').read_text()
cocoa = (root / 'src/waifucad/gui/frontends/cocoa/frontend.d').read_text()
gtk4 = (root / 'src/waifucad/gui/frontends/gtk4/frontend.d').read_text()

for token in ['tokens.count == 4', 'FeatureKind.datumCsys', 'tokens.count == 5', '"face".ptr', 'persistentTopologyOwner']:
    assert token in interp, f'direct Sketch SCL support missing {token}'
for token in ['strcmp(sketch.payload.ptr(), "face".ptr)', 'support.kind == FeatureKind.datumCsys', 'planarFaceFrame']:
    assert token in datums, f'sketchFrame direct support missing {token}'
for frontend in [cocoa, gtk4]:
    assert '"sketch_support".ptr' not in frontend
    assert 'datum_plane_from_csys' not in frontend
    assert 'datum_plane_from_face' not in frontend
    assert 'sketch(:%s, :%s, :%s)' in frontend
    assert 'sketch(:%s, :%s, :face, %s)' in frontend
print('Direct Sketch support semantics regression passed.')
