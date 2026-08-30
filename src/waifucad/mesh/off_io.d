module waifucad.mesh.off_io;

import core.stdc.ctype : isspace;
import core.stdc.math : fabs;
import core.stdc.stdio : FILE, fopen, fclose, fgetc, ungetc, EOF;
import core.stdc.stdlib : strtod, strtoul, malloc, free, qsort;
import core.stdc.string : strcmp;
import waifucad.mesh.types : MeshArena, MeshId, MeshVec3, MeshTriangle, WC_MESH_MAX_VERTICES;
import waifucad.interchange.openscad.options : OpenScadImportOptions;

private bool nextToken(FILE* file, char* buffer, size_t capacity) nothrow @nogc
{
    if (file is null || buffer is null || capacity < 2)
        return false;
    int ch;
    for (;;)
    {
        ch = fgetc(file);
        while (ch != EOF && isspace(ch))
            ch = fgetc(file);
        if (ch == '#')
        {
            while (ch != EOF && ch != '\n')
                ch = fgetc(file);
            continue;
        }
        break;
    }
    if (ch == EOF)
        return false;

    size_t used = 0;
    while (ch != EOF && !isspace(ch) && ch != '#')
    {
        if (used + 1 >= capacity)
            return false;
        buffer[used++] = cast(char)ch;
        ch = fgetc(file);
    }
    if (ch == '#')
        while (ch != EOF && ch != '\n')
            ch = fgetc(file);
    buffer[used] = 0;
    return used != 0;
}

private bool parseUnsigned(FILE* file, uint* value) nothrow @nogc
{
    char[64] token;
    if (!nextToken(file, token.ptr, token.length))
        return false;
    const(char)* end = null;
    auto parsed = strtoul(cast(const(char)*)token.ptr, &end, 10);
    if (end is token.ptr || *end != 0 || parsed > uint.max)
        return false;
    *value = cast(uint)parsed;
    return true;
}

private bool parseDouble(FILE* file, double* value) nothrow @nogc
{
    char[96] token;
    if (!nextToken(file, token.ptr, token.length))
        return false;
    const(char)* end = null;
    auto parsed = strtod(cast(const(char)*)token.ptr, &end);
    if (end is token.ptr || *end != 0)
        return false;
    *value = parsed;
    return true;
}

private double squaredDistance(const MeshVec3* a, const MeshVec3* b) nothrow @nogc
{
    auto dx = a.x - b.x;
    auto dy = a.y - b.y;
    auto dz = a.z - b.z;
    return dx * dx + dy * dy + dz * dz;
}

private bool triangleDegenerate(const MeshArena* arena, MeshId meshId, uint a, uint b, uint c, double tolerance) nothrow @nogc
{
    if (a == b || b == c || a == c)
        return true;
    auto mesh = arena.mesh(meshId);
    if (mesh is null)
        return true;
    auto pa = &arena.vertices[mesh.firstVertex + a];
    auto pb = &arena.vertices[mesh.firstVertex + b];
    auto pc = &arena.vertices[mesh.firstVertex + c];
    auto abx = pb.x - pa.x; auto aby = pb.y - pa.y; auto abz = pb.z - pa.z;
    auto acx = pc.x - pa.x; auto acy = pc.y - pa.y; auto acz = pc.z - pa.z;
    auto cx = aby * acz - abz * acy;
    auto cy = abz * acx - abx * acz;
    auto cz = abx * acy - aby * acx;
    auto area4 = cx * cx + cy * cy + cz * cz;
    auto threshold = tolerance > 0.0 ? tolerance * tolerance * tolerance * tolerance : 1.0e-24;
    return area4 <= threshold;
}

private struct EdgeUse
{
    uint low;
    uint high;
    byte direction;
}

extern(C) private int compareEdges(const(void)* lhs, const(void)* rhs) nothrow @nogc
{
    auto a = cast(const(EdgeUse)*)lhs;
    auto b = cast(const(EdgeUse)*)rhs;
    if (a.low < b.low) return -1;
    if (a.low > b.low) return 1;
    if (a.high < b.high) return -1;
    if (a.high > b.high) return 1;
    return 0;
}

private void setEdge(EdgeUse* edge, uint a, uint b) nothrow @nogc
{
    if (a < b)
    {
        edge.low = a; edge.high = b; edge.direction = 1;
    }
    else
    {
        edge.low = b; edge.high = a; edge.direction = -1;
    }
}

bool meshIsClosedManifold(const MeshArena* arena, MeshId meshId) nothrow @nogc
{
    auto mesh = arena.mesh(meshId);
    if (mesh is null || mesh.triangleCount == 0)
        return false;
    auto edgeCount = cast(size_t)mesh.triangleCount * 3u;
    auto bytes = edgeCount * EdgeUse.sizeof;
    auto edges = cast(EdgeUse*)malloc(bytes);
    if (edges is null)
        return false;

    foreach (i; 0 .. mesh.triangleCount)
    {
        auto triangle = &arena.triangles[mesh.firstTriangle + i];
        setEdge(&edges[i * 3 + 0], triangle.a, triangle.b);
        setEdge(&edges[i * 3 + 1], triangle.b, triangle.c);
        setEdge(&edges[i * 3 + 2], triangle.c, triangle.a);
    }
    qsort(edges, edgeCount, EdgeUse.sizeof, &compareEdges);

    bool closed = true;
    size_t cursor = 0;
    while (cursor < edgeCount)
    {
        auto begin = cursor;
        auto low = edges[cursor].low;
        auto high = edges[cursor].high;
        int directionSum = 0;
        while (cursor < edgeCount && edges[cursor].low == low && edges[cursor].high == high)
        {
            directionSum += edges[cursor].direction;
            ++cursor;
        }
        if (cursor - begin != 2 || directionSum != 0)
        {
            closed = false;
            break;
        }
    }
    free(edges);
    return closed;
}

/* Reads text OFF and triangulates polygon faces as a fan when requested. */
int readOffMesh(MeshArena* arena, const(char)* path, const OpenScadImportOptions* options, MeshId* result) nothrow @nogc
{
    if (arena is null || path is null || options is null || result is null)
        return 1;
    *result = 0;
    auto file = fopen(path, "rb".ptr);
    if (file is null)
        return 2;

    auto oldMeshCount = arena.meshCount;
    auto oldVertexCount = arena.vertexCount;
    auto oldTriangleCount = arena.triangleCount;
    int failure = 0;

    char[64] header;
    if (!nextToken(file, header.ptr, header.length) || strcmp(header.ptr, "OFF".ptr) != 0)
        failure = 3;

    uint sourceVertices = 0, sourceFaces = 0, ignoredEdges = 0;
    if (failure == 0 && (!parseUnsigned(file, &sourceVertices) || !parseUnsigned(file, &sourceFaces) || !parseUnsigned(file, &ignoredEdges)))
        failure = 4;
    if (failure == 0 && (sourceVertices > options.maxVertices || sourceVertices > WC_MESH_MAX_VERTICES || sourceFaces > options.maxTriangles * 2u))
        failure = 5;

    MeshId meshId = 0;
    uint[WC_MESH_MAX_VERTICES] indexMap;
    if (failure == 0)
    {
        meshId = arena.beginMesh(options.preserveSourcePath ? path : null);
        if (meshId == 0)
            failure = 6;
    }

    if (failure == 0)
    {
        auto weld2 = options.weldTolerance * options.weldTolerance;
        foreach (sourceIndex; 0 .. sourceVertices)
        {
            MeshVec3 point;
            if (!parseDouble(file, &point.x) || !parseDouble(file, &point.y) || !parseDouble(file, &point.z))
            {
                failure = 7;
                break;
            }
            point.x *= options.unitScale;
            point.y *= options.unitScale;
            point.z *= options.unitScale;

            uint storedIndex = uint.max;
            auto target = arena.mesh(meshId);
            if (weld2 > 0.0 && target !is null)
            {
                foreach (candidate; 0 .. target.vertexCount)
                {
                    auto existing = &arena.vertices[target.firstVertex + candidate];
                    if (squaredDistance(existing, &point) <= weld2)
                    {
                        storedIndex = candidate;
                        break;
                    }
                }
            }
            if (storedIndex == uint.max && !arena.addVertex(meshId, point, &storedIndex))
            {
                failure = 8;
                break;
            }
            indexMap[sourceIndex] = storedIndex;
        }
    }

    if (failure == 0)
    {
        foreach (_; 0 .. sourceFaces)
        {
            uint faceVertices = 0;
            if (!parseUnsigned(file, &faceVertices) || faceVertices < 3)
            {
                failure = 9;
                break;
            }
            if (!options.triangulatePolygons && faceVertices != 3)
            {
                failure = 10;
                break;
            }
            uint first = 0, previous = 0;
            if (!parseUnsigned(file, &first) || !parseUnsigned(file, &previous) || first >= sourceVertices || previous >= sourceVertices)
            {
                failure = 11;
                break;
            }
            foreach (corner; 2 .. faceVertices)
            {
                uint current = 0;
                if (!parseUnsigned(file, &current) || current >= sourceVertices)
                {
                    failure = 12;
                    break;
                }
                uint a = indexMap[first], b = indexMap[previous], c = indexMap[current];
                if (options.reverseWinding)
                {
                    auto swap = b; b = c; c = swap;
                }
                if (!(options.dropDegenerateTriangles && triangleDegenerate(arena, meshId, a, b, c, options.weldTolerance)))
                {
                    auto target = arena.mesh(meshId);
                    if (target is null || target.triangleCount >= options.maxTriangles || !arena.addTriangle(meshId, a, b, c))
                    {
                        failure = 13;
                        break;
                    }
                }
                previous = current;
            }
            if (failure != 0)
                break;
        }
    }

    fclose(file);

    if (failure == 0 && options.centreOnOrigin)
    {
        auto target = arena.mesh(meshId);
        if (target !is null && target.bounds.valid)
        {
            auto cx = (target.bounds.minimum.x + target.bounds.maximum.x) * 0.5;
            auto cy = (target.bounds.minimum.y + target.bounds.maximum.y) * 0.5;
            auto cz = (target.bounds.minimum.z + target.bounds.maximum.z) * 0.5;
            arena.translateMesh(meshId, -cx, -cy, -cz);
        }
    }

    if (failure == 0 && options.requireClosedMesh)
    {
        if (!meshIsClosedManifold(arena, meshId))
            failure = 14;
        else
        {
            auto target = arena.mesh(meshId);
            if (target !is null) target.closedHint = true;
        }
    }

    if (failure != 0)
    {
        arena.meshCount = oldMeshCount;
        arena.vertexCount = oldVertexCount;
        arena.triangleCount = oldTriangleCount;
        return failure;
    }
    *result = meshId;
    return 0;
}



