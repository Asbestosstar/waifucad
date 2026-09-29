module waifucad.render.softshot;

/*
 * Headless software renderer for batch-mode model screenshots. AIs and SSH
 * sessions cannot open a GUI viewport, so this rasterises the current model
 * to a PNG with nothing but the C standard library: exact WaifuBRep solids
 * are tessellated, dumb mesh bodies are drawn as-is and preview-only bodies
 * fall back to wireframe bounding boxes.
 *
 * The camera is orthographic with yaw/pitch/roll view rotation around the
 * model centre, flat per-face shading and painter's-algorithm sorting, which
 * is robust for the mostly-convex parts this kernel produces. The camera
 * looks at the model from above (positive world Z side) so tall parts are
 * never hidden behind wide bases.
 */

import core.stdc.math : cos, floor, sin, sqrt, fabs;
import core.stdc.stdlib : free, malloc, qsort, realloc;
import waifucad.interchange.openscad.options : OpenScadExportOptions;
import waifucad.kernel.model : Model, WC_MAX_FEATURES;
import waifucad.kernel.types : BoundingBox, ExactGeometryStatus;
import waifucad.mesh.types : DumbMesh, MeshArena, MeshId;
import waifucad.mesh.tessellate_brep : tessellateBRepSolid;
import waifucad.render.png : WC_PNG_MAX_DIMENSION, WC_PNG_OK, writePngRgb;
import waifucad.render.raytrace : renderModelRaytrace;

private enum double WC_SHOT_PI = 3.14159265358979323846264338327950288;

enum WC_SHOT_OK = 0;
enum WC_SHOT_INVALID_ARGUMENT = 10;
enum WC_SHOT_INVALID_SIZE = 11;
enum WC_SHOT_NO_GEOMETRY = 12;
enum WC_SHOT_OUT_OF_MEMORY = 13;
enum WC_SHOT_TESSELLATION_FAILED = 14;
// PNG writer failures are reported as 20 + the WC_PNG_* code.

// ScreenshotOptions.renderMode values.
enum WC_RENDER_FLAT = 0; // orthographic painter's algorithm (this module)
enum WC_RENDER_RAY = 1;  // perspective ray trace with shadows + AO (raytrace.d)

struct ScreenshotOptions
{
    uint width;           // pixels
    uint height;          // pixels
    double yawDegrees;    // rotation about the model up (Z) axis
    double pitchDegrees;  // tilt of the camera above the XY plane
    double rollDegrees;   // in-plane rotation of the finished image
    double zoom;          // > 1 zooms in, < 1 zooms out
    uint backgroundRgb;   // 0xRRGGBB
    bool drawAxes;        // draw the orientation triad in the corner
    uint renderMode;      // WC_RENDER_FLAT or WC_RENDER_RAY
    uint aoSamples;       // ray mode: hemisphere samples per pixel (0 disables AO)
    bool shadows;         // ray mode: trace hard shadows from the key light

    void setDefaults() nothrow @nogc
    {
        width = 1024;
        height = 768;
        yawDegrees = -45.0;
        pitchDegrees = 35.26438968; // classic isometric tilt
        rollDegrees = 0.0;
        zoom = 1.0;
        backgroundRgb = 0x20242Cu;
        drawAxes = true;
        renderMode = WC_RENDER_FLAT;
        aoSamples = 12;
        shadows = true;
    }
}

// Muted engineering palette cycled per body so adjacent features read apart.
private immutable uint[8] bodyPalette =
    [0x8FB4D9u, 0xD9A08Fu, 0x9FD98Fu, 0xD9D08Fu, 0xB48FD9u, 0x8FD9C8u, 0xD98FB4u, 0xC8C8C8u];
private enum uint previewBoxRgb = 0xC0A040u;

private struct ShotTriangle
{
    double[9] v; // world-space x0 y0 z0 x1 y1 z1 x2 y2 z2
    float depth; // mean view-space depth, filled in before sorting
    uint rgb;    // flat-shaded colour, filled in before sorting
}

private struct ShotView
{
    double cy, sy; // yaw about Z
    double cp, sp; // pitch about X
    double cr, sr; // roll in the image plane
    double centreX, centreY, centreZ;
    double scale; // world unit -> pixels
    uint width, height;
}

private extern(C) int compareShotTriangles(const(void)* lhs, const(void)* rhs) nothrow @nogc
{
    auto a = cast(const(ShotTriangle)*)lhs;
    auto b = cast(const(ShotTriangle)*)rhs;
    // Painter's algorithm: draw far triangles first. The camera sits at
    // +view-Y looking towards -Y, so a smaller view Y is farther away.
    if (a.depth < b.depth) return -1;
    if (a.depth > b.depth) return 1;
    return 0;
}

private void rotateView(const(ShotView)* view, double x, double y, double z,
    double* outX, double* outY, double* outZ) nothrow @nogc
{
    // Yaw about Z, then pitch about X. The camera looks along -view-Y with
    // view X to the right and view Z up on screen. The pitch sign puts the
    // camera above the XY plane (positive world Z is nearer for positive
    // pitch), so tall parts are never hidden behind wide bases.
    immutable x1 = x * view.cy - y * view.sy;
    immutable y1 = x * view.sy + y * view.cy;
    immutable z1 = z;
    *outX = x1;
    *outY = z1 * view.sp - y1 * view.cp;
    *outZ = y1 * view.sp + z1 * view.cp;
}

private void projectVertex(const(ShotView)* view, double x, double y, double z,
    double* pixelX, double* pixelY, double* depth) nothrow @nogc
{
    double vx, vy, vz;
    rotateView(view, x - view.centreX, y - view.centreY, z - view.centreZ, &vx, &vy, &vz);
    immutable sx = vx * view.cr - vz * view.sr;
    immutable sy = vx * view.sr + vz * view.cr;
    *pixelX = view.width * 0.5 + sx * view.scale;
    *pixelY = view.height * 0.5 - sy * view.scale; // image rows run downwards
    *depth = vy;
}

private uint shadeColour(uint baseRgb, double nx, double ny, double nz,
    const(ShotView)* view) nothrow @nogc
{
    double vx, vy, vz;
    rotateView(view, nx, ny, nz, &vx, &vy, &vz);
    immutable length = sqrt(vx * vx + vy * vy + vz * vz);
    if (length < 1e-12)
        return baseRgb;
    // Key light from upper-left-front in view space, normalised.
    immutable lx = -0.4182398, ly = 0.7841996, lz = 0.5740797;
    immutable dot = (vx * lx + vy * ly + vz * lz) / length;
    immutable intensity = 0.30 + 0.70 * fabs(dot); // two-sided lighting
    uint r = cast(uint)((baseRgb >> 16) & 0xFFu);
    uint g = cast(uint)((baseRgb >> 8) & 0xFFu);
    uint b = cast(uint)(baseRgb & 0xFFu);
    r = cast(uint)(r * intensity + 0.5);
    g = cast(uint)(g * intensity + 0.5);
    b = cast(uint)(b * intensity + 0.5);
    if (r > 255u) r = 255u;
    if (g > 255u) g = 255u;
    if (b > 255u) b = 255u;
    return (r << 16) | (g << 8) | b;
}

private void fillTriangle(ubyte* rgb, uint width, uint height,
    double x0, double y0, double x1, double y1, double x2, double y2, uint colour) nothrow @nogc
{
    double minX = x0 < x1 ? x0 : x1;
    if (x2 < minX) minX = x2;
    double maxX = x0 > x1 ? x0 : x1;
    if (x2 > maxX) maxX = x2;
    double minY = y0 < y1 ? y0 : y1;
    if (y2 < minY) minY = y2;
    double maxY = y0 > y1 ? y0 : y1;
    if (y2 > maxY) maxY = y2;

    int ix0 = cast(int)floor(minX);
    int iy0 = cast(int)floor(minY);
    int ix1 = cast(int)floor(maxX);
    int iy1 = cast(int)floor(maxY);
    if (ix0 < 0) ix0 = 0;
    if (iy0 < 0) iy0 = 0;
    if (ix1 > cast(int)width - 1) ix1 = cast(int)width - 1;
    if (iy1 > cast(int)height - 1) iy1 = cast(int)height - 1;
    if (ix0 > ix1 || iy0 > iy1) return;

    immutable ubyte r = cast(ubyte)((colour >> 16) & 0xFFu);
    immutable ubyte g = cast(ubyte)((colour >> 8) & 0xFFu);
    immutable ubyte b = cast(ubyte)(colour & 0xFFu);

    foreach (py; iy0 .. iy1 + 1)
    {
        immutable double cy = py + 0.5;
        foreach (px; ix0 .. ix1 + 1)
        {
            immutable double cx = px + 0.5;
            immutable eA = (cx - x1) * (y2 - y1) - (cy - y1) * (x2 - x1);
            immutable eB = (cx - x2) * (y0 - y2) - (cy - y2) * (x0 - x2);
            immutable eC = (cx - x0) * (y1 - y0) - (cy - y0) * (x1 - x0);
            // Accept either winding so tessellation orientation never matters.
            if (!((eA >= 0.0 && eB >= 0.0 && eC >= 0.0) ||
                  (eA <= 0.0 && eB <= 0.0 && eC <= 0.0)))
                continue;
            auto pixel = rgb + (cast(size_t)py * width + px) * 3u;
            pixel[0] = r;
            pixel[1] = g;
            pixel[2] = b;
        }
    }
}

private void drawLine(ubyte* rgb, uint width, uint height,
    double x0, double y0, double x1, double y1, uint colour) nothrow @nogc
{
    immutable dx = x1 - x0;
    immutable dy = y1 - y0;
    immutable steps = cast(int)(fabs(dx) > fabs(dy) ? fabs(dx) : fabs(dy)) + 1;
    immutable ubyte r = cast(ubyte)((colour >> 16) & 0xFFu);
    immutable ubyte g = cast(ubyte)((colour >> 8) & 0xFFu);
    immutable ubyte b = cast(ubyte)(colour & 0xFFu);
    foreach (s; 0 .. steps + 1)
    {
        immutable t = steps == 0 ? 0.0 : cast(double)s / steps;
        immutable px = cast(int)(x0 + dx * t + 0.5);
        immutable py = cast(int)(y0 + dy * t + 0.5);
        if (px < 0 || py < 0 || px >= cast(int)width || py >= cast(int)height)
            continue;
        auto pixel = rgb + (cast(size_t)py * width + px) * 3u;
        pixel[0] = r;
        pixel[1] = g;
        pixel[2] = b;
    }
}

private void includePoint(double x, double y, double z,
    double* minX, double* minY, double* minZ, double* maxX, double* maxY, double* maxZ) nothrow @nogc
{
    if (x < *minX) *minX = x;
    if (y < *minY) *minY = y;
    if (z < *minZ) *minZ = z;
    if (x > *maxX) *maxX = x;
    if (y > *maxY) *maxY = y;
    if (z > *maxZ) *maxZ = z;
}

private bool appendTriangle(ShotTriangle** soup, size_t* count, size_t* capacity,
    const(double)* vertices9, uint rgb) nothrow @nogc
{
    if (*count == *capacity)
    {
        immutable size_t grown = *capacity == 0 ? 1024 : *capacity * 2;
        auto moved = cast(ShotTriangle*)realloc(*soup, grown * ShotTriangle.sizeof);
        if (moved is null)
            return false;
        *soup = moved;
        *capacity = grown;
    }
    auto slot = &(*soup)[*count];
    foreach (k; 0 .. 9)
        slot.v[k] = vertices9[k];
    slot.depth = 0.0f;
    slot.rgb = rgb;
    ++*count;
    return true;
}

/*
 * Render the model to a PNG screenshot. Returns WC_SHOT_OK on success or a
 * WC_SHOT_* error. The model should already be recomputed; exact solids are
 * tessellated on the fly into scratch memory that is freed before return.
 * WC_RENDER_RAY dispatches to the perspective ray tracer in raytrace.d,
 * which shares this error contract.
 */
int renderModelScreenshot(Model* model, const(char)* path, const(ScreenshotOptions)* suppliedOptions) nothrow @nogc
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
    // Ray-traced mode lives in its own module but shares this entry point
    // and error contract.
    if (options.renderMode == WC_RENDER_RAY)
        return renderModelRaytrace(model, path, options);

    // All function-scope state is declared before the first goto: D forbids
    // jumping over a declaration that is still in scope at the label.
    int failure = WC_SHOT_OK;
    ShotTriangle* soup = null;
    size_t soupCount = 0;
    size_t soupCapacity = 0;
    auto scratch = cast(MeshArena*)malloc(MeshArena.sizeof);
    auto boxes = cast(BoundingBox*)malloc(WC_MAX_FEATURES * BoundingBox.sizeof);
    ubyte* rgb = null;
    size_t boxCount = 0;
    double minX = double.max, minY = double.max, minZ = double.max;
    double maxX = -double.max, maxY = -double.max, maxZ = -double.max;
    bool haveGeometry = false;
    ShotView view;

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
            immutable uint colour = bodyPalette[i % bodyPalette.length];
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
                    includePoint(p.x, p.y, p.z, &minX, &minY, &minZ, &maxX, &maxY, &maxZ);
                }
                haveGeometry = true;
                if (!appendTriangle(&soup, &soupCount, &soupCapacity, vertices.ptr, colour))
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
            // Bodies without exact geometry still deserve a visual placeholder.
            boxes[boxCount++] = model.previewBounds[i];
            includePoint(model.previewBounds[i].minX, model.previewBounds[i].minY,
                model.previewBounds[i].minZ, &minX, &minY, &minZ, &maxX, &maxY, &maxZ);
            includePoint(model.previewBounds[i].maxX, model.previewBounds[i].maxY,
                model.previewBounds[i].maxZ, &minX, &minY, &minZ, &maxX, &maxY, &maxZ);
            haveGeometry = true;
        }
    }

    if (!haveGeometry)
    {
        failure = WC_SHOT_NO_GEOMETRY;
        goto cleanup;
    }

    {
        immutable double degToRad = WC_SHOT_PI / 180.0;
        view.cy = cos(options.yawDegrees * degToRad);
        view.sy = sin(options.yawDegrees * degToRad);
        view.cp = cos(options.pitchDegrees * degToRad);
        view.sp = sin(options.pitchDegrees * degToRad);
        view.cr = cos(options.rollDegrees * degToRad);
        view.sr = sin(options.rollDegrees * degToRad);
    }
    view.centreX = (minX + maxX) * 0.5;
    view.centreY = (minY + maxY) * 0.5;
    view.centreZ = (minZ + maxZ) * 0.5;
    {
        // The half-diagonal bounds every rotation of the model, so the view
        // always fits regardless of yaw/pitch/roll.
        immutable dx = maxX - minX, dy = maxY - minY, dz = maxZ - minZ;
        double radius = 0.5 * sqrt(dx * dx + dy * dy + dz * dz);
        if (radius < 1e-9)
            radius = 1.0;
        immutable double fit = options.width < options.height ? options.width : options.height;
        view.scale = fit * 0.42 * options.zoom / radius;
    }
    view.width = options.width;
    view.height = options.height;

    // Shade and depth-sort far to near.
    foreach (t; 0 .. soupCount)
    {
        auto tri = &soup[t];
        double depthSum = 0.0;
        foreach (corner; 0 .. 3)
        {
            double vx, vy, vz;
            rotateView(&view, tri.v[corner * 3] - view.centreX, tri.v[corner * 3 + 1] - view.centreY,
                tri.v[corner * 3 + 2] - view.centreZ, &vx, &vy, &vz);
            depthSum += vy;
        }
        tri.depth = cast(float)(depthSum / 3.0);
        immutable ux = tri.v[3] - tri.v[0], uy = tri.v[4] - tri.v[1], uz = tri.v[5] - tri.v[2];
        immutable wx = tri.v[6] - tri.v[0], wy = tri.v[7] - tri.v[1], wz = tri.v[8] - tri.v[2];
        tri.rgb = shadeColour(tri.rgb, uy * wz - uz * wy, uz * wx - ux * wz, ux * wy - uy * wx, &view);
    }
    if (soupCount > 1)
        qsort(soup, soupCount, ShotTriangle.sizeof, &compareShotTriangles);

    rgb = cast(ubyte*)malloc(cast(size_t)options.width * options.height * 3u);
    if (rgb is null)
    {
        failure = WC_SHOT_OUT_OF_MEMORY;
        goto cleanup;
    }
    {
        ubyte[3] background;
        background[0] = cast(ubyte)((options.backgroundRgb >> 16) & 0xFFu);
        background[1] = cast(ubyte)((options.backgroundRgb >> 8) & 0xFFu);
        background[2] = cast(ubyte)(options.backgroundRgb & 0xFFu);
        foreach (p; 0 .. cast(size_t)options.width * options.height)
        {
            rgb[p * 3] = background[0];
            rgb[p * 3 + 1] = background[1];
            rgb[p * 3 + 2] = background[2];
        }
    }

    foreach (t; 0 .. soupCount)
    {
        auto tri = &soup[t];
        double[3] px, py, pd;
        foreach (corner; 0 .. 3)
            projectVertex(&view, tri.v[corner * 3], tri.v[corner * 3 + 1], tri.v[corner * 3 + 2],
                &px[corner], &py[corner], &pd[corner]);
        fillTriangle(rgb, options.width, options.height,
            px[0], py[0], px[1], py[1], px[2], py[2], tri.rgb);
    }

    // Wireframe placeholders for preview-only bodies, drawn over the solids.
    foreach (b; 0 .. boxCount)
    {
        auto box = &boxes[b];
        double[8] cornerX, cornerY, cornerDepth;
        foreach (corner; 0 .. 8)
        {
            immutable wx = (corner & 1) == 0 ? box.minX : box.maxX;
            immutable wy = (corner & 2) == 0 ? box.minY : box.maxY;
            immutable wz = (corner & 4) == 0 ? box.minZ : box.maxZ;
            projectVertex(&view, wx, wy, wz, &cornerX[corner], &cornerY[corner], &cornerDepth[corner]);
        }
        static immutable ubyte[2][12] edges =
            [[0, 1], [1, 3], [3, 2], [2, 0], [4, 5], [5, 7], [7, 6], [6, 4], [0, 4], [1, 5], [2, 6], [3, 7]];
        foreach (edge; edges)
            drawLine(rgb, options.width, options.height,
                cornerX[edge[0]], cornerY[edge[0]], cornerX[edge[1]], cornerY[edge[1]], previewBoxRgb);
    }

    // Orientation triad so an AI reading the image can tell which way is up.
    if (options.drawAxes)
    {
        immutable double anchorX = 48.0;
        immutable double anchorY = options.height - 48.0;
        immutable double axisLength = 36.0;
        static immutable uint[3] axisColours = [0xE04848u, 0x48C048u, 0x4888E0u]; // X Y Z
        foreach (axis; 0 .. 3)
        {
            double wx = 0.0, wy = 0.0, wz = 0.0;
            if (axis == 0) wx = 1.0;
            else if (axis == 1) wy = 1.0;
            else wz = 1.0;
            double vx, vy, vz;
            rotateView(&view, wx, wy, wz, &vx, &vy, &vz);
            immutable sx = vx * view.cr - vz * view.sr;
            immutable sy = vx * view.sr + vz * view.cr;
            drawLine(rgb, options.width, options.height, anchorX, anchorY,
                anchorX + sx * axisLength, anchorY - sy * axisLength, axisColours[axis]);
        }
    }

    {
        immutable pngRc = writePngRgb(path, rgb, options.width, options.height);
        if (pngRc != WC_PNG_OK)
            failure = 20 + pngRc;
    }

cleanup:
    free(rgb);
    free(boxes);
    free(scratch);
    free(soup);
    return failure;
}
