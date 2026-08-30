module waifucad.brep.classification;

import core.stdc.math : fabs, sqrt;
import waifucad.brep.geometry : add, subtract, scale, dot, normalise, coedgeStartVertex, coedgeEndVertex;
import waifucad.brep.intersections : BRepCurveFaceIntersections, intersectLineFace;
import waifucad.brep.types;

enum BRepTrimClassification : ubyte
{
    unsupported,
    outside,
    boundary,
    inside
}

enum BRepPointClassification : ubyte
{
    unknown,
    outside,
    boundary,
    inside
}

private void projectPoint(BRepVec3 point, ubyte dropAxis, double* x, double* y) nothrow @nogc
{
    if(dropAxis==0){*x=point.y;*y=point.z;}
    else if(dropAxis==1){*x=point.x;*y=point.z;}
    else {*x=point.x;*y=point.y;}
}

private double pointSegmentDistance2(double px,double py,double ax,double ay,double bx,double by) nothrow @nogc
{
    auto dx=bx-ax,dy=by-ay; auto length2=dx*dx+dy*dy;
    if(length2<=1.0e-30){auto ex=px-ax,ey=py-ay;return ex*ex+ey*ey;}
    auto t=((px-ax)*dx+(py-ay)*dy)/length2;if(t<0.0)t=0.0;else if(t>1.0)t=1.0;
    auto ex=px-(ax+t*dx),ey=py-(ay+t*dy);return ex*ex+ey*ey;
}

private BRepTrimClassification classifyLoop(BRepArena* arena, BRepId loopId, BRepVec3 point,
                                             ubyte dropAxis, double tolerance) nothrow @nogc
{
    auto loop=arena.loop(loopId);if(loop is null||loop.coedgeCount<3||loop.firstCoedge==0)return BRepTrimClassification.unsupported;
    double px=0.0,py=0.0;projectPoint(point,dropAxis,&px,&py);
    bool inside=false;auto current=loop.firstCoedge;
    foreach(_;0..loop.coedgeCount)
    {
        auto coedge=arena.coedge(current);if(coedge is null)return BRepTrimClassification.unsupported;
        auto edge=arena.edge(coedge.edge);if(edge is null||edge.curveKind!=BRepCurveKind.line)return BRepTrimClassification.unsupported;
        auto start=arena.vertex(coedgeStartVertex(arena,current));auto finish=arena.vertex(coedgeEndVertex(arena,current));
        if(start is null||finish is null)return BRepTrimClassification.unsupported;
        double ax=0.0,ay=0.0,bx=0.0,by=0.0;projectPoint(start.point,dropAxis,&ax,&ay);projectPoint(finish.point,dropAxis,&bx,&by);
        if(pointSegmentDistance2(px,py,ax,ay,bx,by)<=tolerance*tolerance)return BRepTrimClassification.boundary;
        bool crosses=((ay>py)!=(by>py));
        if(crosses)
        {
            auto xAtY=ax+(py-ay)*(bx-ax)/(by-ay);
            if(xAtY>px)inside=!inside;
        }
        current=coedge.next;
    }
    return inside?BRepTrimClassification.inside:BRepTrimClassification.outside;
}

BRepTrimClassification classifyPointOnPlanarFace(BRepArena* arena, BRepId faceId,
                                                  BRepVec3 point, double tolerance) nothrow @nogc
{
    if(arena is null||tolerance<0.0)return BRepTrimClassification.unsupported;
    auto face=arena.face(faceId);if(face is null||face.surfaceKind!=BRepSurfaceKind.plane||face.firstLoop==0||face.loopCount==0)return BRepTrimClassification.unsupported;
    bool ok=false;auto normal=normalise(face.normal,&ok);if(!ok)return BRepTrimClassification.unsupported;
    auto planeDistance=fabs(dot(normal,subtract(point,face.origin)));if(planeDistance>tolerance)return BRepTrimClassification.outside;
    auto ax=fabs(normal.x),ay=fabs(normal.y),az=fabs(normal.z);ubyte dropAxis=ax>=ay&&ax>=az?0:(ay>=az?1:2);
    auto outer=classifyLoop(arena,face.outerLoop,point,dropAxis,tolerance);
    if(outer==BRepTrimClassification.unsupported||outer==BRepTrimClassification.outside)return outer;
    if(outer==BRepTrimClassification.boundary)return outer;
    foreach(offset;0..face.loopCount)
    {
        auto loopId=face.firstLoop+cast(BRepId)offset;if(loopId==face.outerLoop)continue;
        auto hole=classifyLoop(arena,loopId,point,dropAxis,tolerance);
        if(hole==BRepTrimClassification.unsupported)return hole;
        if(hole==BRepTrimClassification.boundary)return hole;
        if(hole==BRepTrimClassification.inside)return BRepTrimClassification.outside;
    }
    return BRepTrimClassification.inside;
}

bool intersectLineTrimmedPlanarFace(BRepArena* arena, BRepVec3 origin, BRepVec3 direction,
                                    BRepId faceId, double tolerance,
                                    BRepCurveFaceIntersections* result) nothrow @nogc
{
    if(arena is null||result is null)return false;*result=BRepCurveFaceIntersections.init;
    auto face=arena.face(faceId);if(face is null||face.surfaceKind!=BRepSurfaceKind.plane)return false;
    BRepCurveFaceIntersections raw;
    if(!intersectLineFace(arena,origin,direction,faceId,tolerance,&raw))return false;
    result.coincident=raw.coincident;
    foreach(i;0..raw.count)
    {
        auto classification=classifyPointOnPlanarFace(arena,faceId,raw.points[i].point,tolerance);
        if(classification==BRepTrimClassification.unsupported)return false;
        if(classification==BRepTrimClassification.inside||classification==BRepTrimClassification.boundary)
        {
            if(result.count>=result.points.length)return false;
            result.points[result.count++]=raw.points[i];
        }
    }
    return true;
}

private bool boundsContains(const BRepBounds* bounds,BRepVec3 point,double tolerance) nothrow @nogc
{
    return bounds !is null&&bounds.valid&&point.x>=bounds.minimum.x-tolerance&&point.x<=bounds.maximum.x+tolerance&&
           point.y>=bounds.minimum.y-tolerance&&point.y<=bounds.maximum.y+tolerance&&point.z>=bounds.minimum.z-tolerance&&point.z<=bounds.maximum.z+tolerance;
}

/* Exact/tolerant point classification for closed solids whose trimmed faces are
 * planar line-loop polygons. It is boolean groundwork for generic extruded
 * polygonal solids; curved/NURBS faces return unknown rather than falling back
 * to tessellation and pretending the result is exact. */
BRepPointClassification classifyPointInPlanarSolid(BRepArena* arena,BRepId solidId,
                                                    BRepVec3 point,double tolerance) nothrow @nogc
{
    if(arena is null||tolerance<0.0)return BRepPointClassification.unknown;
    auto solid=arena.solid(solidId);if(solid is null||!boundsContains(&solid.bounds,point,tolerance))return BRepPointClassification.outside;
    auto lastFace=solid.firstFace+solid.faceCount;
    foreach(faceId;solid.firstFace..lastFace)
    {
        auto face=arena.face(faceId);if(face is null||face.surfaceKind!=BRepSurfaceKind.plane)return BRepPointClassification.unknown;
        auto onFace=classifyPointOnPlanarFace(arena,faceId,point,tolerance);
        if(onFace==BRepTrimClassification.unsupported)return BRepPointClassification.unknown;
        if(onFace==BRepTrimClassification.boundary||onFace==BRepTrimClassification.inside)return BRepPointClassification.boundary;
    }

    bool directionOk=false;auto direction=normalise(BRepVec3(1.0,0.3713906763541037,0.6191178922316089),&directionOk);
    if(!directionOk)return BRepPointClassification.unknown;
    BRepVec3[128] hits;uint hitCount=0;
    foreach(faceId;solid.firstFace..lastFace)
    {
        BRepCurveFaceIntersections intersection;
        if(!intersectLineTrimmedPlanarFace(arena,point,direction,faceId,tolerance,&intersection))return BRepPointClassification.unknown;
        if(intersection.coincident)return BRepPointClassification.boundary;
        foreach(i;0..intersection.count)
        {
            if(intersection.points[i].curveParameter<=tolerance)continue;
            bool duplicate=false;
            foreach(h;0..hitCount)
            {
                auto delta=subtract(hits[h],intersection.points[i].point);
                if(dot(delta,delta)<=tolerance*tolerance){duplicate=true;break;}
            }
            if(duplicate)continue;
            if(hitCount>=hits.length)return BRepPointClassification.unknown;
            hits[hitCount++]=intersection.points[i].point;
        }
    }
    return (hitCount&1u)!=0?BRepPointClassification.inside:BRepPointClassification.outside;
}

