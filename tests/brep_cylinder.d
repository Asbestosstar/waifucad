module tests.brep_cylinder;

import core.stdc.math : fabs;
import core.stdc.stdio : fprintf, stderr;
import waifucad.brep.geometry : WC_BREP_PI, classifyPoint, evaluateEdge, intersectLinePlane;
import waifucad.brep.kernel : makeCylinder;
import waifucad.brep.properties : massProperties;
import waifucad.brep.types;
import waifucad.brep.validate : validateClosedSolid;

private bool closeEnough(double a, double b, double tolerance = 1.0e-8) nothrow @nogc
{
    return fabs(a - b) <= tolerance;
}

extern(C) int main()
{
    BRepArena arena;
    arena.clear();
    auto solid = makeCylinder(&arena, 8.0, 22.0);
    if (solid == 0)
        return 10;
    if (arena.vertexCount != 2 || arena.edgeCount != 3 || arena.coedgeCount != 6 ||
        arena.loopCount != 3 || arena.faceCount != 3 || arena.shellCount != 1 || arena.solidCount != 1)
    {
        fprintf(stderr, "Unexpected WaifuBRep cylinder topology counts.\n");
        return 11;
    }
    auto validation = validateClosedSolid(&arena, solid);
    if (validation != 0)
    {
        fprintf(stderr, "WaifuBRep cylinder validation failed: %d\n", validation);
        return 12;
    }

    bool pointOk = false;
    auto quarter = evaluateEdge(&arena, 1, 0.25, &pointOk);
    if (!pointOk || !closeEnough(quarter.x, 0.0) || !closeEnough(quarter.y, 8.0) || !closeEnough(quarter.z, 0.0))
        return 13;

    auto properties = massProperties(&arena, solid);
    if (!properties.valid || !closeEnough(properties.volume, WC_BREP_PI * 64.0 * 22.0, 1.0e-6) ||
        !closeEnough(properties.centreOfMass.z, 11.0))
        return 14;

    if (classifyPoint(&arena, solid, BRepVec3(0.0, 0.0, 11.0), 1.0e-8) != BRepPointClassification.inside)
        return 15;
    if (classifyPoint(&arena, solid, BRepVec3(8.0, 0.0, 11.0), 1.0e-8) != BRepPointClassification.boundary)
        return 16;
    if (classifyPoint(&arena, solid, BRepVec3(9.0, 0.0, 11.0), 1.0e-8) != BRepPointClassification.outside)
        return 17;

    BRepLine line;
    line.origin = BRepVec3(0.0, 0.0, -5.0);
    line.direction = BRepVec3(0.0, 0.0, 1.0);
    BRepPlane plane;
    plane.origin = BRepVec3(0.0, 0.0, 3.0);
    plane.normal = BRepVec3(0.0, 0.0, 1.0);
    auto hit = intersectLinePlane(line, plane, 1.0e-10);
    if (hit.kind != BRepIntersectionKind.point || !closeEnough(hit.lineParameter, 8.0) || !closeEnough(hit.point.z, 3.0))
        return 18;
    return 0;
}



