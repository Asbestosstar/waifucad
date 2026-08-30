# Dumb mesh layer

`waifucad.mesh` stores deliberately non-associative triangle meshes. It is used
for imports, flattened interchange and direct/dumb bodies. It is intentionally
separate from WaifuBRep: a mesh may be useful geometry without having a valid
parametric history or exact analytic B-rep topology.

The bootstrap arena is fixed-capacity to preserve BetterC/`@nogc` operation.
Later allocator work may replace the capacities without changing `MeshId` or
the interchange API.



