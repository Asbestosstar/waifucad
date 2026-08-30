# Architecture

## Command flow

`GUI / AI / Batch -> Ruby-style/legacy SCL text -> SCL normaliser/interpreter -> transaction -> parameter/feature graph -> WaifuBRep geometry back-end -> tessellation -> renderer`

The Ruby-style layer is allocation-free syntax normalisation, not a separate modelling API or embedded Ruby runtime. The journal recorder observes the semantic command transaction boundary and may retain the user-entered SCL spelling. This makes a journal a modelling history rather than a recording of pointer motion or widget positions.

WaifuCAD is 64-bit-only. The common BetterC source includes a compile-time eight-byte `size_t` assertion so ABI drift is rejected during compilation.

## ABI boundaries

The project uses versioned plain structs and function pointers for boundaries that may be implemented outside BetterC:

- `GeometryBackendV1`
- `JournalBackendV1`
- `SectionDescriptorV1`
- `ModDescriptorV1`
- `GuiFrontendV1`
- `GraphicsBackendV1`
- `AiProviderV1`

A foreign bridge can therefore be written in C, C++, Objective-C, Rust, Ruby embedding APIs, JNI, or another language without requiring D runtime compatibility. `GeometryBackendV1` remains useful for testing/preview back-ends, but WaifuBRep is the project-owned exact modelling kernel rather than a placeholder for a third-party kernel.

## Parametric model

The bootstrap model uses bounded arrays deliberately. This avoids hidden allocation while the BetterC memory policy is still being defined. A later arena/vector implementation can replace the fixed capacities without changing the public ABI.

A feature stores operands as literals, parameter references or earlier feature references. Parameter changes dirty only affected feature chains. Feature references establish an acyclic dependency depth because the bootstrap graph only permits references to earlier features. Recompute resolves current parameter values and processes dependency depths in order; independent dirty features inside one depth are dispatched through the multicore job ABI.

The WaifuBRep backend performs the dependency-safe preview recompute first, then deterministically rebuilds exact topology. Every feature records whether exact topology exists, whether it is currently preview-only, or whether exact construction failed.

## WaifuBRep

Exact geometry is stored as vertices, edges, coedges, loops, faces, shells and solids. Analytic curve/surface data belongs to the exact topology rather than the renderer. Current exact primitives include box, analytic cylinder, sphere and cone/frustum; line/circle curve evaluation, plane/cylinder surface evaluation, manifold validation and topology-preserving line-edge splitting are already in-tree. See `docs/BREP.md`.

## AI safety boundary

AI code does not receive raw model pointers. Providers connect through the versioned `AiProviderV1` C ABI and exchange owned UTF-8 request/response payloads. Document inspection is performed through the read-only SCL/WCS getter catalogue in `config/scl_getters.json`; getters write only to script-runtime variables and do not enter semantic journals. AI-generated mutations still produce SCL text or structured commands. A dry-run validator remains future work before proposed mutations are committed.

## Multicore boundary

BetterC D does not depend on `core.thread`. The kernel calls `wc_parallel_for` through `src/waifucad/core/jobs.d`, while native thread implementation details remain under `native/threads/`. This is intentionally another C ABI boundary so Solaris, historical UNIX, OpenVMS, z/OS USS or other 64-bit ports can replace the native threading shim without changing parametric model code.

## Dumb mesh/interchange layer

`waifucad.mesh` is intentionally parallel to, not inside, WaifuBRep. Exact
native solids live in WaifuBRep; imported/rendered/tessellated foreign geometry
can live in `MeshArena` and be referenced by a `dumbBody` feature through
`meshId`. This prevents foreign triangle soups from being mistaken for exact
analytic topology or associative modelling history.

`waifucad.interchange.openscad` uses that layer in both directions. Arbitrary
`.scad` source can be evaluated by an external OpenSCAD executable and bridged
through OFF; WaifuCAD export tessellates exact supported B-rep primitives or
uses existing dumb meshes and emits OpenSCAD `polyhedron()` bodies. Option
structs are shared by batch/SCL and are intended to be reused by future GUI
panels.

## Section application layer

WaifuCAD Sections are NX-style application contexts above the shared kernel and
document services.  `modelling` is the default Section.  The global GUI chrome
keeps persistent Sections/Mods ribbon tabs available (with Scripts in Home) while `SectionContext` selects the active
application and `RibbonHostState` exposes that Section's contextual ribbon.
Implemented built-ins own code under `src/waifucad/sections/<id>/`.

PMI is intentionally a separate Section with its own fixed-capacity annotation
store.  Assembly is also a separate future Section; its load-state architecture
is specified in `docs/ASSEMBLIES.md` rather than being embedded into Modelling.



