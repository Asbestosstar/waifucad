# WaifuBRep exact kernel

WaifuCAD owns its boundary-representation kernel. `src/waifucad/brep/` is BetterC D and deliberately does not depend on Open CASCADE, Parasolid, ACIS or another external solid-modelling kernel.

## Topology and identity

The fixed-capacity arena stores vertices, edges, coedges, loops, faces, shells and solids. Raw `BRepId` values are rebuild-local handles. Exact feature-derived topology also carries separate 64-bit persistent semantic IDs, and the arena contains explicit topology-lineage records for implemented split/merge/generated/boolean operations.

Faces now support more than one trim loop (`firstLoop`/`loopCount`) while preserving `outerLoop` as the exterior-loop compatibility field. Solids carry shell count and genus so validation can represent multi-shell cavities and genus-one axisymmetric solids rather than assuming every solid obeys only `V-E+F=2`.

## Analytic and NURBS geometry

Implemented edge geometry includes line, circle and fixed-arena rational NURBS curves. Implemented surfaces include plane, cylinder, cone, sphere, torus and fixed-arena rational NURBS surfaces. Rational curve/surface evaluation uses stored control points, weights and knots without GC allocation.

NURBS support is groundwork rather than a claim of a complete tolerant NURBS solid kernel: general trimmed NURBS faces, robust NURBS intersections and sewing remain follow-up work.

## Exact primitives and construction paths

Implemented exact solids include:

- box;
- cylinder;
- cone/frustum including a true zero-radius apex;
- sphere;
- torus;
- arbitrary closed line-polygon prism/extrude in a datum frame;
- supported straight-path sweep;
- compatible two-profile linear loft/prismatoid;
- aligned-circle loft to cone/frustum;
- supported full-circle polygon revolution producing analytic plane/cylinder/cone topology;
- supported circle revolution producing sphere/torus;
- axis-aligned box intersection and rectangular union bootstrap;
- axis-aligned box subtraction bootstrap including a fully enclosed cavity; and
- closed hollow-box shell bootstrap.

Unsupported/general cases stay `preview-only`; they are not replaced with a bounding box or mesh and called exact.

## Axisymmetric polygon revolution

`makeAxisymmetricPolygonRevolve` revolves a closed line polygon expressed in radial/axial co-ordinates. A radial segment becomes a planar disk/annulus face, a constant-radius axial segment becomes a cylinder, and a sloped radial/axial segment becomes a cone/frustum. A profile away from the axis can therefore produce a genus-one hollow solid with annular end faces. Profiles crossing the axis in a way that would create overlap are rejected.

This is a full-360-degree analytic line-polygon path; arbitrary curved profile segments and partial-angle solid closure require additional topology.

## Validation

`validateClosedSolid()` checks arena ownership/ranges, bounds, edge/coedge manifold use and orientation, loop next/previous reciprocity, endpoint continuity, surface/curve backing data, shell ownership and a loop/genus-aware Euler relationship. Multi-loop faces and multi-shell solids therefore participate in validation rather than being ignored.

## Topology mutation and lineage

`splitLineEdge()` preserves the original edge identity, creates deterministic derived persistent IDs for the split vertex/second edge and records split lineage. `splitPlaneFaceByChord()` splits a supported planar one-loop face between existing boundary vertices, repairs coedge rings, creates the chord/new face and records derived IDs. `mergeLastSplitPlaneFaces()` is a constrained inverse for the current append-only arena model and records merge lineage.

Implemented exact box boolean/shell paths also record generated/boolean lineage. Sphere/sphere intersections now return exact circle/point loci, and parallel offset cylinders return exact longitudinal line loci. General boolean imprinting still needs broader loop/Euler operators plus persistent lineage propagation through every intersection-created entity.

## Intersection groundwork

`src/waifucad/brep/intersections.d` provides fixed-capacity analytic intersection results for supported cases including line/edge versus plane/sphere/cylinder/cone, circle versus plane, plane-plane, plane-sphere, common plane-cylinder/cone cuts and perpendicular plane-torus cuts. Unsupported general torus/NURBS/surface-surface cases return unsupported instead of manufacturing approximate topology.

`src/waifucad/brep/classification.d` adds trim-aware point tests for planar line-loop faces, trimmed line/planar-face intersection filtering, and exact/tolerant inside/outside/boundary classification for closed all-planar solids. Curved or NURBS faces deliberately return `unknown` rather than falling back to tessellation and claiming exact boolean classification.

The remaining industrial boolean pipeline is: general curve/surface and surface/surface intersection -> trim/imprint curves -> region classification -> shell stitching -> tolerant healing.

## Tolerance/healing groundwork

`BRepTolerancePolicy` makes positional/angular/parameter tolerances explicit. Helpers provide finite checks, point coincidence, conservative geometry snapping and diagnostics. Current snapping changes near-coincident vertex positions but deliberately does not merge topology IDs/coedge rings; topological healing must remain explicit.

## Tessellation

`src/waifucad/mesh/tessellate_brep.d` consumes exact WaifuBRep rather than primitive bounding boxes. It supports planar outer-loop ear clipping, concentric circular annular planar faces, analytic cylinder/cone/sphere/torus sampling, and single-trim sampled curved/NURBS boundaries. OpenSCAD export uses this service for exact bodies.

A mesh produced here is an approximation for display/interchange, never an exact replacement for the B-rep. Planar faces may contain multiple sampled inner loops: the tessellator searches deterministic visibility-safe bridges and ear-clips the resulting weakly-simple polygon. Unsafe or over-capacity configurations fail rather than silently filling holes. Curved/NURBS multi-loop trims and full chord/angle error guarantees remain further work.

## Parallelism boundary

The feature-preview/model scheduling stage is multicore. Exact B-rep rebuild remains serial because the current arena is shared and append-oriented. Parallelising exact construction before per-worker arenas or deterministic reservation/merge semantics exist would make topology allocation/order unsafe and is therefore intentionally not done.

