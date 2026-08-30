module waifucad.brep.euler;

import waifucad.brep.builder : addCoedge, addLineEdge, addVertex, addPlaneFace, addLoop;
import waifucad.brep.geometry : evaluateEdge, dot, subtract, cross, length;
import waifucad.brep.naming : derivePersistentTopologyId;
import waifucad.brep.types;

struct BRepEdgeSplitResult
{
    BRepId vertex;
    BRepId firstEdge;
    BRepId secondEdge;
    bool valid;
}

private void insertAfter(BRepArena* arena, BRepId existingId, BRepId insertedId) nothrow @nogc
{
    auto existing = arena.coedge(existingId);
    auto inserted = arena.coedge(insertedId);
    auto following = existing is null ? null : arena.coedge(existing.next);
    if (existing is null || inserted is null || following is null)
        return;
    inserted.previous = existing.id;
    inserted.next = following.id;
    existing.next = inserted.id;
    following.previous = inserted.id;
    auto loop = arena.loop(existing.loop);
    if (loop !is null)
        ++loop.coedgeCount;
}

/*
 * Split a manifold line edge without changing the represented shape.
 *
 * E(A,B) becomes E(A,V) + E2(V,B). The forward coedge receives E2 after E;
 * the reversed coedge receives reversed E2 before reversed E. This is a
 * topology-preserving Euler-style mutation and is an important precursor to
 * intersection imprinting for booleans.
 */
BRepEdgeSplitResult splitLineEdge(BRepArena* arena, BRepId edgeId, double parameter) nothrow @nogc
{
    BRepEdgeSplitResult result;
    if (arena is null || parameter <= 0.0 || parameter >= 1.0 ||
        arena.vertexCount >= arena.vertices.length || arena.edgeCount >= arena.edges.length ||
        arena.coedgeCount + 2 > arena.coedges.length)
        return result;

    auto edge = arena.edge(edgeId);
    if (edge is null || edge.curveKind != BRepCurveKind.line || edge.startVertex == edge.endVertex ||
        edge.firstCoedge == 0 || edge.secondCoedge == 0)
        return result;
    auto first = arena.coedge(edge.firstCoedge);
    auto second = arena.coedge(edge.secondCoedge);
    if (first is null || second is null || first.reversed == second.reversed ||
        arena.loop(first.loop) is null || arena.loop(second.loop) is null)
        return result;

    auto forward = first.reversed ? second : first;
    auto reverse = first.reversed ? first : second;
    if (arena.coedge(forward.next) is null || arena.coedge(reverse.previous) is null)
        return result;

    BRepSolid* owner = null;
    foreach (i; 0 .. arena.solidCount)
    {
        auto candidate = &arena.solids[i];
        if (edgeId >= candidate.firstEdge && edgeId < candidate.firstEdge + candidate.edgeCount)
        {
            owner = candidate;
            break;
        }
    }
    if (owner is null ||
        owner.firstVertex + owner.vertexCount != cast(BRepId)(arena.vertexCount + 1) ||
        owner.firstEdge + owner.edgeCount != cast(BRepId)(arena.edgeCount + 1))
        return result;

    bool pointOk = false;
    auto point = evaluateEdge(arena, edgeId, parameter, &pointOk);
    if (!pointOk)
        return result;

    auto oldEnd = edge.endVertex;
    auto vertexId = addVertex(arena, point);
    if (vertexId == 0)
        return result;

    /* No fallible allocation remains after the capacity and topology checks
       above; the fixed-capacity arena keeps this mutation deterministic. */
    edge.endVertex = vertexId;
    auto secondEdgeId = addLineEdge(arena, vertexId, oldEnd);
    auto forwardSecond = addCoedge(arena, forward.loop, secondEdgeId, false);
    auto reverseSecond = addCoedge(arena, reverse.loop, secondEdgeId, true);
    if (secondEdgeId == 0 || forwardSecond == 0 || reverseSecond == 0)
    {
        /* This should be unreachable after the preflight checks. Mark failure;
           callers should discard/rebuild the arena if an invariant was broken. */
        return result;
    }

    insertAfter(arena, forward.id, forwardSecond);
    insertAfter(arena, reverse.previous, reverseSecond);

    ++owner.vertexCount;
    ++owner.edgeCount;

    if (edge.persistentId != 0)
    {
        auto parent=edge.persistentId;
        auto vertex=arena.vertex(vertexId); auto secondEdge=arena.edge(secondEdgeId);
        vertex.persistentId=derivePersistentTopologyId(parent,BRepTopologyKind.vertex,1u);
        secondEdge.persistentId=derivePersistentTopologyId(parent,BRepTopologyKind.edge,2u);
        if(vertex.persistentId!=0) arena.addLineage(vertex.persistentId,parent,0,BRepLineageKind.split);
        if(secondEdge.persistentId!=0) arena.addLineage(secondEdge.persistentId,parent,0,BRepLineageKind.split);
    }

    result.vertex = vertexId;
    result.firstEdge = edgeId;
    result.secondEdge = secondEdgeId;
    result.valid = true;
    return result;
}




struct BRepFaceSplitResult
{
    BRepId originalFace;
    BRepId newFace;
    BRepId splitEdge;
    bool valid;
}

private bool coedgeEndpoints(BRepArena* arena, BRepId coedgeId, BRepId* start, BRepId* end) nothrow @nogc
{
    auto coedge=arena.coedge(coedgeId); if(coedge is null||start is null||end is null)return false;
    auto edge=arena.edge(coedge.edge); if(edge is null)return false;
    *start=coedge.reversed?edge.endVertex:edge.startVertex;
    *end=coedge.reversed?edge.startVertex:edge.endVertex;
    return true;
}

/* Split one planar, single-loop face by a chord between two existing boundary
 * vertices. The operation is topologically exact and is the Euler-style face
 * split needed by imprinting. It intentionally does not guess intersection
 * points: callers first create/split boundary vertices from intersection data. */
BRepFaceSplitResult splitPlaneFaceByChord(BRepArena* arena, BRepId faceId,
                                          BRepId firstVertex, BRepId secondVertex) nothrow @nogc
{
    BRepFaceSplitResult result;
    if(arena is null||firstVertex==secondVertex||arena.faceCount>=arena.faces.length||
       arena.loopCount>=arena.loops.length||arena.edgeCount>=arena.edges.length||
       arena.coedgeCount+2>arena.coedges.length)return result;
    auto face=arena.face(faceId); if(face is null||face.surfaceKind!=BRepSurfaceKind.plane||face.outerLoop==0)return result;
    auto loop=arena.loop(face.outerLoop); if(loop is null||loop.coedgeCount<4||loop.firstCoedge==0)return result;
    auto shell=arena.shell(face.shell); if(shell is null)return result;
    auto solid=arena.solid(shell.solid); if(solid is null||
       solid.firstFace+solid.faceCount!=cast(BRepId)(arena.faceCount+1)||
       solid.firstEdge+solid.edgeCount!=cast(BRepId)(arena.edgeCount+1))return result;

    BRepId pathStart=0,pathEnd=0; uint pathCount=0;
    auto candidate=loop.firstCoedge;
    foreach(scan;0..loop.coedgeCount)
    {
        BRepId a=0,b=0; if(!coedgeEndpoints(arena,candidate,&a,&b))return result;
        if(a==firstVertex){pathStart=candidate; break;} candidate=arena.coedge(candidate).next;
    }
    if(pathStart==0)return result;
    candidate=pathStart;
    foreach(scan;0..loop.coedgeCount)
    {
        BRepId a=0,b=0; if(!coedgeEndpoints(arena,candidate,&a,&b))return result;
        ++pathCount;
        if(b==secondVertex){pathEnd=candidate; break;}
        candidate=arena.coedge(candidate).next;
    }
    if(pathEnd==0||pathCount==0||pathCount>=loop.coedgeCount)return result;
    auto secondStart=arena.coedge(pathEnd).next;
    auto secondEnd=arena.coedge(pathStart).previous;
    if(secondStart==0||secondEnd==0)return result;

    auto newFaceId=addPlaneFace(arena,face.shell,face.origin,face.normal,face.referenceDirection);
    auto newLoopId=addLoop(arena,newFaceId);
    auto chordId=addLineEdge(arena,firstVertex,secondVertex);
    if(newFaceId==0||newLoopId==0||chordId==0)return result;
    auto reverseChord=addCoedge(arena,loop.id,chordId,true);
    auto forwardChord=addCoedge(arena,newLoopId,chordId,false);
    if(reverseChord==0||forwardChord==0)return result;

    auto first=arena.coedge(pathStart); auto last=arena.coedge(pathEnd); auto reverse=arena.coedge(reverseChord);
    first.previous=reverseChord; last.next=reverseChord; reverse.previous=pathEnd; reverse.next=pathStart;
    loop.firstCoedge=pathStart; loop.coedgeCount=pathCount+1u;

    uint secondCount=0; candidate=secondStart;
    for(;;)
    {
        auto c=arena.coedge(candidate); if(c is null)return result; c.loop=newLoopId; ++secondCount;
        if(candidate==secondEnd)break; candidate=c.next; if(secondCount>64u)return result;
    }
    auto secondFirst=arena.coedge(secondStart); auto secondLast=arena.coedge(secondEnd); auto forward=arena.coedge(forwardChord);
    secondFirst.previous=forwardChord; secondLast.next=forwardChord; forward.previous=secondEnd; forward.next=secondStart;
    auto newLoop=arena.loop(newLoopId); newLoop.firstCoedge=secondStart; newLoop.coedgeCount=secondCount+1u;
    auto newFace=arena.face(newFaceId); newFace.outerLoop=newLoopId; newFace.reversed=face.reversed;
    ++shell.faceCount; ++solid.faceCount; ++solid.edgeCount;

    if(face.persistentId!=0)
    {
        newFace.persistentId=derivePersistentTopologyId(face.persistentId,BRepTopologyKind.face,1u);
        auto chord=arena.edge(chordId); chord.persistentId=derivePersistentTopologyId(face.persistentId,BRepTopologyKind.edge,2u);
        if(newFace.persistentId!=0) arena.addLineage(newFace.persistentId,face.persistentId,0,BRepLineageKind.split);
        if(chord.persistentId!=0) arena.addLineage(chord.persistentId,face.persistentId,0,BRepLineageKind.split);
    }
    result.originalFace=faceId; result.newFace=newFaceId; result.splitEdge=chordId; result.valid=true; return result;
}

/* Exact inverse for a split created by splitPlaneFaceByChord when no later
 * topology was allocated. This constrained merge keeps arena IDs stable for
 * every earlier entity instead of compacting arbitrary arrays. */
bool mergeLastSplitPlaneFaces(BRepArena* arena, const BRepFaceSplitResult* split) nothrow @nogc
{
    if(arena is null||split is null||!split.valid||split.newFace!=arena.faceCount||split.splitEdge!=arena.edgeCount||arena.coedgeCount<2)return false;
    auto face=arena.face(split.originalFace); auto newFace=arena.face(split.newFace); auto edge=arena.edge(split.splitEdge);
    if(face is null||newFace is null||edge is null||face.shell!=newFace.shell||edge.firstCoedge==0||edge.secondCoedge==0)return false;
    auto c0=arena.coedge(edge.firstCoedge); auto c1=arena.coedge(edge.secondCoedge); if(c0 is null||c1 is null)return false;
    if((c0.id!=arena.coedgeCount&&c1.id!=arena.coedgeCount)||(c0.id!=arena.coedgeCount-1&&c1.id!=arena.coedgeCount-1))return false;
    auto oldLoop=arena.loop(face.outerLoop); auto newLoop=arena.loop(newFace.outerLoop); if(oldLoop is null||newLoop is null||newLoop.id!=arena.loopCount)return false;
    auto oldBefore=arena.coedge(c0.loop==oldLoop.id?c0.previous:c1.previous);
    auto oldAfter=arena.coedge(c0.loop==oldLoop.id?c0.next:c1.next);
    auto newBefore=arena.coedge(c0.loop==newLoop.id?c0.previous:c1.previous);
    auto newAfter=arena.coedge(c0.loop==newLoop.id?c0.next:c1.next);
    if(oldBefore is null||oldAfter is null||newBefore is null||newAfter is null)return false;
    oldBefore.next=newAfter.id; newAfter.previous=oldBefore.id; newBefore.next=oldAfter.id; oldAfter.previous=newBefore.id;
    auto candidate=newAfter.id; uint moved=0;
    while(candidate!=oldAfter.id){auto c=arena.coedge(candidate); if(c is null)return false; c.loop=oldLoop.id; ++moved; candidate=c.next; if(moved>64u)return false;}
    oldLoop.coedgeCount=oldLoop.coedgeCount+newLoop.coedgeCount-2u;
    auto shell=arena.shell(face.shell); auto solid=shell is null?null:arena.solid(shell.solid); if(shell is null||solid is null)return false;
    if(face.persistentId!=0&&newFace.persistentId!=0) arena.addLineage(face.persistentId,face.persistentId,newFace.persistentId,BRepLineageKind.merge);
    --arena.coedgeCount; --arena.coedgeCount; --arena.edgeCount; --arena.loopCount; --arena.faceCount;
    --shell.faceCount; --solid.faceCount; --solid.edgeCount;
    return true;
}

