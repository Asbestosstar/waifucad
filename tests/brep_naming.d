module tests.brep_naming;

import core.stdc.stdio : fprintf, stderr;
import waifucad.brep.euler : splitLineEdge;
import waifucad.brep.kernel : makeBox, makeConeFrustum, makeSphere;
import waifucad.brep.naming : assignPrimitivePersistentTopology, edgeByPersistentId,
    faceByPersistentId, makePersistentTopologyId, persistentTopologyKind,
    persistentTopologyOwner, persistentTopologySlot, solidByPersistentId, vertexByPersistentId;
import waifucad.brep.types;

private bool sameBoxNames(BRepArena* a, BRepId aSolidId, BRepArena* b, BRepId bSolidId) nothrow @nogc
{
    auto aSolid = a.solid(aSolidId);
    auto bSolid = b.solid(bSolidId);
    if (aSolid is null || bSolid is null || aSolid.persistentId != bSolid.persistentId ||
        aSolid.vertexCount != bSolid.vertexCount || aSolid.edgeCount != bSolid.edgeCount ||
        aSolid.faceCount != bSolid.faceCount)
        return false;

    foreach (i; 0 .. aSolid.vertexCount)
        if (a.vertex(aSolid.firstVertex + cast(BRepId)i).persistentId !=
            b.vertex(bSolid.firstVertex + cast(BRepId)i).persistentId)
            return false;
    foreach (i; 0 .. aSolid.edgeCount)
        if (a.edge(aSolid.firstEdge + cast(BRepId)i).persistentId !=
            b.edge(bSolid.firstEdge + cast(BRepId)i).persistentId)
            return false;
    foreach (i; 0 .. aSolid.faceCount)
        if (a.face(aSolid.firstFace + cast(BRepId)i).persistentId !=
            b.face(bSolid.firstFace + cast(BRepId)i).persistentId)
            return false;
    return true;
}

extern(C) int main()
{
    BRepArena first;
    first.clear();
    auto firstBox = makeBox(&first, 80.0, 50.0, 10.0);
    if (firstBox == 0 || !assignPrimitivePersistentTopology(&first, firstBox, 42u))
        return 10;

    auto bodyName = first.solid(firstBox).persistentId;
    if (bodyName != makePersistentTopologyId(42u, BRepTopologyKind.solidBody, 0u) ||
        persistentTopologyOwner(bodyName) != 42u || persistentTopologyKind(bodyName) != BRepTopologyKind.solidBody)
        return 11;
    uint slot = 99u;
    if (!persistentTopologySlot(bodyName, &slot) || slot != 0u || solidByPersistentId(&first, bodyName) is null)
        return 12;

    /* Shift every raw arena ID in the second arena, then change box dimensions.
       The semantic persistent names must still be identical. */
    BRepArena second;
    second.clear();
    auto prefix = makeSphere(&second, 2.0);
    if (prefix == 0 || !assignPrimitivePersistentTopology(&second, prefix, 99u))
        return 20;
    auto secondBox = makeBox(&second, 120.0, 35.0, 17.0);
    if (secondBox == 0 || secondBox == firstBox || !assignPrimitivePersistentTopology(&second, secondBox, 42u))
        return 21;
    if (!sameBoxNames(&first, firstBox, &second, secondBox))
    {
        fprintf(stderr, "Persistent box topology changed after arena relocation/dimension edit.\n");
        return 22;
    }

    auto firstSolid = first.solid(firstBox);
    auto vertexName = first.vertex(firstSolid.firstVertex).persistentId;
    auto edgeName = first.edge(firstSolid.firstEdge).persistentId;
    auto faceName = first.face(firstSolid.firstFace).persistentId;
    if (vertexByPersistentId(&first, vertexName) is null || edgeByPersistentId(&first, edgeName) is null ||
        faceByPersistentId(&first, faceName) is null)
        return 23;

    /* A topology-preserving raw Euler split keeps the original edge identity.
       New split topology is intentionally unnamed until a semantic feature or
       boolean-imprint operation supplies a lineage token. */
    auto split = splitLineEdge(&first, firstSolid.firstEdge, 0.5);
    if (!split.valid || first.edge(split.firstEdge).persistentId != edgeName ||
        first.edge(split.secondEdge).persistentId != 0 || first.vertex(split.vertex).persistentId != 0)
        return 24;

    /* Cone/frustum topology changes may add/remove caps. Stable side/seam names
       remain tied to semantic slots rather than face/edge arena positions. */
    BRepArena frustumArena;
    frustumArena.clear();
    auto frustum = makeConeFrustum(&frustumArena, 4.0, 2.0, 9.0);
    if (frustum == 0 || !assignPrimitivePersistentTopology(&frustumArena, frustum, 77u))
        return 30;
    auto seamName = makePersistentTopologyId(77u, BRepTopologyKind.edge, 2u);
    auto sideName = makePersistentTopologyId(77u, BRepTopologyKind.face, 2u);
    if (edgeByPersistentId(&frustumArena, seamName) is null || faceByPersistentId(&frustumArena, sideName) is null)
        return 31;

    BRepArena coneArena;
    coneArena.clear();
    auto cone = makeConeFrustum(&coneArena, 4.0, 0.0, 9.0);
    if (cone == 0 || !assignPrimitivePersistentTopology(&coneArena, cone, 77u) ||
        edgeByPersistentId(&coneArena, seamName) is null || faceByPersistentId(&coneArena, sideName) is null)
        return 32;

    return 0;
}

