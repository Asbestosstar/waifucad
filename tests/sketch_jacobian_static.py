#!/usr/bin/env python3
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
source=(ROOT/'src/waifucad/kernel/sketch_nonlinear.d').read_text()
types=(ROOT/'src/waifucad/kernel/types.d').read_text()
solver=(ROOT/'src/waifucad/kernel/sketch_solver.d').read_text()
build=(ROOT/'build.sh').read_text()
for token in ['WC_SKETCH_JACOBIAN_MAX_VARIABLES = 128','WC_SKETCH_JACOBIAN_MAX_EQUATIONS = 256','analyseSketchJacobian','refineSketchNonlinear','matrixRankPivotedMgs','WC_SKETCH_NONLINEAR_DAMPING']:
    assert token in source, token
for token in ['rankContribution','rankRedundant','jacobianRank','rankDeficiency','rankAnalysisTruncated','underConstrained','overConstrained']:
    assert token in types, token
assert 'refineSketchNonlinear(model' in solver
assert 'src/waifucad/kernel/sketch_nonlinear.d' in build
assert 'recomputeCancelled()' in source
print('Sketch Jacobian/nonlinear static validation passed.')

