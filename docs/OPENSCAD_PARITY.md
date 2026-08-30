# OpenSCAD capability parity for Waifu Scripted CAD

WaifuCAD SCL treats the OpenSCAD cheat-sheet feature set as a minimum scripting capability baseline. `.wcs` source uses the Ruby-like surface; legacy command-form source uses `.scl`. The source checklist is tracked in `config/openscad_parity.json`.

**Parity means equivalent capability, not identical source syntax.** SCL remains a journal-oriented language designed for deterministic replay, AI generation and history-based CAD. For example, OpenSCAD's punctuation modifier characters have explicit SCL verbs (`disable`, `show_only`, `highlight`, `background`), and mathematical expressions can be represented by deterministic runtime commands such as `calc`, `math` and `ternary`.

## Geometry equivalents

SCL exposes the OpenSCAD 2D/3D primitive, transformation, boolean and extrusion families:

```text
circle(:c2d, 10.mm)
circle_d(:c2d_from_diameter, 20.mm)
square(:plate2d, 40.mm, 25.mm, true)
polygon(:tri, "0,0;40,0;20,30")
text(:label, "WAIFUCAD", 8.mm, "Noto Sans")

cube(:raw_block, 40.mm, 30.mm, 12.mm)
cylinder(:pin, 5.mm, 30.mm)
cylinder_d(:pin_from_diameter, 10.mm, 30.mm)
sphere(:ball, 20.mm)
sphere_d(:ball_from_diameter, 40.mm)
frustum(:taper, 12.mm, 5.mm, 40.mm)
frustum_d(:taper_from_diameters, 24.mm, 10.mm, 40.mm)
polyhedron(:custom, "0,0,0;20,0,0;0,20,0;0,0,20", "0,2,1;0,1,3;1,2,3;2,0,3")

translate(:moved, :raw_block, 10.mm, 0, 0)
rotate(:tilted, :moved, 0.deg, 20.deg, 45.deg)
rotate_axis(:spun, :tilted, 30.deg, 0, 1, 0)
scale(:stretched, :spun, 1, 2, 1)
mirror(:mirrored, :stretched, 1, 0, 0)
hull(:envelope, :raw_block, :pin)
minkowski(:rounded_envelope, :raw_block, :ball)
union(:combined, :raw_block, :pin)
difference(:drilled, :raw_block, :pin)
intersection(:overlap, :raw_block, :pin)

linear_extrude(:plate, :plate2d, 10.mm, 0, 0, false)
rotate_extrude(:ring, :c2d, 360.deg)
projection(:outline, :raw_block, false)
```

Radius and diameter forms are both retained as parametric operands (`circle_d`, `sphere_d`, `cylinder_d`, `frustum_d`). OpenSCAD's two offset modes are kept distinct with `offset_delta` (including chamfer metadata) and `offset_r` rather than collapsing their design intent.

WaifuBRep exactness is tracked independently. A command can be fully represented in the feature graph and previewed while its exact B-rep operator is still under development. Exact-vs-preview status must never be hidden.

## Runtime equivalents

The BetterC script runtime provides variables, fixed numeric lists, operators, control helpers and the OpenSCAD mathematical/function family without requiring Phobos or GC allocation:

```text
n = 8
range(:values, 0, 1, 10)
index(:third, :values, 2)
component(:xaxis, :values, :x)
calc(:doubled, :n, :*, 2)
ternary(:size, :n, 20, 10)
math(:root, :sqrt, :doubled)
math(:trig, :sin, 30)
list(:a, 1, 2, 3)
list(:b, 4, 5, 6)
concat(:both, :a, :b)
cross(:normal, :a, :b)
norm(:length, :a)
rands(:samples, 0, 1, 8, 1234)
str(:message, "segments=", :n)
echo_value(:message)
```

`module` and `function` define fixed BetterC callables with up to eight positional arguments. Bodies are semicolon-separated SCL commands, positional arguments are available as `$1` through `$8`, functions return through `$result`, and `call` / `call_function` execute them. Modules may receive up to sixteen explicit child features through `call ... --children ...`; `children OUT [INDEX]` exposes a selected child as a deterministic pass-through feature. `parent_module` is backed by a fixed BetterC call stack.

```text
def(:double, 1, "calc $result $1 + $1")
call_function(:answer, :double, 21)
echo_value(:answer)
```

`for`, `intersection_for`, `if`, `let`, `range`, `each` and `list_append` provide deterministic equivalents for list-comprehension and flow-control work. `load()` executes a `.wcs` file; `require()` loads only module/function definitions (and nested requirements), so top-level modelling statements in a library are not executed. `chr` and `ord` operate on Unicode scalar values encoded as UTF-8. SCL intentionally does not reinterpret arbitrary OpenSCAD source syntax. Actual `.scad` interchange is handled separately: the full-language import path delegates evaluation to OpenSCAD itself and stores the rendered result as a dumb mesh; WaifuCAD-generated polyhedron exports also have a narrow dependency-free round-trip reader.

## Known semantic gaps

Every capability on the tracked cheat-sheet baseline has an SCL equivalent, but several implementation layers are intentionally not production-complete yet:

- Imported DXF/SVG/STL/OFF/AMF/3MF and DAT/PNG `surface` commands currently preserve the file reference, metadata and declared bounds as dumb/reference bodies; native file decoders are still required.
- Numeric lists are fixed-capacity and flat. Nested heterogeneous OpenSCAD-style value trees require the later BetterC script-value arena.
- `intersection_for` provides deterministic loop execution; scripts currently express the geometric reduction explicitly with `intersection` features rather than relying on an implicit child-expression tree.
- SCL provides equivalent capability rather than an OpenSCAD source parser. Existing `.scad` text is therefore not accepted verbatim.
- Many OpenSCAD-equivalent geometry operations are currently model-graph/preview operations rather than exact WaifuBRep operators. Exactness is reported per feature and never inferred from command availability.

These limitations are tracked explicitly so “OpenSCAD capability parity” does not become a misleading claim that SCL is an OpenSCAD parser or that imported `.scad` files preserve parametric history/exact-geometry parity. See `OPENSCAD_INTERCHANGE.md` for the deliberately dumb-body import/export boundary.



