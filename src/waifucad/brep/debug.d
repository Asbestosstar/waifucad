module waifucad.brep.debug;

import core.stdc.stdio : fprintf, stdout;
import waifucad.brep.properties : massProperties;
import waifucad.brep.types : BRepArena, BRepId;
import waifucad.brep.validate : validateClosedSolid;

void dumpBRep(BRepArena* arena) nothrow @nogc
{
    if (arena is null)
        return;
    fprintf(stdout,
        "WaifuBRep: solids=%u shells=%u faces=%u loops=%u coedges=%u edges=%u vertices=%u\n",
        cast(uint)arena.solidCount,
        cast(uint)arena.shellCount,
        cast(uint)arena.faceCount,
        cast(uint)arena.loopCount,
        cast(uint)arena.coedgeCount,
        cast(uint)arena.edgeCount,
        cast(uint)arena.vertexCount);

    foreach (i; 0 .. arena.solidCount)
    {
        auto id = cast(BRepId)(i + 1);
        auto solid = arena.solid(id);
        if (solid is null)
            continue;
        auto properties = massProperties(arena, id);
        fprintf(stdout,
            "  solid #%u kind=%u V=%u E=%u F=%u shell=%u closed_check=%d bounds=[%.3f %.3f %.3f]..[%.3f %.3f %.3f]",
            id,
            cast(uint)solid.primitiveKind,
            solid.vertexCount,
            solid.edgeCount,
            solid.faceCount,
            solid.shell,
            validateClosedSolid(arena, id),
            solid.bounds.minimum.x, solid.bounds.minimum.y, solid.bounds.minimum.z,
            solid.bounds.maximum.x, solid.bounds.maximum.y, solid.bounds.maximum.z);
        if (properties.valid)
            fprintf(stdout, " volume=%.6f area=%.6f centre=[%.3f %.3f %.3f]",
                    properties.volume, properties.surfaceArea,
                    properties.centreOfMass.x, properties.centreOfMass.y, properties.centreOfMass.z);
        fprintf(stdout, "\n");
    }
}

