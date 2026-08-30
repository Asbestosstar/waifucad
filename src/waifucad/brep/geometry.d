module waifucad.brep.geometry;

import core.stdc.math : cos, fabs, sin, sqrt;
import waifucad.brep.types;

enum double WC_BREP_PI = 3.141592653589793238462643383279502884;
enum double WC_BREP_EPSILON = 1.0e-10;

BRepVec3 add(BRepVec3 a, BRepVec3 b) nothrow @nogc
{
    return BRepVec3(a.x + b.x, a.y + b.y, a.z + b.z);
}

BRepVec3 subtract(BRepVec3 a, BRepVec3 b) nothrow @nogc
{
    return BRepVec3(a.x - b.x, a.y - b.y, a.z - b.z);
}

BRepVec3 scale(BRepVec3 value, double amount) nothrow @nogc
{
    return BRepVec3(value.x * amount, value.y * amount, value.z * amount);
}

double dot(BRepVec3 a, BRepVec3 b) nothrow @nogc
{
    return a.x * b.x + a.y * b.y + a.z * b.z;
}

BRepVec3 cross(BRepVec3 a, BRepVec3 b) nothrow @nogc
{
    return BRepVec3(
        a.y * b.z - a.z * b.y,
        a.z * b.x - a.x * b.z,
        a.x * b.y - a.y * b.x);
}

double lengthSquared(BRepVec3 value) nothrow @nogc
{
    return dot(value, value);
}

double length(BRepVec3 value) nothrow @nogc
{
    return sqrt(lengthSquared(value));
}

BRepVec3 normalise(BRepVec3 value, bool* ok) nothrow @nogc
{
    auto magnitude = length(value);
    if (magnitude <= WC_BREP_EPSILON)
    {
        if (ok !is null)
            *ok = false;
        return BRepVec3(0.0, 0.0, 0.0);
    }
    if (ok !is null)
        *ok = true;
    return scale(value, 1.0 / magnitude);
}

bool nearlyEqual(double a, double b, double tolerance) nothrow @nogc
{
    return fabs(a - b) <= tolerance;
}

bool pointsNearlyEqual(BRepVec3 a, BRepVec3 b, double tolerance) nothrow @nogc
{
    return lengthSquared(subtract(a, b)) <= tolerance * tolerance;
}

private bool nurbsBasis(ubyte degree, ubyte count, const(double)* knots, ubyte knotCount, double t, double* output) nothrow @nogc
{
    if (knots is null || output is null || count==0 || degree>=count || knotCount!=count+degree+1 || count>WC_BREP_MAX_NURBS_CURVE_POINTS) return false;
    double[WC_BREP_MAX_NURBS_CURVE_POINTS] current;
    double[WC_BREP_MAX_NURBS_CURVE_POINTS] next;
    auto last=knots[knotCount-1];
    foreach(i;0..count) current[i]=(knots[i]<=t && (t<knots[i+1] || (t==last && i==count-1)))?1.0:0.0;
    foreach(p;1..cast(uint)degree+1u)
    {
        foreach(i;0..count)
        {
            double left=0.0,right=0.0;
            auto ld=knots[i+p]-knots[i];
            if(ld!=0.0) left=(t-knots[i])/ld*current[i];
            if(i+1<count)
            {
                auto rd=knots[i+p+1]-knots[i+1];
                if(rd!=0.0) right=(knots[i+p+1]-t)/rd*current[i+1];
            }
            next[i]=left+right;
        }
        foreach(i;0..count) { current[i]=next[i]; next[i]=0.0; }
    }
    foreach(i;0..count) output[i]=current[i];
    return true;
}

private BRepVec3 evaluateNurbsCurve(const BRepNurbsCurve* curve, double t, bool* ok) nothrow @nogc
{
    if(ok !is null) *ok=false;
    if(curve is null) return BRepVec3(0,0,0);
    double[WC_BREP_MAX_NURBS_CURVE_POINTS] basis;
    if(!nurbsBasis(curve.degree,curve.controlPointCount,curve.knots.ptr,curve.knotCount,t,basis.ptr)) return BRepVec3(0,0,0);
    BRepVec3 numerator; double denominator=0.0;
    foreach(i;0..curve.controlPointCount)
    {
        auto w=basis[i]*curve.weights[i]; denominator+=w; numerator=add(numerator,scale(curve.controlPoints[i],w));
    }
    if(fabs(denominator)<=WC_BREP_EPSILON) return BRepVec3(0,0,0);
    if(ok !is null) *ok=true; return scale(numerator,1.0/denominator);
}

private BRepVec3 evaluateNurbsSurface(const BRepNurbsSurface* surface, double u, double v, bool* ok) nothrow @nogc
{
    if(ok !is null) *ok=false; if(surface is null) return BRepVec3(0,0,0);
    double[WC_BREP_MAX_NURBS_CURVE_POINTS] bu; double[WC_BREP_MAX_NURBS_CURVE_POINTS] bv;
    if(!nurbsBasis(surface.degreeU,surface.countU,surface.knotsU.ptr,surface.knotCountU,u,bu.ptr) ||
       !nurbsBasis(surface.degreeV,surface.countV,surface.knotsV.ptr,surface.knotCountV,v,bv.ptr)) return BRepVec3(0,0,0);
    BRepVec3 numerator; double denominator=0.0;
    foreach(j;0..surface.countV) foreach(i;0..surface.countU)
    {
        auto index=cast(uint)j*cast(uint)surface.countU+i; auto w=bu[i]*bv[j]*surface.weights[index];
        denominator+=w; numerator=add(numerator,scale(surface.controlPoints[index],w));
    }
    if(fabs(denominator)<=WC_BREP_EPSILON) return BRepVec3(0,0,0); if(ok !is null) *ok=true; return scale(numerator,1.0/denominator);
}

BRepId coedgeStartVertex(BRepArena* arena, BRepId coedgeId) nothrow @nogc
{
    auto coedge = arena is null ? null : arena.coedge(coedgeId);
    if (coedge is null)
        return 0;
    auto edge = arena.edge(coedge.edge);
    if (edge is null)
        return 0;
    return coedge.reversed ? edge.endVertex : edge.startVertex;
}

BRepId coedgeEndVertex(BRepArena* arena, BRepId coedgeId) nothrow @nogc
{
    auto coedge = arena is null ? null : arena.coedge(coedgeId);
    if (coedge is null)
        return 0;
    auto edge = arena.edge(coedge.edge);
    if (edge is null)
        return 0;
    return coedge.reversed ? edge.startVertex : edge.endVertex;
}

BRepVec3 evaluateEdge(BRepArena* arena, BRepId edgeId, double t, bool* ok) nothrow @nogc
{
    if (ok !is null)
        *ok = false;
    auto edge = arena is null ? null : arena.edge(edgeId);
    if (edge is null)
        return BRepVec3(0.0, 0.0, 0.0);

    if (edge.curveKind == BRepCurveKind.line)
    {
        auto a = arena.vertex(edge.startVertex);
        auto b = arena.vertex(edge.endVertex);
        if (a is null || b is null)
            return BRepVec3(0.0, 0.0, 0.0);
        if (ok !is null)
            *ok = true;
        return add(a.point, scale(subtract(b.point, a.point), t));
    }

    if (edge.curveKind == BRepCurveKind.circle)
    {
        bool axisOk = false;
        bool referenceOk = false;
        auto axis = normalise(edge.axis, &axisOk);
        auto xAxis = normalise(edge.referenceDirection, &referenceOk);
        if (!axisOk || !referenceOk || edge.radius <= 0.0)
            return BRepVec3(0.0, 0.0, 0.0);
        bool yOk = false;
        auto yAxis = normalise(cross(axis, xAxis), &yOk);
        if (!yOk)
            return BRepVec3(0.0, 0.0, 0.0);
        auto parameter = edge.parameterStart + (edge.parameterEnd - edge.parameterStart) * t;
        auto radial = add(scale(xAxis, cos(parameter) * edge.radius),
                          scale(yAxis, sin(parameter) * edge.radius));
        if (ok !is null)
            *ok = true;
        return add(edge.origin, radial);
    }

    if (edge.curveKind == BRepCurveKind.bspline)
    {
        auto curve=arena.nurbsCurve(edge.geometryId);
        auto parameter=edge.parameterStart+(edge.parameterEnd-edge.parameterStart)*t;
        return evaluateNurbsCurve(curve,parameter,ok);
    }

    return BRepVec3(0.0, 0.0, 0.0);
}

BRepVec3 evaluateCoedge(BRepArena* arena, BRepId coedgeId, double t, bool* ok) nothrow @nogc
{
    auto coedge = arena is null ? null : arena.coedge(coedgeId);
    if (coedge is null)
    {
        if (ok !is null)
            *ok = false;
        return BRepVec3(0.0, 0.0, 0.0);
    }
    return evaluateEdge(arena, coedge.edge, coedge.reversed ? 1.0 - t : t, ok);
}

BRepVec3 evaluateFace(BRepArena* arena, BRepId faceId, double u, double v, bool* ok) nothrow @nogc
{
    if (ok !is null)
        *ok = false;
    auto face = arena is null ? null : arena.face(faceId);
    if (face is null)
        return BRepVec3(0.0, 0.0, 0.0);

    bool normalOk = false;
    bool referenceOk = false;
    if (face.surfaceKind == BRepSurfaceKind.plane)
    {
        auto normal = normalise(face.normal, &normalOk);
        auto xAxis = normalise(face.referenceDirection, &referenceOk);
        if (!normalOk || !referenceOk)
            return BRepVec3(0.0, 0.0, 0.0);
        bool yOk = false;
        auto yAxis = normalise(cross(normal, xAxis), &yOk);
        if (!yOk)
            return BRepVec3(0.0, 0.0, 0.0);
        if (ok !is null)
            *ok = true;
        return add(face.origin, add(scale(xAxis, u), scale(yAxis, v)));
    }

    if (face.surfaceKind == BRepSurfaceKind.cylinder)
    {
        auto axis = normalise(face.axis, &normalOk);
        auto xAxis = normalise(face.referenceDirection, &referenceOk);
        if (!normalOk || !referenceOk || face.radius <= 0.0)
            return BRepVec3(0.0, 0.0, 0.0);
        bool yOk = false;
        auto yAxis = normalise(cross(axis, xAxis), &yOk);
        if (!yOk)
            return BRepVec3(0.0, 0.0, 0.0);
        auto radial = add(scale(xAxis, cos(u) * face.radius),
                          scale(yAxis, sin(u) * face.radius));
        if (ok !is null)
            *ok = true;
        return add(face.origin, add(radial, scale(axis, v)));
    }

    if (face.surfaceKind == BRepSurfaceKind.cone)
    {
        auto axis = normalise(face.axis, &normalOk);
        auto xAxis = normalise(face.referenceDirection, &referenceOk);
        if (!normalOk || !referenceOk || face.axialLength <= 0.0 ||
            face.radius < 0.0 || face.secondaryRadius < 0.0)
            return BRepVec3(0.0, 0.0, 0.0);
        bool yOk = false;
        auto yAxis = normalise(cross(axis, xAxis), &yOk);
        if (!yOk)
            return BRepVec3(0.0, 0.0, 0.0);
        auto radiusAtV = face.radius + (face.secondaryRadius - face.radius) * (v / face.axialLength);
        auto radial = add(scale(xAxis, cos(u) * radiusAtV),
                          scale(yAxis, sin(u) * radiusAtV));
        if (ok !is null)
            *ok = true;
        return add(face.origin, add(radial, scale(axis, v)));
    }

    if (face.surfaceKind == BRepSurfaceKind.sphere)
    {
        auto axis = normalise(face.axis, &normalOk);
        auto xAxis = normalise(face.referenceDirection, &referenceOk);
        if (!normalOk || !referenceOk || face.radius <= 0.0)
            return BRepVec3(0.0, 0.0, 0.0);
        bool yOk = false;
        auto yAxis = normalise(cross(axis, xAxis), &yOk);
        if (!yOk)
            return BRepVec3(0.0, 0.0, 0.0);
        auto cosV = cos(v);
        auto radial = add(add(scale(xAxis, cos(u) * cosV * face.radius),
                              scale(yAxis, sin(u) * cosV * face.radius)),
                          scale(axis, sin(v) * face.radius));
        if (ok !is null)
            *ok = true;
        return add(face.origin, radial);
    }

    if (face.surfaceKind == BRepSurfaceKind.torus)
    {
        auto axis=normalise(face.axis,&normalOk); auto xAxis=normalise(face.referenceDirection,&referenceOk);
        if(!normalOk||!referenceOk||face.radius<=face.secondaryRadius||face.secondaryRadius<=0.0) return BRepVec3(0,0,0);
        bool yOk=false; auto yAxis=normalise(cross(axis,xAxis),&yOk); if(!yOk) return BRepVec3(0,0,0);
        auto majorDirection=add(scale(xAxis,cos(u)),scale(yAxis,sin(u)));
        auto point=add(face.origin,add(scale(majorDirection,face.radius+face.secondaryRadius*cos(v)),scale(axis,face.secondaryRadius*sin(v))));
        if(ok !is null) *ok=true; return point;
    }

    if (face.surfaceKind == BRepSurfaceKind.bspline)
        return evaluateNurbsSurface(arena.nurbsSurface(face.geometryId),u,v,ok);

    return BRepVec3(0.0, 0.0, 0.0);
}

BRepVec3 faceNormalAt(BRepArena* arena, BRepId faceId, double u, double v, bool* ok) nothrow @nogc
{
    if (ok !is null)
        *ok = false;
    auto face = arena is null ? null : arena.face(faceId);
    if (face is null)
        return BRepVec3(0.0, 0.0, 0.0);

    bool valid = false;
    if (face.surfaceKind == BRepSurfaceKind.plane)
    {
        auto normal = normalise(face.normal, &valid);
        if (valid && face.reversed)
            normal = scale(normal, -1.0);
        if (ok !is null)
            *ok = valid;
        return normal;
    }

    if (face.surfaceKind == BRepSurfaceKind.cylinder)
    {
        bool pointOk = false;
        auto point = evaluateFace(arena, faceId, u, v, &pointOk);
        bool axisOk = false;
        auto axis = normalise(face.axis, &axisOk);
        if (!pointOk || !axisOk)
            return BRepVec3(0.0, 0.0, 0.0);
        auto relative = subtract(point, face.origin);
        auto axial = scale(axis, dot(relative, axis));
        auto normal = normalise(subtract(relative, axial), &valid);
        if (valid && face.reversed)
            normal = scale(normal, -1.0);
        if (ok !is null)
            *ok = valid;
        return normal;
    }

    if (face.surfaceKind == BRepSurfaceKind.cone)
    {
        bool pointOk = false;
        auto point = evaluateFace(arena, faceId, u, v, &pointOk);
        bool axisOk = false;
        auto axis = normalise(face.axis, &axisOk);
        if (!pointOk || !axisOk || face.axialLength <= 0.0)
            return BRepVec3(0.0, 0.0, 0.0);
        auto axialDistance = dot(subtract(point, face.origin), axis);
        auto axisPoint = add(face.origin, scale(axis, axialDistance));
        bool radialOk = false;
        auto radial = normalise(subtract(point, axisPoint), &radialOk);
        if (!radialOk)
            return BRepVec3(0.0, 0.0, 0.0);
        auto slope = (face.secondaryRadius - face.radius) / face.axialLength;
        auto normal = normalise(subtract(radial, scale(axis, slope)), &valid);
        if (valid && face.reversed)
            normal = scale(normal, -1.0);
        if (ok !is null)
            *ok = valid;
        return normal;
    }

    if (face.surfaceKind == BRepSurfaceKind.sphere)
    {
        bool pointOk = false;
        auto point = evaluateFace(arena, faceId, u, v, &pointOk);
        if (!pointOk)
            return BRepVec3(0.0, 0.0, 0.0);
        auto normal = normalise(subtract(point, face.origin), &valid);
        if (valid && face.reversed)
            normal = scale(normal, -1.0);
        if (ok !is null)
            *ok = valid;
        return normal;
    }

    if (face.surfaceKind == BRepSurfaceKind.torus)
    {
        bool pointOk=false; auto point=evaluateFace(arena,faceId,u,v,&pointOk);
        bool axisOk=false; auto axis=normalise(face.axis,&axisOk); if(!pointOk||!axisOk) return BRepVec3(0,0,0);
        auto rel=subtract(point,face.origin); auto axial=dot(rel,axis); auto radialPlane=subtract(rel,scale(axis,axial));
        bool radialOk=false; auto majorDir=normalise(radialPlane,&radialOk); if(!radialOk) return BRepVec3(0,0,0);
        auto tubeCentre=add(face.origin,scale(majorDir,face.radius)); auto normal=normalise(subtract(point,tubeCentre),&valid);
        if(valid&&face.reversed) normal=scale(normal,-1.0); if(ok !is null) *ok=valid; return normal;
    }

    if (face.surfaceKind == BRepSurfaceKind.bspline)
    {
        auto surface=arena.nurbsSurface(face.geometryId); if(surface is null) return BRepVec3(0,0,0);
        auto uMin=surface.knotsU[surface.degreeU]; auto uMax=surface.knotsU[surface.countU];
        auto vMin=surface.knotsV[surface.degreeV]; auto vMax=surface.knotsV[surface.countV];
        auto du=(uMax-uMin)*1.0e-6; auto dv=(vMax-vMin)*1.0e-6; if(du==0.0||dv==0.0) return BRepVec3(0,0,0);
        bool aOk=false,bOk=false,cOk=false; auto p=evaluateFace(arena,faceId,u,v,&aOk);
        auto pu=evaluateFace(arena,faceId,u+du<=uMax?u+du:u-du,v,&bOk); auto pv=evaluateFace(arena,faceId,u,v+dv<=vMax?v+dv:v-dv,&cOk);
        if(!aOk||!bOk||!cOk) return BRepVec3(0,0,0); auto normal=normalise(cross(subtract(pu,p),subtract(pv,p)),&valid);
        if(valid&&face.reversed) normal=scale(normal,-1.0); if(ok !is null) *ok=valid; return normal;
    }

    return BRepVec3(0.0, 0.0, 0.0);
}

BRepLinePlaneIntersection intersectLinePlane(BRepLine line, BRepPlane plane, double tolerance) nothrow @nogc
{
    BRepLinePlaneIntersection result;
    result.kind = BRepIntersectionKind.none;
    auto denominator = dot(plane.normal, line.direction);
    auto numerator = dot(plane.normal, subtract(plane.origin, line.origin));
    if (fabs(denominator) <= tolerance)
    {
        if (fabs(numerator) <= tolerance)
            result.kind = BRepIntersectionKind.coincident;
        return result;
    }
    result.lineParameter = numerator / denominator;
    result.point = add(line.origin, scale(line.direction, result.lineParameter));
    result.kind = BRepIntersectionKind.point;
    return result;
}

bool boundsOverlap(const BRepBounds* a, const BRepBounds* b, double tolerance) nothrow @nogc
{
    if (a is null || b is null || !a.valid || !b.valid)
        return false;
    return a.maximum.x + tolerance >= b.minimum.x && b.maximum.x + tolerance >= a.minimum.x &&
           a.maximum.y + tolerance >= b.minimum.y && b.maximum.y + tolerance >= a.minimum.y &&
           a.maximum.z + tolerance >= b.minimum.z && b.maximum.z + tolerance >= a.minimum.z;
}

BRepPointClassification classifyPoint(BRepArena* arena, BRepId solidId, BRepVec3 point, double tolerance) nothrow @nogc
{
    auto solid = arena is null ? null : arena.solid(solidId);
    if (solid is null || !solid.bounds.valid)
        return BRepPointClassification.outside;

    if (solid.primitiveKind == BRepPrimitiveKind.box)
    {
        if (point.x < solid.bounds.minimum.x - tolerance || point.x > solid.bounds.maximum.x + tolerance ||
            point.y < solid.bounds.minimum.y - tolerance || point.y > solid.bounds.maximum.y + tolerance ||
            point.z < solid.bounds.minimum.z - tolerance || point.z > solid.bounds.maximum.z + tolerance)
            return BRepPointClassification.outside;
        auto onBoundary = fabs(point.x - solid.bounds.minimum.x) <= tolerance ||
                          fabs(point.x - solid.bounds.maximum.x) <= tolerance ||
                          fabs(point.y - solid.bounds.minimum.y) <= tolerance ||
                          fabs(point.y - solid.bounds.maximum.y) <= tolerance ||
                          fabs(point.z - solid.bounds.minimum.z) <= tolerance ||
                          fabs(point.z - solid.bounds.maximum.z) <= tolerance;
        return onBoundary ? BRepPointClassification.boundary : BRepPointClassification.inside;
    }

    if (solid.primitiveKind == BRepPrimitiveKind.cylinder)
    {
        BRepFace* side=null; foreach(i;0..solid.faceCount){auto f=arena.face(solid.firstFace+cast(BRepId)i);if(f !is null&&f.surfaceKind==BRepSurfaceKind.cylinder){side=f;break;}}
        if(side is null)return BRepPointClassification.outside; bool axisOk=false; auto axis=normalise(side.axis,&axisOk); if(!axisOk)return BRepPointClassification.outside;
        auto relative=subtract(point,side.origin); auto axial=dot(relative,axis); auto radialVector=subtract(relative,scale(axis,axial)); auto radial=length(radialVector); auto radius=solid.primitiveA; auto height=solid.primitiveB;
        if(radial>radius+tolerance||axial < -tolerance||axial > height+tolerance)return BRepPointClassification.outside;
        auto onBoundary=fabs(radial-radius)<=tolerance||fabs(axial)<=tolerance||fabs(axial-height)<=tolerance;
        return onBoundary?BRepPointClassification.boundary:BRepPointClassification.inside;
    }

    if (solid.primitiveKind == BRepPrimitiveKind.sphere)
    {
        auto sphereFace=arena.face(solid.firstFace);
        auto centre=sphereFace is null?BRepVec3((solid.bounds.minimum.x+solid.bounds.maximum.x)*0.5,(solid.bounds.minimum.y+solid.bounds.maximum.y)*0.5,(solid.bounds.minimum.z+solid.bounds.maximum.z)*0.5):sphereFace.origin;
        auto distance = length(subtract(point, centre));
        auto radius = solid.primitiveA;
        if (distance > radius + tolerance)
            return BRepPointClassification.outside;
        return fabs(distance - radius) <= tolerance ? BRepPointClassification.boundary : BRepPointClassification.inside;
    }

    if (solid.primitiveKind == BRepPrimitiveKind.coneFrustum)
    {
        auto r1=solid.primitiveA, r2=solid.primitiveB, height=solid.primitiveC; BRepFace* side=null;
        foreach(i;0..solid.faceCount){auto f=arena.face(solid.firstFace+cast(BRepId)i);if(f !is null&&f.surfaceKind==BRepSurfaceKind.cone){side=f;break;}}
        if(side is null||height<=0.0)return BRepPointClassification.outside; bool axisOk=false; auto axis=normalise(side.axis,&axisOk); if(!axisOk)return BRepPointClassification.outside;
        auto relative=subtract(point,side.origin); auto axial=dot(relative,axis); if(axial < -tolerance||axial > height+tolerance)return BRepPointClassification.outside;
        auto radiusAt=r1+(r2-r1)*(axial/height); auto radial=length(subtract(relative,scale(axis,axial))); if(radial>radiusAt+tolerance)return BRepPointClassification.outside;
        auto onCap=(r1>0.0&&fabs(axial)<=tolerance)||(r2>0.0&&fabs(axial-height)<=tolerance); auto onSide=fabs(radial-radiusAt)<=tolerance;
        return onCap||onSide?BRepPointClassification.boundary:BRepPointClassification.inside;
    }

    if (solid.primitiveKind == BRepPrimitiveKind.torus)
    {
        auto face=arena.face(solid.firstFace); if(face is null||face.surfaceKind!=BRepSurfaceKind.torus)return BRepPointClassification.outside;
        bool axisOk=false; auto axis=normalise(face.axis,&axisOk); if(!axisOk)return BRepPointClassification.outside; auto relative=subtract(point,face.origin);
        auto axial=dot(relative,axis); auto radialVector=subtract(relative,scale(axis,axial)); auto radial=length(radialVector); auto tubeDistance=sqrt((radial-solid.primitiveA)*(radial-solid.primitiveA)+axial*axial);
        if(tubeDistance>solid.primitiveB+tolerance)return BRepPointClassification.outside;
        return fabs(tubeDistance-solid.primitiveB)<=tolerance?BRepPointClassification.boundary:BRepPointClassification.inside;
    }

    if (solid.primitiveKind == BRepPrimitiveKind.boxShell)
    {
        if(point.x<solid.bounds.minimum.x-tolerance||point.x>solid.bounds.maximum.x+tolerance||point.y<solid.bounds.minimum.y-tolerance||point.y>solid.bounds.maximum.y+tolerance||point.z<solid.bounds.minimum.z-tolerance||point.z>solid.bounds.maximum.z+tolerance)return BRepPointClassification.outside;
        auto t=solid.primitiveD; auto innerMin=BRepVec3(solid.bounds.minimum.x+t,solid.bounds.minimum.y+t,solid.bounds.minimum.z+t); auto innerMax=BRepVec3(solid.bounds.maximum.x-t,solid.bounds.maximum.y-t,solid.bounds.maximum.z-t);
        bool insideInner=point.x>innerMin.x+tolerance&&point.x<innerMax.x-tolerance&&point.y>innerMin.y+tolerance&&point.y<innerMax.y-tolerance&&point.z>innerMin.z+tolerance&&point.z<innerMax.z-tolerance;
        if(insideInner)return BRepPointClassification.outside;
        bool outerBoundary=fabs(point.x-solid.bounds.minimum.x)<=tolerance||fabs(point.x-solid.bounds.maximum.x)<=tolerance||fabs(point.y-solid.bounds.minimum.y)<=tolerance||fabs(point.y-solid.bounds.maximum.y)<=tolerance||fabs(point.z-solid.bounds.minimum.z)<=tolerance||fabs(point.z-solid.bounds.maximum.z)<=tolerance;
        bool innerBoundary=(point.x>=innerMin.x-tolerance&&point.x<=innerMax.x+tolerance&&point.y>=innerMin.y-tolerance&&point.y<=innerMax.y+tolerance&&point.z>=innerMin.z-tolerance&&point.z<=innerMax.z+tolerance)&&
            (fabs(point.x-innerMin.x)<=tolerance||fabs(point.x-innerMax.x)<=tolerance||fabs(point.y-innerMin.y)<=tolerance||fabs(point.y-innerMax.y)<=tolerance||fabs(point.z-innerMin.z)<=tolerance||fabs(point.z-innerMax.z)<=tolerance);
        return outerBoundary||innerBoundary?BRepPointClassification.boundary:BRepPointClassification.inside;
    }

    /* Generic robust point-in-solid classification will use ray/face
       intersections once boolean topology construction is available. */
    return BRepPointClassification.outside;
}



