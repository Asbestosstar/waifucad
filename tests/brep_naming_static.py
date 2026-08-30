#!/usr/bin/env python3
from pathlib import Path
root = Path(__file__).resolve().parents[1]
types = (root / 'src/waifucad/brep/types.d').read_text()
naming = (root / 'src/waifucad/brep/naming.d').read_text()
backend = (root / 'src/waifucad/kernel/waifubrep_backend.d').read_text()
assert 'alias BRepPersistentId = ulong;' in types
for kind in ('body', 'face', 'edge', 'vertex'):
    assert kind in naming
assert 'ownerFeatureId << 32' in naming or 'cast(ulong)ownerFeatureId << 32' in naming
assert 'assignPrimitivePersistentTopology' in backend
assert 'ownsTopology = false' in backend
print('persistent topology naming static checks passed')

