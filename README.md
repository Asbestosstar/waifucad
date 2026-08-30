# WaifuCAD

WaifuCAD is a 64-bit-only, BetterC-first, AI-oriented parametric CAD project written in D. It has two hosts:

- `waifucad-batch`: headless CLI for scripts, journals, automation and CI.
- `waifucad-gui`: desktop host for the Sections ribbon, viewport, Mods and Scripts.

The in-tree exact geometry engine is **WaifuBRep**. It currently has exact analytic box, cylinder, sphere and cone/frustum solids, simple untwisted rectangle/circle extrusion, translated exact primitives, Euler-style edge splitting, validation and primitive mass properties. Operators that are not exact yet remain explicitly labelled `preview-only` instead of silently substituting approximate topology.

## Design rules

1. Kernel-facing D code stays compatible with `-betterC` / `-fno-druntime`.
2. WaifuCAD is 64-bit-only; every declared ISA and OS/ISA target uses 64-bit pointers.
3. Every modelling mutation has a Scripted CAD Language representation.
4. GUI, AI and batch execution route through the same model/journal command path.
5. Journalling records semantic modelling commands, not GUI mouse co-ordinates.
6. Sections are first-party application modules; Mods are third-party extensions; Scripts are executable journal/program files.
7. GUI front-ends and graphics back-ends are independent selections.
8. Platform manifests distinguish requested/research targets from verified ports.
9. Source comments and project prose use British spelling.
10. OpenSCAD's published cheat-sheet capability set is a minimum feature baseline for SCL, without requiring OpenSCAD source syntax.

## Modelling philosophy

WaifuCAD follows the flexible history model expected from NX-like CAD:

- **Preferred:** sketch/profile → extrude, revolve, sweep, loft and downstream detail features.
- **Allowed:** rough/free points, lines, arcs, circles and splines outside sketches. They are useful, but not recommended as the normal way to define production profiles.
- **Allowed:** direct parametric primitives such as boxes and cylinders.
- **Allowed:** dumb bodies with no sketch/feature ancestry, including imported or intentionally non-associative geometry.

The distinction is represented in `ModellingRole`, so GUI and AI tools can recommend good design intent without forbidding legitimate direct/repair workflows. See `docs/MODELLING_WORKFLOWS.md`.

### P1 parametric foundation

WaifuCAD now has persistent expression parameters with unit checking/cycle detection and BetterC-safe formula functions; first-class datum planes, axes and co-ordinate systems including associative derived datums; and a fixed-capacity persistent sketch-constraint solver with bounded Jacobian/rank diagnostics and nonlinear correction for common coupled dimensional/geometric relationships. Sketches can be supported by datum planes and their closed line/polygon/circle regions feed the exact WaifuBRep paths where supported. See `docs/PARAMETRIC_FOUNDATION.md`.

Current exact P1 geometry additionally includes an analytic torus, arbitrary closed line-polygon prism extrusion, supported full polygon revolution, straight sweep/compatible loft, selected exact box booleans and closed box shell construction. These are bounded exact domains, not claims of a complete industrial boolean/surface kernel; unsupported cases remain explicitly `preview-only`.

## First useful commands

```sh
./build.sh batch
./build.sh gui
./build.sh all

./bin/waifucad-batch \
  --script examples/scripts/ruby_style.wcs \
  --journal-out journals/model.wjournal \
  --dump-model

./bin/waifucad-batch --command 'box(:body, 80.mm, 50.mm, 10.mm)' --dump-model
./bin/waifucad-batch --repl
```

`build.sh` prefers LDC and then GDC. Extra compiler/linker switches may be supplied through `DFLAGS` and `LDFLAGS`. Per-OS build scripts live under `build/os/` and architecture helpers under `build/arch/`.

The POSIX multicore bridge uses persistent helpers, bounded per-participant queues/work stealing and cooperative cancellation while retaining dependency-depth ordering. Nested parallel dispatch is serialised to avoid deadlock/oversubscription; exact topology construction remains serial until deterministic per-worker B-rep arenas exist.

## WaifuCAD Scripting Language (SCL)

The default scripting language is **SCL — WaifuCAD Scripting Language**. `.wcs` is reserved for the Ruby-like source surface. The historical whitespace command form now uses `.scl` and is retained only for compatibility, migration and old journal/script replay. Execution remains WaifuCAD's deterministic BetterC interpreter rather than an embedded Ruby runtime.

Preferred modelling example:

```text
waifucad(0.2)
model(:bracket)
param(:width, 80.mm)
param(:depth, 50.mm)
param(:thickness, 10.mm)

sketch(:base_sketch, :XY)
sketch_rect(:base_profile, :base_sketch, :width, :depth, true)
end
extrude(:base_body, :base_profile, :thickness)
recompute()
```

The compatibility layer also accepts Ruby-shaped variables and selected keywords/aliases:

```text
width = 96
puts("updated width")
if true then puts("ready") end
for i in 0..2 do puts(i) end
require("library.wcs")
```

The current Ruby-style flow form is deliberately line-oriented. Full multiline Ruby blocks are not yet part of the parser contract. Every accepted form normalises into the same semantic SCL command path before model mutation, so GUI, batch and journal replay do not acquire separate modelling semantics.

Legacy command-form source is stored with the `.scl` extension. Shipped `.wcs` files must use the Ruby-like surface; `tests/wcs_extension_policy.py` enforces that convention. Examples of the historical format are kept under `examples/scripts/legacy/` for compatibility testing.

A rough line or dumb body remains legitimate:

```text
line(:rough_axis, 0, 0, 0, 0, 0, 100)
dumb_body(:supplier_motor, -40, -30, -25, 40, 30, 90, "supplier STEP body")
```

### OpenSCAD capability baseline

SCL now exposes equivalents for the OpenSCAD cheat-sheet families: variables/operators, constants and special variables; 2D/3D primitives; transformations; booleans; lists; list-comprehension building blocks; flow control; type tests; modules/functions; diagnostics; string/list helpers; and the mathematical function family.

Examples:

```text
circle(:profile, 10)
linear_extrude(:puck, :profile, 20, 0, 0, false)
sphere(:cutter, 8)
translate(:moved_cutter, :cutter, 0, 0, 10)
difference(:result, :puck, :moved_cutter)

list(:vector_a, 1, 2, 3)
list(:vector_b, 4, 5, 6)
cross(:normal, :vector_a, :vector_b)
norm(:length, :vector_a)
```

See `docs/OPENSCAD_PARITY.md`, `config/openscad_parity.json` and `src/waifucad/scl/GRAMMAR.md`. Capability availability and **exact WaifuBRep support are intentionally separate**. Sphere and cone/frustum primitives are now analytic exact WaifuBRep solids; Minkowski, general booleans, twisted extrusion, arbitrary polyhedra and many transformations remain model-graph/preview operations until their exact kernel algorithms are implemented.


## AI/model inspection getters

SCL/WCS provides a read-only getter surface so AI providers and command-line scripts can discover parameters, features, dependencies, geometry status/bounds, exact mass properties, dumb-mesh metadata and PMI without receiving raw kernel pointers. Ruby-like `.wcs` and legacy `.scl` use the same implementation; getters are excluded from semantic journals because they do not mutate the model. See `docs/AI_MODEL_INSPECTION.md` and `examples/scripts/model_getters.wcs`.


### Sketch solver diagnostics

The fixed-capacity BetterC sketch solver now reports residuals, estimated degrees of freedom, independent equation counts and redundant/conflicting/invalid constraints. It also supports selected line-to-circle/arc tangency and line-segment symmetry about another line. These are deterministic projection constraints; a future rank-based nonlinear solver is still required for arbitrary coupled systems. AI/scripts can inspect the result with getters such as `get_sketch_dof`, `get_sketch_max_residual`, `get_sketch_conflicting_constraint_count` and `get_sketch_fully_constrained`.

## Sections and application contexts

WaifuCAD **Sections** are application contexts analogous to NX Applications.
The global ribbon keeps **Sections**, **Mods** and **Scripts** available; choosing
a Section swaps the contextual ribbon while preserving the open document and
viewport.  `modelling` is the default Section.  Sketch is a Modelling command
and work mode, not a separate top-level Section.

The first two Sections with their own contextual ribbon definitions are:

- **Modelling** — Home, Curve, Surface, Analysis and Tools tabs.
- **PMI** — Home, Dimensions, GD&T, Notes and Exchange tabs, plus a
  BetterC-safe fixed-capacity Product and Manufacturing Information store.

The Assembly Section remains a planned application context.  Its design already
requires fully-loaded, lightweight, structure-only, partial and load-on-demand
policies, with per-occurrence states kept distinct from suppression.  See
`docs/SECTIONS.md`, `docs/ASSEMBLIES.md`, `config/sections.json` and
`config/assembly_load_options.json`.

The GTK4 GUI is now the first native front-end verified on the user's RHEL Linux x86-64 host. It launches with no arguments and renders the shared Section/ribbon/command architecture:

```sh
./bin/waifucad-gui
./bin/waifucad-gui --section modelling --command 'box(:body, 20.mm, 10.mm, 5.mm)'
./bin/waifucad-gui --console
./bin/waifucad-gui --bootstrap-info
```

`--console` remains the terminal prototype and `--bootstrap-info` is the non-interactive smoke-test path. The GTK4 front-end renders a real data-driven Modelling/PMI ribbon with project SVG icons, a Model/Assembly/AI navigator rail, the shared command console, wheel zoom, middle-button orbit and focus-aware WASD pan. Ribbon buttons prepare SCL templates instead of bypassing semantic modelling/journalling.

## GUI architecture

The default visual design is `nightcore_2008`: a 1024×768, 4:3-friendly desktop with a purplish-pink Sections ribbon, compact late-2000s controls, CRT-compatible shading and configurable artwork from `waifus/`.

GUI front-end and 3D graphics back-end are independent. Modern targets may select GTK4/Qt6 plus Vulkan or Metal; older UNIX targets can use Motif/Xlib or older GTK/Qt bridges with OpenGL where those ports are actually available.

## Port policy

See `config/architectures.json`, `config/targets.json` and `docs/PORTING.md`. The project is **64-bit-only**, including RV64 for RISC-V and the experimental wasm64/Memory64 WebAssembly direction. A directory does not imply that a port has been verified.

## Waifu artwork

Put user-supplied artwork in `waifus/`. `waifus/manifest.json` records expected filenames. The current working package includes the user-supplied `nightcore.png`, displayed at the top-right of the GTK4 ribbon; future packages should only include artwork supplied or authorised by the user.

## AI patch context

Run:

```sh
./make_todos.sh
```

This regenerates `todos.txt`, concatenating the project instructions, source, build files, configuration, parity tables, documentation, examples and tests so an AI coding agent can prepare later patches with the current requirements in one context file.

## OpenSCAD `.scad` dumb-body interchange

WaifuCAD can now import actual OpenSCAD source as a **dumb mesh body** and
export WaifuCAD bodies as flattened OpenSCAD `polyhedron()` geometry. This is
intentionally different from the OpenSCAD-equivalent SCL command surface:
interchange does not pretend that a foreign CSG program contains native
WaifuCAD sketches, constraints or feature history.

For full OpenSCAD source evaluation, the importer invokes an installed
OpenSCAD command-line executable, renders to text OFF, then reads the result
into `Model.dumbMeshes`. The CLI exposes evaluator/backend selection,
`$fn/$fa/$fs`, repeatable `-D` values, parameter-set files, scaling, welding,
winding, triangulation, closed-mesh checking and safety limits. WaifuCAD's own
polyhedron-only exports can also be re-imported without OpenSCAD through the
internal round-trip reader.

Export supports a named body, all dumb bodies, or all bodies. Exact WaifuBRep
boxes/cylinders/cones/frusta/spheres are tessellated to dumb meshes first;
existing imported meshes pass through directly. Preview-only geometry is
rejected unless the user explicitly chooses the lossy bounding-box fallback.
See `docs/OPENSCAD_INTERCHANGE.md` and `config/openscad_interchange.json`.


## Continuing with another coding LLM

Use `HANDOFF_PROMPT.md` as the self-contained handoff prompt, then give the model `todos.txt` (generated by `./make_todos.sh`) and the project tree. The handoff file describes the non-negotiable BetterC, 64-bit, Sections, PMI, assembly-load, WaifuBRep and journalling rules.





## Native GTK4 GUI

On a Linux host with GTK4 development files available:

```sh
./build.sh gui
./bin/waifucad-gui
```

The default GTK4 shell now includes the contextual SVG-icon ribbon, Nightcore art at the ribbon top-right, live Model Navigator, Assembly/AI navigator entries, mouse-wheel zoom, middle-button orbit and WASD pan. The dedicated WaifuBRep Vulkan renderer remains a separate P1 task; the current viewport is still the honest Cairo/GSK bounds bootstrap.

The GTK4 P1 viewport shows aggregate model bounds, exact/preview/failed feature counts, Section switching and the shared Ruby-like SCL command line. The status bar also reports the Vulkan/NVIDIA/Mesa/lavapipe probe. The dedicated Vulkan 3D renderer remains P1 work; this native GTK4 viewport exists so the application is already visible and interactive while that renderer is developed.

For GTK compositor testing, `--renderer gl` requests GTK's OpenGL renderer and `--renderer vulkan` requests its Vulkan renderer. `--lavapipe` requests GTK Vulkan rendering and, when a standard Mesa lavapipe ICD file is found, limits Vulkan to that ICD. These switches exercise the GTK4 presentation path; they do not falsely mark WaifuCAD's dedicated Vulkan 3D backend complete.
