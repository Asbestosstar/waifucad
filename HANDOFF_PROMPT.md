# WaifuCAD handoff prompt for another LLM

You are continuing development of **WaifuCAD**, a 64-bit-only, AI-oriented parametric CAD system written primarily in D using BetterC-compatible architecture. Work directly from the supplied project tree; do not recreate it from scratch. Read `AGENTS.MD` first, then `todos.txt`, then the source files relevant to the next patch.

## Non-negotiable project constraints

- All supported ISAs/targets are **64-bit only**. Do not add x86-32, ARM32, RV32, wasm32, or another 32-bit target.
- Core/kernel/B-rep/journal/SCL/Sections/Mods code must remain BetterC-safe: no GC allocation, D classes, exceptions, module constructors, or Phobos dependency in those layers.
- Use **British spelling** in code comments, documentation, UI strings and identifiers where a spelling choice exists.
- WaifuBRep is WaifuCAD's own exact geometry kernel. Do not silently substitute Open CASCADE, Parasolid or another external modelling kernel. External interchange libraries may be optional adapters, never the design kernel.
- Preserve exact/preview-only/failed geometry status. Never describe an approximate bounding box/mesh implementation as exact B-rep.
- The recommended modelling workflow is **sketch/profile -> extrude/revolve/sweep/loft -> detail features**, but NX-style rough/free curves outside sketches and non-associative dumb bodies are valid first-class objects and must remain supported.
- OpenSCAD capability parity in `config/openscad_parity.json` is a minimum SCL contract. `.scad` import/export is intentionally a **dumb-body boundary**.
- Journals must record semantic operations, not GUI clicks or raw memory changes. New editable operations should be replayable through SCL/journal infrastructure.
- AI/model inspection uses read-only `get_*` commands shared by `.wcs` and `.scl`; getters must not expose raw model/kernel pointers or enter semantic journals.
- Sections are equivalent to NX application contexts. **Modelling is the default Section.** Each implemented Section owns code under `src/waifucad/sections/<id>/` and its contextual ribbon. Persistent Sections and Mods ribbon tabs remain available while contextual tabs change; Scripts is a Home-ribbon group.
- **PMI is a separate Section**, not modelling history. Basic semantic commands already exist: `pmi_add`, `pmi_text`, `pmi_visible`, `pmi_delete`. Persistent topology association is still unfinished.
- Assemblies are still planned. Preserve the detailed load-policy contract in `config/assembly_load_options.json` and `docs/ASSEMBLIES.md`; suppression and unloading are distinct.
- Preserve dependency-safe multicore recompute. Do not parallelise dependent feature operations out of order.
- Do not claim a target is verified merely because a port directory or LLVM backend exists.

## Current architecture/state

- BetterC kernel/model graph, semantic journal recorder and SCL interpreter exist.
- Expression parameters include unit-aware arithmetic plus fixed BetterC formula functions; the sketch solver now has bounded finite-difference Jacobian/rank diagnostics and damped nonlinear correction in addition to projection solving.
- Expression parameters are persistent and reevaluated before recompute with named references, unit checking, divide-by-zero/unknown-reference handling and cycle protection.
- Datum planes, axes and co-ordinate systems are first-class features. Every part starts with pinned `absolute_csys` at 0,0,0. Associative CSYS-derived/offset planes and exact-planar-face-derived support planes exist; sketches reference datum planes and datum dependencies participate in dirty/dependency ordering.
- The fixed-capacity sketch solver persists common geometric/dimensional constraints and now combines projection solving with residual/DOF/redundancy/conflict diagnostics, a 128-variable/256-equation finite-difference Jacobian, pivoted two-pass modified Gram-Schmidt rank analysis and damped nonlinear correction. Line/curve tangency works in either operand order and external curve/curve tangency is supported; very large sketches and richer symmetry/internal tangency remain unfinished.
- WaifuBRep contains analytic box/cylinder/cone/frustum/sphere/torus topology; arbitrary closed line-polygon prism extrusion; supported analytic polygon revolution, straight sweep, compatible loft and selected box boolean/shell exact paths; multi-loop/genus-aware validation; persistent semantic topology IDs and lineage for implemented mutations.
- Planar chord face split/constrained merge, line-edge split, analytic intersection groundwork (including sphere/sphere and parallel-cylinder intersections), fixed-arena rational NURBS evaluation and explicit tolerance/healing groundwork exist. General robust boolean trim/imprint/classification/stitching and trimmed NURBS remain unfinished.
- Topology-aware exact-BRep tessellation is used by OpenSCAD export for supported trim/surface domains. Planar faces can now triangulate bounded multiple sampled inner loops through visibility-checked bridges; unsafe/over-capacity cases still fail rather than fill holes. Full chord/angle-guaranteed curved/NURBS trim tessellation remains TODO.
- Multicore feature recompute uses a C ABI/pthread scheduler with persistent workers, bounded participant queues/work stealing, nested-serial oversubscription policy and cooperative cancellation. Dependency-depth ordering is preserved. Exact topology construction remains serial until deterministic per-worker arena merge semantics exist.
- Modelling Section is the default contextual ribbon. PMI Section and its BetterC-safe annotation store exist.
- OpenSCAD-equivalent SCL surface and dumb-body `.scad` importer/exporter exist. The external evaluator now reserves its OFF path through a secure `mkstemp` C ABI service rather than `tmpnam`.
- SCL uses an allocation-free Ruby-like `.wcs` surface (`box(:body, 80.mm, 50.mm, 10.mm)`, symbols, assignments and selected Ruby keywords/aliases). Historical whitespace command-form source uses `.scl` for migration/compatibility; journal replay remains compatible. Batch supports `--command` and `--repl`.
- Feature dialogues are now toolkit-neutral `FeatureDialogueDescriptorV1` data. Ribbon commands no longer require the visible command line: simple actions execute immediately and complex modelling actions open data-driven dialogues. Every built-in dialogue has its own waifu image assignment from `waifus/`. Feature-reference fields carry semantic pick roles (profile/body/path/any feature); GTK4 can arm a Select action and accept matching Model Navigator rows or visible viewport geometry. A Sketch container is a valid profile when `resolveProfile` resolves its one region/closed loop. Editable supported history features use semantic `feature_edit(...)` to redefine the existing feature in place while preserving its EntityId; Model Navigator double activation reopens the same dialogue. Future Mod/script/FeatureScript parameter importers must target the descriptor/SCL boundary rather than writing kernel memory directly.
- GTK4 is the first functional native GUI frontend. It launches with no arguments. There is no separate top toolbar: persistent Sections/Mods ribbon tabs precede contextual Section tabs in every Section, Scripts is a Home group, Sections also contains a Mods group, and Nightcore art remains at ribbon top-right. The Model/Assembly/AI rail stays visible while navigator content can collapse to zero and its colours come from theme tokens. Model Navigator omits sketch child entities, keeps the part name visible in a compact 1024x768 layout, supports right-click Properties/Fit/Delete plus dependency-safe drag-and-drop reordering through semantic SCL, and exposes CSYS planes/planar faces as sketch supports. Sketches can be created on datum/CSYS planes or exact planar B-rep faces selected in navigator/viewport, and GUI-created CSYS/face support is stored directly on the Sketch feature rather than as a visible `sketch_support*` datum feature. Sketch snapping recognises line endpoints, rectangle corners, circle/arc reference points and the support origin/X/Y axes, with one-second ambiguity selection; line-to-line endpoint snaps also create semantic coincident constraints. Wheel zoom is cursor-centred. The normal 3D view renders sketch primitives on their real datum support frames instead of drawing the union of sketch bounds as a fake cube. Exact planar WaifuBRep faces are rendered by default in both GTK4 and Cocoa so prismatic exact bodies stay visible without a fake bounds cube. Generic body bounds are a diagnostic overlay disabled by default (`WC_SHOW_BODY_BOUNDS=1` enables it); selected-body bounds remain available as a selection aid until the full curved/tessellated renderer lands. The graphics area can select whole display-bound bodies, highlights their planar-face children, provides a right-click Fit menu, and draws resolvable datum CSYS frames with X/Y/Z axes plus translucent XY/YZ/XZ planes. Qt/Motif/Xlib remain scaffold work, and the dedicated Vulkan WaifuBRep renderer is still unfinished. Cocoa/AppKit is the native macOS front-end: macOS GUI targets select it in `build.sh` without any GTK4 probe or dependency. The v2 Objective-C bridge (`native/gui/cocoa/wc_cocoa.m`) mirrors the GTK4 host: tabbed ribbon with scrolling SVG-icon command groups and Nightcore art (including a compact, top-first two-row Sections launcher that fits the fixed AppKit ribbon height), Model/Assembly/AI rail with the collapsible navigator (badges, CSYS-plane/planar-face child rows, context menu, drag-and-drop reordering), the GTK4 draw pipeline over a Metal clear pass, middle-drag orbit / cursor-centred wheel zoom / WASD pan / fit menus / face hover-selection, the centred command-console overlay and the status bar; data-driven feature dialogues and interactive sketch editing now consume the same toolkit-neutral descriptor/callback contracts as GTK4, including semantic selection, native file choosers, sketch support selection and snapping. Locale label lookup and the dedicated Metal WaifuBRep renderer remain TODO, and non-macOS hosts link the headless stub.
- Data-driven feature dialogues now use distinct waifu art, semantic profile/body/path picking from Model Navigator/viewport, and `feature_edit` for identity-preserving edits. Sketch is a first-class profile in both preview and exact recompute. Native file choosers are used for Run Script, Run Journal, Record Journal destinations, and file-valued import/export dialogue fields; these still execute through semantic SCL/journal commands.
- Read-only AI/model inspection exposes 144 getter commands through the same SCL runtime in `.wcs` and `.scl`, including expressions, constraints, datum frames, feature dependencies, exact/preview status/properties, topology persistent IDs/lineage/genus/loops, NURBS counts, scheduler state, dumb meshes and PMI. Getters do not expose raw kernel pointers or enter semantic journals.
- `AiProviderV1` defines the provider-neutral C ABI for owned UTF-8 request/response payloads and capability negotiation; providers never receive `Model*`/WaifuBRep pointers.
- 14 architecture families and all declared targets are constrained to 64-bit. RISC-V is RV64 only; LoongArch is LA64 (`loongarch64`) research only; WebAssembly is wasm64/Memory64 research only.
- Assembly remains planned. Its load-policy contract must remain independent from this modelling-kernel work.

## Current verification note

- User-verified LDC compile/full smoke test and GTK4 native window launch on RHEL Linux x86-64 on 2026-08-19. Do not generalise that verification to other operating systems, architectures or GUI front-ends.
- Native GPU probing now enumerates Vulkan physical devices without Vulkan headers and distinguishes hardware from software-only Vulkan, with NVIDIA/Mesa/lavapipe/llvmpipe diagnostics. The dedicated WaifuCAD Vulkan 3D renderer is still TODO.

## Recommended next work order

0. **Compiler/run hardening on a real LDC host**: run the new advanced BetterC tests and fix any LDC semantic issues before broadening exact algorithms. Do not convert static checks into claims of a verified D build.
1. **Sketch solver maturity**: the 128-variable/256-equation Jacobian/nonlinear path, pivoted rank analysis, line/curve tangency and external curve/curve tangency are implemented. Next remove the fixed diagnostic window for very large coupled sketches and add richer symmetry/internal-tangency forms while preserving BetterC storage rules.
2. **General boolean pipeline**: expand surface/surface intersections into trim/imprint curves, region classification, shell stitching and tolerant healing. Carry persistent topology lineage through every generated entity.
3. **General trimmed geometry**: planar multi-loop triangulation is now present within fixed sampling/capacity limits. Next add chord/angle-guaranteed curved/NURBS multi-loop tessellation, then trimmed analytic/NURBS topology and robust NURBS intersections/sewing.
4. **Exact feature breadth**: curved-path sweep, more general loft/revolve/partial revolve and conventional selected-face shell/remove-face semantics.
5. **Scheduling polish**: cooperative cancellation checkpoints now exist in the sketch solver and WaifuBRep tessellator. Extend them to long boolean/NURBS/healing operations and connect native GUI cancellation once a frontend is functional. Keep dependent-feature ordering and serial shared-BRep mutation.
6. **PMI association hardening**: replace the temporary generic subentity-index fields with persistent topology references, then add PMI view sets/annotation planes/standards validation.
7. Continue the roadmap in `AGENTS.MD` for deterministic serialisation/undo, Assembly, Drawing, Sheet Metal, Manufacturing/CAM, Inspection, Routing, Simulation, visualisation and interchange.

If a requested next patch is narrower than this order, follow the requested scope first. Do not describe the current bootstrap exact domains as a complete industrial CAD kernel merely to check a roadmap box.

## Assembly load-policy requirements

When assembly implementation begins, one option structure must be shared by GUI, batch, SCL and journal replay. It should support:

- document policy: fully loaded, lightweight, structure-only, partial, load-on-demand;
- occurrence state: fully loaded, lightweight, structure-only, deferred, unloaded, suppressed;
- geometry preference: exact, tessellated, bounds-only, auto;
- recursive load depth; reference-set/representation choice;
- interpart dependency promotion policy;
- PMI and attribute loading level;
- stale proxy policy;
- memory budget and bounded I/O concurrency;
- stable occurrence identity/transform/selection references across promotion and demotion.

The AI should request the **lightest sufficient representation** for its task. Measuring one component must not automatically fully load a 50,000-component assembly.

## Patch workflow

1. Read `AGENTS.MD` and the relevant source/docs/config.
2. Make the smallest coherent architectural patch.
3. Update tests and documentation with the code.
4. Preserve BetterC constraints and the 64-bit-only policy.
5. Run all available static/shell/JSON/C tests. If no D compiler is present, say so explicitly rather than claiming a D compile.
6. Run `./make_todos.sh` so `todos.txt` contains the new state. This also regenerates `PROJECT_TREE.txt` and appends the dimensions of every `waifus/**/*.png` asset.
7. Do not hand-edit the generated waifu PNG index in `PROJECT_TREE.txt`.
8. Package the updated project.
9. Summarise what is exact, what is only scaffold/preview, what was actually tested, and the next best TODO item.

## Immediate patch already started in this handoff

Basic PMI SCL/journal commands have been added. Verify and preserve:

```text
pmi_add KIND NAME "TEXT" [FEATURE|none] [SUBENTITY_KIND] [SUBENTITY_INDEX]
pmi_text NAME "NEW TEXT"
pmi_visible NAME true|false
pmi_delete NAME
```

These generic subentity fields are temporary. Do **not** build more features around raw transient face/edge indices; move toward persistent topology naming first.

### Additional LDC/BetterC semantic rules
- Do not use `ref` as an identifier (for example `auto ref = ...`); `ref` is a D keyword/storage class. Use names such as `referenceDirection`.
- For `core.stdc.stdlib.strtod`/`strtoul`, keep the input and `endptr` qualifiers consistent. WaifuCAD parses read-only text as `const(char)*`, so use `const(char)* end`; when parsing a mutable stack token buffer, cast/pass the input as `const(char)*` as well.
- In struct member functions, reset a value with `this = Type.init`; `this` is the struct lvalue and must not be dereferenced with `*this`.
- When a pointer field must be reassignable but its pointee is read-only, spell it `const(Type)*`; avoid prefix `const Type*` in such state fields because D qualifiers are transitive/ambiguous for this purpose.
- If an `auto` local is derived from a const expression but will later be modified, give it an explicit mutable value type (for example `double tx = ...`).
- Narrow feature operand counts to `ubyte` only after enforcing the fixed-capacity/range check.






