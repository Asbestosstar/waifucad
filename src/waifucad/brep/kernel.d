module waifucad.brep.kernel;

import waifucad.brep.builder;
import waifucad.brep.geometry : WC_BREP_PI;
import waifucad.brep.types;

private BRepId abortConstruction(BRepArena* arena, BRepArenaMark mark) nothrow @nogc
{
    rollbackArena(arena, mark);
    return 0;
}

/*
 * Construct an exact, manifold six-face rectangular solid. Every topological
 * edge is shared by two oppositely oriented coedges.
 */
BRepId makeBoxAt(BRepArena* arena, double width, double depth, double height,
                 double centreX, double centreY, double baseZ) nothrow @nogc
{
    if (arena is null || width <= 0.0 || depth <= 0.0 || height <= 0.0)
        return 0;

    auto mark = markArena(arena);
    auto solidId = addSolid(arena, BRepPrimitiveKind.box);
    if (solidId == 0)
        return 0;
    auto shellId = addShell(arena, solidId);
    if (shellId == 0)
        return abortConstruction(arena, mark);

    auto halfW = width * 0.5;
    auto halfD = depth * 0.5;
    BRepVec3[8] points;
    points[0] = BRepVec3(centreX - halfW, centreY - halfD, baseZ);
    points[1] = BRepVec3(centreX + halfW, centreY - halfD, baseZ);
    points[2] = BRepVec3(centreX + halfW, centreY + halfD, baseZ);
    points[3] = BRepVec3(centreX - halfW, centreY + halfD, baseZ);
    points[4] = BRepVec3(centreX - halfW, centreY - halfD, baseZ + height);
    points[5] = BRepVec3(centreX + halfW, centreY - halfD, baseZ + height);
    points[6] = BRepVec3(centreX + halfW, centreY + halfD, baseZ + height);
    points[7] = BRepVec3(centreX - halfW, centreY + halfD, baseZ + height);

    BRepId[8] vertices;
    foreach (i; 0 .. 8)
    {
        vertices[i] = addVertex(arena, points[i]);
        if (vertices[i] == 0)
            return abortConstruction(arena, mark);
    }

    /* Each row is counter-clockwise when viewed from outside the solid. */
    ubyte[4][6] faceVertices = [
        [0, 3, 2, 1],
        [4, 5, 6, 7],
        [0, 1, 5, 4],
        [1, 2, 6, 5],
        [2, 3, 7, 6],
        [3, 0, 4, 7]
    ];
    BRepVec3[6] normals = [
        BRepVec3( 0.0,  0.0, -1.0),
        BRepVec3( 0.0,  0.0,  1.0),
        BRepVec3( 0.0, -1.0,  0.0),
        BRepVec3( 1.0,  0.0,  0.0),
        BRepVec3( 0.0,  1.0,  0.0),
        BRepVec3(-1.0,  0.0,  0.0)
    ];
    BRepVec3[6] references = [
        BRepVec3(1.0, 0.0, 0.0),
        BRepVec3(1.0, 0.0, 0.0),
        BRepVec3(1.0, 0.0, 0.0),
        BRepVec3(0.0, 1.0, 0.0),
        BRepVec3(1.0, 0.0, 0.0),
        BRepVec3(0.0, 1.0, 0.0)
    ];

    foreach (faceIndex; 0 .. 6)
    {
        auto faceId = addPlaneFace(arena, shellId,
                                   points[faceVertices[faceIndex][0]],
                                   normals[faceIndex], references[faceIndex]);
        auto loopId = addLoop(arena, faceId);
        auto face = arena.face(faceId);
        if (faceId == 0 || loopId == 0 || face is null)
            return abortConstruction(arena, mark);
        face.outerLoop = loopId;

        BRepId[4] faceCoedges;
        foreach (side; 0 .. 4)
        {
            auto a = vertices[faceVertices[faceIndex][side]];
            auto b = vertices[faceVertices[faceIndex][(side + 1) % 4]];
            auto edgeId = findLineEdge(arena, a, b);
            if (edgeId == 0)
                edgeId = addLineEdge(arena, a, b);
            auto edge = arena.edge(edgeId);
            if (edge is null)
                return abortConstruction(arena, mark);
            auto reversed = !(edge.startVertex == a && edge.endVertex == b);
            faceCoedges[side] = addCoedge(arena, loopId, edgeId, reversed);
            if (faceCoedges[side] == 0)
                return abortConstruction(arena, mark);
        }
        if (!closeLoop(arena, loopId, faceCoedges.ptr, 4))
            return abortConstruction(arena, mark);
    }

    auto solid = arena.solid(solidId);
    auto shell = arena.shell(shellId);
    if (solid is null || shell is null)
        return abortConstruction(arena, mark);

    solid.firstVertex = cast(BRepId)(mark.vertices + 1);
    solid.vertexCount = cast(uint)(arena.vertexCount - mark.vertices);
    solid.firstEdge = cast(BRepId)(mark.edges + 1);
    solid.edgeCount = cast(uint)(arena.edgeCount - mark.edges);
    solid.firstFace = cast(BRepId)(mark.faces + 1);
    solid.faceCount = cast(uint)(arena.faceCount - mark.faces);
    solid.bounds.minimum = BRepVec3(centreX - halfW, centreY - halfD, baseZ);
    solid.bounds.maximum = BRepVec3(centreX + halfW, centreY + halfD, baseZ + height);
    solid.bounds.valid = true;
    solid.primitiveA = width;
    solid.primitiveB = depth;
    solid.primitiveC = height;

    shell.firstFace = solid.firstFace;
    shell.faceCount = solid.faceCount;
    shell.closed = true;
    return solidId;
}

BRepId makeBox(BRepArena* arena, double width, double depth, double height) nothrow @nogc
{
    return makeBoxAt(arena, width, depth, height, 0.0, 0.0, 0.0);
}

/*
 * Construct an exact analytic right circular cylinder aligned to +Z. The
 * topology uses two periodic circular edges and one seam edge. The seam appears
 * twice, with opposite orientation, in the cylindrical face loop. This is the
 * usual periodic-surface B-rep pattern rather than a faceted approximation.
 */
BRepId makeCylinderAt(BRepArena* arena, double radius, double height,
                      double centreX, double centreY, double baseZ) nothrow @nogc
{
    if (arena is null || radius <= 0.0 || height <= 0.0)
        return 0;

    auto mark = markArena(arena);
    auto solidId = addSolid(arena, BRepPrimitiveKind.cylinder);
    if (solidId == 0)
        return 0;
    auto shellId = addShell(arena, solidId);
    if (shellId == 0)
        return abortConstruction(arena, mark);

    auto xAxis = BRepVec3(1.0, 0.0, 0.0);
    auto zAxis = BRepVec3(0.0, 0.0, 1.0);
    auto bottomCentre = BRepVec3(centreX, centreY, baseZ);
    auto topCentre = BRepVec3(centreX, centreY, baseZ + height);
    auto bottomVertex = addVertex(arena, BRepVec3(centreX + radius, centreY, baseZ));
    auto topVertex = addVertex(arena, BRepVec3(centreX + radius, centreY, baseZ + height));
    if (bottomVertex == 0 || topVertex == 0)
        return abortConstruction(arena, mark);

    auto bottomCircle = addCircleEdge(arena, bottomVertex, bottomCentre, zAxis, xAxis,
                                      radius, 0.0, 2.0 * WC_BREP_PI);
    auto topCircle = addCircleEdge(arena, topVertex, topCentre, zAxis, xAxis,
                                   radius, 0.0, 2.0 * WC_BREP_PI);
    auto seam = addLineEdge(arena, bottomVertex, topVertex);
    if (bottomCircle == 0 || topCircle == 0 || seam == 0)
        return abortConstruction(arena, mark);

    /* Bottom cap: outward normal -Z, so the +Z circle parameterisation is used
       in reverse orientation. */
    auto bottomFace = addPlaneFace(arena, shellId, bottomCentre,
                                   BRepVec3(0.0, 0.0, -1.0), xAxis);
    auto bottomLoop = addLoop(arena, bottomFace);
    auto bottomCoedge = addCoedge(arena, bottomLoop, bottomCircle, true);
    BRepId[1] bottomRing = [bottomCoedge];
    if (bottomFace == 0 || bottomLoop == 0 || bottomCoedge == 0 ||
        !closeLoop(arena, bottomLoop, bottomRing.ptr, 1))
        return abortConstruction(arena, mark);
    arena.face(bottomFace).outerLoop = bottomLoop;

    /* Top cap: outward normal +Z. */
    auto topFace = addPlaneFace(arena, shellId, topCentre,
                                BRepVec3(0.0, 0.0, 1.0), xAxis);
    auto topLoop = addLoop(arena, topFace);
    auto topCoedge = addCoedge(arena, topLoop, topCircle, false);
    BRepId[1] topRing = [topCoedge];
    if (topFace == 0 || topLoop == 0 || topCoedge == 0 ||
        !closeLoop(arena, topLoop, topRing.ptr, 1))
        return abortConstruction(arena, mark);
    arena.face(topFace).outerLoop = topLoop;

    /* Cylindrical side: seam up, top circle reversed, seam down, bottom circle
       forward. The two uses of the seam are the two manifold coedges of that
       topological edge. */
    auto sideFace = addCylinderFace(arena, shellId, bottomCentre, zAxis, xAxis, radius);
    auto sideLoop = addLoop(arena, sideFace);
    if (sideFace == 0 || sideLoop == 0)
        return abortConstruction(arena, mark);
    BRepId[4] sideRing;
    sideRing[0] = addCoedge(arena, sideLoop, seam, false);
    sideRing[1] = addCoedge(arena, sideLoop, topCircle, true);
    sideRing[2] = addCoedge(arena, sideLoop, seam, true);
    sideRing[3] = addCoedge(arena, sideLoop, bottomCircle, false);
    foreach (coedgeId; sideRing)
        if (coedgeId == 0)
            return abortConstruction(arena, mark);
    if (!closeLoop(arena, sideLoop, sideRing.ptr, 4))
        return abortConstruction(arena, mark);
    arena.face(sideFace).outerLoop = sideLoop;

    auto solid = arena.solid(solidId);
    auto shell = arena.shell(shellId);
    if (solid is null || shell is null)
        return abortConstruction(arena, mark);
    solid.firstVertex = cast(BRepId)(mark.vertices + 1);
    solid.vertexCount = cast(uint)(arena.vertexCount - mark.vertices);
    solid.firstEdge = cast(BRepId)(mark.edges + 1);
    solid.edgeCount = cast(uint)(arena.edgeCount - mark.edges);
    solid.firstFace = cast(BRepId)(mark.faces + 1);
    solid.faceCount = cast(uint)(arena.faceCount - mark.faces);
    solid.bounds.minimum = BRepVec3(centreX - radius, centreY - radius, baseZ);
    solid.bounds.maximum = BRepVec3(centreX + radius, centreY + radius, baseZ + height);
    solid.bounds.valid = true;
    solid.primitiveA = radius;
    solid.primitiveB = height;
    solid.primitiveC = 0.0;

    shell.firstFace = solid.firstFace;
    shell.faceCount = solid.faceCount;
    shell.closed = true;
    return solidId;
}

BRepId makeCylinder(BRepArena* arena, double radius, double height) nothrow @nogc
{
    return makeCylinderAt(arena, radius, height, 0.0, 0.0, 0.0);
}

/*
 * Construct an exact analytic sphere. The spherical face is cut along one
 * meridian represented by a semicircular seam edge used twice with opposite
 * coedge orientation. V-E+F = 2 for this closed genus-zero shell.
 */
BRepId makeSphereAt(BRepArena* arena, double radius,
                    double centreX, double centreY, double centreZ) nothrow @nogc
{
    if (arena is null || radius <= 0.0)
        return 0;

    auto mark = markArena(arena);
    auto solidId = addSolid(arena, BRepPrimitiveKind.sphere);
    if (solidId == 0)
        return 0;
    auto shellId = addShell(arena, solidId);
    if (shellId == 0)
        return abortConstruction(arena, mark);

    auto centre = BRepVec3(centreX, centreY, centreZ);
    auto south = addVertex(arena, BRepVec3(centreX, centreY, centreZ - radius));
    auto north = addVertex(arena, BRepVec3(centreX, centreY, centreZ + radius));
    if (south == 0 || north == 0)
        return abortConstruction(arena, mark);

    /* Axis +Y and reference +X make parameters PI/2 and 3PI/2 evaluate to
       the south and north poles respectively. */
    auto seam = addCircleArcEdge(arena, south, north, centre,
                                 BRepVec3(0.0, 1.0, 0.0),
                                 BRepVec3(1.0, 0.0, 0.0),
                                 radius, WC_BREP_PI * 0.5, WC_BREP_PI * 1.5);
    auto faceId = addSphereFace(arena, shellId, centre,
                                BRepVec3(0.0, 0.0, 1.0),
                                BRepVec3(1.0, 0.0, 0.0), radius);
    auto loopId = addLoop(arena, faceId);
    if (seam == 0 || faceId == 0 || loopId == 0)
        return abortConstruction(arena, mark);

    BRepId[2] ring;
    ring[0] = addCoedge(arena, loopId, seam, false);
    ring[1] = addCoedge(arena, loopId, seam, true);
    if (ring[0] == 0 || ring[1] == 0 || !closeLoop(arena, loopId, ring.ptr, 2))
        return abortConstruction(arena, mark);
    arena.face(faceId).outerLoop = loopId;

    auto solid = arena.solid(solidId);
    auto shell = arena.shell(shellId);
    if (solid is null || shell is null)
        return abortConstruction(arena, mark);
    solid.firstVertex = cast(BRepId)(mark.vertices + 1);
    solid.vertexCount = cast(uint)(arena.vertexCount - mark.vertices);
    solid.firstEdge = cast(BRepId)(mark.edges + 1);
    solid.edgeCount = cast(uint)(arena.edgeCount - mark.edges);
    solid.firstFace = cast(BRepId)(mark.faces + 1);
    solid.faceCount = cast(uint)(arena.faceCount - mark.faces);
    solid.bounds.minimum = BRepVec3(centreX - radius, centreY - radius, centreZ - radius);
    solid.bounds.maximum = BRepVec3(centreX + radius, centreY + radius, centreZ + radius);
    solid.bounds.valid = true;
    solid.primitiveA = radius;
    solid.primitiveB = 0.0;
    solid.primitiveC = 0.0;
    shell.firstFace = solid.firstFace;
    shell.faceCount = solid.faceCount;
    shell.closed = true;
    return solidId;
}

BRepId makeSphere(BRepArena* arena, double radius) nothrow @nogc
{
    return makeSphereAt(arena, radius, 0.0, 0.0, 0.0);
}

/*
 * Construct an exact analytic cone or truncated cone aligned to +Z. One or
 * both end radii may be non-zero; a zero end radius becomes a true apex and
 * does not receive a degenerate cap face.
 */
BRepId makeConeFrustumAt(BRepArena* arena, double radius1, double radius2, double height,
                         double centreX, double centreY, double baseZ) nothrow @nogc
{
    if (arena is null || radius1 < 0.0 || radius2 < 0.0 ||
        (radius1 == 0.0 && radius2 == 0.0) || height <= 0.0)
        return 0;

    auto mark = markArena(arena);
    auto solidId = addSolid(arena, BRepPrimitiveKind.coneFrustum);
    if (solidId == 0)
        return 0;
    auto shellId = addShell(arena, solidId);
    if (shellId == 0)
        return abortConstruction(arena, mark);

    auto xAxis = BRepVec3(1.0, 0.0, 0.0);
    auto zAxis = BRepVec3(0.0, 0.0, 1.0);
    auto bottomCentre = BRepVec3(centreX, centreY, baseZ);
    auto topCentre = BRepVec3(centreX, centreY, baseZ + height);
    auto bottomPoint = radius1 > 0.0 ? BRepVec3(centreX + radius1, centreY, baseZ) : bottomCentre;
    auto topPoint = radius2 > 0.0 ? BRepVec3(centreX + radius2, centreY, baseZ + height) : topCentre;
    auto bottomVertex = addVertex(arena, bottomPoint);
    auto topVertex = addVertex(arena, topPoint);
    if (bottomVertex == 0 || topVertex == 0)
        return abortConstruction(arena, mark);

    BRepId bottomCircle = 0;
    BRepId topCircle = 0;
    if (radius1 > 0.0)
        bottomCircle = addCircleEdge(arena, bottomVertex, bottomCentre, zAxis, xAxis,
                                     radius1, 0.0, 2.0 * WC_BREP_PI);
    if (radius2 > 0.0)
        topCircle = addCircleEdge(arena, topVertex, topCentre, zAxis, xAxis,
                                  radius2, 0.0, 2.0 * WC_BREP_PI);
    auto seam = addLineEdge(arena, bottomVertex, topVertex);
    if ((radius1 > 0.0 && bottomCircle == 0) || (radius2 > 0.0 && topCircle == 0) || seam == 0)
        return abortConstruction(arena, mark);

    if (radius1 > 0.0)
    {
        auto bottomFace = addPlaneFace(arena, shellId, bottomCentre,
                                       BRepVec3(0.0, 0.0, -1.0), xAxis);
        auto bottomLoop = addLoop(arena, bottomFace);
        auto bottomCoedge = addCoedge(arena, bottomLoop, bottomCircle, true);
        BRepId[1] ring = [bottomCoedge];
        if (bottomFace == 0 || bottomLoop == 0 || bottomCoedge == 0 ||
            !closeLoop(arena, bottomLoop, ring.ptr, 1))
            return abortConstruction(arena, mark);
        arena.face(bottomFace).outerLoop = bottomLoop;
    }

    if (radius2 > 0.0)
    {
        auto topFace = addPlaneFace(arena, shellId, topCentre,
                                    BRepVec3(0.0, 0.0, 1.0), xAxis);
        auto topLoop = addLoop(arena, topFace);
        auto topCoedge = addCoedge(arena, topLoop, topCircle, false);
        BRepId[1] ring = [topCoedge];
        if (topFace == 0 || topLoop == 0 || topCoedge == 0 ||
            !closeLoop(arena, topLoop, ring.ptr, 1))
            return abortConstruction(arena, mark);
        arena.face(topFace).outerLoop = topLoop;
    }

    auto sideFace = addConeFace(arena, shellId, bottomCentre, zAxis, xAxis,
                                radius1, radius2, height);
    auto sideLoop = addLoop(arena, sideFace);
    if (sideFace == 0 || sideLoop == 0)
        return abortConstruction(arena, mark);

    BRepId[4] sideRing;
    uint sideCount = 0;
    sideRing[sideCount++] = addCoedge(arena, sideLoop, seam, false);
    if (radius2 > 0.0)
        sideRing[sideCount++] = addCoedge(arena, sideLoop, topCircle, true);
    sideRing[sideCount++] = addCoedge(arena, sideLoop, seam, true);
    if (radius1 > 0.0)
        sideRing[sideCount++] = addCoedge(arena, sideLoop, bottomCircle, false);
    foreach (i; 0 .. sideCount)
        if (sideRing[i] == 0)
            return abortConstruction(arena, mark);
    if (!closeLoop(arena, sideLoop, sideRing.ptr, sideCount))
        return abortConstruction(arena, mark);
    arena.face(sideFace).outerLoop = sideLoop;

    auto solid = arena.solid(solidId);
    auto shell = arena.shell(shellId);
    if (solid is null || shell is null)
        return abortConstruction(arena, mark);
    auto maxRadius = radius1 > radius2 ? radius1 : radius2;
    solid.firstVertex = cast(BRepId)(mark.vertices + 1);
    solid.vertexCount = cast(uint)(arena.vertexCount - mark.vertices);
    solid.firstEdge = cast(BRepId)(mark.edges + 1);
    solid.edgeCount = cast(uint)(arena.edgeCount - mark.edges);
    solid.firstFace = cast(BRepId)(mark.faces + 1);
    solid.faceCount = cast(uint)(arena.faceCount - mark.faces);
    solid.bounds.minimum = BRepVec3(centreX - maxRadius, centreY - maxRadius, baseZ);
    solid.bounds.maximum = BRepVec3(centreX + maxRadius, centreY + maxRadius, baseZ + height);
    solid.bounds.valid = true;
    solid.primitiveA = radius1;
    solid.primitiveB = radius2;
    solid.primitiveC = height;
    shell.firstFace = solid.firstFace;
    shell.faceCount = solid.faceCount;
    shell.closed = true;
    return solidId;
}

BRepId makeConeFrustum(BRepArena* arena, double radius1, double radius2, double height) nothrow @nogc
{
    return makeConeFrustumAt(arena, radius1, radius2, height, 0.0, 0.0, 0.0);
}



BRepId makeTorusAt(BRepArena* arena, double majorRadius, double minorRadius,
                    double centreX, double centreY, double centreZ) nothrow @nogc
{
    if(arena is null || majorRadius<=minorRadius || minorRadius<=0.0) return 0;
    auto mark=markArena(arena); auto solidId=addSolid(arena,BRepPrimitiveKind.torus); if(solidId==0) return 0;
    auto shellId=addShell(arena,solidId); if(shellId==0) return abortConstruction(arena,mark);
    auto centre=BRepVec3(centreX,centreY,centreZ); auto x=BRepVec3(1,0,0); auto y=BRepVec3(0,1,0); auto z=BRepVec3(0,0,1);
    auto vertex=addVertex(arena,BRepVec3(centreX+majorRadius+minorRadius,centreY,centreZ)); if(vertex==0) return abortConstruction(arena,mark);
    auto majorSeam=addCircleEdge(arena,vertex,centre,z,x,majorRadius+minorRadius,0.0,2.0*WC_BREP_PI);
    auto tubeCentre=BRepVec3(centreX+majorRadius,centreY,centreZ);
    auto minorSeam=addCircleEdge(arena,vertex,tubeCentre,y,x,minorRadius,0.0,2.0*WC_BREP_PI);
    auto faceId=addTorusFace(arena,shellId,centre,z,x,majorRadius,minorRadius); auto loopId=addLoop(arena,faceId);
    if(majorSeam==0||minorSeam==0||faceId==0||loopId==0) return abortConstruction(arena,mark);
    BRepId[4] ring; ring[0]=addCoedge(arena,loopId,majorSeam,false); ring[1]=addCoedge(arena,loopId,minorSeam,false);
    ring[2]=addCoedge(arena,loopId,majorSeam,true); ring[3]=addCoedge(arena,loopId,minorSeam,true);
    foreach(i;0..4) if(ring[i]==0) return abortConstruction(arena,mark);
    if(!closeLoop(arena,loopId,ring.ptr,4)) return abortConstruction(arena,mark); arena.face(faceId).outerLoop=loopId;
    auto solid=arena.solid(solidId); auto shell=arena.shell(shellId); if(solid is null||shell is null) return abortConstruction(arena,mark);
    auto outer=majorRadius+minorRadius; solid.firstVertex=cast(BRepId)(mark.vertices+1); solid.vertexCount=1;
    solid.firstEdge=cast(BRepId)(mark.edges+1); solid.edgeCount=2; solid.firstFace=cast(BRepId)(mark.faces+1); solid.faceCount=1;
    solid.bounds.minimum=BRepVec3(centreX-outer,centreY-outer,centreZ-minorRadius);
    solid.bounds.maximum=BRepVec3(centreX+outer,centreY+outer,centreZ+minorRadius); solid.bounds.valid=true;
    solid.genus=1; solid.primitiveA=majorRadius; solid.primitiveB=minorRadius; solid.primitiveC=0.0; shell.firstFace=solid.firstFace; shell.faceCount=1; shell.closed=true; return solidId;
}

BRepId makeTorus(BRepArena* arena,double majorRadius,double minorRadius) nothrow @nogc
{ return makeTorusAt(arena,majorRadius,minorRadius,0.0,0.0,0.0); }

