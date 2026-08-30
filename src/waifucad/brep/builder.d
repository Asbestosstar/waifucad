module waifucad.brep.builder;

import waifucad.brep.types;

struct BRepArenaMark
{
    size_t vertices;
    size_t edges;
    size_t coedges;
    size_t loops;
    size_t faces;
    size_t shells;
    size_t solids;
    size_t nurbsCurves;
    size_t nurbsSurfaces;
    size_t lineage;
}

BRepArenaMark markArena(const BRepArena* arena) nothrow @nogc
{
    BRepArenaMark mark;
    if (arena is null)
        return mark;
    mark.vertices = arena.vertexCount;
    mark.edges = arena.edgeCount;
    mark.coedges = arena.coedgeCount;
    mark.loops = arena.loopCount;
    mark.faces = arena.faceCount;
    mark.shells = arena.shellCount;
    mark.solids = arena.solidCount;
    mark.nurbsCurves = arena.nurbsCurveCount;
    mark.nurbsSurfaces = arena.nurbsSurfaceCount;
    mark.lineage = arena.lineageCount;
    return mark;
}

void rollbackArena(BRepArena* arena, BRepArenaMark mark) nothrow @nogc
{
    if (arena is null)
        return;
    arena.vertexCount = mark.vertices;
    arena.edgeCount = mark.edges;
    arena.coedgeCount = mark.coedges;
    arena.loopCount = mark.loops;
    arena.faceCount = mark.faces;
    arena.shellCount = mark.shells;
    arena.solidCount = mark.solids;
    arena.nurbsCurveCount = mark.nurbsCurves;
    arena.nurbsSurfaceCount = mark.nurbsSurfaces;
    arena.lineageCount = mark.lineage;
}

BRepId addSolid(BRepArena* arena, BRepPrimitiveKind primitiveKind) nothrow @nogc
{
    if (arena is null || arena.solidCount >= arena.solids.length)
        return 0;
    auto slot = &arena.solids[arena.solidCount++];
    slot.id = cast(BRepId)arena.solidCount;
    slot.persistentId = 0;
    slot.shell = 0;
    slot.firstShell = 0;
    slot.shellCount = 0;
    slot.firstVertex = 0;
    slot.vertexCount = 0;
    slot.firstEdge = 0;
    slot.edgeCount = 0;
    slot.firstFace = 0;
    slot.faceCount = 0;
    slot.genus = 0;
    slot.bounds.valid = false;
    slot.primitiveKind = primitiveKind;
    slot.primitiveA = 0.0;
    slot.primitiveB = 0.0;
    slot.primitiveC = 0.0;
    slot.primitiveD = 0.0;
    return slot.id;
}

BRepId addShell(BRepArena* arena, BRepId solidId) nothrow @nogc
{
    if (arena is null || arena.shellCount >= arena.shells.length || arena.solid(solidId) is null)
        return 0;
    auto slot = &arena.shells[arena.shellCount++];
    slot.id = cast(BRepId)arena.shellCount;
    slot.solid = solidId;
    slot.firstFace = 0;
    slot.faceCount = 0;
    slot.closed = false;
    auto solid = arena.solid(solidId);
    if (solid.shell == 0) solid.shell = slot.id;
    if (solid.firstShell == 0) solid.firstShell = slot.id;
    ++solid.shellCount;
    return slot.id;
}

BRepId addVertex(BRepArena* arena, BRepVec3 point, double tolerance = 1.0e-9) nothrow @nogc
{
    if (arena is null || arena.vertexCount >= arena.vertices.length || tolerance < 0.0)
        return 0;
    auto slot = &arena.vertices[arena.vertexCount++];
    slot.id = cast(BRepId)arena.vertexCount;
    slot.persistentId = 0;
    slot.point = point;
    slot.tolerance = tolerance;
    return slot.id;
}

BRepId findLineEdge(BRepArena* arena, BRepId a, BRepId b) nothrow @nogc
{
    if (arena is null || a == 0 || b == 0)
        return 0;
    foreach (i; 0 .. arena.edgeCount)
    {
        auto edge = &arena.edges[i];
        if (edge.curveKind != BRepCurveKind.line)
            continue;
        if ((edge.startVertex == a && edge.endVertex == b) ||
            (edge.startVertex == b && edge.endVertex == a))
            return edge.id;
    }
    return 0;
}

BRepId addLineEdge(BRepArena* arena, BRepId a, BRepId b) nothrow @nogc
{
    if (arena is null || arena.edgeCount >= arena.edges.length || a == 0 || b == 0 || a == b ||
        arena.vertex(a) is null || arena.vertex(b) is null)
        return 0;
    auto slot = &arena.edges[arena.edgeCount++];
    slot.id = cast(BRepId)arena.edgeCount;
    slot.persistentId = 0;
    slot.startVertex = a;
    slot.endVertex = b;
    slot.curveKind = BRepCurveKind.line;
    slot.firstCoedge = 0;
    slot.secondCoedge = 0;
    slot.origin = arena.vertex(a).point;
    slot.axis = BRepVec3(0.0, 0.0, 0.0);
    slot.referenceDirection = BRepVec3(0.0, 0.0, 0.0);
    slot.radius = 0.0;
    slot.secondaryRadius = 0.0;
    slot.parameterStart = 0.0;
    slot.parameterEnd = 1.0;
    slot.geometryId = 0;
    return slot.id;
}

BRepId addCircleEdge(BRepArena* arena,
                     BRepId vertexId,
                     BRepVec3 centre,
                     BRepVec3 axis,
                     BRepVec3 referenceDirection,
                     double radius,
                     double parameterStart,
                     double parameterEnd) nothrow @nogc
{
    if (arena is null || arena.edgeCount >= arena.edges.length || vertexId == 0 ||
        arena.vertex(vertexId) is null || radius <= 0.0 || parameterEnd <= parameterStart)
        return 0;
    auto slot = &arena.edges[arena.edgeCount++];
    slot.id = cast(BRepId)arena.edgeCount;
    slot.persistentId = 0;
    /* A full periodic circle is represented by a topological edge whose start
       and end are the same vertex. This is valid B-rep topology. */
    slot.startVertex = vertexId;
    slot.endVertex = vertexId;
    slot.curveKind = BRepCurveKind.circle;
    slot.firstCoedge = 0;
    slot.secondCoedge = 0;
    slot.origin = centre;
    slot.axis = axis;
    slot.referenceDirection = referenceDirection;
    slot.radius = radius;
    slot.secondaryRadius = radius;
    slot.parameterStart = parameterStart;
    slot.parameterEnd = parameterEnd;
    slot.geometryId = 0;
    return slot.id;
}

BRepId addCircleArcEdge(BRepArena* arena,
                        BRepId startVertex,
                        BRepId endVertex,
                        BRepVec3 centre,
                        BRepVec3 axis,
                        BRepVec3 referenceDirection,
                        double radius,
                        double parameterStart,
                        double parameterEnd) nothrow @nogc
{
    if (arena is null || arena.edgeCount >= arena.edges.length || startVertex == 0 || endVertex == 0 ||
        arena.vertex(startVertex) is null || arena.vertex(endVertex) is null ||
        radius <= 0.0 || parameterEnd <= parameterStart)
        return 0;
    auto slot = &arena.edges[arena.edgeCount++];
    slot.id = cast(BRepId)arena.edgeCount;
    slot.persistentId = 0;
    slot.startVertex = startVertex;
    slot.endVertex = endVertex;
    slot.curveKind = BRepCurveKind.circle;
    slot.firstCoedge = 0;
    slot.secondCoedge = 0;
    slot.origin = centre;
    slot.axis = axis;
    slot.referenceDirection = referenceDirection;
    slot.radius = radius;
    slot.secondaryRadius = radius;
    slot.parameterStart = parameterStart;
    slot.parameterEnd = parameterEnd;
    slot.geometryId = 0;
    return slot.id;
}

BRepId addPlaneFace(BRepArena* arena,
                    BRepId shellId,
                    BRepVec3 origin,
                    BRepVec3 normal,
                    BRepVec3 referenceDirection) nothrow @nogc
{
    if (arena is null || arena.faceCount >= arena.faces.length || arena.shell(shellId) is null)
        return 0;
    auto slot = &arena.faces[arena.faceCount++];
    slot.id = cast(BRepId)arena.faceCount;
    slot.persistentId = 0;
    slot.shell = shellId;
    slot.outerLoop = 0;
    slot.firstLoop = 0;
    slot.loopCount = 0;
    slot.surfaceKind = BRepSurfaceKind.plane;
    slot.origin = origin;
    slot.normal = normal;
    slot.axis = normal;
    slot.referenceDirection = referenceDirection;
    slot.radius = 0.0;
    slot.secondaryRadius = 0.0;
    slot.axialLength = 0.0;
    slot.reversed = false;
    slot.geometryId = 0;
    return slot.id;
}

BRepId addCylinderFace(BRepArena* arena,
                       BRepId shellId,
                       BRepVec3 origin,
                       BRepVec3 axis,
                       BRepVec3 referenceDirection,
                       double radius) nothrow @nogc
{
    if (arena is null || arena.faceCount >= arena.faces.length || arena.shell(shellId) is null || radius <= 0.0)
        return 0;
    auto slot = &arena.faces[arena.faceCount++];
    slot.id = cast(BRepId)arena.faceCount;
    slot.persistentId = 0;
    slot.shell = shellId;
    slot.outerLoop = 0;
    slot.firstLoop = 0;
    slot.loopCount = 0;
    slot.surfaceKind = BRepSurfaceKind.cylinder;
    slot.origin = origin;
    slot.normal = BRepVec3(0.0, 0.0, 0.0);
    slot.axis = axis;
    slot.referenceDirection = referenceDirection;
    slot.radius = radius;
    slot.secondaryRadius = radius;
    slot.axialLength = 0.0;
    slot.reversed = false;
    slot.geometryId = 0;
    return slot.id;
}

BRepId addConeFace(BRepArena* arena,
                   BRepId shellId,
                   BRepVec3 origin,
                   BRepVec3 axis,
                   BRepVec3 referenceDirection,
                   double radius1,
                   double radius2,
                   double height) nothrow @nogc
{
    if (arena is null || arena.faceCount >= arena.faces.length || arena.shell(shellId) is null ||
        radius1 < 0.0 || radius2 < 0.0 || (radius1 == 0.0 && radius2 == 0.0) || height <= 0.0)
        return 0;
    auto slot = &arena.faces[arena.faceCount++];
    slot.id = cast(BRepId)arena.faceCount;
    slot.persistentId = 0;
    slot.shell = shellId;
    slot.outerLoop = 0;
    slot.firstLoop = 0;
    slot.loopCount = 0;
    slot.surfaceKind = BRepSurfaceKind.cone;
    slot.origin = origin;
    slot.normal = BRepVec3(0.0, 0.0, 0.0);
    slot.axis = axis;
    slot.referenceDirection = referenceDirection;
    slot.radius = radius1;
    slot.secondaryRadius = radius2;
    slot.axialLength = height;
    slot.reversed = false;
    slot.geometryId = 0;
    return slot.id;
}

BRepId addSphereFace(BRepArena* arena,
                     BRepId shellId,
                     BRepVec3 centre,
                     BRepVec3 axis,
                     BRepVec3 referenceDirection,
                     double radius) nothrow @nogc
{
    if (arena is null || arena.faceCount >= arena.faces.length || arena.shell(shellId) is null || radius <= 0.0)
        return 0;
    auto slot = &arena.faces[arena.faceCount++];
    slot.id = cast(BRepId)arena.faceCount;
    slot.persistentId = 0;
    slot.shell = shellId;
    slot.outerLoop = 0;
    slot.firstLoop = 0;
    slot.loopCount = 0;
    slot.surfaceKind = BRepSurfaceKind.sphere;
    slot.origin = centre;
    slot.normal = BRepVec3(0.0, 0.0, 0.0);
    slot.axis = axis;
    slot.referenceDirection = referenceDirection;
    slot.radius = radius;
    slot.secondaryRadius = radius;
    slot.axialLength = 0.0;
    slot.reversed = false;
    slot.geometryId = 0;
    return slot.id;
}

BRepId addTorusFace(BRepArena* arena, BRepId shellId, BRepVec3 centre, BRepVec3 axis,
                    BRepVec3 referenceDirection, double majorRadius, double minorRadius) nothrow @nogc
{
    if (arena is null || arena.faceCount >= arena.faces.length || arena.shell(shellId) is null ||
        majorRadius <= minorRadius || minorRadius <= 0.0) return 0;
    auto slot=&arena.faces[arena.faceCount++];
    slot.id=cast(BRepId)arena.faceCount; slot.persistentId=0; slot.shell=shellId; slot.outerLoop=0; slot.firstLoop=0; slot.loopCount=0;
    slot.surfaceKind=BRepSurfaceKind.torus; slot.origin=centre; slot.normal=BRepVec3(0,0,0);
    slot.axis=axis; slot.referenceDirection=referenceDirection; slot.radius=majorRadius;
    slot.secondaryRadius=minorRadius; slot.axialLength=0.0; slot.reversed=false; slot.geometryId=0;
    return slot.id;
}

BRepId addNurbsCurve(BRepArena* arena, ubyte degree, const(BRepVec3)* controlPoints, const(double)* weights,
                     ubyte controlPointCount, const(double)* knots, ubyte knotCount) nothrow @nogc
{
    if (arena is null || controlPoints is null || knots is null || degree < 1 ||
        controlPointCount < degree + 1 || controlPointCount > WC_BREP_MAX_NURBS_CURVE_POINTS ||
        knotCount != controlPointCount + degree + 1 || knotCount > WC_BREP_MAX_NURBS_CURVE_KNOTS ||
        arena.nurbsCurveCount >= arena.nurbsCurves.length) return 0;
    foreach(i;1..knotCount) if(knots[i] < knots[i-1]) return 0;
    if(weights !is null) foreach(i;0..controlPointCount) if(weights[i] <= 0.0) return 0;
    auto slot=&arena.nurbsCurves[arena.nurbsCurveCount++];
    slot.id=cast(BRepId)arena.nurbsCurveCount; slot.degree=degree; slot.controlPointCount=controlPointCount; slot.knotCount=knotCount;
    foreach(i;0..controlPointCount) { slot.controlPoints[i]=controlPoints[i]; slot.weights[i]=weights is null?1.0:weights[i]; }
    foreach(i;0..knotCount) slot.knots[i]=knots[i];
    return slot.id;
}

BRepId addNurbsCurveEdge(BRepArena* arena, BRepId startVertex, BRepId endVertex, BRepId curveId,
                         double parameterStart, double parameterEnd) nothrow @nogc
{
    if (arena is null || arena.edgeCount>=arena.edges.length || arena.vertex(startVertex) is null ||
        arena.vertex(endVertex) is null || arena.nurbsCurve(curveId) is null || parameterEnd<=parameterStart) return 0;
    auto slot=&arena.edges[arena.edgeCount++];
    slot.id=cast(BRepId)arena.edgeCount; slot.persistentId=0; slot.startVertex=startVertex; slot.endVertex=endVertex;
    slot.curveKind=BRepCurveKind.bspline; slot.firstCoedge=0; slot.secondCoedge=0; slot.origin=BRepVec3(0,0,0);
    slot.axis=BRepVec3(0,0,0); slot.referenceDirection=BRepVec3(0,0,0); slot.radius=0; slot.secondaryRadius=0;
    slot.parameterStart=parameterStart; slot.parameterEnd=parameterEnd; slot.geometryId=curveId; return slot.id;
}

BRepId addNurbsSurface(BRepArena* arena, ubyte degreeU, ubyte degreeV, ubyte countU, ubyte countV,
                       const(BRepVec3)* controlPoints, const(double)* weights,
                       const(double)* knotsU, ubyte knotCountU, const(double)* knotsV, ubyte knotCountV) nothrow @nogc
{
    if(arena is null || controlPoints is null || knotsU is null || knotsV is null || degreeU<1 || degreeV<1 ||
       countU<degreeU+1 || countV<degreeV+1 || countU>WC_BREP_MAX_NURBS_SURFACE_U || countV>WC_BREP_MAX_NURBS_SURFACE_V ||
       knotCountU!=countU+degreeU+1 || knotCountV!=countV+degreeV+1 ||
       knotCountU>WC_BREP_MAX_NURBS_SURFACE_U_KNOTS || knotCountV>WC_BREP_MAX_NURBS_SURFACE_V_KNOTS ||
       arena.nurbsSurfaceCount>=arena.nurbsSurfaces.length) return 0;
    foreach(i;1..knotCountU) if(knotsU[i]<knotsU[i-1]) return 0; foreach(i;1..knotCountV) if(knotsV[i]<knotsV[i-1]) return 0;
    if(weights !is null) foreach(i;0..cast(uint)countU*cast(uint)countV) if(weights[i] <= 0.0) return 0;
    auto slot=&arena.nurbsSurfaces[arena.nurbsSurfaceCount++];
    slot.id=cast(BRepId)arena.nurbsSurfaceCount; slot.degreeU=degreeU; slot.degreeV=degreeV; slot.countU=countU; slot.countV=countV; slot.knotCountU=knotCountU; slot.knotCountV=knotCountV;
    foreach(i;0..cast(uint)countU*cast(uint)countV) { slot.controlPoints[i]=controlPoints[i]; slot.weights[i]=weights is null?1.0:weights[i]; }
    foreach(i;0..knotCountU) slot.knotsU[i]=knotsU[i]; foreach(i;0..knotCountV) slot.knotsV[i]=knotsV[i];
    return slot.id;
}

BRepId addNurbsSurfaceFace(BRepArena* arena, BRepId shellId, BRepId surfaceId) nothrow @nogc
{
    if(arena is null || arena.faceCount>=arena.faces.length || arena.shell(shellId) is null || arena.nurbsSurface(surfaceId) is null) return 0;
    auto slot=&arena.faces[arena.faceCount++];
    slot.id=cast(BRepId)arena.faceCount; slot.persistentId=0; slot.shell=shellId; slot.outerLoop=0; slot.firstLoop=0; slot.loopCount=0; slot.surfaceKind=BRepSurfaceKind.bspline;
    slot.origin=BRepVec3(0,0,0); slot.normal=BRepVec3(0,0,0); slot.axis=BRepVec3(0,0,0); slot.referenceDirection=BRepVec3(0,0,0);
    slot.radius=0; slot.secondaryRadius=0; slot.axialLength=0; slot.reversed=false; slot.geometryId=surfaceId; return slot.id;
}

BRepId addLoop(BRepArena* arena, BRepId faceId) nothrow @nogc
{
    if (arena is null || arena.loopCount >= arena.loops.length || arena.face(faceId) is null)
        return 0;
    auto slot = &arena.loops[arena.loopCount++];
    slot.id = cast(BRepId)arena.loopCount;
    slot.face = faceId;
    slot.firstCoedge = 0;
    slot.coedgeCount = 0;
    auto face=arena.face(faceId);
    if(face.firstLoop==0) face.firstLoop=slot.id;
    ++face.loopCount;
    return slot.id;
}

BRepId addCoedge(BRepArena* arena, BRepId loopId, BRepId edgeId, bool reversed) nothrow @nogc
{
    if (arena is null || arena.coedgeCount >= arena.coedges.length || arena.loop(loopId) is null)
        return 0;
    auto edge = arena.edge(edgeId);
    if (edge is null || (edge.firstCoedge != 0 && edge.secondCoedge != 0))
        return 0;

    auto slot = &arena.coedges[arena.coedgeCount++];
    slot.id = cast(BRepId)arena.coedgeCount;
    slot.edge = edgeId;
    slot.loop = loopId;
    slot.next = 0;
    slot.previous = 0;
    slot.reversed = reversed;
    if (edge.firstCoedge == 0)
        edge.firstCoedge = slot.id;
    else
        edge.secondCoedge = slot.id;
    return slot.id;
}

bool closeLoop(BRepArena* arena, BRepId loopId, const(BRepId)* coedges, uint count) nothrow @nogc
{
    auto loop = arena is null ? null : arena.loop(loopId);
    if (loop is null || coedges is null || count == 0)
        return false;
    foreach (i; 0 .. count)
    {
        auto coedge = arena.coedge(coedges[i]);
        if (coedge is null || coedge.loop != loopId)
            return false;
    }
    loop.firstCoedge = coedges[0];
    loop.coedgeCount = count;
    foreach (i; 0 .. count)
    {
        auto coedge = arena.coedge(coedges[i]);
        coedge.next = coedges[(i + 1) % count];
        coedge.previous = coedges[(i + count - 1) % count];
    }
    return true;
}



