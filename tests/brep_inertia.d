module tests.brep_inertia;

/* Exact inertia tensor regression tests.
 *
 * Covers the analytic closed forms (box, cylinder, sphere, torus, frustum,
 * boxShell), the generic polyhedron path (prism), parallel-axis shifts to a
 * non-origin centre, and the Jacobi principal-axis eigensolver
 * (reconstruction T = sum(mi * ai * ai^T)).
 */
import core.stdc.math : fabs, sqrt;
import core.stdc.stdio : fprintf, stderr;
import waifucad.brep.types : BRepArena, BRepInertia, BRepVec3;
import waifucad.brep.kernel : makeBox, makeBoxAt, makeCylinder, makeSphere,
    makeTorus, makeConeFrustum;
import waifucad.brep.advanced : makePrism, makeBoxShellAt;
import waifucad.brep.inertia : inertiaProperties;

private int failures = 0;

private void fail(const(char)* what) nothrow @nogc
{
    fprintf(stderr, "brep_inertia: FAIL %s\n", what);
    ++failures;
}

private bool approxRel(double actual, double expected, double tol) nothrow @nogc
{
    auto scale = fabs(expected) > 1.0 ? fabs(expected) : 1.0;
    return fabs(actual - expected) <= tol * scale;
}

private void checkRel(const(char)* what, double actual, double expected, double tol) nothrow @nogc
{
    if (!approxRel(actual, expected, tol))
    {
        fprintf(stderr, "brep_inertia: %s expected %.17g got %.17g\n", what, expected, actual);
        ++failures;
    }
}

private bool approxVec(BRepVec3 a, double x, double y, double z, double tol) nothrow @nogc
{
    return approxRel(a.x, x, tol) && approxRel(a.y, y, tol) && approxRel(a.z, z, tol);
}

/* Principal moments ascending, axes unit and orthonormal. */
private void checkAxes(const(char)* what, const(BRepInertia)* inertia) nothrow @nogc
{
    if (inertia.principalMoments[0] > inertia.principalMoments[1] + 1e-9 * fabs(inertia.principalMoments[1]) ||
        inertia.principalMoments[1] > inertia.principalMoments[2] + 1e-9 * fabs(inertia.principalMoments[2]))
        fail(what);
    foreach (i; 0 .. 3)
    {
        auto axis = inertia.principalAxes[i];
        auto length = sqrt(axis.x * axis.x + axis.y * axis.y + axis.z * axis.z);
        checkRel(what, length, 1.0, 1e-9);
        foreach (j; i + 1 .. 3)
        {
            auto other = inertia.principalAxes[j];
            auto dot = axis.x * other.x + axis.y * other.y + axis.z * other.z;
            checkRel(what, dot, 0.0, 1e-9);
        }
    }
}

/* For coordinate-aligned solids the principal axes must be the world axes. */
private void checkAxesCoordinateAligned(const(char)* what, const(BRepInertia)* inertia) nothrow @nogc
{
    foreach (i; 0 .. 3)
    {
        auto axis = inertia.principalAxes[i];
        foreach (j; 0 .. 3)
        {
            auto component = j == 0 ? axis.x : (j == 1 ? axis.y : axis.z);
            auto expected = i == j ? 1.0 : 0.0;
            // Axes are sign-ambiguous; compare magnitudes.
            checkRel(what, fabs(component), expected, 1e-7);
        }
    }
}

/* Rebuild the cm tensor from the eigendecomposition and compare against the
 * stored cm values. Detects axis/moment pairing mistakes. */
private void checkReconstruction(const(char)* what, const(BRepInertia)* inertia, double tol) nothrow @nogc
{
    double[3][3] tensor;
    foreach (i; 0 .. 3)
        foreach (j; 0 .. 3)
        {
            double sum = 0.0;
            foreach (k; 0 .. 3)
            {
                auto axis = inertia.principalAxes[k];
                double[3] a = [axis.x, axis.y, axis.z];
                sum += inertia.principalMoments[k] * a[i] * a[j];
            }
            tensor[i][j] = sum;
        }
    checkRel(what, tensor[0][0], inertia.cmIxx, tol);
    checkRel(what, tensor[1][1], inertia.cmIyy, tol);
    checkRel(what, tensor[2][2], inertia.cmIzz, tol);
    checkRel(what, tensor[0][1], -inertia.cmPxy, tol);
    checkRel(what, tensor[0][2], -inertia.cmPxz, tol);
    checkRel(what, tensor[1][2], -inertia.cmPyz, tol);
}

extern(C) int main()
{
    BRepArena arena;

    // 1. Box 80x50x10 at origin (base z=0): V=40000, CoM (0,0,5).
    arena.clear();
    auto box = makeBox(&arena, 80.0, 50.0, 10.0);
    auto inertia = inertiaProperties(&arena, box);
    if (box == 0 || !inertia.valid) { fail("box valid"); return 1; }
    {
        immutable v = 40000.0;
        checkRel("box volume", inertia.volume, v, 1e-9);
        if (!approxVec(inertia.centreOfMass, 0.0, 0.0, 5.0, 1e-9)) fail("box centre");
        checkRel("box cmIxx", inertia.cmIxx, v * 2600.0 / 12.0, 1e-9);
        checkRel("box cmIyy", inertia.cmIyy, v * 6500.0 / 12.0, 1e-9);
        checkRel("box cmIzz", inertia.cmIzz, v * 8900.0 / 12.0, 1e-9);
        checkRel("box ixx", inertia.ixx, v * 2600.0 / 12.0 + v * 25.0, 1e-9);
        checkRel("box pxy", inertia.pxy, 0.0, 1e-12);
        checkRel("box cmPxy", inertia.cmPxy, 0.0, 1e-12);
        checkRel("box cmPxz", inertia.cmPxz, 0.0, 1e-12);
        checkRel("box cmPyz", inertia.cmPyz, 0.0, 1e-12);
        checkAxes("box axes", &inertia);
        checkAxesCoordinateAligned("box axes aligned", &inertia);
        checkReconstruction("box reconstruction", &inertia, 1e-9);
    }

    // 2. Box offset to (30,-20,5) base: products follow V*ci*cj.
    arena.clear();
    auto offsetBox = makeBoxAt(&arena, 80.0, 50.0, 10.0, 30.0, -20.0, 5.0);
    inertia = inertiaProperties(&arena, offsetBox);
    if (offsetBox == 0 || !inertia.valid) { fail("offset box valid"); return 1; }
    {
        immutable v = 40000.0;
        if (!approxVec(inertia.centreOfMass, 30.0, -20.0, 10.0, 1e-9)) fail("offset box centre");
        checkRel("offset box pxy", inertia.pxy, -24e6, 1e-9);
        checkRel("offset box pxz", inertia.pxz, 12e6, 1e-9);
        checkRel("offset box pyz", inertia.pyz, -8e6, 1e-9);
        // cm products of a coordinate-aligned box stay zero.
        checkRel("offset box cmPxy", inertia.cmPxy, 0.0, 1e-12);
        checkAxes("offset box axes", &inertia);
        checkAxesCoordinateAligned("offset box axes aligned", &inertia);
        checkReconstruction("offset box reconstruction", &inertia, 1e-9);
    }

    // 3. Cylinder r=5 h=20: cmIzz = V r^2/2, cmIxx = V(3r^2 + h^2)/12.
    arena.clear();
    auto cylinder = makeCylinder(&arena, 5.0, 20.0);
    inertia = inertiaProperties(&arena, cylinder);
    if (cylinder == 0 || !inertia.valid) { fail("cylinder valid"); return 1; }
    {
        immutable v = inertia.volume;
        checkRel("cylinder volume", v, 500.0 * 3.14159265358979323846, 1e-9);
        if (!approxVec(inertia.centreOfMass, 0.0, 0.0, 10.0, 1e-9)) fail("cylinder centre");
        checkRel("cylinder cmIzz", inertia.cmIzz, v * 12.5, 1e-9);
        checkRel("cylinder cmIxx", inertia.cmIxx, v * 475.0 / 12.0, 1e-9);
        checkRel("cylinder cmIyy", inertia.cmIyy, v * 475.0 / 12.0, 1e-9);
        checkAxes("cylinder axes", &inertia);
        checkReconstruction("cylinder reconstruction", &inertia, 1e-9);
    }

    // 4. Sphere r=3: all moments V * 2r^2/5 = 3.6 V.
    arena.clear();
    auto sphere = makeSphere(&arena, 3.0);
    inertia = inertiaProperties(&arena, sphere);
    if (sphere == 0 || !inertia.valid) { fail("sphere valid"); return 1; }
    {
        immutable v = inertia.volume;
        checkRel("sphere cmIxx", inertia.cmIxx, v * 3.6, 1e-9);
        checkRel("sphere cmIyy", inertia.cmIyy, v * 3.6, 1e-9);
        checkRel("sphere cmIzz", inertia.cmIzz, v * 3.6, 1e-9);
        checkAxes("sphere axes", &inertia);
        checkReconstruction("sphere reconstruction", &inertia, 1e-9);
    }

    // 5. Torus R=20 a=5: cmIzz = V(R^2 + 3a^2/4), cmIxx = V(R^2/2 + 5a^2/8).
    arena.clear();
    auto torus = makeTorus(&arena, 20.0, 5.0);
    inertia = inertiaProperties(&arena, torus);
    if (torus == 0 || !inertia.valid) { fail("torus valid"); return 1; }
    {
        immutable v = inertia.volume;
        checkRel("torus cmIzz", inertia.cmIzz, v * 418.75, 1e-9);
        checkRel("torus cmIxx", inertia.cmIxx, v * 215.625, 1e-9);
        checkRel("torus cmIyy", inertia.cmIyy, v * 215.625, 1e-9);
        checkAxes("torus axes", &inertia);
        checkReconstruction("torus reconstruction", &inertia, 1e-9);
    }

    // 6. Frustum with equal radii must match the cylinder exactly.
    arena.clear();
    auto frustumCylinder = makeConeFrustum(&arena, 4.0, 4.0, 12.0);
    inertia = inertiaProperties(&arena, frustumCylinder);
    if (frustumCylinder == 0 || !inertia.valid) { fail("frustum-cylinder valid"); return 1; }
    {
        immutable v = inertia.volume;
        checkRel("frustum-cylinder volume", v, 192.0 * 3.14159265358979323846, 1e-9);
        checkRel("frustum-cylinder cmIzz", inertia.cmIzz, v * 8.0, 1e-9);
        checkRel("frustum-cylinder cmIxx", inertia.cmIxx, v * (3.0 * 16.0 + 144.0) / 12.0, 1e-9);
        checkAxes("frustum-cylinder axes", &inertia);
        checkReconstruction("frustum-cylinder reconstruction", &inertia, 1e-9);
    }

    // 7. Tapered frustum (r1=6, r2=2, h=9) against an independent midpoint
    //    slice quadrature: V = pi h (r1^2 + r1 r2 + r2^2)/3 = 156 pi,
    //    Izz = pi h (r1^4 + ... + r2^4)/10.
    arena.clear();
    auto frustum = makeConeFrustum(&arena, 6.0, 2.0, 9.0);
    inertia = inertiaProperties(&arena, frustum);
    if (frustum == 0 || !inertia.valid) { fail("frustum valid"); return 1; }
    {
        immutable pi = 3.14159265358979323846;
        immutable v = 156.0 * pi;
        checkRel("frustum volume", inertia.volume, v, 1e-9);
        immutable s4 = 1296.0 + 432.0 + 144.0 + 48.0 + 16.0; // 1936
        checkRel("frustum cmIzz", inertia.cmIzz, pi * 9.0 * s4 / 10.0, 1e-9);
        // Independent numeric check of the axial moment about the cm.
        immutable slices = 200000;
        immutable dz = 9.0 / slices;
        double numericIxx = 0.0;
        double numericVolume = 0.0;
        double numericZ = 0.0;
        foreach (i; 0 .. slices)
        {
            immutable z = (i + 0.5) * dz;
            immutable r = 6.0 + (2.0 - 6.0) * z / 9.0;
            immutable dv = pi * r * r * dz;
            numericVolume += dv;
            numericZ += dv * z;
        }
        immutable zc = numericZ / numericVolume;
        foreach (i; 0 .. slices)
        {
            immutable z = (i + 0.5) * dz;
            immutable r = 6.0 + (2.0 - 6.0) * z / 9.0;
            immutable dv = pi * r * r * dz;
            numericIxx += dv * (0.25 * r * r + (z - zc) * (z - zc));
        }
        checkRel("frustum cmIxx quadrature", inertia.cmIxx, numericIxx, 1e-6);
        if (!approxVec(inertia.centreOfMass, 0.0, 0.0, zc, 1e-6)) fail("frustum centre");
        checkAxes("frustum axes", &inertia);
        checkReconstruction("frustum reconstruction", &inertia, 1e-6);
    }

    // 8. boxShell 80x50x10 t=2 at origin: outer - inner closed forms.
    arena.clear();
    auto shell = makeBoxShellAt(&arena, 80.0, 50.0, 10.0, 2.0, 0.0, 0.0, 0.0);
    inertia = inertiaProperties(&arena, shell);
    if (shell == 0 || !inertia.valid) { fail("boxShell valid"); return 1; }
    {
        immutable outerV = 40000.0;
        immutable innerV = 76.0 * 46.0 * 6.0; // 20976
        immutable v = outerV - innerV;        // 19024
        checkRel("boxShell volume", inertia.volume, v, 1e-9);
        if (!approxVec(inertia.centreOfMass, 0.0, 0.0, 5.0, 1e-9)) fail("boxShell centre");
        checkRel("boxShell cmIxx", inertia.cmIxx,
                 (outerV * 2600.0 - innerV * 2152.0) / 12.0, 1e-9);
        checkRel("boxShell cmIyy", inertia.cmIyy,
                 (outerV * 6500.0 - innerV * (76.0 * 76.0 + 36.0)) / 12.0, 1e-9);
        checkRel("boxShell cmIzz", inertia.cmIzz,
                 (outerV * 8900.0 - innerV * (76.0 * 76.0 + 46.0 * 46.0)) / 12.0, 1e-9);
        checkAxes("boxShell axes", &inertia);
        checkAxesCoordinateAligned("boxShell axes aligned", &inertia);
        checkReconstruction("boxShell reconstruction", &inertia, 1e-9);
    }

    // 9. Generic polyhedron path: prism over an asymmetric trapezoid.
    //    Profile (0,0),(4,0),(6,3),(2,3), extrusion (0,0,5) -> V=60.
    arena.clear();
    BRepVec3[4] profile = [
        BRepVec3(0.0, 0.0, 0.0), BRepVec3(4.0, 0.0, 0.0),
        BRepVec3(6.0, 3.0, 0.0), BRepVec3(2.0, 3.0, 0.0)
    ];
    auto prism = makePrism(&arena, profile.ptr, 4, BRepVec3(0.0, 0.0, 5.0));
    inertia = inertiaProperties(&arena, prism);
    if (prism == 0 || !inertia.valid) { fail("prism valid"); return 1; }
    {
        checkRel("prism volume", inertia.volume, 60.0, 1e-9);
        if (!approxVec(inertia.centreOfMass, 3.0, 1.5, 2.5, 1e-9)) fail("prism centre");
        checkRel("prism ixx", inertia.ixx, 680.0, 1e-9);
        checkRel("prism iyy", inertia.iyy, 1140.0, 1e-9);
        checkRel("prism izz", inertia.izz, 820.0, 1e-9);
        checkRel("prism pxy", inertia.pxy, 300.0, 1e-9);
        checkRel("prism pxz", inertia.pxz, 450.0, 1e-9);
        checkRel("prism pyz", inertia.pyz, 225.0, 1e-9);
        checkRel("prism cmIxx", inertia.cmIxx, 170.0, 1e-9);
        checkRel("prism cmIyy", inertia.cmIyy, 225.0, 1e-9);
        checkRel("prism cmIzz", inertia.cmIzz, 145.0, 1e-9);
        checkRel("prism cmPxy", inertia.cmPxy, 30.0, 1e-9);
        checkRel("prism cmPxz", inertia.cmPxz, 0.0, 1e-12);
        checkRel("prism cmPyz", inertia.cmPyz, 0.0, 1e-12);
        checkAxes("prism axes", &inertia);
        checkReconstruction("prism reconstruction", &inertia, 1e-7);
    }

    // Invalid solid id must not be mistaken for a valid result.
    arena.clear();
    inertia = inertiaProperties(&arena, 0);
    if (inertia.valid) fail("invalid id must be invalid");

    if (failures != 0)
    {
        fprintf(stderr, "brep_inertia: %d failure(s)\n", failures);
        return 1;
    }
    fprintf(stderr, "brep_inertia: all checks passed\n");
    return 0;
}
