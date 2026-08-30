# WaifuCAD Scripting Language (`.wcs`)

SCL is a deterministic, journal-friendly CAD language with a Ruby-style surface. It is **not** an embedded Ruby interpreter and it is not OpenSCAD source syntax. The OpenSCAD cheat-sheet capability surface remains a minimum SCL requirement; see `config/openscad_parity.json` and `docs/OPENSCAD_PARITY.md`.

## Ruby-style surface and CLI

The interpreter first normalises Ruby-like `.wcs` punctuation/keywords into a deterministic internal command form, then executes the normal SCL transaction path. New/shipped `.wcs` source must use the Ruby-like surface. The historical whitespace command form is documented as `.scl` compatibility syntax and remains executable for migration and old journal/script replay.

```text
model(:bracket)
param(:width, 80.mm)
width = 96
box(:body, :width, 50.mm, 10.mm)
puts("done")
require("library.wcs")
if true then puts("ready") end
for i in 0..2 do puts(i) end
```

Current sugar includes `name(args...)`, `:symbols`, numeric `.mm`/`.deg` suffixes, ordinary variable assignment, `puts` -> `echo`, `load` -> `include`, `require` -> `use`, `def` -> `function`, `nil` -> `undef`, and single-line Ruby-shaped `if`/inclusive-range `for`. A bare `end` currently aliases `end_sketch` for sketch-oriented CLI use. Full multiline Ruby block parsing is not yet implemented.

The batch host can execute one typed command or run an interactive command line:

```sh
./bin/waifucad-batch --command 'box(:body, 80.mm, 50.mm, 10.mm)'
./bin/waifucad-batch --repl
```

The command reference below describes the deterministic internal/legacy `.scl` form that Ruby-like `.wcs` calls map onto; it is not the preferred spelling for new `.wcs` files.

## Document and parameters

```text
waifucad VERSION
model NAME
param NAME NUMBER [mm|deg]
set NAME NUMBER
recompute
feature_move_up NAME
feature_move_down NAME
feature_move_before NAME TARGET
feature_move_after NAME TARGET
feature_delete NAME
```

`feature_move_up` and `feature_move_down` reorder adjacent history entries only when doing so preserves feature-dependency order. `feature_move_before` and `feature_move_after` support drag-and-drop history editing and validate the complete proposed order before mutating the feature array. `feature_delete` rejects a feature that is still referenced by another feature. These commands exist so Model Navigator editing remains semantic and journal-replayable rather than changing GUI-only array positions.

## Preferred sketch-driven workflow

```text
sketch NAME PLANE
sketch_line NAME SKETCH X1 Y1 X2 Y2
sketch_arc NAME SKETCH CX CY R START_DEG END_DEG
sketch_circle NAME SKETCH R
sketch_circle_at NAME SKETCH CX CY R
sketch_rect NAME SKETCH WIDTH HEIGHT [CENTRED]
sketch_rect_at NAME SKETCH X Y WIDTH HEIGHT
sketch_polygon NAME SKETCH "x,y;x,y;..."
sketch_text NAME SKETCH "text" SIZE ["font"]
end_sketch

extrude NAME PROFILE HEIGHT [TWIST] [SLICES] [CENTRED] [CONVEXITY]
linear_extrude NAME PROFILE HEIGHT [TWIST] [SLICES] [CENTRED] [CONVEXITY]
revolve NAME PROFILE ANGLE_DEG [CONVEXITY]
rotate_extrude NAME PROFILE ANGLE_DEG [CONVEXITY]
sweep NAME PROFILE PATH
loft NAME PROFILE_A PROFILE_B
```

Sketch-driven construction is the recommended default for AI-generated production geometry.

## Rough/free geometry outside sketches

Valid NX-style non-sketch geometry:

```text
point NAME X Y Z
line NAME X1 Y1 Z1 X2 Y2 Z2
arc NAME CX CY CZ R START_DEG END_DEG
curve_circle NAME CX CY CZ R
spline_bbox NAME MINX MINY MINZ MAXX MAXY MAXZ ["control-point payload"]
```

These objects are intentionally tagged as rough/free geometry rather than preferred sketch geometry.

## Dumb bodies

```text
dumb_body NAME MINX MINY MINZ MAXX MAXY MAXZ ["description"]
```

Dumb bodies have no required sketch/extrude history and are deliberately non-associative.

## OpenSCAD-equivalent direct geometry

```text
circle NAME R
circle_d NAME DIAMETER
square NAME SIZE [CENTRED]
square NAME WIDTH HEIGHT [CENTRED]
polygon NAME "x,y;x,y;..." ["path_indices;..."]
text NAME "text" SIZE [FONT] [DIRECTION] [LANGUAGE] [SCRIPT] [HALIGN] [VALIGN] [SPACING]
import2d NAME "file" MINX MINY MAXX MAXY [CONVEXITY]
projection NAME SOURCE [CUT]

cube NAME SIZE [CENTRED]
cube NAME WIDTH DEPTH HEIGHT [CENTRED]
box NAME WIDTH DEPTH HEIGHT
cylinder NAME R HEIGHT [CENTRED]
cylinder_d NAME DIAMETER HEIGHT [CENTRED]
sphere NAME R
sphere_d NAME DIAMETER
frustum NAME R1 R2 HEIGHT [CENTRED]
frustum_d NAME D1 D2 HEIGHT [CENTRED]
cone NAME R1 R2 HEIGHT [CENTRED]
polyhedron NAME "x,y,z;..." "face_indices;..." [CONVEXITY]
import3d NAME "file" MINX MINY MINZ MAXX MAXY MAXZ [CONVEXITY]
import NAME "file" MINX MINY MINZ MAXX MAXY MAXZ [CONVEXITY]
surface NAME "file" MINX MINY MINZ MAXX MAXY MAXZ [CENTRED] [CONVEXITY]
```

Imported geometry is retained as a dumb/reference body until its native file decoder is implemented. This means the SCL command and metadata/convexity/centring semantics exist now, while native DXF/SVG/STL/OFF/AMF/3MF/DAT/PNG decoding remains an explicit implementation item.

## Transformations and booleans

```text
translate NAME SOURCE X Y Z
rotate NAME SOURCE RX RY RZ
rotate_axis NAME SOURCE ANGLE AX AY AZ
scale NAME SOURCE SX SY SZ
resize NAME SOURCE X Y Z [AUTO_X] [AUTO_Y] [AUTO_Z] [CONVEXITY]
mirror NAME SOURCE NX NY NZ
multmatrix NAME SOURCE M00 M01 M02 M03 M10 M11 M12 M13 M20 M21 M22 M23 M30 M31 M32 M33
colour NAME SOURCE R G B [A]
colour NAME SOURCE NAME_OR_HEX [A]
color NAME SOURCE R G B [A]
color NAME SOURCE NAME_OR_HEX [A]
offset NAME SOURCE DELTA [CHAMFER]
offset_delta NAME SOURCE DELTA [CHAMFER]
offset_r NAME SOURCE RADIUS
hull NAME A B
minkowski NAME A B [CONVEXITY]
union NAME A B
difference NAME TARGET TOOL
subtract NAME TARGET TOOL
intersection NAME A B
intersect NAME A B
render NAME SOURCE [CONVEXITY]
```

OpenSCAD modifier-character equivalents are explicit verbs:

```text
disable NAME SOURCE
show_only NAME SOURCE
highlight NAME SOURCE
background NAME SOURCE
```

## Detail features beyond the OpenSCAD baseline

```text
fillet NAME SOURCE RADIUS
chamfer NAME SOURCE AMOUNT
shell NAME SOURCE THICKNESS
```

## Script values and operators

```text
var NAME VALUE
list NAME VALUE...
range NAME START STEP END
each OUT LIST
list_append LIST VALUE
index OUT LIST INDEX
component OUT LIST x|y|z
calc OUT LEFT OP RIGHT
unary OUT OP VALUE
ternary OUT CONDITION YES NO
```

`calc` supports `+ - * / % ^ < <= == != >= > && ||`; `unary` supports `+ - !`. Constants `PI` and `undef` are recognised by the script runtime.

Special variables are pre-created: `$fa`, `$fs`, `$fn`, `$t`, `$vpr`, `$vpt`, `$vpd`, `$vpf`, `$children`, `$preview`.

## Read-only model getters

Both Ruby-like `.wcs` and legacy `.scl` expose the same read-only getter surface for AI/model inspection. Getters store their result in the first output variable and are not semantic journal mutations. Examples:

```text
# .wcs
count = get_feature_count()
name = get_feature_name(0)
kind = get_feature_kind(:body)
bounds = get_feature_bounds(:body)
volume = get_feature_volume(:body)

# equivalent .scl
get_feature_count count
get_feature_name name 0
get_feature_kind kind body
get_feature_bounds bounds body
get_feature_volume volume body
```

The complete model/parameter/feature/operand/geometry/dumb-mesh/PMI getter catalogue is in `docs/AI_MODEL_INSPECTION.md`. `.wcs` getter return assignment is normalised to the deterministic `COMMAND OUT ...` form used by `.scl`. Enumeration indices can be runtime numeric variables, but remain inspection cursors only; they are not persistent topology references.

## Functions and helpers

```text
math OUT abs|sign|sin|cos|tan|acos|asin|atan|atan2|floor|round|ceil|ln|len|log|pow|sqrt|exp|min|max ARG...
type_test OUT is_undef|is_bool|is_num|is_string|is_list|is_function VALUE
concat OUT LIST_A LIST_B
lookup OUT KEY FLAT_XY_TABLE
str OUT VALUE...
chr OUT CODE
ord OUT STRING
search OUT NEEDLE LIST
version OUT
version_num OUT
parent_module OUT [INDEX]
norm OUT LIST
cross OUT LIST_A LIST_B
rands OUT MIN MAX COUNT [SEED]
```

OpenSCAD-style trigonometric functions use degrees. `chr` and `ord` encode/decode Unicode scalar values as UTF-8 rather than being limited to ASCII.

## Callable modules/functions and flow control

```text
module NAME ARG_COUNT "command;command;..."
function NAME ARG_COUNT "command;command;..."
call NAME ARG... [--children FEATURE...]
call_function OUT NAME ARG...
children OUT [INDEX]  # omit INDEX to expose all supplied children as one grouped pass-through

if CONDITION COMMAND...
let NAME VALUE COMMAND...
for NAME START STEP END COMMAND...
intersection_for NAME START STEP END COMMAND...
```

Callable positional arguments are `$1` through `$8`; functions return through `$result`. A module call may provide up to sixteen child features after `--children`; `$children` reports the count, `children OUT INDEX` exposes one selected child, and `children OUT` groups every supplied child as an explicit pass-through feature. `parent_module` reads the fixed BetterC call stack. `range`, `for`, `if`, `let`, `each` and `list_append` are the building blocks for deterministic list-comprehension equivalents.


## PMI Section commands

PMI mutations use semantic SCL commands so they can be recorded and replayed by the normal journal system. PMI remains outside the modelling feature graph.

```text
pmi_add KIND NAME "TEXT" [FEATURE|none] [SUBENTITY_KIND] [SUBENTITY_INDEX]
pmi_text NAME "NEW TEXT"
pmi_visible NAME true|false
pmi_delete NAME
```

Supported `KIND` values are `note`, `linear_dimension`, `angular_dimension`, `radial_dimension`, `diameter_dimension`, `datum_feature`, `feature_control_frame`, `surface_texture`, `weld_symbol`, `centreline`, and `annotation_plane`. The optional feature/subentity fields are deliberately generic until persistent topological naming is complete; journal files must not pretend transient face/edge indices are a finished association scheme.

## File and diagnostics

```text
load("file.wcs")
require("file.wcs")
puts("message")
echo_value(:VALUE)
assert(:CONDITION, "message")
```

`load()` executes the referenced file and normalises to internal `include`. `require()` loads only callable definitions and nested requirements by normalising to internal `use`; it deliberately skips top-level modelling statements, matching the side-effect-free library-loading role. Legacy `.scl` files may still spell these commands as `include` and `use`.

## Design constraints

Expressions, selections and topology references must stay structured and replayable. A scripting convenience must not bypass the model transaction/journal path or write directly into WaifuBRep memory. Exact-vs-preview geometry status remains explicit for every modelling operation.

## OpenSCAD dumb-body interchange

Actual `.scad` interchange is deliberately separated from OpenSCAD-equivalent
SCL modelling commands:

```text
scad_import NAME FILE [auto|internal|external] [SCALE] [FN] [FA] [FS] [auto|manifold|cgal] [CENTRE] [WELD] [REQUIRE_CLOSED]
scad_export FILE [FEATURE|all_dumb|all] [PRECISION] [CONVEXITY] [FN] [FA] [FS] [SCALE] [reject|bbox] [CENTRE]
```

`scad_import` always creates one or more `dumbBody` mesh features. `external`
uses the installed OpenSCAD evaluator and imports its rendered OFF output;
`internal` is a dependency-free reader for WaifuCAD's own polyhedron-only SCAD
round trips. `auto` chooses the internal path for a recognised WaifuCAD dumb
SCAD export and otherwise uses the external evaluator.

`scad_export` always flattens selected bodies to OpenSCAD `polyhedron()`
geometry. It never serialises sketches, constraints, feature parameters or
WaifuBRep topology as editable OpenSCAD construction history. The batch CLI
provides the extended import/export option set documented in
`docs/OPENSCAD_INTERCHANGE.md`.



## Parametric foundation: expressions, datums and constraints

New `.wcs` source should use the Ruby-like forms below. The equivalent output-first/whitespace command ABI remains available in legacy `.scl` files.

```text
model(:fixture)
param(:width, 80.mm)
param_expr(:half_width, :mm, "width / 2")
param_expr(:wall, :mm, "half_width / 8")
set_expr(:wall, "width / 20")

datum_csys(:part_csys, 0, 0, 0, 1, 0, 0, 0, 1, 0)
datum_plane_from_csys(:top_support, :part_csys, :XY)
# Exact planar faces can also support an associative datum plane when their persistent ID is known:
# datum_plane_from_face(:face_support, :body, 1234567890123456789)
datum_plane_offset(:work_plane, :top_support, 20.mm)
datum_axis_from_csys(:spin_axis, :part_csys, :Z)
datum_csys_from(:inspection_csys, :work_plane, 10.mm, 0, 0)

sketch(:profile, :work_plane)
sketch_line(:a, :profile, 0, 0, 40, 0)
sketch_line(:b, :profile, 40, 0, 40, 20)
sketch_line(:c, :profile, 40, 20, 0, 20)
sketch_line(:d, :profile, 0, 20, 0, 0)
sketch_constraint(:horizontal, :ca, :profile, :a)
sketch_constraint(:vertical, :cb, :profile, :b)
sketch_constraint(:coincident, :cc, :profile, :a, 1, :b, 0)
# Additional relations:
# sketch_constraint(:tangent, :ct, :profile, :line, 1, :circle)
# sketch_constraint(:symmetry, :cs, :profile, :segment, :axis_line)
extrude(:body, :profile, 10.mm)
```

Expression parameters support scalar literals, named parameters, `PI`/`TAU`/`E`, parentheses, unary `+`/`-`, and `+ - * /`. Functions include `abs(x)`, dimensionless `sqrt(x)`, degree-based `sin(x)`/`cos(x)`/`tan(x)`, degree-returning `atan2(y, x)`, and unit-preserving `min(a,b)`/`max(a,b)`/`clamp(x,lo,hi)`. Length/angle units are checked. Cycles, divide-by-zero, domain errors and incompatible units are rejected instead of silently producing a value.

Implemented persistent sketch constraint kinds are `coincident`, `horizontal`, `vertical`, `distance`, `equal_length`, `parallel`, `perpendicular`, `angle`, `midpoint`, `concentric`, `equal_radius`, `radius`, `diameter`, `tangent`, `symmetry` and `fix_point`. `tangent` currently constrains a selected line endpoint to a circle/arc and aligns the line tangent there; `symmetry` constrains the endpoints of one line segment symmetrically about a second line. The fixed-capacity projection solver reports residuals, redundant/conflicting/invalid constraints, equation counts and estimated degrees of freedom. A future general nonlinear/Jacobian solver is still required for arbitrary coupled constraint systems.

Datum features are first-class model features and therefore participate in dependency depth, dirty propagation, SCL journalling and getters. Every new part begins with an `absolute_csys` at 0,0,0. `datum_plane`, `datum_axis` and `datum_csys` define absolute frames; `datum_plane_from_csys`, `datum_plane_from_face`, `datum_plane_offset`, `datum_axis_from_csys` and `datum_csys_from` create associative derived datums. `datum_plane_from_face` accepts only a persistent ID belonging to an exact planar face of the named owner feature.

## Exact P1 geometry domains

The following forms now have exact WaifuBRep paths when their documented bootstrap conditions are met:

```text
torus(:ring, 30.mm, 5.mm)
revolve_axis(:turned, :closed_polygon_profile, :spin_axis, 360.deg)
sweep(:swept, :closed_profile, :straight_line_path)
loft(:lofted, :compatible_profile_a, :compatible_profile_b)
intersect(:common, :axis_aligned_box_a, :axis_aligned_box_b)
shell(:hollow, :axis_aligned_box, 2.mm)
```

Exact extrusion accepts a single closed planar polygon/line-loop or circle region and honours a datum-plane frame. Full 360-degree polygon revolution uses analytic plane/cylinder/cone topology for line segments in a radial/axial half-plane; circles can produce exact spheres/tori in the supported axis relationship. Straight sweeps and compatible two-profile lofts are exact in their supported linear domains. Box boolean and closed-box-shell exact paths are deliberately narrow bootstrap algorithms; unsupported general cases remain `preview-only`.

`get_feature_geometry_status(...)` and `get_feature_bounds_source(...)` should always be used by AI callers when exactness matters.

