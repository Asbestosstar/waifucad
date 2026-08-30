module waifucad.brep.naming;

import waifucad.brep.types;

/*
 * Persistent topology identity v1.
 *
 * Raw BRepId values are arena locations and are rebuilt during recompute.  A
 * persistent ID instead combines the owning model feature EntityId (upper
 * 32 bits) with a topology kind and a semantic slot (lower 32 bits).  The
 * semantic slot is independent of dimensions, so ordinary parameter edits of
 * an analytic primitive preserve body/face/edge/vertex identity.
 *
 * This identity is document-session persistent. Cross-save persistence waits
 * for deterministic document serialisation, and boolean/split lineage must
 * provide explicit semantic lineage tokens rather than reusing arena indices.
 */
private enum ulong WC_TOPOLOGY_KIND_SHIFT = 28;
private enum ulong WC_TOPOLOGY_SLOT_MASK = 0x0FFF_FFFFUL;
private enum ulong WC_TOPOLOGY_KIND_MASK = 0xFUL;

enum WC_TOPOLOGY_MAX_SEMANTIC_SLOT = 0x0FFF_FFFE;

BRepPersistentId makePersistentTopologyId(uint ownerFeatureId,
                                          BRepTopologyKind kind,
                                          uint semanticSlot) nothrow @nogc
{
    if (ownerFeatureId == 0 || kind == BRepTopologyKind.none ||
        semanticSlot > WC_TOPOLOGY_MAX_SEMANTIC_SLOT)
        return 0;
    return (cast(ulong)ownerFeatureId << 32) |
           (cast(ulong)kind << WC_TOPOLOGY_KIND_SHIFT) |
           (cast(ulong)semanticSlot + 1UL);
}

uint persistentTopologyOwner(BRepPersistentId id) nothrow @nogc
{
    return cast(uint)(id >> 32);
}

BRepTopologyKind persistentTopologyKind(BRepPersistentId id) nothrow @nogc
{
    if (id == 0)
        return BRepTopologyKind.none;
    auto raw = cast(ubyte)((id >> WC_TOPOLOGY_KIND_SHIFT) & WC_TOPOLOGY_KIND_MASK);
    if (raw > cast(ubyte)BRepTopologyKind.vertex)
        return BRepTopologyKind.none;
    return cast(BRepTopologyKind)raw;
}

bool persistentTopologySlot(BRepPersistentId id, uint* semanticSlot) nothrow @nogc
{
    if (semanticSlot is null || persistentTopologyKind(id) == BRepTopologyKind.none)
        return false;
    auto stored = cast(uint)(id & WC_TOPOLOGY_SLOT_MASK);
    if (stored == 0)
        return false;
    *semanticSlot = stored - 1u;
    return true;
}

BRepSolid* solidByPersistentId(BRepArena* arena, BRepPersistentId id) nothrow @nogc
{
    if (arena is null || id == 0)
        return null;
    foreach (i; 0 .. arena.solidCount)
        if (arena.solids[i].persistentId == id)
            return &arena.solids[i];
    return null;
}

BRepFace* faceByPersistentId(BRepArena* arena, BRepPersistentId id) nothrow @nogc
{
    if (arena is null || id == 0)
        return null;
    foreach (i; 0 .. arena.faceCount)
        if (arena.faces[i].persistentId == id)
            return &arena.faces[i];
    return null;
}

BRepEdge* edgeByPersistentId(BRepArena* arena, BRepPersistentId id) nothrow @nogc
{
    if (arena is null || id == 0)
        return null;
    foreach (i; 0 .. arena.edgeCount)
        if (arena.edges[i].persistentId == id)
            return &arena.edges[i];
    return null;
}

BRepVertex* vertexByPersistentId(BRepArena* arena, BRepPersistentId id) nothrow @nogc
{
    if (arena is null || id == 0)
        return null;
    foreach (i; 0 .. arena.vertexCount)
        if (arena.vertices[i].persistentId == id)
            return &arena.vertices[i];
    return null;
}

private void assignBody(BRepSolid* solid, uint ownerFeatureId) nothrow @nogc
{
    solid.persistentId = makePersistentTopologyId(ownerFeatureId, BRepTopologyKind.solidBody, 0);
}

private bool assignBox(BRepArena* arena, BRepSolid* solid, uint ownerFeatureId) nothrow @nogc
{
    if (solid.vertexCount != 8 || solid.faceCount != 6)
        return false;

    foreach (local; 0 .. solid.vertexCount)
    {
        auto vertex = arena.vertex(solid.firstVertex + cast(BRepId)local);
        if (vertex is null)
            return false;
        vertex.persistentId = makePersistentTopologyId(ownerFeatureId, BRepTopologyKind.vertex, cast(uint)local);
    }

    foreach (local; 0 .. solid.faceCount)
    {
        auto face = arena.face(solid.firstFace + cast(BRepId)local);
        if (face is null)
            return false;
        /* Box face slots: bottom, top, -Y, +X, +Y, -X. */
        face.persistentId = makePersistentTopologyId(ownerFeatureId, BRepTopologyKind.face, cast(uint)local);
    }

    foreach (local; 0 .. solid.edgeCount)
    {
        auto edge = arena.edge(solid.firstEdge + cast(BRepId)local);
        if (edge is null)
            return false;
        auto a = arena.vertex(edge.startVertex);
        auto b = arena.vertex(edge.endVertex);
        if (a is null || b is null || a.persistentId == 0 || b.persistentId == 0)
            return false;
        uint aSlot = 0;
        uint bSlot = 0;
        if (!persistentTopologySlot(a.persistentId, &aSlot) || !persistentTopologySlot(b.persistentId, &bSlot))
            return false;
        auto low = aSlot < bSlot ? aSlot : bSlot;
        auto high = aSlot < bSlot ? bSlot : aSlot;
        /* Endpoint-pair encoding is stable even if edge arena creation order changes. */
        auto edgeSlot = low * 8u + high;
        edge.persistentId = makePersistentTopologyId(ownerFeatureId, BRepTopologyKind.edge, edgeSlot);
    }
    return true;
}

private bool assignAxialPrimitive(BRepArena* arena, BRepSolid* solid, uint ownerFeatureId) nothrow @nogc
{
    if (solid.vertexCount < 2)
        return false;

    /* The bootstrap cylinder/cone/frustum constructors have one semantic
       bottom and one semantic top vertex. Determine them geometrically rather
       than trusting arena order so zero-radius cap changes do not rename them. */
    foreach (local; 0 .. solid.vertexCount)
    {
        auto vertex = arena.vertex(solid.firstVertex + cast(BRepId)local);
        if (vertex is null)
            return false;
        auto slot = vertex.point.z <= (solid.bounds.minimum.z + solid.bounds.maximum.z) * 0.5 ? 0u : 1u;
        vertex.persistentId = makePersistentTopologyId(ownerFeatureId, BRepTopologyKind.vertex, slot);
    }

    foreach (local; 0 .. solid.edgeCount)
    {
        auto edge = arena.edge(solid.firstEdge + cast(BRepId)local);
        if (edge is null)
            return false;
        uint slot = 2u; // axial seam
        if (edge.curveKind == BRepCurveKind.circle)
            slot = edge.origin.z <= (solid.bounds.minimum.z + solid.bounds.maximum.z) * 0.5 ? 0u : 1u;
        edge.persistentId = makePersistentTopologyId(ownerFeatureId, BRepTopologyKind.edge, slot);
    }

    foreach (local; 0 .. solid.faceCount)
    {
        auto face = arena.face(solid.firstFace + cast(BRepId)local);
        if (face is null)
            return false;
        uint slot = 2u; // analytic side
        if (face.surfaceKind == BRepSurfaceKind.plane)
            slot = face.normal.z < 0.0 ? 0u : 1u;
        face.persistentId = makePersistentTopologyId(ownerFeatureId, BRepTopologyKind.face, slot);
    }
    return true;
}

private bool assignSphere(BRepArena* arena, BRepSolid* solid, uint ownerFeatureId) nothrow @nogc
{
    if (solid.vertexCount != 2 || solid.edgeCount != 1 || solid.faceCount != 1)
        return false;
    foreach (local; 0 .. solid.vertexCount)
    {
        auto vertex = arena.vertex(solid.firstVertex + cast(BRepId)local);
        if (vertex is null)
            return false;
        auto slot = vertex.point.z <= (solid.bounds.minimum.z + solid.bounds.maximum.z) * 0.5 ? 0u : 1u;
        vertex.persistentId = makePersistentTopologyId(ownerFeatureId, BRepTopologyKind.vertex, slot);
    }
    auto edge = arena.edge(solid.firstEdge);
    auto face = arena.face(solid.firstFace);
    if (edge is null || face is null)
        return false;
    edge.persistentId = makePersistentTopologyId(ownerFeatureId, BRepTopologyKind.edge, 0);
    face.persistentId = makePersistentTopologyId(ownerFeatureId, BRepTopologyKind.face, 0);
    return true;
}


private bool assignTorus(BRepArena* arena, BRepSolid* solid, uint ownerFeatureId) nothrow @nogc
{
    if(solid.vertexCount!=1||solid.edgeCount!=2||solid.faceCount!=1) return false;
    auto vertex=arena.vertex(solid.firstVertex); auto e0=arena.edge(solid.firstEdge); auto e1=arena.edge(solid.firstEdge+1); auto face=arena.face(solid.firstFace);
    if(vertex is null||e0 is null||e1 is null||face is null) return false;
    vertex.persistentId=makePersistentTopologyId(ownerFeatureId,BRepTopologyKind.vertex,0);
    e0.persistentId=makePersistentTopologyId(ownerFeatureId,BRepTopologyKind.edge,0); e1.persistentId=makePersistentTopologyId(ownerFeatureId,BRepTopologyKind.edge,1);
    face.persistentId=makePersistentTopologyId(ownerFeatureId,BRepTopologyKind.face,0); return true;
}

private bool assignSequential(BRepArena* arena, BRepSolid* solid, uint ownerFeatureId) nothrow @nogc
{
    if (arena is null || solid is null) return false;
    foreach (local; 0 .. solid.vertexCount)
    {
        auto vertex=arena.vertex(solid.firstVertex+cast(BRepId)local); if(vertex is null)return false;
        vertex.persistentId=makePersistentTopologyId(ownerFeatureId,BRepTopologyKind.vertex,cast(uint)local);
    }
    foreach (local; 0 .. solid.edgeCount)
    {
        auto edge=arena.edge(solid.firstEdge+cast(BRepId)local); if(edge is null)return false;
        edge.persistentId=makePersistentTopologyId(ownerFeatureId,BRepTopologyKind.edge,cast(uint)local);
    }
    foreach (local; 0 .. solid.faceCount)
    {
        auto face=arena.face(solid.firstFace+cast(BRepId)local); if(face is null)return false;
        face.persistentId=makePersistentTopologyId(ownerFeatureId,BRepTopologyKind.face,cast(uint)local);
    }
    return true;
}

bool assignPrimitivePersistentTopology(BRepArena* arena,
                                       BRepId solidId,
                                       uint ownerFeatureId) nothrow @nogc
{
    auto solid = arena is null ? null : arena.solid(solidId);
    if (solid is null || ownerFeatureId == 0 || !solid.bounds.valid)
        return false;
    assignBody(solid, ownerFeatureId);
    final switch (solid.primitiveKind)
    {
        case BRepPrimitiveKind.box:
            return assignBox(arena, solid, ownerFeatureId);
        case BRepPrimitiveKind.cylinder:
        case BRepPrimitiveKind.coneFrustum:
            return assignAxialPrimitive(arena, solid, ownerFeatureId);
        case BRepPrimitiveKind.sphere:
            return assignSphere(arena, solid, ownerFeatureId);
        case BRepPrimitiveKind.torus:
            return assignTorus(arena, solid, ownerFeatureId);
        case BRepPrimitiveKind.generic:
        case BRepPrimitiveKind.boxShell:
            return assignSequential(arena, solid, ownerFeatureId);
    }
}

/* Deterministically derive a child topology identity from an existing stable
 * identity. This is used only when a semantic topology mutation supplies a
 * child ordinal; raw arena indices are never used as persistent identity. */
BRepPersistentId derivePersistentTopologyId(BRepPersistentId parent,
                                             BRepTopologyKind childKind,
                                             uint childOrdinal) nothrow @nogc
{
    uint slot=0;
    auto owner=persistentTopologyOwner(parent);
    if(owner==0 || !persistentTopologySlot(parent,&slot) || childKind==BRepTopologyKind.none) return 0;
    ulong mixed=(cast(ulong)slot*65537UL + cast(ulong)childOrdinal*257UL +
                 cast(ulong)persistentTopologyKind(parent)*17UL + 0x5A5AUL) & WC_TOPOLOGY_SLOT_MASK;
    if(mixed==WC_TOPOLOGY_SLOT_MASK) --mixed;
    return makePersistentTopologyId(owner,childKind,cast(uint)mixed);
}

bool recordSolidLineage(BRepArena* arena, BRepId resultId, BRepId parentAId,
                        BRepId parentBId, BRepLineageKind kind) nothrow @nogc
{
    if(arena is null) return false;
    auto result=arena.solid(resultId); auto a=arena.solid(parentAId);
    auto b=parentBId==0?null:arena.solid(parentBId);
    if(result is null || a is null || result.persistentId==0 || a.persistentId==0) return false;
    return arena.addLineage(result.persistentId,a.persistentId,b is null?0:b.persistentId,kind);
}

