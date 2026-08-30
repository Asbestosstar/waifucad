module waifucad.kernel.builtin_preview;

import core.stdc.math : cos, sin, sqrt;
import waifucad.core.jobs : parallelForCancelable, WC_PARALLEL_CANCELLED;
import waifucad.kernel.model : Model;
import waifucad.kernel.types : FeatureKind, Feature, BoundingBox, OperandKind;
import waifucad.kernel.backend_api : GeometryBackendV1, WC_GEOMETRY_ABI_V1;
import waifucad.kernel.datums : DatumFrame, sketchFrame, datumFeatureFrame, datumAxis, framePoint;
import waifucad.kernel.profiles : ProfileRegion, ProfileRegionKind, resolveProfile;
import waifucad.brep.types : BRepVec3, BRepProfileSegmentKind;

private enum WC_PI = 3.14159265358979323846264338327950288;

private double minimum(double a, double b) nothrow @nogc { return a < b ? a : b; }
private double maximum(double a, double b) nothrow @nogc { return a > b ? a : b; }
private double absolute(double value) nothrow @nogc { return value < 0.0 ? -value : value; }

private void copyBounds(BoundingBox* destination, const BoundingBox* source) nothrow @nogc
{
    if (destination is null || source is null)
        return;
    *destination = *source;
}

private void setBounds(BoundingBox* bounds, double minX, double minY, double minZ,
                       double maxX, double maxY, double maxZ) nothrow @nogc
{
    if (bounds is null)
        return;
    bounds.minX = minimum(minX, maxX);
    bounds.minY = minimum(minY, maxY);
    bounds.minZ = minimum(minZ, maxZ);
    bounds.maxX = maximum(minX, maxX);
    bounds.maxY = maximum(minY, maxY);
    bounds.maxZ = maximum(minZ, maxZ);
    bounds.valid = true;
}

private void unionBounds(BoundingBox* destination, const BoundingBox* a, const BoundingBox* b) nothrow @nogc
{
    if (destination is null || a is null || b is null || !a.valid || !b.valid)
        return;
    setBounds(destination,
              minimum(a.minX, b.minX), minimum(a.minY, b.minY), minimum(a.minZ, b.minZ),
              maximum(a.maxX, b.maxX), maximum(a.maxY, b.maxY), maximum(a.maxZ, b.maxZ));
}

private bool intersectBounds(BoundingBox* destination, const BoundingBox* a, const BoundingBox* b) nothrow @nogc
{
    if (destination is null || a is null || b is null || !a.valid || !b.valid)
        return false;
    auto minX = maximum(a.minX, b.minX);
    auto minY = maximum(a.minY, b.minY);
    auto minZ = maximum(a.minZ, b.minZ);
    auto maxX = minimum(a.maxX, b.maxX);
    auto maxY = minimum(a.maxY, b.maxY);
    auto maxZ = minimum(a.maxZ, b.maxZ);
    if (minX > maxX || minY > maxY || minZ > maxZ)
        return false;
    setBounds(destination, minX, minY, minZ, maxX, maxY, maxZ);
    return true;
}

private BoundingBox* sourceBounds(Model* model, const Feature* feature, uint operandIndex = 0) nothrow @nogc
{
    if (model is null || feature is null || operandIndex >= feature.operandCount ||
        feature.operands[operandIndex].kind != OperandKind.feature)
        return null;
    return model.boundsForFeature(feature.operands[operandIndex].featureId);
}

private void expandPoint(BoundingBox* result, double x, double y, double z) nothrow @nogc
{
    if (result is null)
        return;
    if (!result.valid)
    {
        setBounds(result, x, y, z, x, y, z);
        return;
    }
    result.minX = minimum(result.minX, x);
    result.minY = minimum(result.minY, y);
    result.minZ = minimum(result.minZ, z);
    result.maxX = maximum(result.maxX, x);
    result.maxY = maximum(result.maxY, y);
    result.maxZ = maximum(result.maxZ, z);
}

private void transformedBounds(BoundingBox* destination, const BoundingBox* source,
                               const double[16]* matrix) nothrow @nogc
{
    if (destination is null || source is null || matrix is null || !source.valid)
        return;
    destination.valid = false;
    foreach (corner; 0 .. 8)
    {
        auto x = (corner & 1) != 0 ? source.maxX : source.minX;
        auto y = (corner & 2) != 0 ? source.maxY : source.minY;
        auto z = (corner & 4) != 0 ? source.maxZ : source.minZ;
        double tx = (*matrix)[0] * x + (*matrix)[1] * y + (*matrix)[2] * z + (*matrix)[3];
        double ty = (*matrix)[4] * x + (*matrix)[5] * y + (*matrix)[6] * z + (*matrix)[7];
        double tz = (*matrix)[8] * x + (*matrix)[9] * y + (*matrix)[10] * z + (*matrix)[11];
        double tw = (*matrix)[12] * x + (*matrix)[13] * y + (*matrix)[14] * z + (*matrix)[15];
        if (tw != 0.0 && tw != 1.0)
        {
            tx /= tw;
            ty /= tw;
            tz /= tw;
        }
        expandPoint(destination, tx, ty, tz);
    }
}

private void expandFrameRectangle(BoundingBox* bounds, const DatumFrame* frame, double minX, double minY, double maxX, double maxY) nothrow @nogc
{
    bounds.valid=false;
    auto p0=framePoint(frame,minX,minY); auto p1=framePoint(frame,maxX,minY);
    auto p2=framePoint(frame,maxX,maxY); auto p3=framePoint(frame,minX,maxY);
    expandPoint(bounds,p0.x,p0.y,p0.z); expandPoint(bounds,p1.x,p1.y,p1.z);
    expandPoint(bounds,p2.x,p2.y,p2.z); expandPoint(bounds,p3.x,p3.y,p3.z);
}

/*
 * Resolve semantic profile geometry directly instead of relying on the sketch
 * container's preview bounds.  A sketch is a first-class profile in WaifuCAD,
 * and its region entities are later history children, so using only the sketch
 * feature's cached bounds made a perfectly valid `extrude(:body, :sketch, ...)`
 * fail after the sketch editor had already recomputed.
 */
private bool profileBoundsFromRegion(const ProfileRegion* profile, BoundingBox* bounds) nothrow @nogc
{
    if (profile is null || bounds is null || !profile.valid)
        return false;
    bounds.valid = false;
    final switch (profile.kind)
    {
        case ProfileRegionKind.none:
            return false;
        case ProfileRegionKind.polygon:
            foreach (i; 0 .. profile.pointCount)
                expandPoint(bounds, profile.points[i].x, profile.points[i].y, profile.points[i].z);
            break;
        case ProfileRegionKind.circle:
            {
                auto centre = profile.frame.origin;
                auto ex = profile.radius * sqrt(profile.frame.xAxis.x * profile.frame.xAxis.x +
                                                profile.frame.yAxis.x * profile.frame.yAxis.x);
                auto ey = profile.radius * sqrt(profile.frame.xAxis.y * profile.frame.xAxis.y +
                                                profile.frame.yAxis.y * profile.frame.yAxis.y);
                auto ez = profile.radius * sqrt(profile.frame.xAxis.z * profile.frame.xAxis.z +
                                                profile.frame.yAxis.z * profile.frame.yAxis.z);
                setBounds(bounds, centre.x - ex, centre.y - ey, centre.z - ez,
                                  centre.x + ex, centre.y + ey, centre.z + ez);
            }
            break;
        case ProfileRegionKind.mixed:
            foreach (i; 0 .. profile.segmentCount)
            {
                auto segment = &profile.segments[i];
                expandPoint(bounds, segment.start.x, segment.start.y, segment.start.z);
                expandPoint(bounds, segment.finish.x, segment.finish.y, segment.finish.z);
                if (segment.kind == BRepProfileSegmentKind.circularArc)
                {
                    /* Conservative whole-circle extent for an arc. */
                    auto ex = segment.radius * sqrt(profile.frame.xAxis.x * profile.frame.xAxis.x +
                                                     profile.frame.yAxis.x * profile.frame.yAxis.x);
                    auto ey = segment.radius * sqrt(profile.frame.xAxis.y * profile.frame.xAxis.y +
                                                     profile.frame.yAxis.y * profile.frame.yAxis.y);
                    auto ez = segment.radius * sqrt(profile.frame.xAxis.z * profile.frame.xAxis.z +
                                                     profile.frame.yAxis.z * profile.frame.yAxis.z);
                    expandPoint(bounds, segment.centre.x - ex, segment.centre.y - ey, segment.centre.z - ez);
                    expandPoint(bounds, segment.centre.x + ex, segment.centre.y + ey, segment.centre.z + ez);
                }
            }
            break;
    }
    return bounds.valid;
}

private bool semanticProfileBounds(Model* model, uint featureId, BoundingBox* bounds, ProfileRegion* profile = null) nothrow @nogc
{
    if (model is null || bounds is null || featureId == 0)
        return false;
    ProfileRegion local;
    auto target = profile is null ? &local : profile;
    if (!resolveProfile(model, featureId, target))
        return false;
    return profileBoundsFromRegion(target, bounds);
}

private void translateBounds(BoundingBox* destination, const BoundingBox* source, BRepVec3 delta) nothrow @nogc
{
    if (destination is null || source is null || !source.valid)
        return;
    setBounds(destination, source.minX + delta.x, source.minY + delta.y, source.minZ + delta.z,
                           source.maxX + delta.x, source.maxY + delta.y, source.maxZ + delta.z);
}

private const(BoundingBox)* sourceOrProfileBounds(Model* model, const Feature* feature, uint operandIndex,
                                                   BoundingBox* scratch) nothrow @nogc
{
    auto source = sourceBounds(model, feature, operandIndex);
    if (source !is null && source.valid)
        return source;
    if (feature is null || operandIndex >= feature.operandCount ||
        feature.operands[operandIndex].kind != OperandKind.feature || scratch is null)
        return null;
    return semanticProfileBounds(model, feature.operands[operandIndex].featureId, scratch) ? scratch : null;
}

private bool sketchSupportFrame(Model* model, const Feature* feature, DatumFrame* frame) nothrow @nogc
{
    if (model is null || feature is null || frame is null || feature.operandCount==0 || feature.operands[0].kind!=OperandKind.feature) return false;
    return sketchFrame(model,feature.operands[0].featureId,frame);
}

private int recomputeOne(Model* model, size_t index) nothrow @nogc
{
    if (model is null || index >= model.featureCount)
        return 1;

    auto feature = &model.features[index];
    auto bounds = &model.previewBounds[index];
    bounds.valid = false;

    final switch (feature.kind)
    {
        case FeatureKind.none:
            break;

        case FeatureKind.sketch:
            /* Closed sketches expose their semantic profile bounds. Open sketches
               remain valid modelling objects and simply have no region bounds yet. */
            {
                BoundingBox profileBounds;
                if (semanticProfileBounds(model, feature.id, &profileBounds))
                    *bounds = profileBounds;
            }
            break;

        case FeatureKind.datumPlane:
        case FeatureKind.datumCsys:
            {
                DatumFrame frame;
                if (!datumFeatureFrame(model,feature.id,&frame)) return 8;
                setBounds(bounds,frame.origin.x,frame.origin.y,frame.origin.z,frame.origin.x,frame.origin.y,frame.origin.z);
            }
            break;
        case FeatureKind.datumAxis:
            {
                BRepVec3 origin;
                BRepVec3 direction;
                if (!datumAxis(model,feature.id,&origin,&direction)) return 9;
                setBounds(bounds,origin.x,origin.y,origin.z,origin.x+direction.x,origin.y+direction.y,origin.z+direction.z);
            }
            break;

        case FeatureKind.freePoint:
            if (feature.operandCount < 3) return 10;
            setBounds(bounds,
                      model.resolveOperand(&feature.operands[0]), model.resolveOperand(&feature.operands[1]), model.resolveOperand(&feature.operands[2]),
                      model.resolveOperand(&feature.operands[0]), model.resolveOperand(&feature.operands[1]), model.resolveOperand(&feature.operands[2]));
            break;

        case FeatureKind.freeLine:
            if (feature.operandCount < 6) return 11;
            setBounds(bounds,
                      model.resolveOperand(&feature.operands[0]), model.resolveOperand(&feature.operands[1]), model.resolveOperand(&feature.operands[2]),
                      model.resolveOperand(&feature.operands[3]), model.resolveOperand(&feature.operands[4]), model.resolveOperand(&feature.operands[5]));
            break;

        case FeatureKind.sketchLine:
            if (feature.operandCount < 5 || feature.operands[0].kind != OperandKind.feature) return 12;
            {
                DatumFrame frame; if(!sketchSupportFrame(model,feature,&frame)) return 12;
                auto a=framePoint(&frame,model.resolveOperand(&feature.operands[1]),model.resolveOperand(&feature.operands[2]));
                auto b=framePoint(&frame,model.resolveOperand(&feature.operands[3]),model.resolveOperand(&feature.operands[4]));
                setBounds(bounds,a.x,a.y,a.z,b.x,b.y,b.z);
            }
            break;

        case FeatureKind.freeArc:
            if (feature.operandCount < 6) return 13;
            {
                auto cx = model.resolveOperand(&feature.operands[0]);
                auto cy = model.resolveOperand(&feature.operands[1]);
                auto cz = model.resolveOperand(&feature.operands[2]);
                auto radius = model.resolveOperand(&feature.operands[3]);
                if (radius < 0.0) return 14;
                setBounds(bounds, cx - radius, cy - radius, cz, cx + radius, cy + radius, cz);
            }
            break;

        case FeatureKind.sketchArc:
            if (feature.operandCount < 6 || feature.operands[0].kind != OperandKind.feature) return 15;
            {
                DatumFrame frame; if(!sketchSupportFrame(model,feature,&frame)) return 15;
                auto cx=model.resolveOperand(&feature.operands[1]); auto cy=model.resolveOperand(&feature.operands[2]);
                auto radius=model.resolveOperand(&feature.operands[3]); if(radius<0.0) return 16;
                auto centre=framePoint(&frame,cx,cy);
                auto ex=radius*sqrt(frame.xAxis.x*frame.xAxis.x+frame.yAxis.x*frame.yAxis.x);
                auto ey=radius*sqrt(frame.xAxis.y*frame.xAxis.y+frame.yAxis.y*frame.yAxis.y);
                auto ez=radius*sqrt(frame.xAxis.z*frame.xAxis.z+frame.yAxis.z*frame.yAxis.z);
                setBounds(bounds,centre.x-ex,centre.y-ey,centre.z-ez,centre.x+ex,centre.y+ey,centre.z+ez);
            }
            break;

        case FeatureKind.freeCircle:
            if (feature.operandCount < 4) return 17;
            {
                auto cx = model.resolveOperand(&feature.operands[0]);
                auto cy = model.resolveOperand(&feature.operands[1]);
                auto cz = model.resolveOperand(&feature.operands[2]);
                auto radius = model.resolveOperand(&feature.operands[3]);
                if (radius < 0.0) return 18;
                setBounds(bounds, cx - radius, cy - radius, cz, cx + radius, cy + radius, cz);
            }
            break;

        case FeatureKind.freeSpline:
            if (feature.operandCount < 6) return 19;
            setBounds(bounds,
                      model.resolveOperand(&feature.operands[0]), model.resolveOperand(&feature.operands[1]), model.resolveOperand(&feature.operands[2]),
                      model.resolveOperand(&feature.operands[3]), model.resolveOperand(&feature.operands[4]), model.resolveOperand(&feature.operands[5]));
            break;

        case FeatureKind.sketchCircle:
            if (feature.operandCount < 2 || feature.operands[0].kind != OperandKind.feature) return 20;
            {
                DatumFrame frame; if(!sketchSupportFrame(model,feature,&frame)) return 20;
                auto radiusIndex=feature.operandCount>=4?3u:1u;
                auto radius=model.resolveOperand(&feature.operands[radiusIndex]); if(radius<0.0) return 21;
                auto centre=frame.origin;
                if(feature.operandCount>=4) centre=framePoint(&frame,model.resolveOperand(&feature.operands[1]),model.resolveOperand(&feature.operands[2]));
                auto ex=radius*sqrt(frame.xAxis.x*frame.xAxis.x+frame.yAxis.x*frame.yAxis.x);
                auto ey=radius*sqrt(frame.xAxis.y*frame.xAxis.y+frame.yAxis.y*frame.yAxis.y);
                auto ez=radius*sqrt(frame.xAxis.z*frame.xAxis.z+frame.yAxis.z*frame.yAxis.z);
                setBounds(bounds,centre.x-ex,centre.y-ey,centre.z-ez,centre.x+ex,centre.y+ey,centre.z+ez);
            }
            break;

        case FeatureKind.circle2d:
            if (feature.operandCount < 1) return 22;
            {
                auto radius = model.resolveOperand(&feature.operands[0]);
                if (feature.operandCount >= 2 && model.resolveOperand(&feature.operands[1]) != 0.0)
                    radius *= 0.5;
                if (radius < 0.0) return 23;
                setBounds(bounds, -radius, -radius, 0.0, radius, radius, 0.0);
            }
            break;

        case FeatureKind.sketchRectangle:
            if (feature.operandCount < 3 || feature.operands[0].kind != OperandKind.feature) return 24;
            {
                DatumFrame frame; if(!sketchSupportFrame(model,feature,&frame)) return 24;
                double minX; double minY; double maxX; double maxY;
                if (feature.operandCount >= 5)
                {
                    auto originX=model.resolveOperand(&feature.operands[1]); auto originY=model.resolveOperand(&feature.operands[2]);
                    auto width=model.resolveOperand(&feature.operands[3]); auto height=model.resolveOperand(&feature.operands[4]);
                    if(width<0.0||height<0.0) return 25;
                    minX=originX; minY=originY; maxX=originX+width; maxY=originY+height;
                }
                else
                {
                    auto width=model.resolveOperand(&feature.operands[1]); auto height=model.resolveOperand(&feature.operands[2]);
                    if(width<0.0||height<0.0) return 25;
                    auto centred=feature.operandCount>=4 && model.resolveOperand(&feature.operands[3])!=0.0;
                    minX=centred?-width*0.5:0.0; maxX=centred?width*0.5:width;
                    minY=centred?-height*0.5:0.0; maxY=centred?height*0.5:height;
                }
                expandFrameRectangle(bounds,&frame,minX,minY,maxX,maxY);
            }
            break;

        case FeatureKind.square2d:
            if (feature.operandCount < 2) return 26;
            {
                auto width = model.resolveOperand(&feature.operands[0]);
                auto height = model.resolveOperand(&feature.operands[1]);
                if (width < 0.0 || height < 0.0) return 27;
                auto centred = feature.operandCount >= 3 && model.resolveOperand(&feature.operands[2]) != 0.0;
                if (centred)
                    setBounds(bounds, -width * 0.5, -height * 0.5, 0.0, width * 0.5, height * 0.5, 0.0);
                else
                    setBounds(bounds, 0.0, 0.0, 0.0, width, height, 0.0);
            }
            break;

        case FeatureKind.sketchPolygon:
            if (feature.operandCount < 5 || feature.operands[0].kind != OperandKind.feature) return 28;
            {
                DatumFrame frame; if(!sketchSupportFrame(model,feature,&frame)) return 28;
                expandFrameRectangle(bounds,&frame,model.resolveOperand(&feature.operands[1]),model.resolveOperand(&feature.operands[2]),
                    model.resolveOperand(&feature.operands[3]),model.resolveOperand(&feature.operands[4]));
            }
            break;

        case FeatureKind.polygon2d:
            if (feature.operandCount < 4) return 29;
            setBounds(bounds,
                      model.resolveOperand(&feature.operands[0]), model.resolveOperand(&feature.operands[1]), 0.0,
                      model.resolveOperand(&feature.operands[2]), model.resolveOperand(&feature.operands[3]), 0.0);
            break;

        case FeatureKind.sketchText:
            if (feature.operandCount < 2 || feature.operands[0].kind != OperandKind.feature) return 30;
            {
                auto size = model.resolveOperand(&feature.operands[1]);
                if (size < 0.0) return 31;
                auto width = size * 0.60 * cast(double)feature.payload.length;
                setBounds(bounds, 0.0, -size * 0.2, 0.0, width, size, 0.0);
            }
            break;

        case FeatureKind.text2d:
            if (feature.operandCount < 1) return 32;
            {
                auto size = model.resolveOperand(&feature.operands[0]);
                if (size < 0.0) return 33;
                auto width = size * 0.60 * cast(double)feature.payload.length;
                setBounds(bounds, 0.0, -size * 0.2, 0.0, width, size, 0.0);
            }
            break;

        case FeatureKind.box:
            if (feature.operandCount < 3) return 24;
            {
                auto width = model.resolveOperand(&feature.operands[0]);
                auto depth = model.resolveOperand(&feature.operands[1]);
                auto height = model.resolveOperand(&feature.operands[2]);
                if (width < 0.0 || depth < 0.0 || height < 0.0) return 25;
                if (feature.operandCount >= 4)
                {
                    // OpenSCAD-style cube form: centre=false occupies the
                    // positive octant; centre=true is centred on the origin.
                    auto centred = model.resolveOperand(&feature.operands[3]) != 0.0;
                    if (centred)
                        setBounds(bounds, -width * 0.5, -depth * 0.5, -height * 0.5,
                                  width * 0.5, depth * 0.5, height * 0.5);
                    else
                        setBounds(bounds, 0.0, 0.0, 0.0, width, depth, height);
                }
                else
                {
                    // WaifuCAD direct box keeps the CAD-friendly XY-centred,
                    // base-on-Z=0 convention used by earlier journals.
                    setBounds(bounds, -width * 0.5, -depth * 0.5, 0.0,
                              width * 0.5, depth * 0.5, height);
                }
            }
            break;

        case FeatureKind.cylinder:
            if (feature.operandCount < 2) return 26;
            {
                auto radius = model.resolveOperand(&feature.operands[0]);
                auto cylinderHeight = model.resolveOperand(&feature.operands[1]);
                auto centred = feature.operandCount >= 3 && model.resolveOperand(&feature.operands[2]) != 0.0;
                if (feature.operandCount >= 4 && model.resolveOperand(&feature.operands[3]) != 0.0)
                    radius *= 0.5;
                if (radius < 0.0 || cylinderHeight < 0.0) return 27;
                auto baseZ = centred ? -cylinderHeight * 0.5 : 0.0;
                setBounds(bounds, -radius, -radius, baseZ, radius, radius, baseZ + cylinderHeight);
            }
            break;

        case FeatureKind.sphere:
            if (feature.operandCount < 1) return 28;
            {
                auto radius = model.resolveOperand(&feature.operands[0]);
                if (feature.operandCount >= 2 && model.resolveOperand(&feature.operands[1]) != 0.0)
                    radius *= 0.5;
                if (radius < 0.0) return 29;
                setBounds(bounds, -radius, -radius, -radius, radius, radius, radius);
            }
            break;

        case FeatureKind.torus:
            if (feature.operandCount < 2) return 300;
            {
                auto major=absolute(model.resolveOperand(&feature.operands[0]));
                auto minor=absolute(model.resolveOperand(&feature.operands[1]));
                if(major<=minor || minor<=0.0) return 301;
                auto outer=major+minor;
                setBounds(bounds,-outer,-outer,-minor,outer,outer,minor);
            }
            break;

        case FeatureKind.coneFrustum:
            if (feature.operandCount < 3) return 30;
            {
                auto r1 = absolute(model.resolveOperand(&feature.operands[0]));
                auto r2 = absolute(model.resolveOperand(&feature.operands[1]));
                auto height = model.resolveOperand(&feature.operands[2]);
                auto centred = feature.operandCount >= 4 && model.resolveOperand(&feature.operands[3]) != 0.0;
                if (feature.operandCount >= 5 && model.resolveOperand(&feature.operands[4]) != 0.0)
                {
                    r1 *= 0.5;
                    r2 *= 0.5;
                }
                if (height < 0.0) return 31;
                auto radius = maximum(r1, r2);
                auto baseZ = centred ? -height * 0.5 : 0.0;
                setBounds(bounds, -radius, -radius, baseZ, radius, radius, baseZ + height);
            }
            break;

        case FeatureKind.dumbBody:
        case FeatureKind.import2d:
        case FeatureKind.import3d:
        case FeatureKind.polyhedron:
            if (feature.operandCount < 6) return 32;
            setBounds(bounds,
                      model.resolveOperand(&feature.operands[0]), model.resolveOperand(&feature.operands[1]), model.resolveOperand(&feature.operands[2]),
                      model.resolveOperand(&feature.operands[3]), model.resolveOperand(&feature.operands[4]), model.resolveOperand(&feature.operands[5]));
            break;

        case FeatureKind.heightSurface:
            if (feature.operandCount < 6) return 32;
            {
                auto minX = model.resolveOperand(&feature.operands[0]);
                auto minY = model.resolveOperand(&feature.operands[1]);
                auto minZ = model.resolveOperand(&feature.operands[2]);
                auto maxX = model.resolveOperand(&feature.operands[3]);
                auto maxY = model.resolveOperand(&feature.operands[4]);
                auto maxZ = model.resolveOperand(&feature.operands[5]);
                auto centred = feature.operandCount >= 7 && model.resolveOperand(&feature.operands[6]) != 0.0;
                if (centred)
                {
                    auto centreX = (minX + maxX) * 0.5;
                    auto centreY = (minY + maxY) * 0.5;
                    minX -= centreX; maxX -= centreX;
                    minY -= centreY; maxY -= centreY;
                }
                setBounds(bounds, minX, minY, minZ, maxX, maxY, maxZ);
            }
            break;

        case FeatureKind.extrude:
            if (feature.operandCount < 2 || feature.operands[0].kind != OperandKind.feature) return 33;
            {
                BoundingBox sourceStorage;
                ProfileRegion profile;
                auto distance = model.resolveOperand(&feature.operands[1]);
                auto centred = feature.operandCount >= 5 && model.resolveOperand(&feature.operands[4]) != 0.0;
                if (semanticProfileBounds(model, feature.operands[0].featureId, &sourceStorage, &profile))
                {
                    auto extrusion = BRepVec3(profile.frame.zAxis.x * distance,
                                              profile.frame.zAxis.y * distance,
                                              profile.frame.zAxis.z * distance);
                    BoundingBox first;
                    BoundingBox second;
                    if (centred)
                    {
                        auto half = BRepVec3(extrusion.x * 0.5, extrusion.y * 0.5, extrusion.z * 0.5);
                        translateBounds(&first, &sourceStorage, BRepVec3(-half.x, -half.y, -half.z));
                        translateBounds(&second, &sourceStorage, half);
                    }
                    else
                    {
                        first = sourceStorage;
                        translateBounds(&second, &sourceStorage, extrusion);
                    }
                    unionBounds(bounds, &first, &second);
                }
                else
                {
                    /* Compatibility fallback for non-profile historical inputs. */
                    auto source = sourceBounds(model, feature);
                    if (source is null || !source.valid) return 34;
                    copyBounds(bounds, source);
                    if (centred)
                    {
                        auto half = absolute(distance) * 0.5;
                        bounds.minZ = source.minZ - half;
                        bounds.maxZ = source.maxZ + half;
                    }
                    else if (distance >= 0.0)
                        bounds.maxZ += distance;
                    else
                        bounds.minZ += distance;
                    bounds.valid = true;
                }
            }
            break;

        case FeatureKind.revolve:
            if (feature.operandCount < 2) return 35;
            {
                BoundingBox sourceStorage;
                auto source = sourceOrProfileBounds(model, feature, 0, &sourceStorage);
                if (source is null || !source.valid) return 36;
                // Conservative revolution about Z using the furthest XY extent.
                auto radius = maximum(maximum(absolute(source.minX), absolute(source.maxX)),
                                      maximum(absolute(source.minY), absolute(source.maxY)));
                setBounds(bounds, -radius, -radius, source.minZ, radius, radius, source.maxZ);
            }
            break;

        case FeatureKind.sweep:
        case FeatureKind.loft:
            if (feature.operandCount < 2) return 37;
            {
                BoundingBox firstStorage;
                BoundingBox secondStorage;
                auto first = sourceOrProfileBounds(model, feature, 0, &firstStorage);
                auto second = sourceOrProfileBounds(model, feature, 1, &secondStorage);
                if (first is null || second is null || !first.valid || !second.valid) return 38;
                unionBounds(bounds, first, second);
            }
            break;

        case FeatureKind.translate:
            if (feature.operandCount < 4) return 39;
            {
                auto source = sourceBounds(model, feature);
                if (source is null || !source.valid) return 40;
                auto x = model.resolveOperand(&feature.operands[1]);
                auto y = model.resolveOperand(&feature.operands[2]);
                auto z = model.resolveOperand(&feature.operands[3]);
                setBounds(bounds, source.minX + x, source.minY + y, source.minZ + z,
                          source.maxX + x, source.maxY + y, source.maxZ + z);
            }
            break;

        case FeatureKind.rotate:
            if (feature.operandCount < 4) return 41;
            {
                auto source = sourceBounds(model, feature);
                if (source is null || !source.valid) return 42;
                auto rx = model.resolveOperand(&feature.operands[1]) * WC_PI / 180.0;
                auto ry = model.resolveOperand(&feature.operands[2]) * WC_PI / 180.0;
                auto rz = model.resolveOperand(&feature.operands[3]) * WC_PI / 180.0;
                auto cx = cos(rx); auto sx = sin(rx);
                auto cy = cos(ry); auto sy = sin(ry);
                auto cz = cos(rz); auto sz = sin(rz);
                double[16] matrix = [
                    cz * cy, cz * sy * sx - sz * cx, cz * sy * cx + sz * sx, 0.0,
                    sz * cy, sz * sy * sx + cz * cx, sz * sy * cx - cz * sx, 0.0,
                    -sy,     cy * sx,                cy * cx,                0.0,
                    0.0,     0.0,                    0.0,                    1.0
                ];
                transformedBounds(bounds, source, &matrix);
            }
            break;

        case FeatureKind.rotateAxis:
            if (feature.operandCount < 5) return 43;
            {
                auto source = sourceBounds(model, feature);
                if (source is null || !source.valid) return 44;
                auto angle = model.resolveOperand(&feature.operands[1]) * WC_PI / 180.0;
                auto nx = model.resolveOperand(&feature.operands[2]);
                auto ny = model.resolveOperand(&feature.operands[3]);
                auto nz = model.resolveOperand(&feature.operands[4]);
                auto magnitude = sqrt(nx * nx + ny * ny + nz * nz);
                if (magnitude == 0.0) return 45;
                nx /= magnitude; ny /= magnitude; nz /= magnitude;
                auto c = cos(angle);
                auto si = sin(angle);
                auto one = 1.0 - c;
                double[16] matrix = [
                    c + nx * nx * one,      nx * ny * one - nz * si, nx * nz * one + ny * si, 0.0,
                    ny * nx * one + nz * si, c + ny * ny * one,      ny * nz * one - nx * si, 0.0,
                    nz * nx * one - ny * si, nz * ny * one + nx * si, c + nz * nz * one,      0.0,
                    0.0,                     0.0,                     0.0,                     1.0
                ];
                transformedBounds(bounds, source, &matrix);
            }
            break;

        case FeatureKind.scale:
            if (feature.operandCount < 4) return 46;
            {
                auto source = sourceBounds(model, feature);
                if (source is null || !source.valid) return 44;
                auto sx = model.resolveOperand(&feature.operands[1]);
                auto sy = model.resolveOperand(&feature.operands[2]);
                auto sz = model.resolveOperand(&feature.operands[3]);
                setBounds(bounds, source.minX * sx, source.minY * sy, source.minZ * sz,
                          source.maxX * sx, source.maxY * sy, source.maxZ * sz);
            }
            break;

        case FeatureKind.resize:
            if (feature.operandCount < 4) return 45;
            {
                auto source = sourceBounds(model, feature);
                if (source is null || !source.valid) return 46;
                auto targetX = model.resolveOperand(&feature.operands[1]);
                auto targetY = model.resolveOperand(&feature.operands[2]);
                auto targetZ = model.resolveOperand(&feature.operands[3]);
                auto currentX = source.maxX - source.minX;
                auto currentY = source.maxY - source.minY;
                auto currentZ = source.maxZ - source.minZ;
                auto sx = targetX == 0.0 || currentX == 0.0 ? 1.0 : targetX / currentX;
                auto sy = targetY == 0.0 || currentY == 0.0 ? 1.0 : targetY / currentY;
                auto sz = targetZ == 0.0 || currentZ == 0.0 ? 1.0 : targetZ / currentZ;
                auto autoX = feature.operandCount >= 5 && model.resolveOperand(&feature.operands[4]) != 0.0;
                auto autoY = feature.operandCount >= 6 && model.resolveOperand(&feature.operands[5]) != 0.0;
                auto autoZ = feature.operandCount >= 7 && model.resolveOperand(&feature.operands[6]) != 0.0;
                double sharedScale = 1.0;
                if (targetX != 0.0 && currentX != 0.0) sharedScale = sx;
                else if (targetY != 0.0 && currentY != 0.0) sharedScale = sy;
                else if (targetZ != 0.0 && currentZ != 0.0) sharedScale = sz;
                if (autoX) sx = sharedScale;
                if (autoY) sy = sharedScale;
                if (autoZ) sz = sharedScale;
                setBounds(bounds, source.minX * sx, source.minY * sy, source.minZ * sz,
                          source.maxX * sx, source.maxY * sy, source.maxZ * sz);
            }
            break;

        case FeatureKind.mirror:
            if (feature.operandCount < 4) return 47;
            {
                auto source = sourceBounds(model, feature);
                if (source is null || !source.valid) return 48;
                auto nx = model.resolveOperand(&feature.operands[1]);
                auto ny = model.resolveOperand(&feature.operands[2]);
                auto nz = model.resolveOperand(&feature.operands[3]);
                auto length = sqrt(nx * nx + ny * ny + nz * nz);
                if (length == 0.0) return 49;
                nx /= length; ny /= length; nz /= length;
                double[16] matrix = [
                    1.0 - 2.0 * nx * nx, -2.0 * nx * ny,       -2.0 * nx * nz,       0.0,
                    -2.0 * ny * nx,      1.0 - 2.0 * ny * ny, -2.0 * ny * nz,       0.0,
                    -2.0 * nz * nx,      -2.0 * nz * ny,       1.0 - 2.0 * nz * nz, 0.0,
                    0.0,                 0.0,                  0.0,                  1.0
                ];
                transformedBounds(bounds, source, &matrix);
            }
            break;

        case FeatureKind.multMatrix:
            if (feature.operandCount < 17) return 50;
            {
                auto source = sourceBounds(model, feature);
                if (source is null || !source.valid) return 51;
                double[16] matrix;
                foreach (i; 0 .. 16)
                    matrix[i] = model.resolveOperand(&feature.operands[i + 1]);
                transformedBounds(bounds, source, &matrix);
            }
            break;

        case FeatureKind.displayModifier:
            {
                auto source = sourceBounds(model, feature);
                if (source is null || !source.valid) return 52;
                copyBounds(bounds, source);
                foreach (operandIndex; 1 .. feature.operandCount)
                {
                    auto extra = sourceBounds(model, feature, cast(uint)operandIndex);
                    if (extra is null || !extra.valid) return 52;
                    BoundingBox merged;
                    merged.valid = false;
                    unionBounds(&merged, bounds, extra);
                    copyBounds(bounds, &merged);
                }
                bounds.valid = true;
            }
            break;

        case FeatureKind.colour:
        case FeatureKind.renderBarrier:
        case FeatureKind.fillet:
        case FeatureKind.chamfer:
        case FeatureKind.shell:
            {
                auto source = sourceBounds(model, feature);
                if (source is null || !source.valid) return 52;
                copyBounds(bounds, source);
                bounds.valid = true;
            }
            break;

        case FeatureKind.offset2d:
            if (feature.operandCount < 2) return 53;
            {
                auto source = sourceBounds(model, feature);
                if (source is null || !source.valid) return 54;
                auto amount = model.resolveOperand(&feature.operands[1]);
                setBounds(bounds, source.minX - amount, source.minY - amount, source.minZ,
                          source.maxX + amount, source.maxY + amount, source.maxZ);
            }
            break;

        case FeatureKind.projection:
            {
                auto source = sourceBounds(model, feature);
                if (source is null || !source.valid) return 55;
                setBounds(bounds, source.minX, source.minY, 0.0, source.maxX, source.maxY, 0.0);
            }
            break;

        case FeatureKind.hull:
        case FeatureKind.booleanUnion:
            if (feature.operandCount < 2) return 56;
            {
                auto left = sourceBounds(model, feature, 0);
                auto right = sourceBounds(model, feature, 1);
                if (left is null || right is null || !left.valid || !right.valid) return 57;
                unionBounds(bounds, left, right);
            }
            break;

        case FeatureKind.booleanSubtract:
            if (feature.operandCount < 2) return 58;
            {
                auto target = sourceBounds(model, feature, 0);
                auto tool = sourceBounds(model, feature, 1);
                if (target is null || tool is null || !target.valid || !tool.valid) return 59;
                copyBounds(bounds, target); // subtraction cannot enlarge the target
                bounds.valid = true;
            }
            break;

        case FeatureKind.booleanIntersect:
            if (feature.operandCount < 2) return 60;
            {
                auto left = sourceBounds(model, feature, 0);
                auto right = sourceBounds(model, feature, 1);
                if (left is null || right is null || !left.valid || !right.valid) return 61;
                // Empty intersection is a valid operation with no drawable preview bounds.
                intersectBounds(bounds, left, right);
            }
            break;

        case FeatureKind.minkowski:
            if (feature.operandCount < 2) return 62;
            {
                auto left = sourceBounds(model, feature, 0);
                auto right = sourceBounds(model, feature, 1);
                if (left is null || right is null || !left.valid || !right.valid) return 63;
                setBounds(bounds,
                          left.minX + right.minX, left.minY + right.minY, left.minZ + right.minZ,
                          left.maxX + right.maxX, left.maxY + right.maxY, left.maxZ + right.maxZ);
            }
            break;
    }

    feature.dirty = false;
    return 0;
}

private struct PreviewPass
{
    Model* model;
    ubyte dependencyDepth;
}

extern(C) private void recomputeAtDepth(void* opaque, size_t index) nothrow @nogc
{
    auto pass = cast(PreviewPass*)opaque;
    if (pass is null || pass.model is null || index >= pass.model.featureCount)
        return;
    auto feature = &pass.model.features[index];
    if (!feature.dirty || feature.dependencyDepth != pass.dependencyDepth)
        return;
    pass.model.previewErrors[index] = recomputeOne(pass.model, index);
}

extern(C) private int recomputePreview(Model* model) nothrow @nogc
{
    if (model is null)
        return 1;

    ubyte maximumDepth = 0;
    foreach (i; 0 .. model.featureCount)
    {
        model.previewErrors[i] = 0;
        if (model.features[i].dirty && model.features[i].dependencyDepth > maximumDepth)
            maximumDepth = model.features[i].dependencyDepth;
    }

    uint depth = 0;
    while (depth <= cast(uint)maximumDepth)
    {
        PreviewPass pass;
        pass.model = model;
        pass.dependencyDepth = cast(ubyte)depth;
        auto threadResult = parallelForCancelable(model.featureCount, model.workerCount, &recomputeAtDepth, &pass, &model.recomputeCancellation);
        if (threadResult != 0)
            return 100 + threadResult;

        foreach (i; 0 .. model.featureCount)
            if (model.features[i].dependencyDepth == pass.dependencyDepth && model.previewErrors[i] != 0)
                return model.previewErrors[i];
        ++depth;
    }
    return 0;
}

GeometryBackendV1 builtinPreviewBackend() nothrow @nogc
{
    GeometryBackendV1 backend;
    backend.abiVersion = WC_GEOMETRY_ABI_V1;
    backend.name = "builtin-preview-multicore".ptr;
    backend.recompute = &recomputePreview;
    return backend;
}




