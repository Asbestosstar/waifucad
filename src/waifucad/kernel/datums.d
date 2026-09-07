module waifucad.kernel.datums;

import core.stdc.string : strcmp;
import waifucad.brep.geometry : cross, dot, normalise, scale, subtract;
import waifucad.brep.types : BRepVec3, BRepSurfaceKind;
import waifucad.brep.naming : faceByPersistentId, persistentTopologyOwner;
import waifucad.kernel.model : Model;
import waifucad.kernel.types : EntityId, FeatureKind, OperandKind;

struct DatumFrame
{
    BRepVec3 origin;
    BRepVec3 xAxis;
    BRepVec3 yAxis;
    BRepVec3 zAxis;
    bool valid;
}

private BRepVec3 chooseReference(BRepVec3 normal) nothrow @nogc
{
    auto candidate = (normal.x < 0.8 && normal.x > -0.8) ? BRepVec3(1.0, 0.0, 0.0) : BRepVec3(0.0, 1.0, 0.0);
    return subtract(candidate, scale(normal, dot(candidate, normal)));
}

private bool orthonormalFrame(BRepVec3 origin, BRepVec3 xInput, BRepVec3 yInput, DatumFrame* result) nothrow @nogc
{
    if (result is null) return false;
    bool xOk = false;
    auto x = normalise(xInput, &xOk);
    if (!xOk) return false;
    auto yProjected = subtract(yInput, scale(x, dot(yInput, x)));
    bool yOk = false;
    auto y = normalise(yProjected, &yOk);
    if (!yOk) return false;
    bool zOk = false;
    auto z = normalise(cross(x, y), &zOk);
    if (!zOk) return false;
    y = cross(z, x);
    result.origin = origin;
    result.xAxis = x;
    result.yAxis = y;
    result.zAxis = z;
    result.valid = true;
    return true;
}


private bool parsePersistentId(const(char)* text, ulong* value) nothrow @nogc
{
    if (text is null || value is null || *text == 0) return false;
    ulong result = 0;
    auto cursor = text;
    while (*cursor != 0)
    {
        if (*cursor < '0' || *cursor > '9') return false;
        auto digit = cast(ulong)(*cursor - '0');
        if (result > (ulong.max - digit) / 10UL) return false;
        result = result * 10UL + digit;
        ++cursor;
    }
    if (result == 0) return false;
    *value = result;
    return true;
}

private bool planarFaceFrame(Model* model, EntityId ownerFeatureId, const(char)* persistentText, DatumFrame* result) nothrow @nogc
{
    if (model is null || result is null || ownerFeatureId == 0) return false;
    ulong persistentId = 0;
    if (!parsePersistentId(persistentText, &persistentId) || persistentTopologyOwner(persistentId) != ownerFeatureId)
        return false;
    auto face = faceByPersistentId(&model.exactGeometry, persistentId);
    if (face is null || face.surfaceKind != BRepSurfaceKind.plane) return false;
    auto normal = face.reversed ? scale(face.normal, -1.0) : face.normal;
    auto referenceDirection = face.referenceDirection;
    if (dot(referenceDirection, referenceDirection) <= 1.0e-20)
        referenceDirection = chooseReference(normal);
    auto yInput = cross(normal, referenceDirection);
    if (!orthonormalFrame(face.origin, referenceDirection, yInput, result)) return false;
    if (dot(result.zAxis, normal) < 0.0)
    {
        result.yAxis = scale(result.yAxis, -1.0);
        result.zAxis = scale(result.zAxis, -1.0);
    }
    return true;
}
bool principalFrame(const(char)* name, DatumFrame* result) nothrow @nogc
{
    if (name is null || result is null) return false;
    if (strcmp(name, "XY".ptr) == 0 || strcmp(name, "xy".ptr) == 0)
        return orthonormalFrame(BRepVec3(0,0,0), BRepVec3(1,0,0), BRepVec3(0,1,0), result);
    if (strcmp(name, "YZ".ptr) == 0 || strcmp(name, "yz".ptr) == 0)
        return orthonormalFrame(BRepVec3(0,0,0), BRepVec3(0,1,0), BRepVec3(0,0,1), result);
    if (strcmp(name, "XZ".ptr) == 0 || strcmp(name, "xz".ptr) == 0 || strcmp(name, "ZX".ptr) == 0)
        return orthonormalFrame(BRepVec3(0,0,0), BRepVec3(1,0,0), BRepVec3(0,0,1), result);
    return false;
}

bool datumFeatureFrame(Model* model, EntityId featureId, DatumFrame* result) nothrow @nogc
{
    if (model is null || result is null) return false;
    auto feature = model.featureById(featureId);
    if (feature is null) return false;
    if (feature.kind == FeatureKind.datumCsys)
    {
        if(feature.operandCount >= 4 && feature.operands[0].kind == OperandKind.feature)
        {
            DatumFrame parent; if(!datumFeatureFrame(model,feature.operands[0].featureId,&parent)) return false;
            auto dx=model.resolveOperand(&feature.operands[1]); auto dy=model.resolveOperand(&feature.operands[2]); auto dz=model.resolveOperand(&feature.operands[3]);
            result.origin=BRepVec3(parent.origin.x+parent.xAxis.x*dx+parent.yAxis.x*dy+parent.zAxis.x*dz,
                                  parent.origin.y+parent.xAxis.y*dx+parent.yAxis.y*dy+parent.zAxis.y*dz,
                                  parent.origin.z+parent.xAxis.z*dx+parent.yAxis.z*dy+parent.zAxis.z*dz);
            result.xAxis=parent.xAxis; result.yAxis=parent.yAxis; result.zAxis=parent.zAxis; result.valid=true; return true;
        }
        if (feature.operandCount < 9) return false;
        auto origin = BRepVec3(model.resolveOperand(&feature.operands[0]), model.resolveOperand(&feature.operands[1]), model.resolveOperand(&feature.operands[2]));
        auto x = BRepVec3(model.resolveOperand(&feature.operands[3]), model.resolveOperand(&feature.operands[4]), model.resolveOperand(&feature.operands[5]));
        auto y = BRepVec3(model.resolveOperand(&feature.operands[6]), model.resolveOperand(&feature.operands[7]), model.resolveOperand(&feature.operands[8]));
        return orthonormalFrame(origin, x, y, result);
    }
    if (feature.kind == FeatureKind.datumPlane)
    {
        if (feature.operandCount >= 1 && feature.operands[0].kind == OperandKind.feature &&
            strcmp(feature.payload.ptr(), "face".ptr) == 0)
            return planarFaceFrame(model, feature.operands[0].featureId, feature.payload2.ptr(), result);
        if(feature.operandCount >= 1 && feature.operands[0].kind == OperandKind.feature)
        {
            DatumFrame parent; if(!datumFeatureFrame(model,feature.operands[0].featureId,&parent)) return false;
            if(strcmp(feature.payload.ptr(),"offset".ptr)==0)
            {
                if(feature.operandCount<2) return false; auto distance=model.resolveOperand(&feature.operands[1]);
                *result=parent; result.origin=BRepVec3(parent.origin.x+parent.zAxis.x*distance,parent.origin.y+parent.zAxis.y*distance,parent.origin.z+parent.zAxis.z*distance); return true;
            }
            if(strcmp(feature.payload.ptr(),"XY".ptr)==0 || strcmp(feature.payload.ptr(),"xy".ptr)==0){*result=parent;return true;}
            if(strcmp(feature.payload.ptr(),"YZ".ptr)==0 || strcmp(feature.payload.ptr(),"yz".ptr)==0)
                return orthonormalFrame(parent.origin,parent.yAxis,parent.zAxis,result);
            if(strcmp(feature.payload.ptr(),"XZ".ptr)==0 || strcmp(feature.payload.ptr(),"xz".ptr)==0)
                return orthonormalFrame(parent.origin,parent.xAxis,parent.zAxis,result);
            return false;
        }
        if (feature.operandCount < 6) return false;
        auto origin = BRepVec3(model.resolveOperand(&feature.operands[0]), model.resolveOperand(&feature.operands[1]), model.resolveOperand(&feature.operands[2]));
        auto nInput = BRepVec3(model.resolveOperand(&feature.operands[3]), model.resolveOperand(&feature.operands[4]), model.resolveOperand(&feature.operands[5]));
        bool nOk = false;
        auto normal = normalise(nInput, &nOk);
        if (!nOk) return false;
        BRepVec3 xInput;
        if (feature.operandCount >= 9)
            xInput = BRepVec3(model.resolveOperand(&feature.operands[6]), model.resolveOperand(&feature.operands[7]), model.resolveOperand(&feature.operands[8]));
        else
            xInput = chooseReference(normal);
        auto yInput = cross(normal, xInput);
        if (!orthonormalFrame(origin, xInput, yInput, result)) return false;
        /* Preserve the requested normal direction. */
        if (dot(result.zAxis, normal) < 0.0)
        {
            result.yAxis = scale(result.yAxis, -1.0);
            result.zAxis = scale(result.zAxis, -1.0);
        }
        return true;
    }
    return false;
}

bool datumAxis(Model* model, EntityId featureId, BRepVec3* origin, BRepVec3* direction) nothrow @nogc
{
    if (model is null || origin is null || direction is null) return false;
    auto feature = model.featureById(featureId);
    if (feature is null || feature.kind != FeatureKind.datumAxis) return false;
    if(feature.operandCount >= 1 && feature.operands[0].kind == OperandKind.feature)
    {
        DatumFrame parent; if(!datumFeatureFrame(model,feature.operands[0].featureId,&parent)) return false;
        *origin=parent.origin;
        if(strcmp(feature.payload.ptr(),"X".ptr)==0 || strcmp(feature.payload.ptr(),"x".ptr)==0)*direction=parent.xAxis;
        else if(strcmp(feature.payload.ptr(),"Y".ptr)==0 || strcmp(feature.payload.ptr(),"y".ptr)==0)*direction=parent.yAxis;
        else if(strcmp(feature.payload.ptr(),"Z".ptr)==0 || strcmp(feature.payload.ptr(),"z".ptr)==0)*direction=parent.zAxis;
        else return false;
        return true;
    }
    if(feature.operandCount < 6) return false;
    *origin = BRepVec3(model.resolveOperand(&feature.operands[0]), model.resolveOperand(&feature.operands[1]), model.resolveOperand(&feature.operands[2]));
    auto raw = BRepVec3(model.resolveOperand(&feature.operands[3]), model.resolveOperand(&feature.operands[4]), model.resolveOperand(&feature.operands[5]));
    bool ok = false;
    *direction = normalise(raw, &ok);
    return ok;
}

bool sketchFrame(Model* model, EntityId sketchId, DatumFrame* result) nothrow @nogc
{
    if (model is null || result is null) return false;
    auto sketch = model.featureById(sketchId);
    if (sketch is null || sketch.kind != FeatureKind.sketch) return false;
    if (sketch.operandCount >= 1 && sketch.operands[0].kind == OperandKind.feature)
    {
        auto supportId = sketch.operands[0].featureId;
        auto support = model.featureById(supportId);
        if (support is null) return false;

        /* Face-backed sketches carry the persistent face identity directly.
           Do not manufacture a datum-plane history feature merely to host a
           sketch: the sketch itself owns the associative support reference. */
        if (strcmp(sketch.payload.ptr(), "face".ptr) == 0)
            return planarFaceFrame(model, supportId, sketch.payload2.ptr(), result);

        if (support.kind == FeatureKind.datumPlane)
            return datumFeatureFrame(model, supportId, result);

        /* A CSYS XY/YZ/XZ plane is likewise a direct sketch support. */
        if (support.kind == FeatureKind.datumCsys)
        {
            DatumFrame parent;
            if (!datumFeatureFrame(model, supportId, &parent)) return false;
            if (strcmp(sketch.payload.ptr(), "XY".ptr) == 0 || strcmp(sketch.payload.ptr(), "xy".ptr) == 0)
            {
                *result = parent;
                return true;
            }
            if (strcmp(sketch.payload.ptr(), "YZ".ptr) == 0 || strcmp(sketch.payload.ptr(), "yz".ptr) == 0)
                return orthonormalFrame(parent.origin, parent.yAxis, parent.zAxis, result);
            if (strcmp(sketch.payload.ptr(), "XZ".ptr) == 0 || strcmp(sketch.payload.ptr(), "xz".ptr) == 0)
                return orthonormalFrame(parent.origin, parent.xAxis, parent.zAxis, result);
            return false;
        }
        return false;
    }
    return principalFrame(sketch.payload.ptr(), result);
}

BRepVec3 framePoint(const DatumFrame* frame, double x, double y, double z = 0.0) nothrow @nogc
{
    if (frame is null || !frame.valid) return BRepVec3(0,0,0);
    return BRepVec3(frame.origin.x + frame.xAxis.x*x + frame.yAxis.x*y + frame.zAxis.x*z,
                    frame.origin.y + frame.xAxis.y*x + frame.yAxis.y*y + frame.zAxis.y*z,
                    frame.origin.z + frame.xAxis.z*x + frame.yAxis.z*y + frame.zAxis.z*z);
}


