module waifucad.mesh.payload_io;

import core.stdc.ctype : isspace;
import core.stdc.stdlib : strtod, strtoul;
import waifucad.mesh.types : MeshArena, MeshId, MeshVec3;

private void skipSpaceAndBrackets(const(char)** cursor) nothrow @nogc
{
    while (**cursor != 0 && (isspace(cast(ubyte)**cursor) || **cursor == '[' || **cursor == ']'))
        *cursor = *cursor + 1;
}

private bool readDouble(const(char)** cursor, double* value) nothrow @nogc
{
    skipSpaceAndBrackets(cursor);
    const(char)* end = null;
    auto parsed = strtod(*cursor, &end);
    if (end is *cursor) return false;
    *value = parsed;
    *cursor = end;
    return true;
}

private bool readIndex(const(char)** cursor, uint* value) nothrow @nogc
{
    skipSpaceAndBrackets(cursor);
    const(char)* end = null;
    auto parsed = strtoul(*cursor, &end, 10);
    if (end is *cursor || parsed > uint.max) return false;
    *value = cast(uint)parsed;
    *cursor = end;
    return true;
}

private bool consume(const(char)** cursor, char expected) nothrow @nogc
{
    skipSpaceAndBrackets(cursor);
    if (**cursor != expected) return false;
    *cursor = *cursor + 1;
    return true;
}

/* Converts SCL's compact polyhedron point/face payload into a real dumb mesh. */
int meshFromPolyhedronPayload(MeshArena* arena, const(char)* points, const(char)* faces, MeshId* result) nothrow @nogc
{
    if (arena is null || points is null || faces is null || result is null) return 1;
    *result = 0;
    auto id = arena.beginMesh("SCL polyhedron".ptr);
    if (id == 0) return 2;

    auto cursor = points;
    while (true)
    {
        skipSpaceAndBrackets(&cursor);
        if (*cursor == 0) break;
        MeshVec3 point;
        if (!readDouble(&cursor,&point.x) || !consume(&cursor,',') ||
            !readDouble(&cursor,&point.y) || !consume(&cursor,',') ||
            !readDouble(&cursor,&point.z)) return 3;
        if (!arena.addVertex(id,point)) return 4;
        skipSpaceAndBrackets(&cursor);
        if (*cursor == ';' || *cursor == ',') ++cursor;
        else if (*cursor != 0) return 5;
    }

    auto mesh = arena.mesh(id);
    if (mesh is null || mesh.vertexCount < 3) return 6;
    cursor = faces;
    while (true)
    {
        skipSpaceAndBrackets(&cursor);
        if (*cursor == 0) break;
        uint first=0, previous=0;
        if (!readIndex(&cursor,&first) || !consume(&cursor,',') || !readIndex(&cursor,&previous)) return 7;
        if (first>=mesh.vertexCount || previous>=mesh.vertexCount) return 8;
        uint count=2;
        while (true)
        {
            skipSpaceAndBrackets(&cursor);
            if (*cursor == ';' || *cursor == 0) break;
            if (*cursor == ',') ++cursor;
            uint current=0;
            if (!readIndex(&cursor,&current) || current>=mesh.vertexCount) return 9;
            if (!arena.addTriangle(id,first,previous,current)) return 10;
            previous=current;
            ++count;
        }
        if (count<3) return 11;
        if (*cursor==';') ++cursor;
    }
    if (mesh.triangleCount==0) return 12;
    mesh.sourceFormat.set("SCL/polyhedron".ptr);
    *result=id;
    return 0;
}



