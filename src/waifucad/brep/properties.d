module waifucad.brep.properties;

import core.stdc.math : sqrt;
import waifucad.brep.geometry : WC_BREP_PI;
import waifucad.brep.types;

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

    return result;
}



