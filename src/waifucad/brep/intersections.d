module waifucad.brep.intersections;

import core.stdc.math : fabs, sqrt;
import waifucad.brep.geometry : add, subtract, scale, dot, cross, length, normalise, evaluateEdge, WC_BREP_EPSILON;
import waifucad.brep.types;

enum WC_BREP_MAX_INTERSECTION_POINTS = 8;
enum WC_BREP_MAX_INTERSECTION_CURVES = 4;

enum BRepIntersectionCurveKind : ubyte
{
    none,
    line,
    circle,
    point,
    coincident
}

struct BRepIntersectionPoint
{
    BRepVec3 point;
    double curveParameter;
}

struct BRepCurveFaceIntersections
{
    BRepIntersectionPoint[WC_BREP_MAX_INTERSECTION_POINTS] points;
    uint count;
    bool coincident;
}

struct BRepIntersectionCurve
{
    BRepIntersectionCurveKind kind;
    BRepVec3 origin;
    BRepVec3 direction;
    BRepVec3 axis;
    BRepVec3 referenceDirection;
    double radius;
}

struct BRepFaceFaceIntersections
{
    BRepIntersectionCurve[WC_BREP_MAX_INTERSECTION_CURVES] curves;
    uint count;
    bool coincident;
}

private bool appendPoint(BRepCurveFaceIntersections* result, BRepVec3 point, double parameter,
                         double tolerance) nothrow @nogc
{
    if(result is null) return false;
    foreach(i;0..result.count)
    {
        auto delta=subtract(result.points[i].point,point);
        if(dot(delta,delta)<=tolerance*tolerance) return true;
    }
    if(result.count>=result.points.length) return false;
    result.points[result.count].point=point;
    result.points[result.count].curveParameter=parameter;
    ++result.count;
    return true;
}

private bool linePlane(BRepVec3 origin, BRepVec3 direction, const BRepFace* face,
                       double tolerance, BRepCurveFaceIntersections* result) nothrow @nogc
{
    bool ok=false; auto normal=normalise(face.normal,&ok); if(!ok)return false;
    auto denominator=dot(normal,direction); auto numerator=dot(normal,subtract(face.origin,origin));
    if(fabs(denominator)<=tolerance)
    {
        if(fabs(numerator)<=tolerance) result.coincident=true;
        return true;
    }
    auto t=numerator/denominator;
    return appendPoint(result,add(origin,scale(direction,t)),t,tolerance);
}

private bool lineSphere(BRepVec3 origin, BRepVec3 direction, const BRepFace* face,
                        double tolerance, BRepCurveFaceIntersections* result) nothrow @nogc
{
    auto rel=subtract(origin,face.origin); auto a=dot(direction,direction); if(a<=WC_BREP_EPSILON)return false;
    auto b=2.0*dot(rel,direction); auto c=dot(rel,rel)-face.radius*face.radius;
    auto discriminant=b*b-4.0*a*c; if(discriminant < -tolerance)return true;
    if(discriminant<0.0)discriminant=0.0; auto root=sqrt(discriminant);
    auto t0=(-b-root)/(2.0*a); auto t1=(-b+root)/(2.0*a);
    appendPoint(result,add(origin,scale(direction,t0)),t0,tolerance);
    if(root>tolerance)appendPoint(result,add(origin,scale(direction,t1)),t1,tolerance);
    return true;
}

private bool lineCylinder(BRepVec3 origin, BRepVec3 direction, const BRepFace* face,
                          double tolerance, BRepCurveFaceIntersections* result) nothrow @nogc
{
    bool ok=false; auto axis=normalise(face.axis,&ok); if(!ok)return false;
    auto rel=subtract(origin,face.origin);
    auto dPerp=subtract(direction,scale(axis,dot(direction,axis)));
    auto rPerp=subtract(rel,scale(axis,dot(rel,axis)));
    auto a=dot(dPerp,dPerp); auto b=2.0*dot(rPerp,dPerp); auto c=dot(rPerp,rPerp)-face.radius*face.radius;
    if(a<=WC_BREP_EPSILON)
    {
        if(fabs(c)<=tolerance)result.coincident=true;
        return true;
    }
    auto discriminant=b*b-4.0*a*c; if(discriminant < -tolerance)return true;
    if(discriminant<0.0)discriminant=0.0; auto root=sqrt(discriminant);
    auto t0=(-b-root)/(2.0*a); auto t1=(-b+root)/(2.0*a);
    appendPoint(result,add(origin,scale(direction,t0)),t0,tolerance);
    if(root>tolerance)appendPoint(result,add(origin,scale(direction,t1)),t1,tolerance);
    return true;
}

private bool lineCone(BRepVec3 origin,BRepVec3 direction,const BRepFace* face,double tolerance,BRepCurveFaceIntersections* result) nothrow @nogc
{
    bool ok=false; auto axis=normalise(face.axis,&ok); if(!ok||face.axialLength<=WC_BREP_EPSILON)return false;
    auto rel=subtract(origin,face.origin); auto z0=dot(rel,axis); auto dz=dot(direction,axis);
    auto p=subtract(rel,scale(axis,z0)); auto d=subtract(direction,scale(axis,dz));
    auto slope=(face.secondaryRadius-face.radius)/face.axialLength;
    auto radial0=face.radius+slope*z0; auto radialD=slope*dz;
    auto a=dot(d,d)-radialD*radialD; auto b=2.0*(dot(p,d)-radial0*radialD); auto c=dot(p,p)-radial0*radial0;
    if(fabs(a)<=WC_BREP_EPSILON)
    {
        if(fabs(b)<=WC_BREP_EPSILON){if(fabs(c)<=tolerance)result.coincident=true;return true;}
        auto t=-c/b; auto axial=z0+dz*t; if(axial>=-tolerance&&axial<=face.axialLength+tolerance)appendPoint(result,add(origin,scale(direction,t)),t,tolerance); return true;
    }
    auto disc=b*b-4.0*a*c; if(disc < -tolerance)return true; if(disc<0.0)disc=0.0; auto root=sqrt(disc);
    auto t0=(-b-root)/(2.0*a), t1=(-b+root)/(2.0*a); auto zA=z0+dz*t0, zB=z0+dz*t1;
    if(zA>=-tolerance&&zA<=face.axialLength+tolerance)appendPoint(result,add(origin,scale(direction,t0)),t0,tolerance);
    if(root>tolerance&&zB>=-tolerance&&zB<=face.axialLength+tolerance)appendPoint(result,add(origin,scale(direction,t1)),t1,tolerance);
    return true;
}

bool intersectLineFace(BRepArena* arena, BRepVec3 origin, BRepVec3 direction,
                       BRepId faceId, double tolerance,
                       BRepCurveFaceIntersections* result) nothrow @nogc
{
    if(result is null||arena is null||tolerance<0.0)return false; *result=BRepCurveFaceIntersections.init;
    auto face=arena.face(faceId); if(face is null)return false;
    final switch(face.surfaceKind)
    {
        case BRepSurfaceKind.plane: return linePlane(origin,direction,face,tolerance,result);
        case BRepSurfaceKind.sphere: return lineSphere(origin,direction,face,tolerance,result);
        case BRepSurfaceKind.cylinder: return lineCylinder(origin,direction,face,tolerance,result);
        case BRepSurfaceKind.cone: return lineCone(origin,direction,face,tolerance,result);
        case BRepSurfaceKind.torus:
        case BRepSurfaceKind.bspline:
        case BRepSurfaceKind.none:
            return false;
    }
}

/* Curve/face intersection for the exact line and circle curves currently used
 * by primitive topology. Circle/plane is analytic; other circle/surface pairs
 * use bounded chord sampling as tolerant groundwork and never create topology
 * directly from an unverified sample. */
bool intersectEdgeFace(BRepArena* arena, BRepId edgeId, BRepId faceId,
                       double tolerance, BRepCurveFaceIntersections* result) nothrow @nogc
{
    if(arena is null||result is null)return false; *result=BRepCurveFaceIntersections.init;
    auto edge=arena.edge(edgeId); auto face=arena.face(faceId); if(edge is null||face is null)return false;
    if(edge.curveKind==BRepCurveKind.line)
    {
        auto a=arena.vertex(edge.startVertex); auto b=arena.vertex(edge.endVertex); if(a is null||b is null)return false;
        BRepCurveFaceIntersections raw; if(!intersectLineFace(arena,a.point,subtract(b.point,a.point),faceId,tolerance,&raw))return false;
        foreach(i;0..raw.count) if(raw.points[i].curveParameter>=-tolerance&&raw.points[i].curveParameter<=1.0+tolerance)
            appendPoint(result,raw.points[i].point,raw.points[i].curveParameter,tolerance);
        result.coincident=raw.coincident; return true;
    }
    if(edge.curveKind==BRepCurveKind.circle && face.surfaceKind==BRepSurfaceKind.plane)
    {
        bool axisOk=false,normalOk=false; auto axis=normalise(edge.axis,&axisOk); auto normal=normalise(face.normal,&normalOk);
        if(!axisOk||!normalOk)return false;
        auto planeOffset=dot(normal,subtract(edge.origin,face.origin));
        auto alignment=fabs(dot(axis,normal));
        if(alignment>=1.0-tolerance)
        {
            if(fabs(planeOffset)<=tolerance) result.coincident=true;
            return true;
        }
        // Intersect the circle plane with the target plane, then the resulting
        // line with the circle in its local two-dimensional basis.
        auto lineDirection=cross(axis,normal); bool lineOk=false; lineDirection=normalise(lineDirection,&lineOk); if(!lineOk)return true;
        auto d1=dot(axis,edge.origin); auto d2=dot(normal,face.origin); auto denom=dot(lineDirection,lineDirection);
        auto point=scale(add(scale(cross(normal,lineDirection),d1),scale(cross(lineDirection,axis),d2)),1.0/denom);
        auto rel=subtract(point,edge.origin); auto projection=dot(rel,lineDirection);
        auto closest=add(point,scale(lineDirection,-projection));
        auto radial2=dot(subtract(closest,edge.origin),subtract(closest,edge.origin));
        auto remaining=edge.radius*edge.radius-radial2; if(remaining < -tolerance)return true;
        if(remaining<0.0)remaining=0.0; auto offset=sqrt(remaining);
        appendPoint(result,add(closest,scale(lineDirection,offset)),0.0,tolerance);
        if(offset>tolerance)appendPoint(result,add(closest,scale(lineDirection,-offset)),0.0,tolerance);
        return true;
    }
    return false;
}

private bool appendCurve(BRepFaceFaceIntersections* result, BRepIntersectionCurve curve) nothrow @nogc
{
    if(result is null||result.count>=result.curves.length)return false; result.curves[result.count++]=curve; return true;
}

private BRepVec3 referenceDirectionForAxis(BRepVec3 axis) nothrow @nogc
{
    auto seed=fabs(axis.x)<0.75?BRepVec3(1.0,0.0,0.0):BRepVec3(0.0,1.0,0.0);
    bool ok=false;auto reference=normalise(cross(axis,seed),&ok);
    if(!ok)return BRepVec3(0.0,0.0,1.0);
    return reference;
}

private bool sphereSphere(const BRepFace* first,const BRepFace* second,double tolerance,
                          BRepFaceFaceIntersections* result) nothrow @nogc
{
    auto delta=subtract(second.origin,first.origin);auto distance=length(delta);
    auto radiusSum=first.radius+second.radius;auto radiusDifference=fabs(first.radius-second.radius);
    if(distance<=tolerance)
    {
        if(radiusDifference<=tolerance)result.coincident=true;
        return true;
    }
    if(distance>radiusSum+tolerance||distance<radiusDifference-tolerance)return true;
    bool axisOk=false;auto axis=normalise(delta,&axisOk);if(!axisOk)return false;
    auto x=(distance*distance+first.radius*first.radius-second.radius*second.radius)/(2.0*distance);
    auto radiusSquared=first.radius*first.radius-x*x;
    if(radiusSquared < -tolerance)return true;
    if(radiusSquared<0.0)radiusSquared=0.0;
    BRepIntersectionCurve curve;curve.origin=add(first.origin,scale(axis,x));curve.axis=axis;
    curve.referenceDirection=referenceDirectionForAxis(axis);curve.radius=sqrt(radiusSquared);
    curve.kind=curve.radius<=tolerance?BRepIntersectionCurveKind.point:BRepIntersectionCurveKind.circle;
    return appendCurve(result,curve);
}

private bool parallelCylinderCylinder(const BRepFace* first,const BRepFace* second,double tolerance,
                                      BRepFaceFaceIntersections* result) nothrow @nogc
{
    bool firstOk=false,secondOk=false;auto axis=normalise(first.axis,&firstOk);auto secondAxis=normalise(second.axis,&secondOk);
    if(!firstOk||!secondOk)return false;
    if(fabs(fabs(dot(axis,secondAxis))-1.0)>tolerance)return false;

    auto between=subtract(second.origin,first.origin);
    auto perpendicular=subtract(between,scale(axis,dot(between,axis)));
    auto distance=length(perpendicular);
    auto radiusSum=first.radius+second.radius;auto radiusDifference=fabs(first.radius-second.radius);
    if(distance<=tolerance)
    {
        if(radiusDifference<=tolerance)result.coincident=true;
        return true;
    }
    if(distance>radiusSum+tolerance||distance<radiusDifference-tolerance)return true;

    bool lateralOk=false;auto lateral=normalise(perpendicular,&lateralOk);if(!lateralOk)return false;
    auto x=(distance*distance+first.radius*first.radius-second.radius*second.radius)/(2.0*distance);
    auto heightSquared=first.radius*first.radius-x*x;
    if(heightSquared < -tolerance)return true;
    if(heightSquared<0.0)heightSquared=0.0;
    auto centre=add(first.origin,scale(lateral,x));
    bool sideOk=false;auto side=normalise(cross(axis,lateral),&sideOk);if(!sideOk)return false;
    auto offset=sqrt(heightSquared);

    BRepIntersectionCurve firstLine;firstLine.kind=BRepIntersectionCurveKind.line;firstLine.origin=add(centre,scale(side,offset));firstLine.direction=axis;
    if(!appendCurve(result,firstLine))return false;
    if(offset>tolerance)
    {
        auto secondLine=firstLine;secondLine.origin=add(centre,scale(side,-offset));
        if(!appendCurve(result,secondLine))return false;
    }
    return true;
}

bool intersectFaces(BRepArena* arena, BRepId firstFaceId, BRepId secondFaceId,
                    double tolerance, BRepFaceFaceIntersections* result) nothrow @nogc
{
    if(arena is null||result is null||tolerance<0.0)return false; *result=BRepFaceFaceIntersections.init;
    auto first=arena.face(firstFaceId); auto second=arena.face(secondFaceId); if(first is null||second is null)return false;
    if(first.surfaceKind==BRepSurfaceKind.sphere && second.surfaceKind==BRepSurfaceKind.sphere)
        return sphereSphere(first,second,tolerance,result);
    if(first.surfaceKind==BRepSurfaceKind.cylinder && second.surfaceKind==BRepSurfaceKind.cylinder)
    {
        bool firstOk=false,secondOk=false;auto firstAxis=normalise(first.axis,&firstOk);auto secondAxis=normalise(second.axis,&secondOk);
        if(firstOk&&secondOk&&fabs(fabs(dot(firstAxis,secondAxis))-1.0)<=tolerance)
            return parallelCylinderCylinder(first,second,tolerance,result);
    }
    if(first.surfaceKind==BRepSurfaceKind.plane && second.surfaceKind==BRepSurfaceKind.plane)
    {
        bool aOk=false,bOk=false; auto a=normalise(first.normal,&aOk); auto b=normalise(second.normal,&bOk); if(!aOk||!bOk)return false;
        auto direction=cross(a,b); auto denom=dot(direction,direction);
        if(denom<=tolerance*tolerance)
        {
            if(fabs(dot(a,subtract(second.origin,first.origin)))<=tolerance)result.coincident=true;
            return true;
        }
        auto d1=dot(a,first.origin); auto d2=dot(b,second.origin);
        BRepIntersectionCurve curve; curve.kind=BRepIntersectionCurveKind.line;
        curve.origin=scale(add(scale(cross(b,direction),d1),scale(cross(direction,a),d2)),1.0/denom);
        bool dOk=false; curve.direction=normalise(direction,&dOk); if(!dOk)return false; return appendCurve(result,curve);
    }

    const(BRepFace)* plane=null; const(BRepFace)* curved=null;
    if(first.surfaceKind==BRepSurfaceKind.plane){plane=first;curved=second;}
    else if(second.surfaceKind==BRepSurfaceKind.plane){plane=second;curved=first;}
    if(plane !is null)
    {
        bool nOk=false,aOk=false; auto normal=normalise(plane.normal,&nOk); auto axis=normalise(curved.axis,&aOk); if(!nOk)return false;
        if(curved.surfaceKind==BRepSurfaceKind.sphere)
        {
            auto signedDistance=dot(normal,subtract(curved.origin,plane.origin)); auto distance=fabs(signedDistance);
            if(distance>curved.radius+tolerance)return true;
            BRepIntersectionCurve curve; curve.origin=subtract(curved.origin,scale(normal,signedDistance)); curve.axis=normal;
            curve.radius=sqrt(curved.radius*curved.radius-distance*distance);
            curve.kind=curve.radius<=tolerance?BRepIntersectionCurveKind.point:BRepIntersectionCurveKind.circle;
            return appendCurve(result,curve);
        }
        if((curved.surfaceKind==BRepSurfaceKind.cylinder||curved.surfaceKind==BRepSurfaceKind.cone) && aOk && fabs(fabs(dot(normal,axis))-1.0)<=tolerance)
        {
            auto axial=dot(axis,subtract(plane.origin,curved.origin));
            double radius=curved.radius;
            if(curved.surfaceKind==BRepSurfaceKind.cone && curved.axialLength>0.0)
                radius=curved.radius+(curved.secondaryRadius-curved.radius)*(axial/curved.axialLength);
            if(radius<0.0)return true;
            BRepIntersectionCurve curve; curve.kind=radius<=tolerance?BRepIntersectionCurveKind.point:BRepIntersectionCurveKind.circle;
            curve.origin=add(curved.origin,scale(axis,axial)); curve.axis=axis; curve.referenceDirection=curved.referenceDirection; curve.radius=radius;
            return appendCurve(result,curve);
        }
        if(curved.surfaceKind==BRepSurfaceKind.torus && aOk && fabs(fabs(dot(normal,axis))-1.0)<=tolerance)
        {
            auto axial=dot(axis,subtract(plane.origin,curved.origin)); if(fabs(axial)>curved.secondaryRadius+tolerance)return true;
            auto radialOffset=sqrt(curved.secondaryRadius*curved.secondaryRadius-axial*axial);
            BRepIntersectionCurve outer; outer.kind=BRepIntersectionCurveKind.circle; outer.origin=add(curved.origin,scale(axis,axial)); outer.axis=axis; outer.referenceDirection=curved.referenceDirection; outer.radius=curved.radius+radialOffset; appendCurve(result,outer);
            auto innerRadius=curved.radius-radialOffset; if(innerRadius>tolerance){auto inner=outer; inner.radius=innerRadius; appendCurve(result,inner);} return true;
        }
    }
    return false;
}

