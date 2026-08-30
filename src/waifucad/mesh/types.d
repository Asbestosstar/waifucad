module waifucad.mesh.types;

import waifucad.core.fixed_string : FixedString64, FixedString256;

alias MeshId = uint;

enum WC_MESH_MAX_MESHES = 64;
enum WC_MESH_MAX_VERTICES = 16384;
enum WC_MESH_MAX_TRIANGLES = 32768;

struct MeshVec3
{
    double x;
    double y;
    double z;
}

struct MeshTriangle
{
    uint a;
    uint b;
    uint c;
}

struct MeshBounds
{
    MeshVec3 minimum;
    MeshVec3 maximum;
    bool valid;
}

struct DumbMesh
{
    MeshId id;
    uint firstVertex;
    uint vertexCount;
    uint firstTriangle;
    uint triangleCount;
    MeshBounds bounds;
    FixedString256 sourcePath;
    FixedString64 sourceFormat;
    uint convexityHint;
    bool closedHint;
}

/*
 * Dumb meshes deliberately live outside WaifuBRep. They are the correct home
 * for imported tessellated data and flattened interchange output: useful CAD
 * geometry, but with no invented sketch or feature-history associativity.
 */
struct MeshArena
{
    DumbMesh[WC_MESH_MAX_MESHES] meshes;
    MeshVec3[WC_MESH_MAX_VERTICES] vertices;
    MeshTriangle[WC_MESH_MAX_TRIANGLES] triangles;
    size_t meshCount;
    size_t vertexCount;
    size_t triangleCount;

    void clear() nothrow @nogc
    {
        meshCount = 0;
        vertexCount = 0;
        triangleCount = 0;
    }

    DumbMesh* mesh(MeshId id) nothrow @nogc
    {
        return id == 0 || id > meshCount ? null : &meshes[id - 1];
    }

    const(DumbMesh)* mesh(MeshId id) const nothrow @nogc
    {
        return id == 0 || id > meshCount ? null : &meshes[id - 1];
    }

    MeshId beginMesh(const(char)* sourcePath = null) nothrow @nogc
    {
        if (meshCount >= meshes.length)
            return 0;
        auto slot = &meshes[meshCount];
        *slot = DumbMesh.init;
        slot.id = cast(MeshId)(meshCount + 1);
        slot.firstVertex = cast(uint)vertexCount;
        slot.firstTriangle = cast(uint)triangleCount;
        slot.sourcePath.set(sourcePath);
        slot.sourceFormat.set("mesh".ptr);
        ++meshCount;
        return slot.id;
    }

    bool addVertex(MeshId meshId, MeshVec3 point, uint* localIndex = null) nothrow @nogc
    {
        auto target = mesh(meshId);
        if (target is null || vertexCount >= vertices.length)
            return false;
        if (localIndex !is null)
            *localIndex = target.vertexCount;
        vertices[vertexCount++] = point;
        ++target.vertexCount;
        if (!target.bounds.valid)
        {
            target.bounds.minimum = point;
            target.bounds.maximum = point;
            target.bounds.valid = true;
        }
        else
        {
            if (point.x < target.bounds.minimum.x) target.bounds.minimum.x = point.x;
            if (point.y < target.bounds.minimum.y) target.bounds.minimum.y = point.y;
            if (point.z < target.bounds.minimum.z) target.bounds.minimum.z = point.z;
            if (point.x > target.bounds.maximum.x) target.bounds.maximum.x = point.x;
            if (point.y > target.bounds.maximum.y) target.bounds.maximum.y = point.y;
            if (point.z > target.bounds.maximum.z) target.bounds.maximum.z = point.z;
        }
        return true;
    }

    bool addTriangle(MeshId meshId, uint a, uint b, uint c) nothrow @nogc
    {
        auto target = mesh(meshId);
        if (target is null || triangleCount >= triangles.length ||
            a >= target.vertexCount || b >= target.vertexCount || c >= target.vertexCount)
            return false;
        triangles[triangleCount++] = MeshTriangle(a, b, c);
        ++target.triangleCount;
        return true;
    }

    MeshVec3* vertexForMesh(MeshId meshId, uint localIndex) nothrow @nogc
    {
        auto target = mesh(meshId);
        if (target is null || localIndex >= target.vertexCount)
            return null;
        return &vertices[target.firstVertex + localIndex];
    }

    MeshTriangle* triangleForMesh(MeshId meshId, uint localIndex) nothrow @nogc
    {
        auto target = mesh(meshId);
        if (target is null || localIndex >= target.triangleCount)
            return null;
        return &triangles[target.firstTriangle + localIndex];
    }

    bool translateMesh(MeshId meshId, double dx, double dy, double dz) nothrow @nogc
    {
        auto target = mesh(meshId);
        if (target is null)
            return false;
        foreach (i; 0 .. target.vertexCount)
        {
            auto point = &vertices[target.firstVertex + i];
            point.x += dx;
            point.y += dy;
            point.z += dz;
        }
        if (target.bounds.valid)
        {
            target.bounds.minimum.x += dx; target.bounds.maximum.x += dx;
            target.bounds.minimum.y += dy; target.bounds.maximum.y += dy;
            target.bounds.minimum.z += dz; target.bounds.maximum.z += dz;
        }
        return true;
    }
}



