# AGENTS.MD — WaifuCAD engineering instructions

## Non-negotiable project rules

- Keep the kernel, WaifuBRep, journal ABI, Section ABI and Mod ABI BetterC-safe.
- WaifuCAD is 64-bit-only. Do not add a target with 32-bit pointers; `core/platform_bits.d` must remain in every common build.
- Every concrete ISA in `CpuArchitecture`, every `config/architectures.json` entry and every `config/targets.json` target must be 64-bit. Do not add RV32, x86-32, ARM32, wasm32 or any other 32-bit compatibility target.
- Do not introduce a Phobos dependency into `src/waifucad/core`, `brep`, `kernel`, `journal`, `scl`, `sections` or `mods` without an explicit architecture decision.
- Do not use GC allocation, D classes, exceptions or static/module constructors in BetterC code.
- Use British spelling in code comments, identifiers where natural, documentation and UI text.  External API spellings may be preserved when required by that API.
- A GUI action that mutates a model must be expressible as SCL and routed through the command transaction path so journalling can reproduce it.
- AI-generated modelling operations must use the same SCL/transaction path; do not give an AI provider direct write access to kernel memory.
- AI/model inspection must use the read-only SCL/WCS getter surface or another versioned read-only ABI; never expose raw `Model*`, feature-array or WaifuBRep pointers to providers.
- Read-only `get_*` inspection commands write only to script-runtime output variables and must not be recorded as semantic model journal mutations.
- Treat `config/targets.json` as a statement of intent/capability status, not marketing.  Never change a target to `verified` without a reproducible build/run record.
- Keep GUI front-end choice separate from graphics back-end choice.
- macOS targets default to the native Cocoa/AppKit front-end with Metal graphics. GTK4 on macOS is an optional fallback and must never be a macOS build requirement.
- Prefer C ABI boundaries for plug-ins and foreign runtimes.
- Preserve 1024×768 usability for the default theme.
- Preserve dependency-safe multicore recompute. Never parallelise a feature with an unmet feature dependency.
- Keep native threading behind the `wc_threads.h` C ABI; do not introduce `core.thread` into BetterC kernel code.
- Keep WaifuBRep as the project-owned exact geometry kernel; do not silently replace it with an external solid-modelling kernel.
- Preserve the NX-like modelling spectrum: sketch-driven associative features are preferred, but rough/free curves outside sketches and non-associative dumb bodies must remain valid first-class document objects.
- AI-generated production parts should prefer sketch/profile -> extrude/revolve/sweep/loft unless the user requests direct/rough/dumb geometry or a direct primitive is materially clearer.
- Treat `config/openscad_parity.json` as a minimum SCL capability contract. Do not remove an OpenSCAD cheat-sheet equivalent without an explicit architecture decision and migration path.
- OpenSCAD capability parity does not mean OpenSCAD source-syntax compatibility and does not allow hiding preview-only geometry as exact WaifuBRep output.
- Treat Sections as NX-style application contexts: each implemented built-in Section owns code under `src/waifucad/sections/<id>/` plus its contextual ribbon data. The persistent Sections and Mods ribbon tabs must remain available while Section activation swaps contextual tabs; Scripts belongs to the Home ribbon as a group, not separate top-level chrome.
- Keep `modelling` as the default Section. Sketch is a Modelling command/mode, not a separate top-level Section.
- Keep PMI in its own `src/waifucad/sections/pmi/` code area; do not bury PMI annotations in the modelling feature graph.
- Treat OpenSCAD `.scad` import/export as a dumb-body interchange boundary. Imports must not invent sketches/features; exports must flatten to mesh/polyhedron geometry rather than claiming to preserve native history.
- Keep arbitrary OpenSCAD evaluation outside the kernel. The external importer may delegate language evaluation to an installed OpenSCAD executable, while the internal importer is only a deterministic WaifuCAD round-trip reader unless it is explicitly expanded and tested.
- Keep exact-vs-preview geometry status explicit for every feature operator.
- Regenerate `todos.txt` with `./make_todos.sh` after meaningful project changes so future AI patch context stays current.
- Keep `HANDOFF_PROMPT.md` current enough that another coding LLM can continue without relying on chat history.

## Expanding TODO list

### P0 — foundation
- [x] BetterC-compatible base types and fixed strings.
- [x] Parametric model and feature graph storage.
- [x] Journal recorder.
- [x] SCL interpreter and first modelling commands.
- [x] Batch executable entry point.
- [x] GUI host entry point and front-end/back-end registries.
- [x] Sections, Mods and Scripts ABI skeletons.
- [x] JSON localisation assets.
- [x] Nightcore 2008 theme assets and CRT shader starters.
- [x] Target, OS, CPU architecture, GUI front-end and GPU stack folders.
- [x] BetterC-safe multicore job ABI with POSIX pthread implementation and automatic logical-processor detection.
- [x] `make_todos.sh` AI context generator.
- [x] Compile and smoke-test with LDC on Linux x86-64. (User-verified on RHEL Linux x86-64, 2026-08-19.)
- [ ] Compile and smoke-test with GDC on Linux x86-64.
- [x] Add per-OS `.sh` build entry points under `build/os/` and `ports/os/*/build.sh`.
- [x] Enforce a 64-bit-only ABI and add WebAssembly Memory64/wasm64 research target records.
- [x] Add RISC-V as RV64-only (`riscv64`) with Linux/BSD research targets and an RV64 Linux cross-build helper.
- [x] Add LoongArch as LA64-only (`loongarch64`) with a Linux research target and an LA64 Linux cross-build helper; new-world ABI, no LSX/LASX assumption in portable code.
- [x] Add machine-readable 64-bit architecture/target width metadata and reject 32-bit target declarations.
- [x] Clear preview/exact derived state on model reinitialisation so repeated CLI/scripts and read-only inspection cannot observe stale geometry metadata.

### P1 — modelling kernel
- [x] Add parameter/feature dependency-directed dirty propagation rather than whole-document recompute.
- [x] Add expression parameters (`width / 2`, named formulae, dependency evaluation, cycle protection and unit checking), plus BetterC-safe `abs`/`sqrt`/degree-trig/`atan2`/`min`/`max`/`clamp` functions and `PI`/`TAU`/`E` constants.
- [x] Add first-class modelling roles for preferred sketch features, direct parametric primitives, rough/free curves and dumb bodies.
- [x] Initialise every part with a pinned `absolute_csys` at 0,0,0 and canonical axes so GUI/batch/SCL share the same default construction frame.
- [x] Add SCL sketch containers plus line/arc/circle/rectangle/polygon/text profile entities and preserve the preferred sketch-driven workflow.
- [x] Add fixed-capacity persistent sketch constraints with iterative solving for coincident/horizontal/vertical/distance/equal-length/parallel/perpendicular/angle/midpoint/concentric/equal-radius/radius/diameter/fixed-point relationships.
- [x] Extend the sketch solver with residual-based convergence, redundancy/conflict diagnostics, explicit degrees-of-freedom reporting, tangency and line-about-line symmetry.
- [x] Add a bounded finite-difference Jacobian/rank analysis and damped nonlinear correction path with per-constraint rank contribution plus explicit under/over-constrained diagnostics.
- [x] Expand the allocation-free nonlinear/Jacobian workspace from 64 variables/128 equations to 128 variables/256 equations, replace elimination-only rank detection with column-pivoted two-pass modified Gram-Schmidt, and support line/curve tangency in either operand order plus external curve/curve tangency.
- [ ] Scale nonlinear solving beyond the fixed 128-variable/256-equation workspace for very large/arbitrarily coupled sketches, and add richer symmetry/internal-tangency variants without introducing GC allocation.
- [x] Add NX-style rough/free point, line, arc, circle and spline-bounds objects outside sketches.
- [x] Add explicit non-associative dumb-body objects with independent bounds/payload metadata.
- [x] Implement datum planes, datum axes and datum co-ordinate systems, including associative CSYS-derived axes/planes, plane offsets and derived CSYS origins.
- [x] Add SCL/preview implementations for extrude, revolve, union, subtract, fillet and chamfer.
- [x] Generalise exact planar closed-line/polygon extrusion and full polygon revolution; add exact single-loop mixed line/circular-arc extrusion with cylindrical side faces, supported straight sweep, compatible-profile loft, axis-aligned box intersect/union/subtract and closed box shell construction.
- [ ] Extend exact sweep/loft/intersect/shell to arbitrary curved paths/profiles and robust general boolean classification/imprinting/stitching.
- [x] Define persistent topological naming strategy for current exact feature-derived topology.
- [x] Add persistent topology lineage for implemented line/face splits, constrained face merge, box booleans and generated shell topology.
- [ ] Propagate persistent lineage through general boolean imprint/stitch operations and deterministic save/load identity.
- [ ] Add undo/redo transaction log.
- [ ] Add deterministic document serialisation.
- [x] Add the in-tree WaifuBRep kernel behind `GeometryBackendV1`.
- [x] Implement exact manifold box topology and closed-solid validation.
- [x] Implement manifold line-edge splitting with coedge-ring repair and deterministic derived persistent IDs.
- [x] Add exact planar chord face split and a constrained inverse merge with topology validation/lineage.
- [ ] Generalise loop creation/removal, non-planar face split/merge and Euler operators required by arbitrary boolean imprinting.
- [x] Implement exact analytic cylinder primitive with periodic circles and cylindrical surface data.
- [x] Add exact box/cylinder volume, surface area and centre-of-mass properties.
- [x] Track exact / preview-only / failed geometry status per feature.
- [x] Implement exact analytic cone/frustum and sphere primitives.
- [x] Implement exact analytic torus topology/evaluation and multi-loop planar annular faces used by axisymmetric solids.
- [ ] Generalise trimmed analytic surfaces beyond the implemented planar-annulus/axisymmetric cases.
- [x] Add analytic curve/face and face/face intersection groundwork for line/circle against plane/sphere/cylinder/cone, common plane-vs-analytic surface cases, sphere/sphere circles/points and parallel cylinder/cylinder intersection lines.
- [x] Add trim-aware planar face point/line classification and exact tolerant point-in-solid classification for closed all-planar solids without tessellation fallback.
- [ ] Implement robust general curve/surface and surface/surface intersection, trim-curve generation, boolean region classification and shell stitching.
- [x] Add fixed-arena rational NURBS curve/surface storage and evaluation plus explicit tolerance/healing groundwork.
- [ ] Implement trimmed NURBS topology, robust NURBS intersections, tolerant sewing and duplicate/coincident topology merging.
- [x] Add a topology-aware WaifuBRep tessellation service used by OpenSCAD export for arbitrary exact solids in the currently supported trim/surface domains.
- [x] Add bounded arbitrary multi-loop planar-face tessellation using sampled trim loops, visibility-checked hole bridges and ear clipping; unsafe/over-capacity hole configurations fail rather than fill material.
- [ ] Add full multi-loop curved/NURBS-face tessellation with chord/angle error guarantees and remove the remaining sampled planar capacity limits without introducing unbounded allocation.

### P1 — multicore and scheduling
- [x] Parallelise independent dirty features by dependency depth.
- [x] Add `--threads 0..64` batch control and automatic online-processor detection.
- [x] Add native C scheduler test that confirms work executes exactly once and uses multiple participating threads where available.
- [x] Replace per-dispatch pthread creation with a persistent POSIX helper pool.
- [x] Add bounded per-participant queues and work stealing inside one dependency-safe dispatch depth.
- [x] Add nested parallelism/oversubscription policy: nested pool dispatches execute serially.
- [x] Add cancellation tokens integrated with preview dispatch and exact recompute feature boundaries.
- [x] Add cooperative cancellation checkpoints inside the iterative sketch solver and WaifuBRep tessellation loops.
- [ ] Extend safe cancellation checkpoints into future long boolean/NURBS/healing operations and wire cancellation to native GUI events.

### P1 — OpenSCAD capability baseline
- [x] Add machine-readable OpenSCAD cheat-sheet parity table in `config/openscad_parity.json`.
- [x] Add SCL equivalents for circle/square/polygon/text, sphere/cube/cylinder/frustum/polyhedron, projection, extrusion, transformations, hull, Minkowski and all three booleans at model-graph/preview level.
- [x] Add SCL script runtime for scalar variables, fixed numeric lists, operators, ternary selection, ranges, list indexing, type tests and deterministic flow helpers.
- [x] Add OpenSCAD mathematical function equivalents with degree-based trigonometry plus concat/lookup/str/chr/ord/search/version/rands/norm/cross helpers.
- [x] Add fixed BetterC callable `module`/`function` macros with positional arguments and deterministic invocation.
- [x] Implement side-effect-free `use` loading for module/function definitions and nested `use` declarations.
- [x] Implement UTF-8 `chr`/`ord` for Unicode scalar values.
- [ ] Add the nested heterogeneous BetterC script-value/list arena.
- [ ] Add native DXF/SVG importers for 2D OpenSCAD import parity.
- [x] Add dumb-mesh ownership with fixed-capacity `MeshArena` and feature `meshId` references.
- [x] Add native text OFF mesh importer with polygon triangulation, scaling, welding, winding and optional closed-manifold validation.
- [ ] Add native STL/AMF/3MF importers and optional mesh-to-WaifuBRep healing/conversion.
- [ ] Add DAT/PNG height-surface loading.
- [x] Add deterministic module-child support through explicit `call ... --children ...` plus `children OUT [INDEX]`, and callable-stack-backed `parent_module`.
- [ ] Consider optional block-syntax sugar later; keep explicit feature references as the preferred journal form.
- [ ] Add exact WaifuBRep implementations for OpenSCAD-equivalent geometry that is currently preview-only.

### P1 — OpenSCAD interchange
- [x] Add `.scad` importer that always creates dumb mesh bodies.
- [x] Add external OpenSCAD evaluator path with OFF bridge and selectable automatic/Manifold/CGAL backend.
- [x] Add dependency-free internal reader for WaifuCAD polyhedron-only SCAD round trips.
- [x] Add repeatable OpenSCAD `-D` definitions plus `$fn`/`$fa`/`$fs`, parameter-file/set, scaling, welding, winding, triangulation and mesh-safety controls.
- [x] Add `.scad` exporter that flattens exact/dumb geometry to `polyhedron()` bodies.
- [x] Add export controls for scope, tessellation, precision, convexity, scaling, centring, winding, comments, render wrapper and explicit bounding-box fallback.
- [x] Add round-trip metadata comments that remain valid OpenSCAD comments and allow dependency-free re-import.
- [x] Replace C `tmpnam` bootstrap with a BetterC-facing C ABI temporary-file service backed by secure POSIX `mkstemp`, with explicit ownership/removal and caller-selected temporary directory support.
- [ ] Add connected-component splitting option so disconnected rendered shells can become separate dumb bodies on import.
- [ ] Add optional mesh simplification/decimation with explicit error tolerance.
- [ ] Complete curved/NURBS trimmed-WaifuBRep tessellation so every exact body can export without primitive-specific or single-loop limitations.
- [ ] Add GUI OpenSCAD import/export option panels using the same option structs as batch/SCL.


### P1 — Sections and PMI
- [x] Make Modelling the explicit default Section and give it its own contextual ribbon descriptor.
- [x] Add a global Section context/ribbon host where the persistent Sections ribbon tab swaps contextual ribbons without closing the document or viewport.
- [x] Add the PMI Section with its own source directory, Home/Dimensions/GD&T/Notes/Exchange ribbon tabs and BetterC-safe annotation store.
- [x] Route basic PMI creation/edit commands through SCL so PMI mutations are journal-replayable (`pmi_add`, `pmi_text`, `pmi_visible`, `pmi_delete`).
- [ ] Add persistent-topology associations for PMI dimensions, datums and feature-control frames once topological naming is stable.
- [ ] Add PMI view sets, annotation-plane editing, standards profiles and validation rules.
- [ ] Implement STEP AP242 PMI import/export only after the PMI association model is stable.
- [ ] Give Assembly, Drawing, Manufacturing, AI and Journalling their own Section directories and contextual ribbon descriptors as their implementations begin.

### P1 — assemblies (planned)
- [ ] Add assembly prototype/component/occurrence data structures with stable 64-bit occurrence identity and transforms.
- [ ] Implement assembly load policies: fully loaded, lightweight, structure-only, partial and load-on-demand.
- [ ] Implement per-occurrence states: fully loaded, lightweight, structure-only, deferred, unloaded and suppressed; suppression must remain distinct from unloading.
- [ ] Preserve occurrence identity, transform and selection references while promoting/demoting load state.
- [ ] Add batch `--assembly-load` policy selection and equivalent SCL/journal commands.
- [ ] Add an open-assembly GUI chooser for load policy and per-component overrides.
- [ ] Multicore independent component loading with dependency ordering, cancellation and bounded I/O concurrency.
- [ ] Add assembly constraints/joints, arrangements/configurations and reference sets without relying on display-mesh identity.
- [ ] Add lightweight display/proxy representation separate from exact part B-rep and editable feature history.
- [ ] Ensure AI inspection requests the lightest sufficient assembly load state and never forces a full assembly load without need.
- [ ] Implement the Assembly Section ribbon only when the underlying assembly document model is ready.
- [ ] Share one `AssemblyLoadOptions` contract across GUI, batch, SCL and journal replay; do not fork option semantics per front-end.
- [ ] Add exact/tessellated/bounds-only geometry preference, recursive load depth, reference-set choice, PMI/attribute loading, stale-proxy policy, soft memory budget and bounded I/O concurrency.
- [ ] Add per-occurrence promotion/demotion commands while preserving stable occurrence IDs, transforms, selection references and assembly constraints.
- [ ] Add assembly session diagnostics showing why each occurrence is full/light/structure-only/deferred/unloaded/suppressed and what promoted it.


### P2 — Drawing Section (planned)
- [ ] Add `src/waifucad/sections/drawing/` only when the drawing document/view model starts; register its own contextual ribbon.
- [ ] Add drawing sheets, borders/title blocks, model views, projected views, section views, detail views and broken views.
- [ ] Keep drawing dimensions/notes associative to PMI/model topology where possible rather than duplicating annotation semantics.
- [ ] Add hidden-line/visible-line generation from WaifuBRep and lightweight assembly proxies.
- [ ] Add DWG/DXF/PDF/SVG export architecture with explicit fidelity diagnostics.
- [ ] Add drawing update states so stale views can be detected and regenerated deterministically.

### P2 — Sheet Metal workflow/Section candidate
- [ ] Add material/thickness/bend-rule tables, bend allowance/deduction and K-factor support.
- [ ] Add tab/flange, contour flange, bend, unbend/rebend, jog, hem, bead, dimple and normal-cut features.
- [ ] Add flat-pattern generation with persistent bend/face identity and manufacturing annotations.
- [ ] Decide whether Sheet Metal remains a Modelling sub-workflow or becomes its own Section once the command surface is large enough.

### P2 — Advanced shape and surface design
- [ ] Extend exact WaifuBRep with trimmed NURBS curves/surfaces, curve-on-surface, projection, offset and tolerant intersection/healing.
- [ ] Add studio spline, bridge curve, law curve, through-curves, through-curve mesh, swept surface, fill surface and surface trim/sew.
- [ ] Add continuity analysis for G0/G1/G2/G3 where mathematically meaningful.
- [ ] Add zebra, reflection, curvature-comb and surface-deviation analysis.
- [ ] Keep ordinary surface commands inside Modelling initially; create a separate Shape/Surface Section only if workflow complexity justifies it.

### P2 — Manufacturing/CAM Section (planned)
- [ ] Add `src/waifucad/sections/manufacturing/` with its own ribbon only after the CAM document model exists.
- [ ] Add MCS/workpiece/blank/part geometry, tools/holders, operations, methods, programmes and setup groups.
- [ ] Add 2.5D milling, drilling, turning and basic 3-axis rough/finish toolpaths before advanced simultaneous multi-axis work.
- [ ] Add stock-removal simulation independent from exact design B-rep.
- [ ] Define a versioned post-processor ABI and machine/tool-library formats.
- [ ] Make toolpath generation cancellable and multicore where operations are independent.

### P2 — Inspection Section candidate
- [ ] Add PMI-driven inspection characteristics, measurement plans and result association.
- [ ] Add CMM/probe path planning and portable result import/export contracts.
- [ ] Add deviation maps and pass/fail reporting without mutating design geometry.
- [ ] Decide whether Inspection is a dedicated Section or a Manufacturing/PMI sub-workflow after the data model stabilises.

### P2 — Routing Section candidate
- [ ] Add mechanical/electrical routing path graphs, ports, connection points, stock/diameter rules and bend-radius constraints.
- [ ] Add hose/tube/pipe and wire/bundle representations with cut-length/BOM outputs.
- [ ] Add route validation for minimum bend radius, collisions and disconnected endpoints.

### P2 — Simulation/analysis architecture
- [ ] Define a solver-neutral analysis model separate from the design B-rep.
- [ ] Add materials, idealisations, mesh controls, loads, constraints and result fields.
- [ ] Keep external solver adapters modular; never make one commercial solver a kernel dependency.
- [ ] Add result contour/deformation visualisation through the graphics backend abstraction.

### P2 — Visualisation and rendering
- [ ] Add materials/appearances, scene lights, environment maps, camera bookmarks and render presets.
- [ ] Keep engineering display modes deterministic and separate from photorealistic rendering.
- [ ] Add section/clipping planes, exploded display states and saved view sets.

### P2 — Data exchange and healing
- [ ] Add STEP AP203/AP214/AP242, IGES and Parasolid-style neutral-bridge planning without making an external kernel mandatory.
- [ ] Add native STL/OBJ/PLY/3MF mesh interchange with units and colour/material metadata.
- [ ] Add import diagnostics: units, missing references, open shells, non-manifold geometry, tolerance/healing actions and information loss.
- [ ] Keep imported non-parametric geometry as dumb bodies unless an explicit feature-recognition operation is requested.

### P2 — document, attributes and versioning
- [ ] Add deterministic 64-bit document/object identity and persistent cross-document references.
- [ ] Add attributes/properties, layers/categories, reference sets and named selections.
- [ ] Add part/assembly revision metadata without coupling WaifuCAD to a specific PLM product.
- [ ] Add save checkpoints, recovery journals, crash-safe atomic save and format-version migration tests.
- [ ] Add model comparison/diff at document, feature, topology and PMI levels.

### P2 — performance and large-model work
- [ ] Add memory accounting per model/assembly occurrence/mesh/B-rep arena.
- [ ] Add out-of-core/lightweight caches for very large assemblies and tessellation data.
- [ ] Add incremental viewport invalidation instead of full redraw/re-tessellation after small edits.
- [ ] Add performance telemetry that can be enabled for profiling without recording private model contents.

### P1 — journalling and automation
- [ ] Finish SCL grammar and parser diagnostics with line/column reporting.
- [x] Add allocation-free Ruby-like SCL surface syntax; reserve `.wcs` for that surface and `.scl` for the historical whitespace command form while preserving journal replay.
- [x] Add direct one-command (`--command`) and interactive (`--repl`) SCL entry points to the batch host.
- [x] Migrate all shipped `.wcs` examples to Ruby-like syntax and add an extension-policy regression test.
- [ ] Generalise Ruby-style flow/function syntax to deterministic multiline blocks if required; do not turn the BetterC interpreter into an embedded Ruby runtime.
- [x] Add direct SCL journal replay entry point via `--journal-in`.
- [ ] Add journal replay verification hashes.
- [ ] Add journal metadata: WaifuCAD build, units, locale, kernel back-end and Mod list.
- [ ] Add Ruby journal adapter C ABI bridge.
- [ ] Add Java journal adapter C ABI bridge.
- [ ] Add Groovy journal adapter C ABI bridge.
- [ ] Add Crystal journal adapter C ABI bridge.
- [ ] Add sandbox policy for untrusted Scripts.

### P1 — GUI
- [x] Add a shared centred AutoCAD-like command-console state/layout that routes model mutations through SCL.
- [x] Render the shared command console in the GTK4 native front-end while preserving the shared SCL command path; terminal prototype remains available.
- [x] Declare Cocoa/AppKit as the native macOS front-end: macOS GUI targets build through `native/gui/cocoa` (C ABI scaffold plus stub) and never probe or link GTK4.
- [x] Implement the Objective-C AppKit/Metal bridge `native/gui/cocoa/wc_cocoa.m` (v2, GTK4 layout/feature parity): tabbed ribbon with scrolling SVG-icon command groups, Nightcore art, Model/Assembly/AI rail with collapsible navigator (badges, CSYS-plane/planar-face child rows, context menu, drag-and-drop reordering), GTK4 draw pipeline over a Metal clear pass (grid, translucent body bounds, sketches on support frames, face hover/selection, CSYS frames, axis triad), middle-drag orbit, cursor-centred wheel zoom, WASD pan, fit menus, centred command-console overlay and status bar; every widget action stays on the shared semantic SCL/journal command path.
- [x] Bring Cocoa/AppKit to GTK4 GUI workflow parity for the current bootstrap renderer: shared data-driven feature dialogues, semantic navigator/viewport picking, editable feature reopening, native file fields, interactive sketch mode with support selection/snapping/ambiguity choice, and matching sketch ribbon tools all use the same neutral descriptors and SCL/journal callbacks.
- [ ] Finish remaining Cocoa presentation/backend work: `assets/locales/` label lookup and the dedicated Metal WaifuBRep renderer replacing the shared bounds-wireframe bootstrap display.
- [x] Render toolkit-neutral Modelling/PMI ribbon descriptors as real GTK4 tabs/groups/buttons with project-owned SVG icons; ribbon commands now execute simple actions directly or open data-driven feature dialogues while all model mutations still use semantic SCL transactions.
- [x] Move the Nightcore theme image to the ribbon top-right and keep the viewport/navigation area free for CAD work.
- [x] Launch the GTK4 application with no command-line arguments; retain `--bootstrap-info` for non-interactive smoke tests and `--console` for the terminal prototype.
- [x] Implement the GTK4 bridge with native C ABI widgets, contextual ribbon, navigator stack, shared command line and redrawable P1 viewport. The earlier GTK4 bounds-window revision was user-runtime-verified on RHEL Linux x86-64; this expanded ribbon/navigation revision still requires a fresh user-host build/run check.
- [ ] Implement Qt6 bridge.
- [ ] Implement GTK3 bridge for conservative UNIX targets.
- [ ] Implement GTK2/GTK1 historical bridges only where a real target needs them.
- [ ] Implement Motif bridge.
- [ ] Implement Xlib minimal bridge.
- [x] Add GTK4 contextual-ribbon overflow behaviour at the 1024×768 baseline: groups wrap command buttons into rows of at most four and reduce SVG icon/button size when the available ribbon width is constrained, with horizontal scrolling as the final overflow path.
- [x] Add a live GTK4 Model Navigator plus left navigator rail entries for Model, Assembly and AI Agent; allow the Model Navigator content pane to collapse to zero width while retaining the narrow application rail.
- [x] Add dependency-safe semantic Model Navigator history editing: right-click Properties/Fit/Delete plus drag-and-drop reordering use journalled SCL commands, rejecting operations that would break dependency order or delete a referenced feature. The older bottom-arrow/delete control strip has been removed.
- [x] Add toolkit-neutral scriptable `FeatureDialogueDescriptorV1` data with a distinct waifu assignment per built-in dialogue, direct ribbon invocation, semantic profile/body/path pick fields that can select from Model Navigator or the graphics area where that feature class is visible, atomic in-place `feature_edit` transactions that preserve EntityId, and Model Navigator double-activation reopening editable feature dialogues; Sketch containers are valid profile selections when `resolveProfile` can form one region. Keep FeatureScript as a future metadata/operation adapter rather than executing it against kernel memory.
- [x] Keep Sketch-as-profile semantics consistent through preview and exact recompute, and expose native filesystem choosers for feature-dialogue file fields, Run Script, Record Journal and Run Journal; file actions still route through semantic SCL.
- [x] Add a GTK4 sketch-editing mode: Sketch enters an orthographic 2D editor, double-activating a sketch history row reopens it, and line/circle/rectangle drawing from the graphics area creates journalled SCL sketch entities with live cursor preview.
- [x] Make Sketch support explicit without manufacturing history helpers: a sketch may directly reference a datum plane, a CSYS XY/YZ/XZ plane, or an exact planar B-rep face selected from Model Navigator/viewport. GUI-created face/CSYS sketches persist that support on the Sketch feature itself; do not create `sketch_support*` datum features.
- [x] Add sketch snapping with hover highlighting and one-second ambiguity ellipsis/chooser: line endpoints, rectangle corners, circle centres/quadrants, arc centres/endpoints, the sketch-support origin and X/Y axes are recognised; line-to-line endpoint snaps also create journalled coincident constraints.
- [x] Keep sketch child geometry out of Model Navigator so sketch lines/arcs/circles/rectangles remain internal sketch entities rather than top-level history rows.
- [x] Make wheel zoom cursor-centred in both sketch and 3D bootstrap views.
- [x] Keep the left Model/Assembly/AI application rail visible independently from the collapsible navigator pane and drive navigator/rail background colours from theme tokens.
- [x] Remove the extra top application toolbar: Sections and Mods are persistent ribbon tabs and Scripts is a Home-ribbon group.
- [x] Keep Sections and Mods available from every Section, including registered Sections whose contextual ribbon is still planned; the Sections tab also contains a Mods management group.
- [x] Make the default 1024×768 Model Navigator compact with a visible part name, zero-width shrink support and explicit horizontal/vertical scrolling for long history labels; set the paned divider only after both children exist so GTK cannot replace the intended compact width with the navigator's natural width.
- [x] Add P1 graphics-area body picking from feature display bounds, highlight the selected body plus its exposed planar-face children, and expose right-click Fit/Fit Selected/Properties actions.
- [x] Render all resolvable datum CSYS frames in the 3D viewport, including the absolute part CSYS at model origin, with X/Y/Z axes plus translucent XY/YZ/XZ construction planes in addition to the view-orientation triad; construction planes remain visible/selectable in an otherwise empty part and occupy only the positive square quadrant bounded by their two positive CSYS axes rather than mirroring through the origin.
- [x] Render sketch entities in the normal 3D viewport on their real support frames instead of drawing the union of all preview bounds as one misleading box; exact planar WaifuBRep faces are drawn by default in both GTK4 and Cocoa so exact prismatic bodies remain visible without a fake bounds cube. Generic body bounds are a diagnostic overlay disabled by default (`WC_SHOW_BODY_BOUNDS=1` enables it), while selected-body bounds remain a selection aid until full curved/tessellated rendering lands.
- [ ] Add constraint navigator and command finder; Assembly/AI navigator data models remain partial until those Sections mature.
- [x] Add NX-inspired GTK4 viewport navigation without copying proprietary resources: wheel zoom and middle-button drag orbit.
- [x] Implement WASD viewport pan with focus rules: keyboard navigation is suppressed while an editable command/text field owns focus; Shift accelerates pan.
- [ ] Add high-DPI scaling without breaking the 1024×768 baseline.

### P1 — graphics
- [x] Add a header-free Vulkan 1.0 loader/physical-device capability probe that distinguishes hardware from software devices without making Vulkan a kernel dependency.
- [ ] Implement the dedicated WaifuCAD Vulkan 3D renderer; the current GTK4 bootstrap viewport draws exact planar B-rep face polygons plus sketch/datum geometry, with diagnostic bounds only on request, but still lacks the full curved/tessellated depth-buffered renderer.
- [ ] Implement Metal renderer for current macOS.
- [ ] Implement OpenGL renderer for legacy UNIX and fallback use.
- [ ] Prefer a dedicated OpenGL GPU over software Vulkan when policy says it will be faster.
- [x] Add NVIDIA/Mesa/lavapipe/llvmpipe detection to the native graphics probe and show an explicit software-Vulkan warning in the GTK4 status bar.
- [ ] Add GPU crash-safe renderer restart boundary.
- [ ] Add selection/picking buffer and construction geometry rendering.

### P1 — AI
- [x] Define provider-neutral AI request/response ABI (`AiProviderV1`) without raw model/kernel pointers.
- [ ] Add structured SCL generation mode with schema validation.
- [x] Add 144 read-only SCL/WCS model-inspection getters covering expressions, constraints, datums, parameters/features/dependencies, exact/preview geometry, persistent topology/lineage, NURBS/scheduler state, dumb meshes and PMI without leaking raw pointers.
- [ ] Add dry-run transaction evaluation before AI changes are committed.
- [ ] Add AI journal annotations explaining intent separately from executable commands.
- [ ] Add visual-feedback bridge for screenshots/viewport captures.

### P2 — platform work
- [ ] Add automated capability probe report per target.
- [ ] Establish LDC cross targets where LLVM code generation exists and C runtime/linker support is available.
- [ ] Establish GDC native builds where GCC/GDC exists.
- [ ] Verify Solaris 11.4 SPARC64 batch build and native pthread shim.
- [ ] Verify Solaris 11.4 x86-64 batch build and native pthread shim.
- [ ] Build/probe the user-confirmed Solaris GTK4 path on representative Solaris hosts.
- [ ] Build/probe the user-confirmed Solaris Vulkan path on representative hardware/software stacks.
- [ ] Research illumos SPARC64 and AArch64 state before claiming either.
- [ ] Verify FreeBSD x86-64 and AArch64.
- [ ] Verify Linux riscv64 native and cross builds with LDC and/or GDC.
- [ ] Verify FreeBSD riscv64 WaifuCAD batch build before changing its target status.
- [ ] Research NetBSD/OpenBSD architecture-specific GUI dependencies.
- [ ] Research HP-UX PA-RISC64 and IA64 compiler bootstrap options.
- [ ] Research AIX POWER big-endian toolchain first; do not assume a ppc64le AIX userland.
- [ ] Treat OpenVMS x86-64, Itanium and Alpha as separate ports.
- [ ] Keep requested OpenVMS PA-RISC as invalid unless the operating system gains such a port.
- [ ] Keep z/OS batch-only until a concrete GUI transport/use case is selected.
- [ ] Research OpenServer 10 toolchain availability.
- [ ] Preserve historical Tru64 Alpha, IRIX MIPS64 and macOS PowerPC targets as separate compatibility projects.
- [ ] Verify WebAssembly wasm64/WASI preview 1 batch build with a Memory64-capable LDC/Clang/sysroot/runtime stack.
- [ ] Verify WebAssembly wasm64/WASI preview 2 batch build with a Memory64-capable LDC/Clang/sysroot/runtime stack.
- [ ] Add browser-hosted wasm64 GUI/graphics bindings separately from WASI.

### P2 — Mods and SDK
- [ ] Dynamic library discovery per OS.
- [ ] ABI version negotiation and capability masks.
- [ ] Signed/unsigned Mod policy.
- [ ] Stable C header generated from D ABI definitions.
- [ ] Example Mod adding a Section and one SCL command.
- [ ] Out-of-process Mod option for crash isolation.

### P3 — release engineering
- [ ] Reproducible release manifests.
- [ ] Per-target CI matrix only after runners/emulators exist.
- [ ] Binary package layout for modern UNIX-like systems.
- [ ] Historical-port build documentation kept separate from current release support.

## Build-system regression guards

- Keep compiler-driver flags separated: POSIX C compilation may use `-pthread`, but LDC link commands must not receive raw `-pthread`; use the compiler normalisation in `build/compiler.sh`.

### D parser/compiler hygiene
- Treat D keywords as unavailable for identifiers and module path components. In particular, never use `debug`, `scope`, `body`, `package`, or `ref` as field/parameter/local/module identifiers; `ref` remains valid only in its D storage-class role.
- Current D compilers reject implicit adjacent string literal concatenation; join literal fragments explicitly with `~` or use one literal.
- Run `python3 tests/d_parser_hazards.py` before handing off a source patch. This complements, but does not replace, compiling with LDC/GDC.

### D compiler compatibility rules
- Use D's built-in `size_t`; do **not** import `size_t` from `core.stdc.stddef`. Current LDC/druntime layouts do not export it there consistently.
- Static ribbon descriptor tables use `__gshared const`, not transitively `immutable`, because their descriptor structs contain pointer fields and LDC rejects the mutable-aggregate-to-immutable conversion used by the old initialisers.
- Run `python3 tests/d_semantic_compat.py` before handing off compiler-facing patches.

### Additional LDC/BetterC semantic rules
- For `core.stdc.stdlib.strtod`/`strtoul`, keep the input and `endptr` qualifiers consistent. WaifuCAD parses read-only text as `const(char)*`, so use `const(char)* end`; when parsing a mutable stack token buffer, cast/pass the input as `const(char)*` as well.
- In struct member functions, reset a value with `this = Type.init`; `this` is the struct lvalue and must not be dereferenced with `*this`.
- When a pointer field must be reassignable but its pointee is read-only, spell it `const(Type)*`; avoid prefix `const Type*` in such state fields because D qualifiers are transitive/ambiguous for this purpose.
- If an `auto` local is derived from a const expression but will later be modified, give it an explicit mutable value type (for example `double tx = ...`).
- Narrow feature operand counts to `ubyte` only after enforcing the fixed-capacity/range check.






