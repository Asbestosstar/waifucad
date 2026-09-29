module waifucad.brep.inertia;

/*
 * Exact second moments (inertia tensor) for WaifuBRep solids at unit
 * density. Analytic primitives use closed forms; closed planar polyhedra
 * integrate exactly over their stored topology with the divergence theorem
 * (the same supported domain as massProperties). Principal moments and axes
 * come from a classical cyclic Jacobi eigenvalue iteration on the symmetric
 * 3x3 centre-of-mass tensor. Curved or open solids outside the analytic set
 * report no inertia rather than an approximation.
 *
 * Convention: FrameMoments stores the plain second moments Sxx = ∫x² dV,
 * Sxy = ∫xy dV, ... from which the inertia moments follow as
 * Ixx = Syy + Szz, with the symmetric tensor using negated products.
 */

import core.stdc.math : atan2, cos, fabs, sin, sqrt;
import waifucad.brep.geometry : WC_BREP_PI, add, coedgeStartVertex, cross, dot,
    length, normalise, scale, subtract;
import waifucad.brep.properties : massProperties;
import waifucad.brep.types;
import waifucad.brep.validate : validateClosedSolid;

private enum WC_INERTIA_MAX_RING = 256;
private enum double WC_INERTIA_PLANE_TOL = 1.0e-6;
private enum double WC_INERTIA_EPSILON = 1.0e-9;

private struct FrameMoments
{
    double sxx, syy, szz; // ∫x² dV, ∫y² dV, ∫z² dV (centre-of-mass frame)
    double sxy, sxz, syz; // product integrals ∫xy dV, ... (centre-of-mass frame)
    bool valid;
}

/* Classical cyclic Jacobi diagonalisation of a symmetric 3x3 matrix stored
 * row-major. Fills eigenvalues ascending with matching unit eigenvectors. */
private bool jacobiEigen3x3(const(double)* m, double[3]* eigenvalues, BRepVec3[3]* eigenvectors) nothrow @nogc
{
    double[9] a;
    double[9] v;
    foreach (i; 0 .. 9)
    {
        a[i] = m[i];
        v[i] = 0.0;
    }
    v[0] = 1.0;
    v[4] = 1.0;
    v[8] = 1.0;

    static immutable ubyte[2][3] pairs = [[0, 1], [0, 2], [1, 2]];
    foreach (sweep; 0 .. 64)
    {
        immutable off = sqrt(a[1] * a[1] + a[2] * a[2] + a[5] * a[5]);
        immutable scale_ = fabs(a[0]) + fabs(a[4]) + fabs(a[8]);
        if (off <= 1e-14 * (scale_ + 1e-300))
            break;
        foreach (pair; pairs)
        {
            immutable p = pair[0];
            immutable q = pair[1];
            immutable app = a[p * 3 + p];
            immutable aqq = a[q * 3 + q];
            immutable apq = a[p * 3 + q];
            if (apq == 0.0)
                continue;
            // Zero a[p][q] with A' = JᵀAJ, J the Givens rotation of angle θ
            // in the (p,q) plane: tan(2θ) = 2·apq / (app − aqq).
            immutable theta = 0.5 * atan2(2.0 * apq, app - aqq);
            immutable c = cos(theta);
            immutable s = sin(theta);
            immutable newApp = c * c * app + 2.0 * s * c * apq + s * s * aqq;
            immutable newAqq = s * s * app - 2.0 * s * c * apq + c * c * aqq;
            foreach (k; 0 .. 3)
            {
                if (k == p || k == q)
                    continue;
                immutable akp = a[k * 3 + p];
                immutable akq = a[k * 3 + q];
                a[k * 3 + p] = c * akp + s * akq;
                a[p * 3 + k] = a[k * 3 + p];
                a[k * 3 + q] = -s * akp + c * akq;
                a[q * 3 + k] = a[k * 3 + q];
            }
            a[p * 3 + p] = newApp;
            a[q * 3 + q] = newAqq;
            a[p * 3 + q] = 0.0;
            a[q * 3 + p] = 0.0;
            foreach (k; 0 .. 3)
            {
                immutable vkp = v[k * 3 + p];
                immutable vkq = v[k * 3 + q];
                v[k * 3 + p] = c * vkp + s * vkq;
                v[k * 3 + q] = -s * vkp + c * vkq;
            }
        }
    }

    // Sort ascending by eigenvalue, carrying the matching axis along.
    size_t[3] order = [0, 1, 2];
    foreach (i; 1 .. 3)
    {
        immutable key = a[order[i] * 3 + order[i]];
        immutable column = order[i];
        auto j = i;
        while (j > 0 && a[order[j - 1] * 3 + order[j - 1]] > key)
        {
            order[j] = order[j - 1];
            --j;
        }
        order[j] = column;
    }
    foreach (i; 0 .. 3)
    {
        immutable column = order[i];
        (*eigenvalues)[i] = a[column * 3 + column];
        auto axis = BRepVec3(v[column], v[3 + column], v[6 + column]);
        bool unit = false;
        axis = normalise(axis, &unit);
        if (!unit)
            return false;
        (*eigenvectors)[i] = axis;
    }
    return true;
}

/* Fill the origin-frame and principal fields from centre-of-mass-frame
 * moments via the parallel axis theorem, then diagonalise. */
private void finishInertia(BRepInertia* result, const(FrameMoments)* frame,
    double volume, BRepVec3 centre) nothrow @nogc
{
    result.cmIxx = frame.syy + frame.szz;
    result.cmIyy = frame.sxx + frame.szz;
    result.cmIzz = frame.sxx + frame.syy;
    result.cmPxy = frame.sxy;
    result.cmPxz = frame.sxz;
    result.cmPyz = frame.syz;
    result.ixx = result.cmIxx + volume * (centre.y * centre.y + centre.z * centre.z);
    result.iyy = result.cmIyy + volume * (centre.x * centre.x + centre.z * centre.z);
    result.izz = result.cmIzz + volume * (centre.x * centre.x + centre.y * centre.y);
    result.pxy = result.cmPxy + volume * centre.x * centre.y;
    result.pxz = result.cmPxz + volume * centre.x * centre.z;
    result.pyz = result.cmPyz + volume * centre.y * centre.z;
    result.volume = volume;
    result.centreOfMass = centre;

    // The symmetric inertia matrix carries negated products off-diagonal.
    double[9] tensor;
    tensor[0] = result.cmIxx;
    tensor[4] = result.cmIyy;
    tensor[8] = result.cmIzz;
    tensor[1] = tensor[3] = -result.cmPxy;
    tensor[2] = tensor[6] = -result.cmPxz;
    tensor[5] = tensor[7] = -result.cmPyz;
    result.valid = jacobiEigen3x3(tensor.ptr, &result.principalMoments, &result.principalAxes);
}

/* Closed-form centre-of-mass second moments for the analytic primitives. All
 * of them are symmetric about their centre, so the products vanish. The
 * frustum's axial moment additionally depends on the centre of mass, which
 * the caller has already computed. */
private FrameMoments analyticFrameMoments(const(BRepSolid)* solid, double volume,
    BRepVec3 centre) nothrow @nogc
{
    /* Zero-fill explicitly: D default-initialises doubles to NaN, and the
     * symmetric primitives below intentionally never write the (zero)
     * product integrals. */
    FrameMoments frame = FrameMoments(0.0, 0.0, 0.0, 0.0, 0.0, 0.0, false);
    switch (solid.primitiveKind)
    {
        case BRepPrimitiveKind.box:
        {
            immutable w = solid.primitiveA, d = solid.primitiveB, h = solid.primitiveC;
            if (w <= 0.0 || d <= 0.0 || h <= 0.0) return frame;
            frame.sxx = volume * w * w / 12.0;
            frame.syy = volume * d * d / 12.0;
            frame.szz = volume * h * h / 12.0;
            frame.valid = true;
            return frame;
        }
        case BRepPrimitiveKind.cylinder:
        {
            // Axis along Z: radial Sxx = V r²/4, axial Szz = V h²/12.
            immutable r = solid.primitiveA, h = solid.primitiveB;
            if (r <= 0.0 || h <= 0.0) return frame;
            frame.sxx = volume * r * r / 4.0;
            frame.syy = frame.sxx;
            frame.szz = volume * h * h / 12.0;
            frame.valid = true;
            return frame;
        }
        case BRepPrimitiveKind.sphere:
        {
            immutable r = solid.primitiveA;
            if (r <= 0.0) return frame;
            frame.sxx = volume * r * r / 5.0;
            frame.syy = frame.sxx;
            frame.szz = frame.sxx;
            frame.valid = true;
            return frame;
        }
        case BRepPrimitiveKind.torus:
        {
            // Major radius R about Z, minor radius a.
            immutable major = solid.primitiveA, minor = solid.primitiveB;
            if (major <= minor || minor <= 0.0) return frame;
            immutable radial = volume * (major * major / 2.0 + 3.0 * minor * minor / 8.0);
            frame.sxx = radial;
            frame.syy = radial;
            frame.szz = volume * minor * minor / 4.0;
            frame.valid = true;
            return frame;
        }
        case BRepPrimitiveKind.coneFrustum:
        {
            // Radius r1 at the base plane, r2 at the top, axis along Z.
            immutable r1 = solid.primitiveA, r2 = solid.primitiveB, h = solid.primitiveC;
            immutable sum2 = r1 * r1 + r1 * r2 + r2 * r2;
            if (h <= 0.0 || sum2 <= 0.0) return frame;
            immutable sum4 = r1 * r1 * r1 * r1 + r1 * r1 * r1 * r2 +
                r1 * r1 * r2 * r2 + r1 * r2 * r2 * r2 + r2 * r2 * r2 * r2;
            // Radial second moment: ∫x² dV = ∫ (π r⁴/4) dz = π h Σ4 / 20.
            frame.sxx = WC_BREP_PI * h * sum4 / 20.0;
            frame.syy = frame.sxx;
            // Axial: ∫ z² dV = π h³ (r1²/3 + r1 k h/2 + k² h²/5) with the
            // taper k = (r2 − r1)/h, about the base plane; shift to the
            // centre of mass with the parallel axis theorem.
            immutable k = (r2 - r1) / h;
            immutable baseSzz = WC_BREP_PI * h * h * h *
                (r1 * r1 / 3.0 + r1 * k * h / 2.0 + k * k * h * h / 5.0);
            immutable zRel = centre.z - solid.bounds.minimum.z;
            frame.szz = baseSzz - volume * zRel * zRel;
            frame.valid = frame.szz > 0.0;
            return frame;
        }
        case BRepPrimitiveKind.boxShell:
        {
            // Outer box minus the concentric inner cavity.
            immutable w = solid.primitiveA, d = solid.primitiveB, h = solid.primitiveC;
            immutable t = solid.primitiveD;
            if (t <= 0.0 || w <= 2.0 * t || d <= 2.0 * t || h <= 2.0 * t) return frame;
            immutable iw = w - 2.0 * t, id = d - 2.0 * t, ih = h - 2.0 * t;
            immutable outerV = w * d * h, innerV = iw * id * ih;
            if (innerV <= 0.0 || outerV <= innerV) return frame;
            frame.sxx = (outerV * w * w - innerV * iw * iw) / 12.0;
            frame.syy = (outerV * d * d - innerV * id * id) / 12.0;
            frame.szz = (outerV * h * h - innerV * ih * ih) / 12.0;
            frame.valid = true;
            return frame;
        }
        default:
            return frame;
    }
}

/* Exact second moments of a closed planar polyhedron about the global
 * origin, by the divergence theorem over the stored topology: the volume
 * integral of xᵢxⱼ becomes a sum over signed tetrahedra fanned from the
 * origin across each face ring. Mirrors the domain rules of massProperties
 * (one-loop plane faces on the stored plane, closed single shell). */
private bool polyhedronSecondMoments(BRepArena* arena, const(BRepSolid)* solid, BRepId solidId,
    double* outSxx, double* outSyy, double* outSzz,
    double* outSxy, double* outSxz, double* outSyz) nothrow @nogc
{
    if (solid.primitiveKind != BRepPrimitiveKind.generic ||
        solid.shellCount != 1 || solid.faceCount < 4 ||
        validateClosedSolid(arena, solidId) != 0)
        return false;

    double sxx = 0.0, syy = 0.0, szz = 0.0, sxy = 0.0, sxz = 0.0, syz = 0.0;
    bool supported = true;
    foreach (fi; 0 .. solid.faceCount)
    {
        auto face = arena.face(solid.firstFace + cast(BRepId)fi);
        if (face is null || face.surfaceKind != BRepSurfaceKind.plane ||
            face.loopCount != 1 || face.outerLoop == 0)
        {
            supported = false;
            break;
        }
        bool normalOk = false;
        auto storedNormal = normalise(face.normal, &normalOk);
        if (!normalOk)
        {
            supported = false;
            break;
        }
        auto loop = arena.loop(face.outerLoop);
        if (loop is null || loop.coedgeCount < 3 || loop.coedgeCount > WC_INERTIA_MAX_RING)
        {
            supported = false;
            break;
        }
        BRepVec3[WC_INERTIA_MAX_RING] ring;
        uint ringCount = 0;
        auto coedgeId = loop.firstCoedge;
        while (coedgeId != 0 && ringCount < loop.coedgeCount)
        {
            auto coedge = arena.coedge(coedgeId);
            if (coedge is null)
            {
                supported = false;
                break;
            }
            auto ringVertex = arena.vertex(coedgeStartVertex(arena, coedgeId));
            if (ringVertex is null)
            {
                supported = false;
                break;
            }
            if (fabs(dot(subtract(ringVertex.point, face.origin), storedNormal)) > WC_INERTIA_PLANE_TOL)
            {
                supported = false;
                break;
            }
            ring[ringCount++] = ringVertex.point;
            coedgeId = coedge.next == loop.firstCoedge ? 0 : coedge.next;
        }
        if (!supported || ringCount != loop.coedgeCount)
        {
            supported = false;
            break;
        }

        // Same Newell winding convention as massProperties.
        BRepVec3 newell = BRepVec3(0.0, 0.0, 0.0);
        foreach (i; 0 .. ringCount)
        {
            auto current = ring[i];
            auto following = ring[(i + 1) % ringCount];
            newell = add(newell, cross(current, following));
        }
        auto outward = face.reversed ? scale(storedNormal, -1.0) : storedNormal;
        auto winding = dot(newell, outward) >= 0.0 ? 1.0 : -1.0;

        /* Signed tetrahedra from the origin over a fan of the ring. For a
         * tetrahedron (0, a, b, c) with signed volume V6/6, the second
         * moment integral is
         *   ∫_T xᵢxⱼ dV = (V6/120) · (aᵢaⱼ + bᵢbⱼ + cᵢcⱼ + sᵢsⱼ),
         * s = a + b + c, which is exact for degree-2 polynomials. */
        foreach (i; 1 .. ringCount - 1)
        {
            auto a = ring[0];
            auto b = ring[i];
            auto c = ring[i + 1];
            immutable v6 = winding * dot(a, cross(b, c));
            immutable sx = a.x + b.x + c.x;
            immutable sy = a.y + b.y + c.y;
            immutable sz = a.z + b.z + c.z;
            immutable factor = v6 / 120.0;
            sxx += factor * (a.x * a.x + b.x * b.x + c.x * c.x + sx * sx);
            syy += factor * (a.y * a.y + b.y * b.y + c.y * c.y + sy * sy);
            szz += factor * (a.z * a.z + b.z * b.z + c.z * c.z + sz * sz);
            sxy += factor * (a.x * a.y + b.x * b.y + c.x * c.y + sx * sy);
            sxz += factor * (a.x * a.z + b.x * b.z + c.x * c.z + sx * sz);
            syz += factor * (a.y * a.z + b.y * b.z + c.y * c.z + sy * sz);
        }
    }
    if (!supported)
        return false;
    *outSxx = sxx;
    *outSyy = syy;
    *outSzz = szz;
    *outSxy = sxy;
    *outSxz = sxz;
    *outSyz = syz;
    return true;
}

/* Exact inertia tensor of a solid at unit density. Returns valid=false for
 * solids outside the supported domain (unknown ids, open shells, curved
 * non-analytic geometry). */
BRepInertia inertiaProperties(BRepArena* arena, BRepId solidId) nothrow @nogc
{
    BRepInertia result;
    auto solid = arena is null ? null : arena.solid(solidId);
    if (solid is null)
        return result;
    auto props = massProperties(arena, solidId);
    if (!props.valid || props.volume <= WC_INERTIA_EPSILON)
        return result;
    immutable volume = props.volume;
    immutable centre = props.centreOfMass;

    FrameMoments frame = analyticFrameMoments(solid, volume, centre);
    if (!frame.valid)
    {
        // Planar polyhedra integrate about the global origin; shift back to
        // the centre-of-mass frame with the parallel axis theorem.
        double xx, yy, zz, xy, xz, yz;
        if (!polyhedronSecondMoments(arena, solid, solidId, &xx, &yy, &zz, &xy, &xz, &yz))
            return result;
        frame.sxx = xx - volume * centre.x * centre.x;
        frame.syy = yy - volume * centre.y * centre.y;
        frame.szz = zz - volume * centre.z * centre.z;
        frame.sxy = xy - volume * centre.x * centre.y;
        frame.sxz = xz - volume * centre.x * centre.z;
        frame.syz = yz - volume * centre.y * centre.z;
        frame.valid = true;
    }
    finishInertia(&result, &frame, volume, centre);
    return result;
}
