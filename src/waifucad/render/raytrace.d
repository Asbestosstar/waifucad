module waifucad.render.raytrace;

/*
 * Ray-traced model renderer for batch-mode screenshots. Where softshot.d
 * favours speed and robustness (orthographic painter's algorithm), this
 * renderer favours fidelity: a perspective camera, BVH-accelerated triangle
 * intersections, hard shadows from a directional key light, cosine-weighted
 * hemisphere ambient occlusion and Blinn-Phong specular highlights.
 *
 * Everything is deterministic — AO uses Halton low-discrepancy samples, the
 * light and camera are fixed by the options — so identical models render
 * byte-identical PNGs, which the test-suite relies on. No floating point
 * accumulation order depends on threads; the loop is strictly serial.
 *
 * Only the C standard library is used, matching the project's betterC
 * dependency-free rule.
 */

import core.stdc.math : cos, sin, sqrt, fabs, tan, pow;
import core.stdc.stdlib : free, malloc, qsort, realloc;
import waifucad.interchange.openscad.options : OpenScadExportOptions;
import waifucad.kernel.model : Model, WC_MAX_FEATURES;
import waifucad.kernel.types : BoundingBox, ExactGeometryStatus;
import waifucad.mesh.types : DumbMesh, MeshArena, MeshId;
import waifucad.mesh.tessellate_brep : tessellateBRepSolid;
import waifucad.render.png : writePngRgb, WC_PNG_MAX_DIMENSION, WC_PNG_OK;
import waifucad.render.softshot : ScreenshotOptions, WC_SHOT_OK,
    WC_SHOT_INVALID_ARGUMENT, WC_SHOT_INVALID_SIZE, WC_SHOT_NO_GEOMETRY,
    WC_SHOT_OUT_OF_MEMORY, WC_SHOT_TESSELLATION_FAILED;

private enum double WC_RAY_PI = 3.14159265358979323846264338327950288;
private enum uint WC_RAY_LEAF_SIZE = 4;
private enum uint WC_RAY_BUILD_MAX_DEPTH = 64;
private enum uint WC_RAY_MAX_AO_SAMPLES = 64;

private struct RayTriangle
{
    double[9] v;   // world-space corners x0 y0 z0 x1 y1 z1 x2 y2 z2
    double[3] n;   // unit face normal (winding-dependent, flipped at shade time)
    double[6] b;   // bounds: minx miny minz maxx maxy maxz
    uint rgb;      // 0xRRGGBB base colour
}

private struct BvhNode
{
    double[6] b;      // bounds
    int left;         // left child node index, or -1 for a leaf
    int right;        // right child node index, or -1 for a leaf
    uint start;       // leaf: first entry in order[]
    uint count;       // leaf: entry count (0 for internal nodes)
}

private struct RayHit
{
    double t;         // ray parameter of the nearest intersection
    double[3] n;      // geometric normal at the hit
    uint rgb;         // base colour of the hit triangle
    bool hit;
}

private immutable uint[8] rayPalette =
    [0x8FB4D9u, 0xD9A08Fu, 0x9FD98Fu, 0xD9D08Fu, 0xB48FD9u, 0x8FD9C8u, 0xD98FB4u, 0xC8C8C8u];
private enum uint rayPreviewRgb = 0xC0A040u;

/* ------------------------------------------------------------------ */
/* Small vector helpers (fixed-size arrays keep this @nogc).          */
/* ------------------------------------------------------------------ */

private void vecSub(const(double)* a, const(double)* b, double* out_) nothrow @nogc
{
    out_[0] = a[0] - b[0];
    out_[1] = a[1] - b[1];
    out_[2] = a[2] - b[2];
}

private void vecCross(const(double)* a, const(double)* b, double* out_) nothrow @nogc
{
    immutable x = a[1] * b[2] - a[2] * b[1];
    immutable y = a[2] * b[0] - a[0] * b[2];
    immutable z = a[0] * b[1] - a[1] * b[0];
    out_[0] = x;
    out_[1] = y;
    out_[2] = z;
}

private double vecDot(const(double)* a, const(double)* b) nothrow @nogc
{
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2];
}

private double vecLength(const(double)* a) nothrow @nogc
{
    return sqrt(vecDot(a, a));
}

private bool vecNormalise(double* a) nothrow @nogc
{
    immutable len = vecLength(a);
    if (len < 1e-300)
        return false;
    a[0] /= len;
    a[1] /= len;
    a[2] /= len;
    return true;
}

/* ------------------------------------------------------------------ */
/* BVH construction: top-down median split on the largest centroid     */
/* axis. A binary tree with L leaves has exactly 2L - 1 nodes, so the  */
/* node array is preallocated to 2n - 1 and needs no growth.           */
/* ------------------------------------------------------------------ */

/* qsort has no context pointer, so the build comparator reads these. The
 * build is strictly serial, so the globals are safe. */
private __gshared const(RayTriangle)* g_sortTriangles;
private __gshared size_t g_sortAxis;

private extern(C) int compareTriangleCentroids(const(void)* lhs, const(void)* rhs) nothrow @nogc
{
    immutable a = *cast(const(uint)*)lhs;
    immutable b = *cast(const(uint)*)rhs;
    immutable ca = g_sortTriangles[a].b[g_sortAxis] + g_sortTriangles[a].b[g_sortAxis + 3];
    immutable cb = g_sortTriangles[b].b[g_sortAxis] + g_sortTriangles[b].b[g_sortAxis + 3];
    if (ca < cb) return -1;
    if (ca > cb) return 1;
    return 0;
}

private void boundsInclude(double* b, const(double)* other) nothrow @nogc
{
    foreach (axis; 0 .. 3)
    {
        if (other[axis] < b[axis]) b[axis] = other[axis];
        if (other[axis + 3] > b[axis + 3]) b[axis + 3] = other[axis + 3];
    }
}

private bool buildBvhNode(const(RayTriangle)* triangles, uint* order,
    uint start, uint count, BvhNode* nodes, uint* nodeCount, uint depth,
    int* outIndex) nothrow @nogc
{
    immutable nodeIndex = *nodeCount;
    ++*nodeCount;
    auto node = &nodes[nodeIndex];
    node.left = -1;
    node.right = -1;
    node.start = start;
    node.count = count;
    node.b[0] = double.max;
    node.b[1] = double.max;
    node.b[2] = double.max;
    node.b[3] = -double.max;
    node.b[4] = -double.max;
    node.b[5] = -double.max;

    double[3] centroidMin = [double.max, double.max, double.max];
    double[3] centroidMax = [-double.max, -double.max, -double.max];
    foreach (i; start .. start + count)
    {
        auto tri = &triangles[order[i]];
        boundsInclude(node.b.ptr, tri.b.ptr);
        foreach (axis; 0 .. 3)
        {
            immutable c = (tri.b[axis] + tri.b[axis + 3]) * 0.5;
            if (c < centroidMin[axis]) centroidMin[axis] = c;
            if (c > centroidMax[axis]) centroidMax[axis] = c;
        }
    }

    if (count <= WC_RAY_LEAF_SIZE || depth >= WC_RAY_BUILD_MAX_DEPTH)
    {
        *outIndex = cast(int)nodeIndex;
        return true;
    }

    size_t axis = 0;
    double widest = centroidMax[0] - centroidMin[0];
    foreach (candidate; 1 .. 3)
    {
        immutable extent = centroidMax[candidate] - centroidMin[candidate];
        if (extent > widest)
        {
            widest = extent;
            axis = candidate;
        }
    }
    if (widest <= 1e-300)
    {
        // All centroids coincide; no useful split exists.
        *outIndex = cast(int)nodeIndex;
        return true;
    }

    g_sortTriangles = triangles;
    g_sortAxis = axis;
    qsort(order + start, count, uint.sizeof, &compareTriangleCentroids);

    immutable half = count / 2;
    int leftIndex = -1, rightIndex = -1;
    if (!buildBvhNode(triangles, order, start, half, nodes, nodeCount, depth + 1, &leftIndex))
        return false;
    if (!buildBvhNode(triangles, order, start + half, count - half, nodes, nodeCount, depth + 1, &rightIndex))
        return false;
    // children were appended after this node, so re-fetch the (stable) slot
    node = &nodes[nodeIndex];
    node.left = leftIndex;
    node.right = rightIndex;
    node.count = 0;
    *outIndex = cast(int)nodeIndex;
    return true;
}

/* ------------------------------------------------------------------ */
/* Intersection routines.                                              */
/* ------------------------------------------------------------------ */

private bool hitBounds(const(double)* b, const(double)* origin,
    const(double)* invDir, double maxT) nothrow @nogc
{
    double tMin = 0.0;
    double tMax = maxT;
    foreach (axis; 0 .. 3)
    {
        immutable t0 = (b[axis] - origin[axis]) * invDir[axis];
        immutable t1 = (b[axis + 3] - origin[axis]) * invDir[axis];
        immutable near = t0 < t1 ? t0 : t1;
        immutable far = t0 > t1 ? t0 : t1;
        if (near > tMin) tMin = near;
        if (far < tMax) tMax = far;
        if (tMin > tMax)
            return false;
    }
    return true;
}

/* Möller–Trumbore, accepting either winding (two-sided). */
private bool hitTriangle(const(RayTriangle)* tri, const(double)* origin,
    const(double)* dir, double maxT, double* outT) nothrow @nogc
{
    double[3] e1, e2, p, tv, q;
    vecSub(tri.v.ptr + 3, tri.v.ptr, e1.ptr);
    vecSub(tri.v.ptr + 6, tri.v.ptr, e2.ptr);
    vecCross(dir, e2.ptr, p.ptr);
    immutable det = vecDot(e1.ptr, p.ptr);
    if (fabs(det) < 1e-300)
        return false;
    immutable invDet = 1.0 / det;
    vecSub(origin, tri.v.ptr, tv.ptr);
    immutable u = vecDot(tv.ptr, p.ptr) * invDet;
    if (u < -1e-12 || u > 1.0 + 1e-12)
        return false;
    vecCross(tv.ptr, e1.ptr, q.ptr);
    immutable v = vecDot(dir, q.ptr) * invDet;
    if (v < -1e-12 || u + v > 1.0 + 1e-12)
        return false;
    immutable t = vecDot(e2.ptr, q.ptr) * invDet;
    if (t <= 1e-9 || t >= maxT)
        return false;
    *outT = t;
    return true;
}

private bool traceRay(const(BvhNode)* nodes, const(uint)* order,
    const(RayTriangle)* triangles, const(double)* origin, const(double)* dir,
    double maxT, RayHit* result, bool stopAtFirst) nothrow @nogc
{
    double[3] invDir;
    foreach (axis; 0 .. 3)
    {
        // A huge signed reciprocal keeps the slab test working for
        // axis-aligned rays without a division by zero.
        immutable d = dir[axis];
        invDir[axis] = fabs(d) < 1e-300 ? (d < 0.0 ? -1e300 : 1e300) : 1.0 / d;
    }

    int[96] stack;
    uint stackCount = 0;
    stack[stackCount++] = 0;
    result.hit = false;
    result.t = maxT;

    while (stackCount > 0)
    {
        immutable nodeIndex = stack[--stackCount];
        auto node = &nodes[nodeIndex];
        if (!hitBounds(node.b.ptr, origin, invDir.ptr, result.t))
            continue;
        if (node.count != 0)
        {
            foreach (i; node.start .. node.start + node.count)
            {
                auto tri = &triangles[order[i]];
                double t = 0.0;
                if (!hitTriangle(tri, origin, dir, result.t, &t))
                    continue;
                result.hit = true;
                result.t = t;
                result.n = tri.n;
                result.rgb = tri.rgb;
                if (stopAtFirst)
                    return true;
            }
        }
        else if (node.left >= 0 && node.right >= 0)
        {
            if (stackCount + 2 > stack.length)
            {
                // A balanced median-split tree cannot get this deep; treat
                // the overflow as a miss rather than corrupting memory.
                continue;
            }
            stack[stackCount++] = node.left;
            stack[stackCount++] = node.right;
        }
    }
    return result.hit;
}

/* ------------------------------------------------------------------ */
/* Deterministic sampling.                                             */
/* ------------------------------------------------------------------ */

private double halton(uint index, uint base) nothrow @nogc
{
    double fraction = 1.0;
    double result = 0.0;
    uint i = index;
    while (i > 0)
    {
        fraction /= base;
        result += fraction * (i % base);
        i /= base;
    }
    return result;
}

/* Cosine-weighted hemisphere direction about n from a Halton sample. */
private void hemisphereDirection(const(double)* n, double u1, double u2, double* out_) nothrow @nogc
{
    immutable r = sqrt(u1);
    immutable phi = 2.0 * WC_RAY_PI * u2;
    immutable lx = r * cos(phi);
    immutable ly = r * sin(phi);
    immutable lz2 = 1.0 - u1;
    immutable lz = lz2 > 0.0 ? sqrt(lz2) : 0.0;

    double[3] tangent;
    double[3] up;
    if (fabs(n[0]) < 0.9)
    {
        up[0] = 1.0; up[1] = 0.0; up[2] = 0.0;
    }
    else
    {
        up[0] = 0.0; up[1] = 1.0; up[2] = 0.0;
    }
    vecCross(n, up.ptr, tangent.ptr);
    vecNormalise(tangent.ptr);
    double[3] bitangent;
    vecCross(n, tangent.ptr, bitangent.ptr);

    foreach (axis; 0 .. 3)
        out_[axis] = tangent[axis] * lx + bitangent[axis] * ly + n[axis] * lz;
    vecNormalise(out_);
}

/* ------------------------------------------------------------------ */
/* Camera. The view rotation convention matches softshot.d: yaw about  */
/* the world Z axis, then pitch about view X with the camera on the    */
/* +view-Y side (above the model for positive pitch), looking along    */
/* -view-Y with view Z up; roll rotates the finished image.            */
/* ------------------------------------------------------------------ */

private struct RayCamera
{
    double[3] origin;   // world-space eye position
    double cy, sy;      // yaw
    double cp, sp;      // pitch
    double cr, sr;      // roll
    double tanHalfX;    // half horizontal field-of-view tangent
    double tanHalfY;    // half vertical field-of-view tangent
    uint width, height;
}

/* Inverse of softshot's rotateView: view -> world direction. */
private void viewDirectionToWorld(const(RayCamera)* camera,
    double vx, double vy, double vz, double* out_) nothrow @nogc
{
    // Undo the pitch about X (note the sign convention shared with
    // softshot.d: view Y = z1*sp - y1*cp, view Z = y1*sp + z1*cp).
    immutable y1 = vz * camera.sp - vy * camera.cp;
    immutable z1 = vy * camera.sp + vz * camera.cp;
    // Undo the yaw about Z.
    out_[0] = vx * camera.cy + y1 * camera.sy;
    out_[1] = -vx * camera.sy + y1 * camera.cy;
    out_[2] = z1;
}

/* ------------------------------------------------------------------ */
/* Geometry collection (mirrors softshot.d's per-feature sources).     */
/* ------------------------------------------------------------------ */

private bool appendRayTriangle(RayTriangle** soup, size_t* count, size_t* capacity,
    const(double)* vertices9, uint rgb) nothrow @nogc
{
    if (*count == *capacity)
    {
        immutable size_t grown = *capacity == 0 ? 1024 : *capacity * 2;
        auto moved = cast(RayTriangle*)realloc(*soup, grown * RayTriangle.sizeof);
        if (moved is null)
            return false;
        *soup = moved;
        *capacity = grown;
    }
    auto slot = &(*soup)[*count];
    foreach (k; 0 .. 9)
        slot.v[k] = vertices9[k];
    double[3] e1, e2;
    vecSub(vertices9 + 3, vertices9, e1.ptr);
    vecSub(vertices9 + 6, vertices9, e2.ptr);
    vecCross(e1.ptr, e2.ptr, slot.n.ptr);
    if (!vecNormalise(slot.n.ptr))
        return true; // degenerate triangle: dropped, a ray could never hit it
    foreach (axis; 0 .. 3)
    {
        double lo = vertices9[axis];
        double hi = vertices9[axis];
        if (vertices9[3 + axis] < lo) lo = vertices9[3 + axis];
        if (vertices9[3 + axis] > hi) hi = vertices9[3 + axis];
        if (vertices9[6 + axis] < lo) lo = vertices9[6 + axis];
        if (vertices9[6 + axis] > hi) hi = vertices9[6 + axis];
        slot.b[axis] = lo;
        slot.b[axis + 3] = hi;
    }
    slot.rgb = rgb;
    ++*count;
    return true;
}

private void includeBoxPoint(double x, double y, double z,
    double* minX, double* minY, double* minZ, double* maxX, double* maxY, double* maxZ) nothrow @nogc
{
    if (x < *minX) *minX = x;
    if (y < *minY) *minY = y;
    if (z < *minZ) *minZ = z;
    if (x > *maxX) *maxX = x;
    if (y > *maxY) *maxY = y;
    if (z > *maxZ) *maxZ = z;
}

/* Add the 12 triangles of an axis-aligned preview box. */
private bool appendPreviewBox(RayTriangle** soup, size_t* count, size_t* capacity,
    const(BoundingBox)* box, uint rgb) nothrow @nogc
{
    double[24] c; // 8 corners, xyz each
    foreach (corner; 0 .. 8)
    {
        c[corner * 3] = (corner & 1) == 0 ? box.minX : box.maxX;
        c[corner * 3 + 1] = (corner & 2) == 0 ? box.minY : box.maxY;
        c[corner * 3 + 2] = (corner & 4) == 0 ? box.minZ : box.maxZ;
    }
    static immutable ubyte[3][12] faces =
        [[0, 2, 1], [1, 2, 3], [4, 5, 6], [5, 7, 6],   // -z, +z
         [0, 1, 4], [1, 5, 4], [2, 6, 3], [3, 6, 7],   // -y, +y
         [0, 4, 2], [2, 4, 6], [1, 3, 5], [3, 7, 5]];  // -x, +x
    foreach (face; faces)
    {
        double[9] vertices;
        foreach (corner; 0 .. 3)
        {
            vertices[corner * 3] = c[face[corner] * 3];
            vertices[corner * 3 + 1] = c[face[corner] * 3 + 1];
            vertices[corner * 3 + 2] = c[face[corner] * 3 + 2];
        }
        if (!appendRayTriangle(soup, count, capacity, vertices.ptr, rgb))
            return false;
    }
    return true;
}

/* ------------------------------------------------------------------ */
/* Main entry point.                                                   */
/* ------------------------------------------------------------------ */

/*
 * Ray-trace the model to a PNG. Shares ScreenshotOptions and the WC_SHOT_*
 * error contract with the flat renderer; aoSamples (0 disables AO) and
 * shadows control the extra fidelity passes. drawAxes has no ray-traced
 * equivalent yet and is ignored.
 */
int renderModelRaytrace(Model* model, const(char)* path, const(ScreenshotOptions)* suppliedOptions) nothrow @nogc
{
    if (model is null || path is null)
        return WC_SHOT_INVALID_ARGUMENT;
    ScreenshotOptions defaults;
    defaults.setDefaults();
    auto options = suppliedOptions is null ? &defaults : suppliedOptions;
    if (options.width == 0 || options.height == 0 ||
        options.width > WC_PNG_MAX_DIMENSION || options.height > WC_PNG_MAX_DIMENSION)
        return WC_SHOT_INVALID_SIZE;
    if (!(options.zoom > 0.0) || options.zoom > 1000.0)
        return WC_SHOT_INVALID_ARGUMENT;

    // All function-scope state is declared before the first goto: D forbids
    // jumping over a declaration that is still in scope at the label.
    int failure = WC_SHOT_OK;
    RayTriangle* soup = null;
    size_t soupCount = 0;
    size_t soupCapacity = 0;
    auto scratch = cast(MeshArena*)malloc(MeshArena.sizeof);
    auto boxes = cast(BoundingBox*)malloc(WC_MAX_FEATURES * BoundingBox.sizeof);
    uint* order = null;
    BvhNode* nodes = null;
    ubyte* rgb = null;
    size_t boxCount = 0;
    double minX = double.max, minY = double.max, minZ = double.max;
    double maxX = -double.max, maxY = -double.max, maxZ = -double.max;
    bool haveGeometry = false;
    RayCamera camera;
    double sceneRadius;

    if (scratch is null || boxes is null)
    {
        failure = WC_SHOT_OUT_OF_MEMORY;
        goto cleanup;
    }

    foreach (i; 0 .. model.featureCount)
    {
        auto feature = &model.features[i];
        const(MeshArena)* arena = null;
        const(DumbMesh)* mesh = null;

        if (feature.meshId != 0)
        {
            arena = &model.dumbMeshes;
            mesh = arena.mesh(feature.meshId);
        }
        else if (model.exactStatus[i] == ExactGeometryStatus.exact)
        {
            scratch.clear();
            OpenScadExportOptions tessOptions;
            tessOptions.setDefaults();
            tessOptions.unitScale = 1.0;
            tessOptions.centreEachBody = false;
            tessOptions.reverseWinding = false;
            MeshId meshId = 0;
            if (tessellateBRepSolid(scratch, &model.exactGeometry, model.exactSolidIds[i],
                    &tessOptions, &meshId) != 0)
            {
                failure = WC_SHOT_TESSELLATION_FAILED;
                goto cleanup;
            }
            arena = scratch;
            mesh = scratch.mesh(meshId);
        }

        if (mesh !is null && mesh.triangleCount != 0)
        {
            immutable uint colour = rayPalette[i % rayPalette.length];
            foreach (t; 0 .. mesh.triangleCount)
            {
                auto tri = &arena.triangles[mesh.firstTriangle + t];
                double[9] vertices;
                uint[3] indices = [tri.a, tri.b, tri.c];
                foreach (corner, index; indices)
                {
                    auto p = &arena.vertices[mesh.firstVertex + index];
                    vertices[corner * 3] = p.x;
                    vertices[corner * 3 + 1] = p.y;
                    vertices[corner * 3 + 2] = p.z;
                    includeBoxPoint(p.x, p.y, p.z, &minX, &minY, &minZ, &maxX, &maxY, &maxZ);
                }
                haveGeometry = true;
                if (!appendRayTriangle(&soup, &soupCount, &soupCapacity, vertices.ptr, colour))
                {
                    failure = WC_SHOT_OUT_OF_MEMORY;
                    goto cleanup;
                }
            }
        }
        else if ((model.exactStatus[i] == ExactGeometryStatus.previewOnly ||
                  model.exactStatus[i] == ExactGeometryStatus.failed) &&
                 model.previewBounds[i].valid && boxCount < WC_MAX_FEATURES)
        {
            // Preview-only bodies appear as solid boxes so occlusions and
            // shadows still behave sensibly in the ray-traced view.
            if (!appendPreviewBox(&soup, &soupCount, &soupCapacity,
                    &model.previewBounds[i], rayPreviewRgb))
            {
                failure = WC_SHOT_OUT_OF_MEMORY;
                goto cleanup;
            }
            includeBoxPoint(model.previewBounds[i].minX, model.previewBounds[i].minY,
                model.previewBounds[i].minZ, &minX, &minY, &minZ, &maxX, &maxY, &maxZ);
            includeBoxPoint(model.previewBounds[i].maxX, model.previewBounds[i].maxY,
                model.previewBounds[i].maxZ, &minX, &minY, &minZ, &maxX, &maxY, &maxZ);
            haveGeometry = true;
            ++boxCount;
        }
    }

    if (!haveGeometry)
    {
        failure = WC_SHOT_NO_GEOMETRY;
        goto cleanup;
    }

    // BVH build: order[] is the permuted triangle index array, nodes[] is
    // preallocated to the binary-tree bound of 2n - 1 nodes.
    order = cast(uint*)malloc(soupCount * uint.sizeof);
    nodes = cast(BvhNode*)malloc((2 * soupCount - 1) * BvhNode.sizeof);
    if (order is null || nodes is null)
    {
        failure = WC_SHOT_OUT_OF_MEMORY;
        goto cleanup;
    }
    {
        uint nodeCount = 0;
        foreach (i; 0 .. soupCount)
            order[i] = cast(uint)i;
        int rootIndex = -1;
        if (!buildBvhNode(soup, order, 0, cast(uint)soupCount, nodes, &nodeCount, 0, &rootIndex) || rootIndex != 0)
        {
            failure = WC_SHOT_OUT_OF_MEMORY;
            goto cleanup;
        }
    }

    // Perspective camera. The bounding sphere's half-diagonal fit guarantees
    // the model is framed at every rotation, like the orthographic renderer.
    {
        immutable dx = maxX - minX, dy = maxY - minY, dz = maxZ - minZ;
        double radius = 0.5 * sqrt(dx * dx + dy * dy + dz * dz);
        if (radius < 1e-9)
            radius = 1.0;
        sceneRadius = radius;

        immutable double degToRad = WC_RAY_PI / 180.0;
        camera.cy = cos(options.yawDegrees * degToRad);
        camera.sy = sin(options.yawDegrees * degToRad);
        camera.cp = cos(options.pitchDegrees * degToRad);
        camera.sp = sin(options.pitchDegrees * degToRad);
        camera.cr = cos(options.rollDegrees * degToRad);
        camera.sr = sin(options.rollDegrees * degToRad);

        immutable tanHalfY = tan(20.0 * degToRad); // 40 degree vertical fov
        immutable aspect = cast(double)options.width / options.height;
        camera.tanHalfY = tanHalfY;
        camera.tanHalfX = tanHalfY * aspect;
        immutable tanFit = aspect < 1.0 ? camera.tanHalfX : tanHalfY;
        immutable distance = radius * 1.2 / (tanFit * options.zoom);
        camera.width = options.width;
        camera.height = options.height;

        // The camera sits at +view-Y (above the model for positive pitch)
        // looking towards -view-Y.
        double[3] eye;
        viewDirectionToWorld(&camera, 0.0, distance, 0.0, eye.ptr);
        camera.origin[0] = eye[0] + (minX + maxX) * 0.5;
        camera.origin[1] = eye[1] + (minY + maxY) * 0.5;
        camera.origin[2] = eye[2] + (minZ + maxZ) * 0.5;
    }

    rgb = cast(ubyte*)malloc(cast(size_t)options.width * options.height * 3u);
    if (rgb is null)
    {
        failure = WC_SHOT_OUT_OF_MEMORY;
        goto cleanup;
    }

    {
        immutable eps = sceneRadius * 1e-5 + 1e-12;
        immutable aoMaxDistance = sceneRadius;
        immutable aoSamples = options.aoSamples > WC_RAY_MAX_AO_SAMPLES
            ? WC_RAY_MAX_AO_SAMPLES : options.aoSamples;

        // Key light direction in world space: the same view-space light the
        // flat renderer uses, mapped through the inverse view rotation.
        double[3] light;
        {
            double[3] lightView = [-0.4182398, 0.7841996, 0.5740797];
            double[3] lightWorld;
            viewDirectionToWorld(&camera, lightView[0], lightView[1], lightView[2], lightWorld.ptr);
            vecNormalise(lightWorld.ptr);
            light = lightWorld;
        }

        immutable ubyte bgR = cast(ubyte)((options.backgroundRgb >> 16) & 0xFFu);
        immutable ubyte bgG = cast(ubyte)((options.backgroundRgb >> 8) & 0xFFu);
        immutable ubyte bgB = cast(ubyte)(options.backgroundRgb & 0xFFu);

        foreach (py; 0 .. options.height)
        {
            foreach (px; 0 .. options.width)
            {
                auto pixel = rgb + (cast(size_t)py * options.width + px) * 3u;

                // Pixel offsets in the image plane, roll applied.
                immutable nxPx = (2.0 * (px + 0.5) / options.width - 1.0) * camera.tanHalfX;
                immutable nyPx = (1.0 - 2.0 * (py + 0.5) / options.height) * camera.tanHalfY;
                immutable rx = nxPx * camera.cr - nyPx * camera.sr;
                immutable ry = nxPx * camera.sr + nyPx * camera.cr;
                double[3] dirView = [rx, -1.0, ry];
                vecNormalise(dirView.ptr);
                double[3] dirWorld;
                viewDirectionToWorld(&camera, dirView[0], dirView[1], dirView[2], dirWorld.ptr);
                vecNormalise(dirWorld.ptr);

                RayHit hit;
                if (!traceRay(nodes, order, soup, camera.origin.ptr, dirWorld.ptr,
                        double.max / 4.0, &hit, false))
                {
                    pixel[0] = bgR;
                    pixel[1] = bgG;
                    pixel[2] = bgB;
                    continue;
                }

                // Two-sided lighting: flip the geometric normal towards the eye.
                double[3] normal = hit.n;
                if (vecDot(normal.ptr, dirWorld.ptr) > 0.0)
                {
                    normal[0] = -normal[0];
                    normal[1] = -normal[1];
                    normal[2] = -normal[2];
                }

                double[3] point;
                foreach (axis; 0 .. 3)
                    point[axis] = camera.origin[axis] + dirWorld[axis] * hit.t + normal[axis] * eps;

                // Hard shadow towards the directional key light.
                double visibility = 1.0;
                if (options.shadows)
                {
                    RayHit shadowHit;
                    if (traceRay(nodes, order, soup, point.ptr, light.ptr,
                            double.max / 4.0, &shadowHit, true))
                        visibility = 0.0;
                }

                // Ambient occlusion from cosine-weighted hemisphere samples.
                double ao = 1.0;
                if (aoSamples > 0)
                {
                    uint occluded = 0;
                    immutable pixelIndex = py * options.width + px;
                    foreach (sample; 0 .. aoSamples)
                    {
                        immutable seed = pixelIndex * aoSamples + sample + 1;
                        double[3] aoDir;
                        hemisphereDirection(normal.ptr, halton(seed, 2), halton(seed, 3), aoDir.ptr);
                        RayHit aoHit;
                        if (traceRay(nodes, order, soup, point.ptr, aoDir.ptr,
                                aoMaxDistance, &aoHit, true))
                            ++occluded;
                    }
                    ao = 1.0 - 0.85 * (cast(double)occluded / aoSamples);
                }

                immutable diffuseRaw = vecDot(normal.ptr, light.ptr);
                immutable diffuse = diffuseRaw > 0.0 ? diffuseRaw * visibility : 0.0;

                // Blinn-Phong specular from the key light.
                double specular = 0.0;
                if (visibility > 0.0)
                {
                    double[3] half_;
                    foreach (axis; 0 .. 3)
                        half_[axis] = light[axis] - dirWorld[axis];
                    if (vecNormalise(half_.ptr))
                    {
                        immutable facing = vecDot(normal.ptr, half_.ptr);
                        if (facing > 0.0)
                            specular = 0.25 * pow(facing, 32.0);
                    }
                }

                immutable baseR = cast(double)((hit.rgb >> 16) & 0xFFu);
                immutable baseG = cast(double)((hit.rgb >> 8) & 0xFFu);
                immutable baseB = cast(double)(hit.rgb & 0xFFu);
                double[3] linear = [
                    baseR * (0.28 * ao + 0.72 * diffuse) + specular * 255.0,
                    baseG * (0.28 * ao + 0.72 * diffuse) + specular * 255.0,
                    baseB * (0.28 * ao + 0.72 * diffuse) + specular * 255.0];
                foreach (channel; 0 .. 3)
                {
                    double unit = linear[channel] / 255.0;
                    if (unit < 0.0) unit = 0.0;
                    if (unit > 1.0) unit = 1.0;
                    // Gentle display gamma; the linear ramp looks too dark.
                    immutable corrected = pow(unit, 1.0 / 1.8);
                    uint value = cast(uint)(corrected * 255.0 + 0.5);
                    if (value > 255u) value = 255u;
                    pixel[channel] = cast(ubyte)value;
                }
            }
        }
    }

    {
        immutable pngRc = writePngRgb(path, rgb, options.width, options.height);
        if (pngRc != WC_PNG_OK)
            failure = 20 + pngRc;
    }

cleanup:
    free(rgb);
    free(nodes);
    free(order);
    free(boxes);
    free(scratch);
    free(soup);
    return failure;
}
