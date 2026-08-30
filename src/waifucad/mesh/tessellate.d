module waifucad.mesh.tessellate;

import core.stdc.math : ceil, cos, sin, sqrt;
import waifucad.brep.types : BRepSolid, BRepPrimitiveKind;
import waifucad.mesh.types : MeshArena, MeshId, MeshVec3;
import waifucad.interchange.openscad.options : OpenScadExportOptions;

private enum WC_PI = 3.14159265358979323846264338327950288;

private uint clampSegments(uint value, const OpenScadExportOptions* options) nothrow @nogc
{
    auto minimum = options.minimumSegments < 3 ? 3u : options.minimumSegments;
    auto maximum = options.maximumSegments < minimum ? minimum : options.maximumSegments;
    if (value < minimum) value = minimum;
    if (value > maximum) value = maximum;
    return value;
}

uint segmentsForRadius(double radius, const OpenScadExportOptions* options) nothrow @nogc
{
    if (options.fn >= 3)
        return clampSegments(options.fn, options);
    uint byAngle = options.fa > 0.0 ? cast(uint)ceil(360.0 / options.fa) : options.minimumSegments;
    uint byLength = options.fs > 0.0 ? cast(uint)ceil((2.0 * WC_PI * radius) / options.fs) : options.minimumSegments;
    return clampSegments(byAngle > byLength ? byAngle : byLength, options);
}

private bool addTriangle(MeshArena* arena, MeshId id, uint a, uint b, uint c, bool reverse) nothrow @nogc
{
    return reverse ? arena.addTriangle(id, a, c, b) : arena.addTriangle(id, a, b, c);
}

private int tessellateBox(MeshArena* arena, MeshId id, const BRepSolid* solid, const OpenScadExportOptions* options) nothrow @nogc
{
    auto b = &solid.bounds;
    double scale = options.unitScale;
    MeshVec3[8] p = [
        MeshVec3(b.minimum.x*scale,b.minimum.y*scale,b.minimum.z*scale),
        MeshVec3(b.maximum.x*scale,b.minimum.y*scale,b.minimum.z*scale),
        MeshVec3(b.maximum.x*scale,b.maximum.y*scale,b.minimum.z*scale),
        MeshVec3(b.minimum.x*scale,b.maximum.y*scale,b.minimum.z*scale),
        MeshVec3(b.minimum.x*scale,b.minimum.y*scale,b.maximum.z*scale),
        MeshVec3(b.maximum.x*scale,b.minimum.y*scale,b.maximum.z*scale),
        MeshVec3(b.maximum.x*scale,b.maximum.y*scale,b.maximum.z*scale),
        MeshVec3(b.minimum.x*scale,b.maximum.y*scale,b.maximum.z*scale)
    ];
    foreach (point; p)
        if (!arena.addVertex(id, point)) return 1;
    uint[36] indices = [
        0,2,1, 0,3,2,
        4,5,6, 4,6,7,
        0,1,5, 0,5,4,
        1,2,6, 1,6,5,
        2,3,7, 2,7,6,
        3,0,4, 3,4,7
    ];
    foreach (i; 0 .. 12)
        if (!addTriangle(arena,id,indices[i*3],indices[i*3+1],indices[i*3+2],options.reverseWinding)) return 2;
    return 0;
}

private int tessellateCylinderLike(MeshArena* arena, MeshId id, const BRepSolid* solid, const OpenScadExportOptions* options) nothrow @nogc
{
    auto r1 = solid.primitiveA;
    auto r2 = solid.primitiveKind == BRepPrimitiveKind.cylinder ? r1 : solid.primitiveB;
    auto height = solid.primitiveKind == BRepPrimitiveKind.cylinder ? solid.primitiveB : solid.primitiveC;
    auto radius = r1 > r2 ? r1 : r2;
    auto segments = segmentsForRadius(radius, options);
    auto cx = (solid.bounds.minimum.x + solid.bounds.maximum.x) * 0.5;
    auto cy = (solid.bounds.minimum.y + solid.bounds.maximum.y) * 0.5;
    auto z0 = solid.bounds.minimum.z;
    auto z1 = solid.bounds.maximum.z;
    auto scale = options.unitScale;

    bool bottomApex = r1 == 0.0;
    bool topApex = r2 == 0.0;
    uint bottomStart = 0, topStart = 0, bottomCentre = uint.max, topCentre = uint.max;

    if (bottomApex)
    {
        if (!arena.addVertex(id, MeshVec3(cx*scale, cy*scale, z0*scale), &bottomStart)) return 3;
    }
    else
    {
        bottomStart = arena.mesh(id).vertexCount;
        foreach (i; 0 .. segments)
        {
            auto angle = (2.0 * WC_PI * cast(double)i) / cast(double)segments;
            if (!arena.addVertex(id, MeshVec3((cx+r1*cos(angle))*scale,(cy+r1*sin(angle))*scale,z0*scale))) return 4;
        }
        if (!arena.addVertex(id, MeshVec3(cx*scale,cy*scale,z0*scale), &bottomCentre)) return 5;
    }

    if (topApex)
    {
        if (!arena.addVertex(id, MeshVec3(cx*scale, cy*scale, z1*scale), &topStart)) return 6;
    }
    else
    {
        topStart = arena.mesh(id).vertexCount;
        foreach (i; 0 .. segments)
        {
            auto angle = (2.0 * WC_PI * cast(double)i) / cast(double)segments;
            if (!arena.addVertex(id, MeshVec3((cx+r2*cos(angle))*scale,(cy+r2*sin(angle))*scale,z1*scale))) return 7;
        }
        if (!arena.addVertex(id, MeshVec3(cx*scale,cy*scale,z1*scale), &topCentre)) return 8;
    }

    foreach (i; 0 .. segments)
    {
        auto next = (i + 1) % segments;
        if (bottomApex)
        {
            if (!addTriangle(arena,id,bottomStart,topStart+i,topStart+next,options.reverseWinding)) return 9;
        }
        else if (topApex)
        {
            if (!addTriangle(arena,id,bottomStart+i,bottomStart+next,topStart,options.reverseWinding)) return 10;
        }
        else
        {
            if (!addTriangle(arena,id,bottomStart+i,bottomStart+next,topStart+next,options.reverseWinding)) return 11;
            if (!addTriangle(arena,id,bottomStart+i,topStart+next,topStart+i,options.reverseWinding)) return 12;
        }
        if (!bottomApex && !addTriangle(arena,id,bottomCentre,bottomStart+next,bottomStart+i,options.reverseWinding)) return 13;
        if (!topApex && !addTriangle(arena,id,topCentre,topStart+i,topStart+next,options.reverseWinding)) return 14;
    }
    return 0;
}

private int tessellateSphere(MeshArena* arena, MeshId id, const BRepSolid* solid, const OpenScadExportOptions* options) nothrow @nogc
{
    auto radius = solid.primitiveA;
    auto segments = segmentsForRadius(radius, options);
    auto stacks = segments / 2;
    if (stacks < 4) stacks = 4;
    auto cx = (solid.bounds.minimum.x + solid.bounds.maximum.x) * 0.5;
    auto cy = (solid.bounds.minimum.y + solid.bounds.maximum.y) * 0.5;
    auto cz = (solid.bounds.minimum.z + solid.bounds.maximum.z) * 0.5;
    auto scale = options.unitScale;

    uint north = 0;
    if (!arena.addVertex(id, MeshVec3(cx*scale,cy*scale,(cz+radius)*scale), &north)) return 15;
    uint firstRing = arena.mesh(id).vertexCount;
    foreach (stack; 1 .. stacks)
    {
        auto phi = WC_PI * cast(double)stack / cast(double)stacks;
        auto ringRadius = radius * sin(phi);
        auto z = cz + radius * cos(phi);
        foreach (slice; 0 .. segments)
        {
            auto theta = 2.0 * WC_PI * cast(double)slice / cast(double)segments;
            if (!arena.addVertex(id, MeshVec3((cx+ringRadius*cos(theta))*scale,(cy+ringRadius*sin(theta))*scale,z*scale))) return 16;
        }
    }
    uint south = 0;
    if (!arena.addVertex(id, MeshVec3(cx*scale,cy*scale,(cz-radius)*scale), &south)) return 17;

    foreach (slice; 0 .. segments)
    {
        auto next = (slice + 1) % segments;
        if (!addTriangle(arena,id,north,firstRing+slice,firstRing+next,options.reverseWinding)) return 18;
    }
    foreach (stack; 0 .. stacks - 2)
    {
        auto ringA = firstRing + stack * segments;
        auto ringB = ringA + segments;
        foreach (slice; 0 .. segments)
        {
            auto next = (slice + 1) % segments;
            if (!addTriangle(arena,id,ringA+slice,ringB+slice,ringB+next,options.reverseWinding)) return 19;
            if (!addTriangle(arena,id,ringA+slice,ringB+next,ringA+next,options.reverseWinding)) return 20;
        }
    }
    auto lastRing = firstRing + (stacks - 2) * segments;
    foreach (slice; 0 .. segments)
    {
        auto next = (slice + 1) % segments;
        if (!addTriangle(arena,id,south,lastRing+next,lastRing+slice,options.reverseWinding)) return 21;
    }
    return 0;
}

int tessellateSolid(MeshArena* arena, const BRepSolid* solid, const OpenScadExportOptions* options, MeshId* result) nothrow @nogc
{
    if (arena is null || solid is null || options is null || result is null || !solid.bounds.valid)
        return 1;
    auto id = arena.beginMesh();
    if (id == 0) return 2;
    int rc = 0;
    final switch (solid.primitiveKind)
    {
        case BRepPrimitiveKind.box:
            rc = tessellateBox(arena,id,solid,options); break;
        case BRepPrimitiveKind.cylinder:
        case BRepPrimitiveKind.coneFrustum:
            rc = tessellateCylinderLike(arena,id,solid,options); break;
        case BRepPrimitiveKind.sphere:
            rc = tessellateSphere(arena,id,solid,options); break;
        case BRepPrimitiveKind.torus:
        case BRepPrimitiveKind.boxShell:
        case BRepPrimitiveKind.generic:
            // General B-rep tessellation lives in tessellate_brep.d.
            rc = 30; break;
    }
    if (rc == 0)
    {
        if (options.centreEachBody)
        {
            auto mesh = arena.mesh(id);
            if (mesh !is null && mesh.bounds.valid)
            {
                auto cx = (mesh.bounds.minimum.x + mesh.bounds.maximum.x) * 0.5;
                auto cy = (mesh.bounds.minimum.y + mesh.bounds.maximum.y) * 0.5;
                auto cz = (mesh.bounds.minimum.z + mesh.bounds.maximum.z) * 0.5;
                arena.translateMesh(id,-cx,-cy,-cz);
            }
        }
        *result = id;
    }
    return rc;
}



