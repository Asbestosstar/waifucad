# Assemblies — planned architecture

Assemblies are a P1/P2 design target and are deliberately listed in the TODOs
before implementation begins.  The Assembly Section will use component
**prototypes** plus placed **occurrences**, with stable occurrence identity,
64-bit-safe IDs and transforms independent of how much component data is
currently loaded.

## Required load options

WaifuCAD assemblies must not force every component into memory.  The first
implementation should support these document-level policies:

- **Fully loaded** — structure, metadata, exact geometry and editable part
  history wherever available.
- **Lightweight** — structure, transforms, bounds, key metadata and display
  tessellation, with exact geometry/history deferred.
- **Structure only** — occurrence tree and essential metadata with no component
  geometry.
- **Partial** — selected components fully loaded while the rest use lighter
  states.
- **Load on demand** — begin light and promote data only when a command requires
  it.

Individual occurrences need distinct states: `fully_loaded`, `lightweight`,
`structure_only`, `deferred`, `unloaded` and `suppressed`.  Suppression is a
modelling/configuration decision and must never be conflated with unloading.

## Behavioural requirements

- Preserve occurrence identity and transform through every load-state change.
- Journal explicit load-state changes and command-triggered promotions.
- Batch CLI must be able to force an assembly load policy.
- GUI must expose load policy before opening very large assemblies.
- AI tools should prefer the lightest state sufficient for inspection and only
  request full loading when an operation truly requires exact/component data.
- Selection references must survive lightweight/full promotion.
- Assembly constraints/joints and arrangements/configurations must not depend on
  display tessellation identity.
- Multicore loading should schedule independent component loads while respecting
  file/dependency ordering and user cancellation.

The machine-readable design contract is `config/assembly_load_options.json`.

## Planned load-option controls

Assembly opening must expose both a document-level policy and optional per-occurrence overrides. The policy surface is defined in `config/assembly_load_options.json` and must be shared by GUI, batch, SCL and journals rather than reimplemented separately. Planned controls include:

- representation preference: exact, tessellated/lightweight, bounds-only or automatic;
- recursive load depth for selected subassemblies;
- reference-set/representation choice;
- whether interpart dependencies are allowed to promote referenced components;
- PMI loading: none, visible only or all;
- essential/all attribute loading;
- stale proxy behaviour: allow, warn, refresh or reject;
- soft memory budget and independent bounded I/O concurrency;
- per-occurrence promotion/demotion while preserving occurrence identity and transform.

A component being **suppressed** remains a design/configuration state. A component being **unloaded** remains a resource/load state. The implementation must never collapse the two concepts.



