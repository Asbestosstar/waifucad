# WaifuCAD modelling workflows

WaifuCAD deliberately follows the modelling philosophy of a mature history-based CAD system rather than forcing every object through one construction path.

## Preferred: sketch-driven parametric design

For production parts, AI and GUI tools should normally create a sketch or profile first and then create an associative solid feature from it:

```text
sketch(:base_sketch, :XY)
sketch_rect(:base_profile, :base_sketch, :width, :depth, true)
extrude(:base_body, :base_profile, :thickness)
```

The same preference applies to `revolve`, `sweep`, `loft`, and later feature families. This exposes design intent, makes dimensions easier to edit, and gives constraints/topological naming a stable place to live.

Expression parameters and construction geometry can make that intent explicit:

```text
param(:width, 80.mm)
param_expr(:half_width, :mm, "width / 2")
datum_csys(:part_csys, 0, 0, 0, 1, 0, 0, 0, 1, 0)
datum_plane_from_csys(:base_plane, :part_csys, :XY)
datum_plane_offset(:work_plane, :base_plane, 20.mm)
sketch(:raised_profile, :work_plane)
```

Datum planes/axes/CSYS are first-class associative features, not only display aids. The current sketch solver persists common dimensional/geometric constraints; see `docs/PARAMETRIC_FOUNDATION.md` for its implemented constraint set and limitations.

## Rough/free curves outside sketches

Like NX, WaifuCAD permits points, lines, arcs, circles and eventually splines directly in model space without a sketch container:

```text
point(:datum_probe, 0, 0, 12.mm)
line(:rough_axis, 0, 0, 0, 0, 0, 100.mm)
arc(:rough_arc, 20.mm, 10.mm, 0, 15.mm, 0.deg, 90.deg)
curve_circle(:rough_circle, 0, 0, 25.mm, 8.mm)
```

These objects are tagged `ModellingRole.roughCurve`. They are valid selectable geometry and may feed later features, but the GUI and AI layer should not present them as the preferred way to define an ordinary constrained profile.

## Dumb bodies

A body may exist with no parent sketch, extrusion or other editable construction history. This is required for imported geometry, translated data, repair workflows and deliberate direct modelling.

```text
dumb_body(:vendor_motor, -40.mm, -30.mm, -25.mm, 40.mm, 30.mm, 90.mm, "supplier STEP body")
```

`dumb_body` is explicitly non-associative. File imports are also tagged as dumb-body/reference operations until a native importer converts their content into a richer WaifuBRep history.

## Direct primitives

Direct `box`, `cylinder`, `sphere`, `frustum`, `polyhedron` and OpenSCAD-style 2D primitives are supported because they are concise and useful for scripting. They remain parametric features where their dimensions are parameters, but they are categorised separately from the recommended sketch-driven path.

This distinction is a recommendation, not a restriction. Journals must faithfully preserve whichever modelling style the user chose.

## OpenSCAD interchange is deliberately non-associative

A `.scad` import belongs in the dumb-body branch of the NX-like modelling
spectrum. WaifuCAD may evaluate a very sophisticated OpenSCAD program, but the
resulting rendered mesh still arrives without native WaifuCAD sketches,
constraints or feature parents. Do not infer or fabricate those relationships.

Likewise, `.scad` export is a flattening operation. A well-constructed native
WaifuCAD part may begin with sketches and use extrude/revolve/sweep/loft, but
OpenSCAD export emits tessellated `polyhedron()` dumb bodies. The native model
remains parametric in the WaifuCAD document; the exported interchange file does
not.



