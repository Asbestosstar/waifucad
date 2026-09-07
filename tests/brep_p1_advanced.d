module tests.brep_p1_advanced;

import core.stdc.math : fabs, sqrt;
import waifucad.brep.advanced : makeAxisymmetricPolygonRevolve, makeProfilePrism;
import waifucad.brep.builder : addNurbsCurve, addNurbsCurveEdge, addNurbsSurface, addNurbsSurfaceFace, addSolid, addShell, addVertex,
    addPlaneFace, addLineEdge, addLoop, addCoedge, closeLoop;
import waifucad.brep.euler : splitPlaneFaceByChord, mergeLastSplitPlaneFaces;
import waifucad.brep.geometry : evaluateEdge, evaluateFace, coedgeStartVertex;
import waifucad.brep.intersections : BRepCurveFaceIntersections, BRepFaceFaceIntersections, BRepIntersectionCurveKind, intersectLineFace, intersectFaces;
import waifucad.brep.classification : BRepPointClassification, classifyPointInPlanarSolid;
import waifucad.brep.kernel : makeBox, makeCylinder, makeCylinderAt, makeSphereAt;
import waifucad.brep.naming : assignPrimitivePersistentTopology;
import waifucad.brep.tolerance : BRepTolerancePolicy, snapCoincidentVertexGeometry, toleranceDiagnostics;
import waifucad.brep.types;
import waifucad.brep.validate : validateClosedSolid;
import waifucad.mesh.tessellate_brep : tessellateBRepSolid;
import waifucad.mesh.types : MeshArena, MeshId;
import waifucad.interchange.openscad.options : OpenScadExportOptions;

private bool closeEnough(double a,double b,double tolerance=1.0e-7) nothrow @nogc { return fabs(a-b)<=tolerance; }

private double meshTriangleArea(const MeshArena* arena, MeshId meshId) nothrow @nogc
{
    auto mesh=arena.mesh(meshId);if(mesh is null)return 0.0;double total=0.0;
    foreach(i;0..mesh.triangleCount)
    {
        auto triangle=&arena.triangles[mesh.firstTriangle+i];
        auto a=&arena.vertices[mesh.firstVertex+triangle.a],b=&arena.vertices[mesh.firstVertex+triangle.b],c=&arena.vertices[mesh.firstVertex+triangle.c];
        auto abx=b.x-a.x,aby=b.y-a.y,abz=b.z-a.z,acx=c.x-a.x,acy=c.y-a.y,acz=c.z-a.z;
        auto cx=aby*acz-abz*acy,cy=abz*acx-abx*acz,cz=abx*acy-aby*acx;
        total+=0.5*sqrt(cx*cx+cy*cy+cz*cz);
    }
    return total;
}

extern(C) int main()
{
    // General full polygon revolution: rectangular section away from the axis
    // creates a mathematically exact genus-one hollow cylinder.
    BRepArena revolvedArena; revolvedArena.clear();
    BRepVec3[4] section=[BRepVec3(10,0,0),BRepVec3(20,0,0),BRepVec3(20,0,5),BRepVec3(10,0,5)];
    auto revolved=makeAxisymmetricPolygonRevolve(&revolvedArena,section.ptr,4);
    if(revolved==0) return 10;
    auto revolvedSolid=revolvedArena.solid(revolved);
    if(revolvedSolid is null || revolvedSolid.genus!=1 || validateClosedSolid(&revolvedArena,revolved)!=0) return 11;
    bool foundInnerLoop=false;
    foreach(i;0..revolvedSolid.faceCount){auto face=revolvedArena.face(revolvedSolid.firstFace+cast(BRepId)i);if(face !is null&&face.loopCount==2)foundInnerLoop=true;}
    if(!foundInnerLoop) return 12;

    // Exact plane-face split plus constrained inverse merge and persistent lineage.
    BRepArena splitArena; splitArena.clear(); auto box=makeBox(&splitArena,10,8,6); if(box==0||!assignPrimitivePersistentTopology(&splitArena,box,77)) return 20;
    auto solid=splitArena.solid(box); auto face=splitArena.face(solid.firstFace); auto loop=splitArena.loop(face.outerLoop); if(loop is null||loop.coedgeCount!=4)return 21;
    auto firstCoedge=loop.firstCoedge; auto secondCoedge=splitArena.coedge(firstCoedge).next; auto thirdCoedge=splitArena.coedge(secondCoedge).next;
    auto firstVertex=coedgeStartVertex(&splitArena,firstCoedge); auto oppositeVertex=coedgeStartVertex(&splitArena,thirdCoedge);
    auto split=splitPlaneFaceByChord(&splitArena,face.id,firstVertex,oppositeVertex); if(!split.valid||splitArena.edge(split.splitEdge).persistentId==0)return 22;
    if(validateClosedSolid(&splitArena,box)!=0)return 23;
    if(!mergeLastSplitPlaneFaces(&splitArena,&split)||validateClosedSolid(&splitArena,box)!=0)return 24;

    // Rational NURBS curve and surface evaluators in the fixed BetterC arena.
    BRepArena nurbs; nurbs.clear();
    BRepVec3[2] curvePoints=[BRepVec3(0,0,0),BRepVec3(10,0,0)]; double[4] curveKnots=[0,0,1,1];
    auto curveId=addNurbsCurve(&nurbs,1,curvePoints.ptr,null,2,curveKnots.ptr,4); auto v0=addVertex(&nurbs,curvePoints[0]),v1=addVertex(&nurbs,curvePoints[1]);
    auto edge=addNurbsCurveEdge(&nurbs,v0,v1,curveId,0,1); bool ok=false; auto mid=evaluateEdge(&nurbs,edge,0.5,&ok); if(!ok||!closeEnough(mid.x,5.0))return 30;
    BRepVec3[4] surfacePoints=[BRepVec3(0,0,0),BRepVec3(10,0,0),BRepVec3(0,10,0),BRepVec3(10,10,0)]; double[4] knots=[0,0,1,1];
    auto surfaceId=addNurbsSurface(&nurbs,1,1,2,2,surfacePoints.ptr,null,knots.ptr,4,knots.ptr,4); auto openSolid=addSolid(&nurbs,BRepPrimitiveKind.generic); auto openShell=addShell(&nurbs,openSolid); auto nurbsFace=addNurbsSurfaceFace(&nurbs,openShell,surfaceId);
    auto centre=evaluateFace(&nurbs,nurbsFace,0.5,0.5,&ok); if(!ok||!closeEnough(centre.x,5)||!closeEnough(centre.y,5)||!closeEnough(centre.z,0))return 31;

    // Mixed line/circular-arc profile extrusion produces analytic planar/cylindrical topology.
    BRepArena mixed; mixed.clear();
    BRepProfileSegment[2] mixedSegments;
    mixedSegments[0].kind=BRepProfileSegmentKind.line; mixedSegments[0].start=BRepVec3(0,-5,0); mixedSegments[0].finish=BRepVec3(0,5,0);
    mixedSegments[1].kind=BRepProfileSegmentKind.circularArc; mixedSegments[1].start=BRepVec3(0,5,0); mixedSegments[1].finish=BRepVec3(0,-5,0); mixedSegments[1].centre=BRepVec3(0,0,0); mixedSegments[1].axis=BRepVec3(0,0,1); mixedSegments[1].referenceDirection=BRepVec3(0,1,0); mixedSegments[1].radius=5; mixedSegments[1].parameterEnd=3.14159265358979323846;
    auto mixedSolid=makeProfilePrism(&mixed,mixedSegments.ptr,2,BRepVec3(0,0,10)); if(mixedSolid==0||validateClosedSolid(&mixed,mixedSolid)!=0)return 35;
    bool cylinderSide=false; auto mixedBody=mixed.solid(mixedSolid); foreach(i;0..mixedBody.faceCount){auto member=mixed.face(mixedBody.firstFace+cast(BRepId)i);if(member !is null&&member.surfaceKind==BRepSurfaceKind.cylinder)cylinderSide=true;} if(!cylinderSide)return 36;

    // Analytic curve/face and face/face intersection groundwork.
    BRepArena intersectionArena; intersectionArena.clear(); auto cylinder=makeCylinder(&intersectionArena,2,5); if(cylinder==0)return 40;
    BRepCurveFaceIntersections hits; if(!intersectLineFace(&intersectionArena,BRepVec3(-4,0,2),BRepVec3(1,0,0),3,1.0e-8,&hits)||hits.count!=2)return 41;
    BRepFaceFaceIntersections curves; if(!intersectFaces(&intersectionArena,2,3,1.0e-8,&curves)||curves.count!=1||!closeEnough(curves.curves[0].radius,2))return 42;

    // Sphere/sphere intersection produces an exact circle; parallel offset
    // cylinders produce the exact one/two longitudinal intersection lines.
    BRepArena sphereIntersections; sphereIntersections.clear();
    auto sphereA=makeSphereAt(&sphereIntersections,5,0,0,0);
    auto sphereB=makeSphereAt(&sphereIntersections,5,6,0,0);
    if(sphereA==0||sphereB==0)return 43;
    auto sphereFaceA=sphereIntersections.solid(sphereA).firstFace;
    auto sphereFaceB=sphereIntersections.solid(sphereB).firstFace;
    BRepFaceFaceIntersections sphereCurve;
    if(!intersectFaces(&sphereIntersections,sphereFaceA,sphereFaceB,1.0e-8,&sphereCurve)||sphereCurve.count!=1||sphereCurve.curves[0].kind!=BRepIntersectionCurveKind.circle||!closeEnough(sphereCurve.curves[0].radius,4.0))return 44;

    BRepArena cylinderIntersections; cylinderIntersections.clear();
    auto cylinderA=makeCylinderAt(&cylinderIntersections,5,10,0,0,0);
    auto cylinderB=makeCylinderAt(&cylinderIntersections,5,10,6,0,0);
    if(cylinderA==0||cylinderB==0)return 53;
    auto cylinderFaceA=cylinderIntersections.solid(cylinderA).firstFace+2;
    auto cylinderFaceB=cylinderIntersections.solid(cylinderB).firstFace+2;
    BRepFaceFaceIntersections cylinderLines;
    if(!intersectFaces(&cylinderIntersections,cylinderFaceA,cylinderFaceB,1.0e-8,&cylinderLines)||cylinderLines.count!=2||cylinderLines.curves[0].kind!=BRepIntersectionCurveKind.line||cylinderLines.curves[1].kind!=BRepIntersectionCurveKind.line)return 54;

    // Arbitrary planar multi-loop tessellation: a 10x10 square with a
    // 4x4 square hole must retain 84 square units of material and never fill
    // the inner loop.
    BRepArena trimmed; trimmed.clear();
    auto trimmedSolid=addSolid(&trimmed,BRepPrimitiveKind.generic);auto trimmedShell=addShell(&trimmed,trimmedSolid);
    auto trimmedFace=addPlaneFace(&trimmed,trimmedShell,BRepVec3(0,0,0),BRepVec3(0,0,1),BRepVec3(1,0,0));
    if(trimmedSolid==0||trimmedShell==0||trimmedFace==0)return 55;
    BRepId[4] outerVertices=[addVertex(&trimmed,BRepVec3(0,0,0)),addVertex(&trimmed,BRepVec3(10,0,0)),addVertex(&trimmed,BRepVec3(10,10,0)),addVertex(&trimmed,BRepVec3(0,10,0))];
    BRepId[4] outerEdges;foreach(i;0..4)outerEdges[i]=addLineEdge(&trimmed,outerVertices[i],outerVertices[(i+1)%4]);
    auto outerLoop=addLoop(&trimmed,trimmedFace);BRepId[4] outerCoedges;foreach(i;0..4)outerCoedges[i]=addCoedge(&trimmed,outerLoop,outerEdges[i],false);
    if(outerLoop==0||!closeLoop(&trimmed,outerLoop,outerCoedges.ptr,4))return 56;trimmed.face(trimmedFace).outerLoop=outerLoop;
    BRepId[4] holeVertices=[addVertex(&trimmed,BRepVec3(3,3,0)),addVertex(&trimmed,BRepVec3(7,3,0)),addVertex(&trimmed,BRepVec3(7,7,0)),addVertex(&trimmed,BRepVec3(3,7,0))];
    BRepId[4] holeEdges;foreach(i;0..4)holeEdges[i]=addLineEdge(&trimmed,holeVertices[i],holeVertices[(i+1)%4]);
    auto holeLoop=addLoop(&trimmed,trimmedFace);BRepId[4] holeCoedges;foreach(i;0..4)holeCoedges[i]=addCoedge(&trimmed,holeLoop,holeEdges[i],false);
    if(holeLoop==0||!closeLoop(&trimmed,holeLoop,holeCoedges.ptr,4))return 57;
    auto trimmedBody=trimmed.solid(trimmedSolid);auto trimmedBodyShell=trimmed.shell(trimmedShell);
    trimmedBody.firstVertex=outerVertices[0];trimmedBody.vertexCount=8;trimmedBody.firstEdge=outerEdges[0];trimmedBody.edgeCount=8;trimmedBody.firstFace=trimmedFace;trimmedBody.faceCount=1;
    trimmedBody.bounds.minimum=BRepVec3(0,0,0);trimmedBody.bounds.maximum=BRepVec3(10,10,0);trimmedBody.bounds.valid=true;
    trimmedBodyShell.firstFace=trimmedFace;trimmedBodyShell.faceCount=1;
    MeshArena trimmedMesh;trimmedMesh.clear();OpenScadExportOptions trimOptions;trimOptions.setDefaults();MeshId trimmedMeshId=0;
    if(tessellateBRepSolid(&trimmedMesh,&trimmed,trimmedSolid,&trimOptions,&trimmedMeshId)!=0||trimmedMeshId==0)return 58;
    if(!closeEnough(meshTriangleArea(&trimmedMesh,trimmedMeshId),84.0,1.0e-6))return 59;

    // Trim-aware point classification supports arbitrary closed planar solids without tessellation fallback.
    BRepArena classified; classified.clear(); auto classifiedBox=makeBox(&classified,10,8,6); if(classifiedBox==0)return 45;
    if(classifyPointInPlanarSolid(&classified,classifiedBox,BRepVec3(0,0,2),1.0e-8)!=BRepPointClassification.inside)return 46;
    if(classifyPointInPlanarSolid(&classified,classifiedBox,BRepVec3(20,0,2),1.0e-8)!=BRepPointClassification.outside)return 47;
    if(classifyPointInPlanarSolid(&classified,classifiedBox,BRepVec3(0,0,0),1.0e-8)!=BRepPointClassification.boundary)return 48;

    // Conservative tolerant healing snaps geometry but never merges topology IDs.
    BRepArena tolerant; tolerant.clear(); auto a=addVertex(&tolerant,BRepVec3(1,2,3)), b=addVertex(&tolerant,BRepVec3(1.000001,2,3));
    BRepTolerancePolicy policy; policy.setDefaults(); policy.absoluteLength=1.0e-4; if(snapCoincidentVertexGeometry(&tolerant,&policy)!=1)return 50;
    if(!closeEnough(tolerant.vertex(a).point.x,tolerant.vertex(b).point.x,1.0e-12))return 51; double maxTolerance=0; if(!toleranceDiagnostics(&tolerant,&maxTolerance)||maxTolerance<1.0e-4)return 52;
    return 0;
}

