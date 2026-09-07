module waifucad.brep.properties;

import core.stdc.math : fabs, sqrt;
import waifucad.brep.geometry : WC_BREP_PI, add, coedgeStartVertex, cross, dot, length, normalise, scale, subtract;
import waifucad.brep.validate : validateClosedSolid;
import waifucad.brep.types;

/* Upper bound on one planar face ring for the polyhedron property path.
   Constructed prism/loft rings are far smaller; oversized rings stay
   unsupported rather than approximated. */
private enum WC_PROPERTIES_MAX_RING = 256;
private enum double WC_PROPERTIES_PLANE_TOL = 1.0e-6;
private enum double WC_BREP_EPSILON_PROPERTIES = 1.0e-9;

BRepMassProperties massProperties(BRepArena* arena, BRepId solidId) nothrow @nogc
{
    BRepMassProperties result;
    auto solid = arena is null ? null : arena.solid(solidId);
    if (solid is null || !solid.bounds.valid)
        return result;

    if (solid.primitiveKind == BRepPrimitiveKind.box)
    {
        auto width = solid.primitiveA;
        auto depth = solid.primitiveB;
        auto height = solid.primitiveC;
        if (width <= 0.0 || depth <= 0.0 || height <= 0.0)
            return result;
        result.volume = width * depth * height;
        result.surfaceArea = 2.0 * (width * depth + width * height + depth * height);
        result.centreOfMass = BRepVec3(
            (solid.bounds.minimum.x + solid.bounds.maximum.x) * 0.5,
            (solid.bounds.minimum.y + solid.bounds.maximum.y) * 0.5,
            (solid.bounds.minimum.z + solid.bounds.maximum.z) * 0.5);
        result.valid = true;
        return result;
    }


    if (solid.primitiveKind == BRepPrimitiveKind.boxShell)
    {
        auto width=solid.primitiveA, depth=solid.primitiveB, height=solid.primitiveC, thickness=solid.primitiveD;
        if(width<=2.0*thickness||depth<=2.0*thickness||height<=2.0*thickness||thickness<=0.0)return result;
        auto iw=width-2.0*thickness, id=depth-2.0*thickness, ih=height-2.0*thickness;
        result.volume=width*depth*height-iw*id*ih;
        result.surfaceArea=2.0*(width*depth+width*height+depth*height)+2.0*(iw*id+iw*ih+id*ih);
        result.centreOfMass=BRepVec3((solid.bounds.minimum.x+solid.bounds.maximum.x)*0.5,(solid.bounds.minimum.y+solid.bounds.maximum.y)*0.5,(solid.bounds.minimum.z+solid.bounds.maximum.z)*0.5);
        result.valid=true; return result;
    }

    if (solid.primitiveKind == BRepPrimitiveKind.cylinder)
    {
        auto radius = solid.primitiveA;
        auto height = solid.primitiveB;
        if (radius <= 0.0 || height <= 0.0)
            return result;
        result.volume = WC_BREP_PI * radius * radius * height;
        result.surfaceArea = 2.0 * WC_BREP_PI * radius * (radius + height);
        result.centreOfMass = BRepVec3(
            (solid.bounds.minimum.x + solid.bounds.maximum.x) * 0.5,
            (solid.bounds.minimum.y + solid.bounds.maximum.y) * 0.5,
            (solid.bounds.minimum.z + solid.bounds.maximum.z) * 0.5);
        result.valid = true;
        return result;
    }

    if (solid.primitiveKind == BRepPrimitiveKind.sphere)
    {
        auto radius = solid.primitiveA;
        if (radius <= 0.0)
            return result;
        result.volume = (4.0 / 3.0) * WC_BREP_PI * radius * radius * radius;
        result.surfaceArea = 4.0 * WC_BREP_PI * radius * radius;
        result.centreOfMass = BRepVec3(
            (solid.bounds.minimum.x + solid.bounds.maximum.x) * 0.5,
            (solid.bounds.minimum.y + solid.bounds.maximum.y) * 0.5,
            (solid.bounds.minimum.z + solid.bounds.maximum.z) * 0.5);
        result.valid = true;
        return result;
    }

    if (solid.primitiveKind == BRepPrimitiveKind.coneFrustum)
    {
        auto radius1 = solid.primitiveA;
        auto radius2 = solid.primitiveB;
        auto height = solid.primitiveC;
        auto denominator = radius1 * radius1 + radius1 * radius2 + radius2 * radius2;
        if (height <= 0.0 || denominator <= 0.0)
            return result;
        auto slant = sqrt((radius1 - radius2) * (radius1 - radius2) + height * height);
        result.volume = WC_BREP_PI * height * denominator / 3.0;
        result.surfaceArea = WC_BREP_PI * (radius1 + radius2) * slant +
                             WC_BREP_PI * radius1 * radius1 + WC_BREP_PI * radius2 * radius2;
        auto zFraction = (radius1 * radius1 + 2.0 * radius1 * radius2 + 3.0 * radius2 * radius2) /
                         (4.0 * denominator);
        result.centreOfMass = BRepVec3(
            (solid.bounds.minimum.x + solid.bounds.maximum.x) * 0.5,
            (solid.bounds.minimum.y + solid.bounds.maximum.y) * 0.5,
            solid.bounds.minimum.z + height * zFraction);
        result.valid = true;
        return result;
    }

    if (solid.primitiveKind == BRepPrimitiveKind.torus)
    {
        auto major = solid.primitiveA;
        auto minor = solid.primitiveB;
        if (major <= minor || minor <= 0.0)
            return result;
        result.volume = 2.0 * WC_BREP_PI * WC_BREP_PI * major * minor * minor;
        result.surfaceArea = 4.0 * WC_BREP_PI * WC_BREP_PI * major * minor;
        result.centreOfMass = BRepVec3(
            (solid.bounds.minimum.x + solid.bounds.maximum.x) * 0.5,
            (solid.bounds.minimum.y + solid.bounds.maximum.y) * 0.5,
            (solid.bounds.minimum.z + solid.bounds.maximum.z) * 0.5);
        result.valid = true;
        return result;
    }

    /* Closed single-shell planar polyhedra (polygon prisms, parallel lofts,
       pyramids) integrate exactly over their stored topology with the
       divergence theorem. Every face must be a one-loop plane whose ring
       points lie on the stored plane; curved faces, inner loops and open
       solids remain unsupported here and report no exact properties rather
       than an approximation. */
    if (solid.primitiveKind == BRepPrimitiveKind.generic &&
        solid.shellCount == 1 && solid.faceCount >= 4 &&
        validateClosedSolid(arena, solidId) == 0)
    {
        double volumeSum = 0.0;
        double areaSum = 0.0;
        BRepVec3 centroidSum = BRepVec3(0.0, 0.0, 0.0);
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
            if (loop is null || loop.coedgeCount < 3 || loop.coedgeCount > WC_PROPERTIES_MAX_RING)
            {
                supported = false;
                break;
            }
            BRepVec3[WC_PROPERTIES_MAX_RING] ring;
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
                if (fabs(dot(subtract(ringVertex.point, face.origin), storedNormal)) > WC_PROPERTIES_PLANE_TOL)
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

            /* Newell's normal gives the ring winding and the exact planar
               polygon area (concave rings included). The material side is
               the stored normal, flipped when the face is marked reversed. */
            BRepVec3 newell = BRepVec3(0.0, 0.0, 0.0);
            foreach (i; 0 .. ringCount)
            {
                auto current = ring[i];
                auto following = ring[(i + 1) % ringCount];
                newell = add(newell, cross(current, following));
            }
            auto outward = face.reversed ? scale(storedNormal, -1.0) : storedNormal;
            auto winding = dot(newell, outward) >= 0.0 ? 1.0 : -1.0;
            areaSum += length(newell) * 0.5;

            /* Signed tetrahedra from the origin over a fan of the ring; the
               signed fan is exact for any simple planar polygon. */
            foreach (i; 1 .. ringCount - 1)
            {
                auto a = ring[0];
                auto b = ring[i];
                auto c = ring[i + 1];
                auto determinant = dot(a, cross(b, c));
                volumeSum += winding * determinant / 6.0;
                centroidSum = add(centroidSum, scale(add(a, add(b, c)), winding * determinant / 24.0));
            }
        }
        if (supported && volumeSum > WC_BREP_EPSILON_PROPERTIES)
        {
            result.volume = volumeSum;
            result.surfaceArea = areaSum;
            result.centreOfMass = scale(centroidSum, 1.0 / volumeSum);
            result.valid = true;
            return result;
        }
        return result;
    }

    return result;
}



