# OpenSCAD import and export

WaifuCAD treats OpenSCAD interchange as a **dumb-body boundary**. Importing a
`.scad` file never invents sketches, constraints, extrusions or other feature
history. Exporting never attempts to recreate the native WaifuCAD feature tree.
That matches the NX-like distinction between associative native construction and
legitimate non-associative/dumb bodies.

## Import engines

### `auto`

`auto` recognises WaifuCAD's own dumb-body `.scad` exports and reads those
without an external dependency. Other `.scad` files are evaluated through the
OpenSCAD command-line program and bridged through text OFF geometry.

### `external`

This is the full-language path. WaifuCAD invokes an installed OpenSCAD CLI,
asks it to evaluate/render the source and export OFF, then consumes that OFF as
a non-associative triangle mesh. This means modules, functions, libraries,
booleans, transforms and other OpenSCAD language behaviour are evaluated by
OpenSCAD itself rather than approximately reinterpreted by WaifuCAD.

The evaluator can be selected with `--openscad-bin`. Backend selection supports
`auto`, `manifold` and `cgal`. `auto` intentionally emits no backend flag so older
OpenSCAD releases remain usable; explicitly requesting Manifold/CGAL requires an
OpenSCAD build that implements `--backend`. OpenSCAD's command-line interface accepts
`-o`/`--export-format` exports and current builds expose backend selection; the
WaifuCAD adapter keeps that dependency outside the CAD kernel.

### `internal`

The dependency-free engine is intentionally narrow: it reads WaifuCAD's own
polyhedron-only SCAD export convention. It exists for deterministic round trips
and old/limited platforms where OpenSCAD itself is unavailable. It must not be
advertised as a complete independent OpenSCAD interpreter.

## Import options

The batch application exposes:

- evaluator engine and executable path;
- Manifold/CGAL/automatic OpenSCAD backend selection;
- `$fn`, `$fa`, `$fs` tessellation overrides;
- repeatable `-D` definitions;
- OpenSCAD parameter-file and parameter-set selection;
- dependency-file generation and missing-file make command;
- `OPENSCADPATH` library and OpenSCAD font-path overrides;
- quiet-mode control;
- unit scaling;
- vertex weld tolerance;
- vertex and triangle safety limits;
- centring at the origin;
- winding reversal;
- polygon triangulation policy;
- degenerate-triangle dropping;
- optional closed/manifold mesh requirement;
- hard-warning behaviour;
- parameter/range checking controls;
- forced render mode;
- temporary-file retention and selectable temporary directory;
- source-path provenance retention.

Example:

    ./bin/waifucad-batch \
      --import-openscad bracket.scad \
      --import-name imported_bracket \
      --scad-engine external \
      --scad-backend manifold \
      --scad-fn 96 \
      --scad-weld 0.00001 \
      --scad-require-closed \
      --scad-define 'wall=3.2' \
      --dump-model

The resulting feature is `FeatureKind.dumbBody`, has `ModellingRole.dumbBody`,
and owns a `meshId` in the dumb-mesh arena.

## Export options

OpenSCAD export flattens the selected body/bodies to ordinary
`polyhedron(points=[...], faces=[...])` geometry. Exact WaifuBRep primitives
are tessellated first; imported dumb meshes are written directly. Unsupported
preview-only features are rejected by default. `bbox` fallback is available
only as an explicit lossy diagnostic option.

Controls include:

- named feature, all dumb bodies, or all bodies;
- reject/bounding-box fallback;
- `$fn`, `$fa`, `$fs` and minimum/maximum tessellation segments;
- numeric precision;
- polyhedron convexity hint;
- unit scaling;
- centring;
- winding reversal;
- header/statistics/source comments and optional WaifuCAD round-trip metadata comments;
- emitted OpenSCAD resolution variables;
- one module per dumb body versus flat top-level polyhedra;
- optional `render(convexity=...)` wrapper.

Example:

    ./bin/waifucad-batch \
      --script examples/scripts/brep_box.wcs \
      --export-openscad box-dumb.scad \
      --export-all-bodies \
      --export-scad-fa 6 \
      --export-scad-fs 0.5 \
      --export-scad-precision 12 \
      --export-scad-render

Even when the source is an exact parametric WaifuBRep body, the `.scad` file is
intentionally a dumb tessellated body. Re-importing it does not restore the
original feature graph.

## SCL commands

Compact journal/script forms are also available:

    scad_import BODY FILE [auto|internal|external] [SCALE] [FN] [FA] [FS] [auto|manifold|cgal] [CENTRE] [WELD] [REQUIRE_CLOSED]

    scad_export FILE [FEATURE|all_dumb|all] [PRECISION] [CONVEXITY] [FN] [FA] [FS] [SCALE] [reject|bbox] [CENTRE]

The CLI contains the more extensive option set because SCL journals should stay
compact and deterministic.




## External evaluator temporary files

The external OpenSCAD/OFF bridge reserves its output path through the `wc_make_temp_file` C ABI and POSIX `mkstemp`. The file is created before OpenSCAD is launched, closed before hand-off, and removed after import unless `keepTemporaryFiles` is enabled. `temporaryDirectory` is honoured without falling back to insecure `tmpnam` name generation.
