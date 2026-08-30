#!/usr/bin/env python3
from pathlib import Path
root=Path(__file__).resolve().parents[1]
types=(root/'src/waifucad/kernel/types.d').read_text()
solver=(root/'src/waifucad/kernel/sketch_solver.d').read_text()
model=(root/'src/waifucad/kernel/model.d').read_text()
interpreter=(root/'src/waifucad/scl/interpreter.d').read_text()
getters=(root/'src/waifucad/scl/getters.d').read_text()
assert 'tangent' in types and 'symmetry' in types
assert 'redundant' in types and 'conflicting' in types and 'SketchSolveReport' in types
for text in ['applyTangent','applySymmetry','constraintResidual','classifyConstraints','mutableDegreesOfFreedom','model.recomputeCancelled()']:
    assert text in solver, text
for text in ['initialDegreesOfFreedom','remainingDegreesOfFreedom','conflictingCount','fullyConstrained']:
    assert text in model or text in types
assert 'SketchConstraintKind.tangent' in interpreter and 'SketchConstraintKind.symmetry' in interpreter
for command in ['get_sketch_dof','get_sketch_max_residual','get_sketch_conflicting_constraint_count','get_sketch_fully_constrained','get_sketch_constraint_residual']:
    assert f'"{command}".ptr' in getters, command
print('P1 sketch solver static validation passed.')

