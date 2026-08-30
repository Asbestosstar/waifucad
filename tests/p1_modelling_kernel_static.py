#!/usr/bin/env python3
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
read=lambda p:(ROOT/p).read_text()
build=read('build.sh')
for module in [
 'src/waifucad/brep/advanced.d','src/waifucad/brep/intersections.d','src/waifucad/brep/classification.d','src/waifucad/brep/tolerance.d','src/waifucad/brep/transform.d',
 'src/waifucad/mesh/tessellate_brep.d','src/waifucad/kernel/expressions.d','src/waifucad/kernel/datums.d','src/waifucad/kernel/profiles.d','src/waifucad/kernel/sketch_solver.d','src/waifucad/kernel/sketch_nonlinear.d']:
 assert module in build, module
interp=read('src/waifucad/scl/interpreter.d')
for command in ['param_expr','set_expr','datum_plane','datum_axis','datum_csys','datum_plane_from_csys','datum_plane_offset','datum_axis_from_csys','datum_csys_from','sketch_constraint','sketch_circle_at','revolve_axis','torus']:
 assert f'"{command}".ptr' in interp, command
solver=read('src/waifucad/kernel/sketch_solver.d')
for constraint in ['coincident','horizontal','vertical','distance','equalLength','parallel','perpendicular','angle','midpoint','concentric','equalRadius','radius','diameter','fixPoint']:
 assert f'SketchConstraintKind.{constraint}' in solver, constraint
backend=read('src/waifucad/kernel/waifubrep_backend.d')
for feature in ['exactExtrude','makeProfilePrism','exactRevolve','exactSweep','exactLoft','makeAxisymmetricPolygonRevolve','intersectAxisAlignedBoxes','makeBoxShellAt','recomputeCancelled']:
 assert feature in backend, feature
advanced=read('src/waifucad/brep/advanced.d')
assert 'makeAxisymmetricPolygonRevolve' in advanced and 'face.loopCount' not in advanced  # loops are owned by builder
assert 'solid.genus=' in advanced
assert 'makeProfilePrism' in advanced and 'addCircleArcEdge' in advanced
brep_types=read('src/waifucad/brep/types.d')
for token in ['BRepNurbsCurve','BRepNurbsSurface','BRepTopologyLineage','uint genus','uint loopCount']:
 assert token in brep_types, token
intersections=read('src/waifucad/brep/intersections.d')
for token in ['intersectLineFace','intersectEdgeFace','intersectFaces','lineCone','sphereSphere','parallelCylinderCylinder']:
 assert token in intersections, token

tess=read('src/waifucad/mesh/tessellate_brep.d')
for token in ['tessellatePlanarMultiLoop','triangulateBridgedPolygon','bridgeCrossesOriginalLoops','WC_FACE_TRIANGULATION_LIMIT']:
 assert token in tess, token
exporter=read('src/waifucad/interchange/openscad/exporter.d')
assert 'tessellateBRepSolid' in exporter and 'tessellateSolid(&scratch' not in exporter
jobs=read('native/threads/wc_threads_posix.c')
for token in ['wc_worker_queue','steal','wc_parallel_for_cancelable','wc_cancel','wc_is_cancelled']:
 assert token in jobs, token
model=read('src/waifucad/kernel/model.d')
assert 'CancellationToken recomputeCancellation' in model
assert 'evaluateParameterExpressions' in model
print('P1 modelling-kernel/scheduler static validation passed.')

