module waifucad.interchange.openscad.roundtrip;

import core.stdc.stdio : FILE, fopen, fclose, fgets, sscanf, snprintf;
import core.stdc.string : strstr;
import waifucad.kernel.model : Model;
import waifucad.mesh.types : MeshId, MeshVec3;
import waifucad.mesh.off_io : meshIsClosedManifold;
import waifucad.interchange.openscad.options : OpenScadImportOptions;

private bool isDegenerate(uint a, uint b, uint c) nothrow @nogc
{
    return a == b || b == c || a == c;
}

bool isWaifuCadDumbScad(const(char)* path) nothrow @nogc
{
    auto file = fopen(path, "rb".ptr);
    if (file is null) return false;
    char[512] line;
    bool found = false;
    uint lines = 0;
    while (lines++ < 32 && fgets(line.ptr, cast(int)line.length, file) !is null)
    {
        if (strstr(line.ptr, "WaifuCAD dumb-body OpenSCAD export".ptr) !is null || strstr(line.ptr, "// wc-body-begin".ptr) == line.ptr)
        {
            found = true;
            break;
        }
    }
    fclose(file);
    return found;
}

/*
 * Dependency-free reader for WaifuCAD's own polyhedron-only SCAD exports.
 * Arbitrary OpenSCAD source is handled by the external OpenSCAD evaluator.
 */
int importWaifuCadDumbScad(Model* model, const(char)* path, const(char)* baseName,
                           const OpenScadImportOptions* options, uint* importedBodies) nothrow @nogc
{
    if (model is null || path is null || baseName is null || options is null)
        return 1;
    if (importedBodies !is null) *importedBodies = 0;
    auto file = fopen(path, "rb".ptr);
    if (file is null) return 2;

    auto oldMeshCount = model.dumbMeshes.meshCount;
    auto oldVertexCount = model.dumbMeshes.vertexCount;
    auto oldTriangleCount = model.dumbMeshes.triangleCount;
    auto oldFeatureCount = model.featureCount;
    auto oldNextId = model.nextId;

    char[4096] line;
    char[64] sourceName;
    MeshId currentMesh = 0;
    uint bodyNumber = 0;
    int failure = 0;
    while (fgets(line.ptr, cast(int)line.length, file) !is null)
    {
        if (strstr(line.ptr, "// wc-body-begin".ptr) == line.ptr)
        {
            if (currentMesh != 0) { failure = 3; break; }
            sourceName[0] = 0;
            sscanf(line.ptr, "// wc-body-begin %63s", sourceName.ptr);
            currentMesh = model.dumbMeshes.beginMesh(options.preserveSourcePath ? path : null);
            if (currentMesh == 0) { failure = 4; break; }
            continue;
        }
        if (strstr(line.ptr, "// wc-vertex".ptr) == line.ptr)
        {
            if (currentMesh == 0) { failure = 5; break; }
            MeshVec3 point;
            if (sscanf(line.ptr, "// wc-vertex %lf %lf %lf", &point.x, &point.y, &point.z) != 3) { failure = 6; break; }
            point.x *= options.unitScale; point.y *= options.unitScale; point.z *= options.unitScale;
            if (!model.dumbMeshes.addVertex(currentMesh, point)) { failure = 7; break; }
            continue;
        }
        if (strstr(line.ptr, "// wc-triangle".ptr) == line.ptr)
        {
            if (currentMesh == 0) { failure = 8; break; }
            uint a, b, c;
            if (sscanf(line.ptr, "// wc-triangle %u %u %u", &a, &b, &c) != 3) { failure = 9; break; }
            if (options.reverseWinding) { auto t = b; b = c; c = t; }
            if (options.dropDegenerateTriangles && isDegenerate(a,b,c)) continue;
            auto mesh = model.dumbMeshes.mesh(currentMesh);
            if (mesh is null || mesh.triangleCount >= options.maxTriangles || !model.dumbMeshes.addTriangle(currentMesh,a,b,c)) { failure = 10; break; }
            continue;
        }
        if (strstr(line.ptr, "// wc-body-end".ptr) == line.ptr)
        {
            if (currentMesh == 0) { failure = 11; break; }
            auto mesh = model.dumbMeshes.mesh(currentMesh);
            if (mesh is null || mesh.vertexCount > options.maxVertices) { failure = 12; break; }
            mesh.sourceFormat.set("OpenSCAD/polyhedron".ptr);
            mesh.convexityHint = options.convexity;
            if (options.centreOnOrigin && mesh.bounds.valid)
            {
                auto cx=(mesh.bounds.minimum.x+mesh.bounds.maximum.x)*0.5;
                auto cy=(mesh.bounds.minimum.y+mesh.bounds.maximum.y)*0.5;
                auto cz=(mesh.bounds.minimum.z+mesh.bounds.maximum.z)*0.5;
                model.dumbMeshes.translateMesh(currentMesh,-cx,-cy,-cz);
            }
            if (options.requireClosedMesh && !meshIsClosedManifold(&model.dumbMeshes,currentMesh)) { failure = 13; break; }
            char[64] featureName;
            ++bodyNumber;
            if (bodyNumber == 1)
                snprintf(featureName.ptr, featureName.length, "%s", baseName);
            else
                snprintf(featureName.ptr, featureName.length, "%s_%u", baseName, bodyNumber);
            if (model.addDumbMeshFeature(featureName.ptr,currentMesh,path) == 0) { failure = 14; break; }
            currentMesh = 0;
        }
    }
    fclose(file);
    if (currentMesh != 0 && failure == 0) failure = 15;
    if (bodyNumber == 0 && failure == 0) failure = 16;

    if (failure != 0)
    {
        model.dumbMeshes.meshCount = oldMeshCount;
        model.dumbMeshes.vertexCount = oldVertexCount;
        model.dumbMeshes.triangleCount = oldTriangleCount;
        model.featureCount = oldFeatureCount;
        model.nextId = oldNextId;
        return failure;
    }
    if (importedBodies !is null) *importedBodies = bodyNumber;
    return 0;
}



