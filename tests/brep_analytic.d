module tests.brep_analytic;

import core.stdc.math : fabs;
import core.stdc.stdio : fprintf, stderr;
import waifucad.brep.geometry : WC_BREP_PI, classifyPoint, evaluateFace, faceNormalAt;
import waifucad.brep.kernel : makeSphere, makeConeFrustum;
import waifucad.brep.properties : massProperties;
import waifucad.brep.types;
import waifucad.brep.validate : validateClosedSolid;

private bool closeEnough(double a, double b, double tolerance = 1.0e-7) nothrow @nogc
{
    return fabs(a - b) <= tolerance;
}

extern(C) int main()
{
    BRepArena sphereArena;
    sphereArena.clear();
    auto sphere = makeSphere(&sphereArena, 5.0);
    if (sphere == 0 || sphereArena.vertexCount != 2 || sphereArena.edgeCount != 1 ||
        sphereArena.coedgeCount != 2 || sphereArena.loopCount != 1 || sphereArena.faceCount != 1)
        return 10;
    if (validateClosedSolid(&sphereArena, sphere) != 0)
        return 11;
    auto sphereProperties = massProperties(&sphereArena, sphere);
    if (!sphereProperties.valid || !closeEnough(sphereProperties.volume, (4.0 / 3.0) * WC_BREP_PI * 125.0))
        return 12;
    if (classifyPoint(&sphereArena, sphere, BRepVec3(0.0, 0.0, 0.0), 1.0e-8) != BRepPointClassification.inside ||
        classifyPoint(&sphereArena, sphere, BRepVec3(5.0, 0.0, 0.0), 1.0e-8) != BRepPointClassification.boundary)
        return 13;
    bool surfaceOk = false;
    auto surfacePoint = evaluateFace(&sphereArena, 1, 0.0, 0.0, &surfaceOk);
    if (!surfaceOk || !closeEnough(surfacePoint.x, 5.0) || !closeEnough(surfacePoint.y, 0.0) || !closeEnough(surfacePoint.z, 0.0))
        return 14;
    auto surfaceNormal = faceNormalAt(&sphereArena, 1, 0.0, 0.0, &surfaceOk);
    if (!surfaceOk || !closeEnough(surfaceNormal.x, 1.0))
        return 15;

    BRepArena frustumArena;
    frustumArena.clear();
    auto frustum = makeConeFrustum(&frustumArena, 4.0, 2.0, 9.0);
    if (frustum == 0 || frustumArena.vertexCount != 2 || frustumArena.edgeCount != 3 ||
        frustumArena.coedgeCount != 6 || frustumArena.loopCount != 3 || frustumArena.faceCount != 3)
        return 20;
    if (validateClosedSolid(&frustumArena, frustum) != 0)
        return 21;
    auto frustumProperties = massProperties(&frustumArena, frustum);
    auto expectedVolume = WC_BREP_PI * 9.0 * (16.0 + 8.0 + 4.0) / 3.0;
    if (!frustumProperties.valid || !closeEnough(frustumProperties.volume, expectedVolume))
        return 22;
    if (classifyPoint(&frustumArena, frustum, BRepVec3(0.0, 0.0, 4.5), 1.0e-8) != BRepPointClassification.inside)
        return 23;

    BRepArena coneArena;
    coneArena.clear();
    auto cone = makeConeFrustum(&coneArena, 4.0, 0.0, 9.0);
    if (cone == 0 || coneArena.vertexCount != 2 || coneArena.edgeCount != 2 ||
        coneArena.coedgeCount != 4 || coneArena.loopCount != 2 || coneArena.faceCount != 2)
        return 30;
    auto validation = validateClosedSolid(&coneArena, cone);
    if (validation != 0)
    {
        fprintf(stderr, "WaifuBRep cone validation failed: %d\n", validation);
        return 31;
    }
    return 0;
}



