module waifucad.brep.validate;

import core.stdc.math : fabs;
import waifucad.brep.geometry : WC_BREP_EPSILON, coedgeEndVertex, coedgeStartVertex, dot, length;
import waifucad.brep.types;

enum BRepValidation : int
{
    ok = 0,
    badArena = 1,
    badSolid = 2,
    badShell = 3,
    badRange = 4,
    openEdge = 5,
    badFace = 6,
    badLoop = 7,
    brokenRing = 8,
    eulerMismatch = 9,
    badEdge = 10,
    badOrientation = 11,
    disconnectedLoop = 12,
    badCurve = 13,
    badSurface = 14,
    badBounds = 15
}

private bool validCurve(BRepArena* arena, BRepEdge* edge) nothrow @nogc
{
    if (arena is null || edge is null || arena.vertex(edge.startVertex) is null || arena.vertex(edge.endVertex) is null)
        return false;
    final switch (edge.curveKind)
    {
        case BRepCurveKind.line:
            return edge.startVertex != edge.endVertex;
        case BRepCurveKind.circle:
            return edge.radius > 0.0 && edge.parameterEnd > edge.parameterStart &&
                   length(edge.axis) > WC_BREP_EPSILON && length(edge.referenceDirection) > WC_BREP_EPSILON &&
                   fabs(dot(edge.axis, edge.referenceDirection)) <= 1.0e-7;
        case BRepCurveKind.ellipse:
            return false;
        case BRepCurveKind.bspline:
            return edge.geometryId != 0 && arena.nurbsCurve(edge.geometryId) !is null && edge.parameterEnd > edge.parameterStart;
        case BRepCurveKind.none:
            return false;
    }
}

private bool validSurface(BRepArena* arena, BRepFace* face) nothrow @nogc
{
    if (face is null)
        return false;
    final switch (face.surfaceKind)
    {
        case BRepSurfaceKind.plane:
            return length(face.normal) > WC_BREP_EPSILON && length(face.referenceDirection) > WC_BREP_EPSILON &&
                   fabs(dot(face.normal, face.referenceDirection)) <= 1.0e-7;
        case BRepSurfaceKind.cylinder:
            return face.radius > 0.0 && length(face.axis) > WC_BREP_EPSILON &&
                   length(face.referenceDirection) > WC_BREP_EPSILON &&
                   fabs(dot(face.axis, face.referenceDirection)) <= 1.0e-7;
        case BRepSurfaceKind.cone:
            return face.radius >= 0.0 && face.secondaryRadius >= 0.0 &&
                   (face.radius > 0.0 || face.secondaryRadius > 0.0) && face.axialLength > 0.0 &&
                   length(face.axis) > WC_BREP_EPSILON && length(face.referenceDirection) > WC_BREP_EPSILON &&
                   fabs(dot(face.axis, face.referenceDirection)) <= 1.0e-7;
        case BRepSurfaceKind.sphere:
            return face.radius > 0.0 && length(face.axis) > WC_BREP_EPSILON &&
                   length(face.referenceDirection) > WC_BREP_EPSILON &&
                   fabs(dot(face.axis, face.referenceDirection)) <= 1.0e-7;
        case BRepSurfaceKind.torus:
            return face.radius > face.secondaryRadius && face.secondaryRadius > 0.0 &&
                   length(face.axis) > WC_BREP_EPSILON && length(face.referenceDirection) > WC_BREP_EPSILON &&
                   fabs(dot(face.axis, face.referenceDirection)) <= 1.0e-7;
        case BRepSurfaceKind.bspline:
            return arena !is null && face.geometryId != 0 && arena.nurbsSurface(face.geometryId) !is null;
        case BRepSurfaceKind.none:
            return false;
    }
}

int validateClosedSolid(BRepArena* arena, BRepId solidId) nothrow @nogc
{
    if (arena is null)
        return BRepValidation.badArena;
    auto solid = arena.solid(solidId);
    if (solid is null)
        return BRepValidation.badSolid;
    auto shell = arena.shell(solid.shell);
    if (shell is null || solid.firstShell == 0 || solid.shellCount == 0)
        return BRepValidation.badShell;
    uint shellFaceTotal = 0;
    foreach (shellOffset; 0 .. solid.shellCount)
    {
        auto member = arena.shell(solid.firstShell + cast(BRepId)shellOffset);
        if (member is null || !member.closed || member.solid != solid.id) return BRepValidation.badShell;
        shellFaceTotal += member.faceCount;
    }
    if (solid.vertexCount == 0 || solid.edgeCount == 0 || solid.faceCount == 0 || shellFaceTotal != solid.faceCount)
        return BRepValidation.badRange;
    if (!solid.bounds.valid || solid.bounds.maximum.x < solid.bounds.minimum.x ||
        solid.bounds.maximum.y < solid.bounds.minimum.y || solid.bounds.maximum.z < solid.bounds.minimum.z)
        return BRepValidation.badBounds;

    auto lastVertex = solid.firstVertex + solid.vertexCount - 1;
    auto lastEdge = solid.firstEdge + solid.edgeCount - 1;
    auto lastFace = solid.firstFace + solid.faceCount - 1;
    if (lastVertex > arena.vertexCount || lastEdge > arena.edgeCount || lastFace > arena.faceCount)
        return BRepValidation.badRange;

    foreach (edgeId; solid.firstEdge .. lastEdge + 1)
    {
        auto edge = arena.edge(edgeId);
        if (edge is null || edge.startVertex < solid.firstVertex || edge.startVertex > lastVertex ||
            edge.endVertex < solid.firstVertex || edge.endVertex > lastVertex)
            return BRepValidation.badEdge;
        if (!validCurve(arena, edge))
            return BRepValidation.badCurve;
        if (edge.firstCoedge == 0 || edge.secondCoedge == 0)
            return BRepValidation.openEdge;
        auto first = arena.coedge(edge.firstCoedge);
        auto second = arena.coedge(edge.secondCoedge);
        if (first is null || second is null || first.edge != edge.id || second.edge != edge.id)
            return BRepValidation.openEdge;
        /* A closed orientable manifold uses each edge exactly twice with
           opposite topological orientation. This also handles periodic seam
           edges whose two coedges belong to the same cylindrical face. */
        if (first.reversed == second.reversed)
            return BRepValidation.badOrientation;
    }

    foreach (faceId; solid.firstFace .. lastFace + 1)
    {
        auto face = arena.face(faceId);
        if (face is null || face.outerLoop == 0 || face.firstLoop == 0 || face.loopCount == 0) return BRepValidation.badFace;
        auto ownerShell=arena.shell(face.shell);
        if(ownerShell is null || ownerShell.solid!=solid.id || face.shell<solid.firstShell || face.shell>=solid.firstShell+solid.shellCount)
            return BRepValidation.badFace;
        if (!validSurface(arena, face))
            return BRepValidation.badSurface;
        foreach(loopOffset;0..face.loopCount)
        {
            auto loop = arena.loop(face.firstLoop+cast(BRepId)loopOffset);
            if (loop is null || loop.face != face.id || loop.coedgeCount == 0 || loop.firstCoedge == 0)
                return BRepValidation.badLoop;

            auto current = loop.firstCoedge;
            foreach (_; 0 .. loop.coedgeCount)
            {
                auto coedge = arena.coedge(current);
                if (coedge is null || coedge.loop != loop.id || coedge.next == 0 || coedge.previous == 0)
                    return BRepValidation.brokenRing;
                auto next = arena.coedge(coedge.next);
                auto previous = arena.coedge(coedge.previous);
                if (next is null || previous is null || next.previous != coedge.id || previous.next != coedge.id)
                    return BRepValidation.brokenRing;
                if (coedgeEndVertex(arena, coedge.id) != coedgeStartVertex(arena, next.id))
                    return BRepValidation.disconnectedLoop;
                current = coedge.next;
            }
            if (current != loop.firstCoedge)
                return BRepValidation.brokenRing;
        }
    }

    long innerLoopCount=0;
    foreach(faceId; solid.firstFace .. lastFace + 1)
    {
        auto face=arena.face(faceId);
        if(face !is null && face.loopCount>1) innerLoopCount += cast(long)(face.loopCount-1);
    }
    auto euler = cast(long)solid.vertexCount - cast(long)solid.edgeCount + cast(long)solid.faceCount - innerLoopCount;
    long expectedEuler = 2L * cast(long)solid.shellCount - 2L * cast(long)solid.genus;
    if (euler != expectedEuler)
        return BRepValidation.eulerMismatch;
    return BRepValidation.ok;
}



