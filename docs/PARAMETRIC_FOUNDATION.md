# P1 parametric foundation

This document describes the implemented P1 foundation for expression parameters, datums/CSYS, sketch constraints and the exact-geometry bootstrap that consumes them. All model mutations still pass through SCL/journal transactions and the kernel-facing implementation remains BetterC-safe.

## Expression parameters

A `Parameter` may hold either a literal value or a persistent expression. Formula evaluation occurs before recompute so dirty propagation sees the resulting numeric values.

Ruby-like WCS:

```text
param(:width, 80.mm)
param_expr(:half_width, :mm, "width / 2")
param_expr(:wall, :mm, "half_width / 8")
set_expr(:wall, "width / 20")
```

The evaluator supports numeric literals, named parameters, `PI`/`TAU`/`E`, parentheses, unary signs and `+ - * /`. It also provides BetterC-safe `abs`, dimensionless `sqrt`, degree-based `sin`/`cos`/`tan`, degree-returning `atan2`, and unit-preserving `min`/`max`/`clamp`. It performs unit checking and detects unknown references, divide-by-zero, invalid domains and recursive/cyclic formula chains. It deliberately does not introduce Phobos allocation or an external expression engine.

## Datum co-ordinate systems, planes and axes

Datum geometry is represented by an orthonormal `DatumFrame` containing origin and X/Y/Z basis vectors. The important point is that datum objects are real features with feature operands: downstream sketches and derived datums therefore preserve dependency ordering and dirty propagation.

```text
datum_csys(:part, 0, 0, 0, 1, 0, 0, 0, 1, 0)
datum_plane_from_csys(:xy, :part, :XY)
datum_plane_offset(:machining_plane, :xy, 20.mm)
datum_axis_from_csys(:spindle, :part, :Z)
datum_csys_from(:inspection, :machining_plane, 10.mm, 0, 0)
```

Absolute `datum_plane`, `datum_axis` and `datum_csys` commands are also available. A sketch may use a datum plane as its support, so exact profile extrusion/revolution is no longer tied to the global XY plane.

## Sketch constraints

Constraints live in a fixed-capacity model store and are persistent semantic objects rather than one-shot GUI edits. The BetterC projection solver now tracks residuals and reports each enabled constraint as pending, satisfied, unsatisfied, redundant, conflicting or invalid. Per-sketch reports expose estimated initial/remaining degrees of freedom, independent equation counts, solve iterations, maximum residual, convergence and fully-constrained state.

Implemented relationships are coincident, horizontal, vertical, distance, equal length, parallel, perpendicular, angle, midpoint, concentric, equal radius, radius, diameter, selected line-to-circle/arc tangency, line-segment symmetry about another line and fixed point. Parameter-driven operands are treated as driven rather than overwritten where possible.

The projection pass is followed by a bounded finite-difference Jacobian analysis and damped nonlinear correction for coupled constraints. The local Jacobian reports rank, rank deficiency, per-constraint rank contribution, under/over-constrained state and truncation. The BetterC analysis window is deliberately bounded at 64 mutable literal variables and 128 scalar equations; larger sketches remain valid but report truncated rank analysis. This is still not a claim of a complete NX-class variational solver: stronger rank-revealing factorisation, very-large-sketch scaling and richer tangent/symmetry forms remain further work.

## Exact profile consumption

A sketch container can itself be supplied as a profile when it resolves unambiguously to one region. A single circle/rectangle/polygon child is accepted, an unordered set of sketch lines can be chained into one closed polygon loop by tolerance, and a single connected line/arc chain can retain circular arcs analytically for exact extrusion. Multiple independent regions, general holes and spline-edge regions are rejected until region-selection/trim semantics are explicit.

Supported exact paths now include:

- planar closed polygon/circle extrusion in a datum frame;
- one unambiguous closed mixed line/circular-arc sketch loop extruded with analytic arc trims and cylindrical side faces;
- full 360-degree line-polygon revolution around an arbitrary datum axis using analytic plane/cylinder/cone faces;
- supported circle revolution to sphere/torus;
- straight-path sweep of polygon/circle profiles in supported orientation;
- compatible polygon loft and aligned-circle loft to cone/frustum;
- exact axis-aligned box intersection and rectangular union;
- an axis-aligned box subtraction bootstrap, including a fully enclosed cavity;
- a closed hollow-box shell bootstrap; and
- analytic torus primitive topology.

These are deliberately bounded exact domains. General curved sweeps, arbitrary loft topology, industrial boolean imprint/classification/stitching and conventional face-removal shell semantics are not silently approximated as exact.

## Persistent topology lineage

Current feature-derived exact solids use stable 64-bit semantic topology IDs separate from rebuild-local arena handles. Implemented edge/face splits derive child IDs from their semantic parents, and implemented box booleans/shell generation record lineage records. Cross-save stability still depends on deterministic document serialisation, and future general booleans must carry lineage through imprinting and stitching.

## AI inspection

The getter catalogue in `config/scl_getters.json` exposes formula state, constraints, datum frames, exact topology/genus/loop information, lineage, NURBS counts and recompute cancellation state without giving an AI raw kernel pointers. Getter calls are read-only and are dispatched before journal recording.

