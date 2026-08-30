module waifucad.mesh.tessellate_brep;

import core.stdc.math : fabs;
import waifucad.core.jobs : CancellationToken, isCancelled;
import waifucad.brep.geometry : evaluateCoedge, evaluateFace, faceNormalAt, normalise;
import waifucad.brep.types;
import waifucad.interchange.openscad.options : OpenScadExportOptions;
import waifucad.mesh.tessellate : segmentsForRadius;
import waifucad.mesh.types : MeshArena, MeshId, MeshVec3;

private enum double WC_PI=3.14159265358979323846264338327950288;
private enum uint WC_FACE_SAMPLE_LIMIT=256;
private enum uint WC_FACE_TRIANGULATION_LIMIT=512;
private enum uint WC_FACE_LOOP_LIMIT=32;
enum WC_TESSELLATION_CANCELLED=39;

private bool cancellationRequested(const(CancellationToken)* token) nothrow @nogc
{
    return token !is null && isCancelled(token);
}

private MeshVec3 meshPoint(BRepVec3 point,double scale) nothrow @nogc
{
    return MeshVec3(point.x*scale,point.y*scale,point.z*scale);
}

private bool triangle(MeshArena* arena,MeshId id,uint a,uint b,uint c,bool reverse) nothrow @nogc
{
    return reverse?arena.addTriangle(id,a,c,b):arena.addTriangle(id,a,b,c);
}

private uint edgeSteps(BRepArena* arena,BRepId edgeId,const OpenScadExportOptions* options) nothrow @nogc
{
    auto edge=arena.edge(edgeId); if(edge is null)return 0;
    final switch(edge.curveKind)
    {
        case BRepCurveKind.line:return 1;
        case BRepCurveKind.circle:return segmentsForRadius(edge.radius,options);
        case BRepCurveKind.bspline:
        case BRepCurveKind.ellipse:return options.minimumSegments<8?8u:options.minimumSegments;
        case BRepCurveKind.none:return 0;
    }
}

private bool collectLoopBoundary(BRepArena* brep,BRepId loopId,const OpenScadExportOptions* options,
                                 BRepVec3* points,uint capacity,uint* pointCount,const(CancellationToken)* token) nothrow @nogc
{
    if(brep is null||options is null||points is null||pointCount is null||loopId==0||capacity<3)return false;
    auto loop=brep.loop(loopId); if(loop is null||loop.firstCoedge==0||loop.coedgeCount==0)return false;
    uint count=0; auto current=loop.firstCoedge;
    foreach(_;0..loop.coedgeCount)
    {
        if(cancellationRequested(token))return false;
        auto coedge=brep.coedge(current); if(coedge is null)return false; auto steps=edgeSteps(brep,coedge.edge,options); if(steps==0)return false;
        foreach(sample;0..steps)
        {
            if((sample&31u)==0u&&cancellationRequested(token))return false;
            if(count>=capacity)return false; bool ok=false; auto t=cast(double)sample/cast(double)steps;
            auto point=evaluateCoedge(brep,current,t,&ok); if(!ok)return false;
            if(count==0||fabs(points[count-1].x-point.x)>1.0e-10||fabs(points[count-1].y-point.y)>1.0e-10||fabs(points[count-1].z-point.z)>1.0e-10)
                points[count++]=point;
        }
        current=coedge.next;
    }
    *pointCount=count; return count>=3;
}

private bool collectBoundary(BRepArena* brep,const BRepFace* face,const OpenScadExportOptions* options,
                             BRepVec3* points,uint* pointCount,const(CancellationToken)* token) nothrow @nogc
{
    if(face is null||face.outerLoop==0)return false;
    return collectLoopBoundary(brep,face.outerLoop,options,points,WC_FACE_SAMPLE_LIMIT,pointCount,token);
}

private void project2d(BRepVec3 p,BRepVec3 normal,double* x,double* y) nothrow @nogc
{
    auto ax=fabs(normal.x),ay=fabs(normal.y),az=fabs(normal.z);
    if(ax>=ay&&ax>=az){*x=p.y;*y=p.z;}
    else if(ay>=az){*x=p.x;*y=p.z;}
    else {*x=p.x;*y=p.y;}
}

private double cross2(double ax,double ay,double bx,double by,double cx,double cy) nothrow @nogc
{
    return (bx-ax)*(cy-ay)-(by-ay)*(cx-ax);
}

private bool insideTriangle(double px,double py,double ax,double ay,double bx,double by,double cx,double cy,double orientation) nothrow @nogc
{
    auto c0=cross2(ax,ay,bx,by,px,py)*orientation;
    auto c1=cross2(bx,by,cx,cy,px,py)*orientation;
    auto c2=cross2(cx,cy,ax,ay,px,py)*orientation;
    return c0>=-1.0e-12&&c1>=-1.0e-12&&c2>=-1.0e-12;
}

private bool same2d(double ax,double ay,double bx,double by) nothrow @nogc
{
    return fabs(ax-bx)<=1.0e-10&&fabs(ay-by)<=1.0e-10;
}

private double signedArea2d(const(double)* xs,const(double)* ys,uint start,uint count) nothrow @nogc
{
    double area=0.0;
    foreach(i;0..count){auto j=(i+1)%count;area+=xs[start+i]*ys[start+j]-xs[start+j]*ys[start+i];}
    return area*0.5;
}

private bool pointOnSegment2d(double px,double py,double ax,double ay,double bx,double by) nothrow @nogc
{
    if(fabs(cross2(ax,ay,bx,by,px,py))>1.0e-10)return false;
    auto minX=ax<bx?ax:bx,maxX=ax>bx?ax:bx,minY=ay<by?ay:by,maxY=ay>by?ay:by;
    return px>=minX-1.0e-10&&px<=maxX+1.0e-10&&py>=minY-1.0e-10&&py<=maxY+1.0e-10;
}

private bool pointInLoop2d(double px,double py,const(double)* xs,const(double)* ys,uint start,uint count) nothrow @nogc
{
    bool inside=false;
    foreach(i;0..count)
    {
        auto j=(i+1)%count;auto ax=xs[start+i],ay=ys[start+i],bx=xs[start+j],by=ys[start+j];
        if(pointOnSegment2d(px,py,ax,ay,bx,by))return true;
        if((ay>py)!=(by>py))
        {
            auto xAtY=ax+(py-ay)*(bx-ax)/(by-ay);
            if(xAtY>px)inside=!inside;
        }
    }
    return inside;
}

private int orientation2d(double ax,double ay,double bx,double by,double cx,double cy) nothrow @nogc
{
    auto value=cross2(ax,ay,bx,by,cx,cy);
    if(value>1.0e-10)return 1;
    if(value<-1.0e-10)return -1;
    return 0;
}

private bool segmentsIntersect2d(double ax,double ay,double bx,double by,
                                 double cx,double cy,double dx,double dy) nothrow @nogc
{
    auto o1=orientation2d(ax,ay,bx,by,cx,cy),o2=orientation2d(ax,ay,bx,by,dx,dy);
    auto o3=orientation2d(cx,cy,dx,dy,ax,ay),o4=orientation2d(cx,cy,dx,dy,bx,by);
    if(o1!=o2&&o3!=o4)return true;
    if(o1==0&&pointOnSegment2d(cx,cy,ax,ay,bx,by))return true;
    if(o2==0&&pointOnSegment2d(dx,dy,ax,ay,bx,by))return true;
    if(o3==0&&pointOnSegment2d(ax,ay,cx,cy,dx,dy))return true;
    if(o4==0&&pointOnSegment2d(bx,by,cx,cy,dx,dy))return true;
    return false;
}

private bool bridgeCrossesPath(double ax,double ay,double bx,double by,const(double)* xs,const(double)* ys,uint count) nothrow @nogc
{
    foreach(i;0..count)
    {
        auto j=(i+1)%count;auto cx=xs[i],cy=ys[i],dx=xs[j],dy=ys[j];
        if(same2d(cx,cy,ax,ay)||same2d(dx,dy,ax,ay)||same2d(cx,cy,bx,by)||same2d(dx,dy,bx,by))continue;
        if(segmentsIntersect2d(ax,ay,bx,by,cx,cy,dx,dy))return true;
    }
    return false;
}

private bool bridgeCrossesOriginalLoops(double ax,double ay,double bx,double by,const(double)* xs,const(double)* ys,
                                        const(uint)* starts,const(uint)* counts,uint loopCount) nothrow @nogc
{
    foreach(loopIndex;0..loopCount)
    {
        auto start=starts[loopIndex],count=counts[loopIndex];
        foreach(i;0..count)
        {
            auto j=(i+1)%count;auto cx=xs[start+i],cy=ys[start+i],dx=xs[start+j],dy=ys[start+j];
            if(same2d(cx,cy,ax,ay)||same2d(dx,dy,ax,ay)||same2d(cx,cy,bx,by)||same2d(dx,dy,bx,by))continue;
            if(segmentsIntersect2d(ax,ay,bx,by,cx,cy,dx,dy))return true;
        }
    }
    return false;
}

private bool pointInSampledFace(double px,double py,const(double)* xs,const(double)* ys,
                                const(uint)* starts,const(uint)* counts,uint loopCount) nothrow @nogc
{
    if(loopCount==0||!pointInLoop2d(px,py,xs,ys,starts[0],counts[0]))return false;
    foreach(loopIndex;1..loopCount)
        if(pointInLoop2d(px,py,xs,ys,starts[loopIndex],counts[loopIndex]))return false;
    return true;
}

private bool triangulateBridgedPolygon(MeshArena* mesh,MeshId meshId,const(BRepVec3)* points,const(double)* xs,const(double)* ys,
                                       uint count,double unitScale,bool reverse,const(CancellationToken)* token) nothrow @nogc
{
    if(mesh is null||points is null||xs is null||ys is null||count<3||count>WC_FACE_TRIANGULATION_LIMIT)return false;
    auto area=signedArea2d(xs,ys,0,count);if(fabs(area)<=1.0e-14)return false;auto orientation=area>0.0?1.0:-1.0;
    uint base=mesh.mesh(meshId).vertexCount;foreach(i;0..count)if(!mesh.addVertex(meshId,meshPoint(points[i],unitScale)))return false;
    uint[WC_FACE_TRIANGULATION_LIMIT] remaining;foreach(i;0..count)remaining[i]=i;uint active=count;uint guard=0;
    while(active>3)
    {
        if(cancellationRequested(token))return false;
        bool clipped=false;
        foreach(k;0..active)
        {
            auto prev=remaining[(k+active-1)%active],cur=remaining[k],next=remaining[(k+1)%active];
            auto turn=cross2(xs[prev],ys[prev],xs[cur],ys[cur],xs[next],ys[next])*orientation;
            if(turn<=1.0e-14)continue;
            bool contains=false;
            foreach(q;0..active)
            {
                auto candidate=remaining[q];if(candidate==prev||candidate==cur||candidate==next)continue;
                if(same2d(xs[candidate],ys[candidate],xs[prev],ys[prev])||same2d(xs[candidate],ys[candidate],xs[cur],ys[cur])||same2d(xs[candidate],ys[candidate],xs[next],ys[next]))continue;
                if(insideTriangle(xs[candidate],ys[candidate],xs[prev],ys[prev],xs[cur],ys[cur],xs[next],ys[next],orientation)){contains=true;break;}
            }
            if(contains)continue;
            if(!triangle(mesh,meshId,base+prev,base+cur,base+next,reverse))return false;
            foreach(move;k..active-1)remaining[move]=remaining[move+1];--active;clipped=true;break;
        }
        if(!clipped)
        {
            // Weakly-simple bridge polygons can retain a collinear duplicate at
            // a bridge. Remove only a geometrically redundant vertex; never
            // invent a triangle across a hole.
            bool removed=false;
            foreach(k;0..active)
            {
                auto prev=remaining[(k+active-1)%active],cur=remaining[k],next=remaining[(k+1)%active];
                if(fabs(cross2(xs[prev],ys[prev],xs[cur],ys[cur],xs[next],ys[next]))<=1.0e-14)
                {foreach(move;k..active-1)remaining[move]=remaining[move+1];--active;removed=true;break;}
            }
            if(!removed)return false;
        }
        if(++guard>count*count*2)return false;
    }
    return active==3&&triangle(mesh,meshId,base+remaining[0],base+remaining[1],base+remaining[2],reverse);
}

private int tessellatePlanarMultiLoop(MeshArena* mesh,MeshId meshId,BRepArena* brep,const BRepFace* face,
                                      const OpenScadExportOptions* options,const(CancellationToken)* token) nothrow @nogc
{
    if(mesh is null||brep is null||face is null||options is null||face.loopCount<2||face.loopCount>WC_FACE_LOOP_LIMIT)return 40;
    bool normalOk=false;auto normal=normalise(face.normal,&normalOk);if(!normalOk)return 41;

    BRepVec3[WC_FACE_TRIANGULATION_LIMIT] originalPoints;double[WC_FACE_TRIANGULATION_LIMIT] originalX,originalY;
    uint[WC_FACE_LOOP_LIMIT] starts,counts;uint loopCount=0,total=0;
    BRepVec3[WC_FACE_SAMPLE_LIMIT] sampled;

    // Store the outer loop first regardless of its arena index so point-in-face
    // tests remain deterministic when topology creation order changes.
    uint outerCount=0;if(!collectLoopBoundary(brep,face.outerLoop,options,sampled.ptr,WC_FACE_SAMPLE_LIMIT,&outerCount,token))return cancellationRequested(token)?WC_TESSELLATION_CANCELLED:42;
    if(total+outerCount>WC_FACE_TRIANGULATION_LIMIT)return 43;starts[loopCount]=total;counts[loopCount]=outerCount;
    foreach(i;0..outerCount){originalPoints[total+i]=sampled[i];project2d(sampled[i],normal,&originalX[total+i],&originalY[total+i]);}total+=outerCount;++loopCount;
    foreach(offset;0..face.loopCount)
    {
        auto loopId=face.firstLoop+cast(BRepId)offset;if(loopId==face.outerLoop)continue;
        if(loopCount>=WC_FACE_LOOP_LIMIT)return 44;uint sampleCount=0;
        if(!collectLoopBoundary(brep,loopId,options,sampled.ptr,WC_FACE_SAMPLE_LIMIT,&sampleCount,token))return cancellationRequested(token)?WC_TESSELLATION_CANCELLED:45;
        if(total+sampleCount>WC_FACE_TRIANGULATION_LIMIT)return 46;starts[loopCount]=total;counts[loopCount]=sampleCount;
        foreach(i;0..sampleCount){originalPoints[total+i]=sampled[i];project2d(sampled[i],normal,&originalX[total+i],&originalY[total+i]);}total+=sampleCount;++loopCount;
    }

    auto outerArea=signedArea2d(originalX.ptr,originalY.ptr,starts[0],counts[0]);if(fabs(outerArea)<=1.0e-14)return 47;
    auto outerOrientation=outerArea>0.0?1.0:-1.0;
    BRepVec3[WC_FACE_TRIANGULATION_LIMIT] polygon;double[WC_FACE_TRIANGULATION_LIMIT] polygonX,polygonY;uint polygonCount=counts[0];
    foreach(i;0..polygonCount){auto source=starts[0]+i;polygon[i]=originalPoints[source];polygonX[i]=originalX[source];polygonY[i]=originalY[source];}

    foreach(hole;1..loopCount)
    {
        if(cancellationRequested(token))return WC_TESSELLATION_CANCELLED;
        auto holeStart=starts[hole],holeCount=counts[hole];
        auto holeArea=signedArea2d(originalX.ptr,originalY.ptr,holeStart,holeCount);if(fabs(holeArea)<=1.0e-14)return 48;
        bool reverseHole=(holeArea>0.0?1.0:-1.0)==outerOrientation;
        uint bestOuter=uint.max,bestHole=uint.max;double bestDistanceSquared=double.max;
        foreach(outerIndex;0..polygonCount)
        {
            foreach(holeIndex;0..holeCount)
            {
                auto hx=originalX[holeStart+holeIndex],hy=originalY[holeStart+holeIndex];
                auto ox=polygonX[outerIndex],oy=polygonY[outerIndex];
                if(same2d(ox,oy,hx,hy))continue;
                if(bridgeCrossesPath(ox,oy,hx,hy,polygonX.ptr,polygonY.ptr,polygonCount))continue;
                if(bridgeCrossesOriginalLoops(ox,oy,hx,hy,originalX.ptr,originalY.ptr,starts.ptr,counts.ptr,loopCount))continue;
                auto midX=(ox+hx)*0.5,midY=(oy+hy)*0.5;if(!pointInSampledFace(midX,midY,originalX.ptr,originalY.ptr,starts.ptr,counts.ptr,loopCount))continue;
                auto dx=hx-ox,dy=hy-oy,distanceSquared=dx*dx+dy*dy;
                if(distanceSquared<bestDistanceSquared){bestDistanceSquared=distanceSquared;bestOuter=outerIndex;bestHole=holeIndex;}
            }
        }
        if(bestOuter==uint.max||bestHole==uint.max||polygonCount+holeCount+2>WC_FACE_TRIANGULATION_LIMIT)return 49;

        BRepVec3[WC_FACE_TRIANGULATION_LIMIT] nextPolygon;double[WC_FACE_TRIANGULATION_LIMIT] nextX,nextY;uint nextCount=0;
        foreach(i;0..bestOuter+1){nextPolygon[nextCount]=polygon[i];nextX[nextCount]=polygonX[i];nextY[nextCount]=polygonY[i];++nextCount;}
        foreach(step;0..holeCount)
        {
            uint local=reverseHole?(bestHole+holeCount-step)%holeCount:(bestHole+step)%holeCount;auto source=holeStart+local;
            nextPolygon[nextCount]=originalPoints[source];nextX[nextCount]=originalX[source];nextY[nextCount]=originalY[source];++nextCount;
        }
        auto holeSource=holeStart+bestHole;nextPolygon[nextCount]=originalPoints[holeSource];nextX[nextCount]=originalX[holeSource];nextY[nextCount]=originalY[holeSource];++nextCount;
        nextPolygon[nextCount]=polygon[bestOuter];nextX[nextCount]=polygonX[bestOuter];nextY[nextCount]=polygonY[bestOuter];++nextCount;
        foreach(i;bestOuter+1..polygonCount){nextPolygon[nextCount]=polygon[i];nextX[nextCount]=polygonX[i];nextY[nextCount]=polygonY[i];++nextCount;}
        polygonCount=nextCount;foreach(i;0..polygonCount){polygon[i]=nextPolygon[i];polygonX[i]=nextX[i];polygonY[i]=nextY[i];}
    }

    auto reverse=options.reverseWinding!=face.reversed;
    if(!triangulateBridgedPolygon(mesh,meshId,polygon.ptr,polygonX.ptr,polygonY.ptr,polygonCount,options.unitScale,reverse,token))
        return cancellationRequested(token)?WC_TESSELLATION_CANCELLED:50;
    return 0;
}


private int tessellatePlanarAnnulus(MeshArena* mesh,MeshId meshId,BRepArena* brep,const BRepFace* face,
                                    const OpenScadExportOptions* options,const(CancellationToken)* token) nothrow @nogc
{
    if(face.loopCount!=2)return 30; auto outer=brep.loop(face.firstLoop); auto inner=brep.loop(face.firstLoop+1);
    if(outer is null||inner is null||outer.coedgeCount!=1||inner.coedgeCount!=1)return 31;
    auto outerCo=brep.coedge(outer.firstCoedge); auto innerCo=brep.coedge(inner.firstCoedge); if(outerCo is null||innerCo is null)return 32;
    auto outerEdge=brep.edge(outerCo.edge); auto innerEdge=brep.edge(innerCo.edge);
    if(outerEdge is null||innerEdge is null||outerEdge.curveKind!=BRepCurveKind.circle||innerEdge.curveKind!=BRepCurveKind.circle)return 33;
    auto steps=edgeSteps(brep,outerEdge.id,options); auto innerSteps=edgeSteps(brep,innerEdge.id,options); if(innerSteps>steps)steps=innerSteps; if(steps<3)return 34;
    uint base=mesh.mesh(meshId).vertexCount;
    foreach(i;0..steps)
    {
        if((i&31u)==0u&&cancellationRequested(token))return WC_TESSELLATION_CANCELLED;
        bool okOuter=false,okInner=false; auto t=cast(double)i/cast(double)steps;
        auto po=evaluateCoedge(brep,outerCo.id,t,&okOuter); auto pi=evaluateCoedge(brep,innerCo.id,t,&okInner);
        if(!okOuter||!okInner||!mesh.addVertex(meshId,meshPoint(po,options.unitScale))||!mesh.addVertex(meshId,meshPoint(pi,options.unitScale)))return 35;
    }
    auto reverse=options.reverseWinding!=face.reversed;
    foreach(i;0..steps)
    {
        if((i&31u)==0u&&cancellationRequested(token))return WC_TESSELLATION_CANCELLED;
        auto next=(i+1)%steps; auto o0=base+i*2, h0=o0+1, o1=base+next*2, h1=o1+1;
        if(!triangle(mesh,meshId,o0,o1,h1,reverse)||!triangle(mesh,meshId,o0,h1,h0,reverse))return 36;
    }
    return 0;
}

private int tessellatePlanarFace(MeshArena* mesh,MeshId meshId,BRepArena* brep,const BRepFace* face,
                                 const OpenScadExportOptions* options,const(CancellationToken)* token) nothrow @nogc
{
    if(face.loopCount>1)
    {
        // Keep the direct annulus path for its compact regular triangulation,
        // then bridge and ear-clip arbitrary sampled planar inner loops.  A
        // failure remains explicit rather than silently filling a hole.
        if(face.loopCount==2)
        {
            auto annulus=tessellatePlanarAnnulus(mesh,meshId,brep,face,options,token);
            if(annulus==0)return 0;
            if(annulus==WC_TESSELLATION_CANCELLED)return annulus;
        }
        return tessellatePlanarMultiLoop(mesh,meshId,brep,face,options,token);
    }
    BRepVec3[WC_FACE_SAMPLE_LIMIT] points; uint count=0; if(!collectBoundary(brep,face,options,points.ptr,&count,token))return cancellationRequested(token)?WC_TESSELLATION_CANCELLED:1;
    double[WC_FACE_SAMPLE_LIMIT] xs,ys; bool nOk=false; auto normal=normalise(face.normal,&nOk); if(!nOk)return 2;
    double area=0.0; foreach(i;0..count){project2d(points[i],normal,&xs[i],&ys[i]);}
    foreach(i;0..count){auto j=(i+1)%count;area+=xs[i]*ys[j]-xs[j]*ys[i];}
    if(fabs(area)<=1.0e-14)return 3; auto orientation=area>0.0?1.0:-1.0;
    uint base=mesh.mesh(meshId).vertexCount; foreach(i;0..count)if(!mesh.addVertex(meshId,meshPoint(points[i],options.unitScale)))return 4;
    uint[WC_FACE_SAMPLE_LIMIT] remaining; foreach(i;0..count)remaining[i]=i; uint active=count; uint guard=0;
    auto reverse=options.reverseWinding!=face.reversed;
    while(active>3)
    {
        if(cancellationRequested(token))return WC_TESSELLATION_CANCELLED;
        bool clipped=false;
        foreach(k;0..active)
        {
            auto prev=remaining[(k+active-1)%active],cur=remaining[k],next=remaining[(k+1)%active];
            if(cross2(xs[prev],ys[prev],xs[cur],ys[cur],xs[next],ys[next])*orientation<=1.0e-14)continue;
            bool contains=false; foreach(q;0..active){auto candidate=remaining[q];if(candidate==prev||candidate==cur||candidate==next)continue;
                if(insideTriangle(xs[candidate],ys[candidate],xs[prev],ys[prev],xs[cur],ys[cur],xs[next],ys[next],orientation)){contains=true;break;}}
            if(contains)continue; if(!triangle(mesh,meshId,base+prev,base+cur,base+next,reverse))return 5;
            foreach(move;k..active-1)remaining[move]=remaining[move+1]; --active; clipped=true; break;
        }
        if(!clipped||++guard>count*count)return 6;
    }
    if(active==3&&!triangle(mesh,meshId,base+remaining[0],base+remaining[1],base+remaining[2],reverse))return 7;
    return 0;
}

private int tessellateBoundaryFan(MeshArena* mesh,MeshId meshId,BRepArena* brep,const BRepFace* face,
                                  const OpenScadExportOptions* options,const(CancellationToken)* token) nothrow @nogc
{
    // A fan is safe only for a single outer trim.  Reject holes rather than
    // exporting a mesh that fills material which does not exist in the B-rep.
    if(face.loopCount>1)return 38;
    BRepVec3[WC_FACE_SAMPLE_LIMIT] points; uint count=0; if(!collectBoundary(brep,face,options,points.ptr,&count,token))return cancellationRequested(token)?WC_TESSELLATION_CANCELLED:8;
    if(cancellationRequested(token))return WC_TESSELLATION_CANCELLED;
    BRepVec3 centre; foreach(i;0..count){centre.x+=points[i].x;centre.y+=points[i].y;centre.z+=points[i].z;} centre.x/=count;centre.y/=count;centre.z/=count;
    uint base=mesh.mesh(meshId).vertexCount; foreach(i;0..count)if(!mesh.addVertex(meshId,meshPoint(points[i],options.unitScale)))return 9;
    uint centreIndex=0;if(!mesh.addVertex(meshId,meshPoint(centre,options.unitScale),&centreIndex))return 10;
    auto reverse=options.reverseWinding!=face.reversed; foreach(i;0..count){auto next=(i+1)%count;if(!triangle(mesh,meshId,centreIndex,base+i,base+next,reverse))return 11;} return 0;
}

private int tessellateCylinderConeSide(MeshArena* mesh,MeshId meshId,BRepArena* brep,const BRepSolid* solid,
                                       const BRepFace* face,const OpenScadExportOptions* options,const(CancellationToken)* token) nothrow @nogc
{
    auto radius=face.radius>face.secondaryRadius?face.radius:face.secondaryRadius; auto segments=segmentsForRadius(radius,options);
    auto axial=face.surfaceKind==BRepSurfaceKind.cone?face.axialLength:(solid.primitiveKind==BRepPrimitiveKind.cylinder?solid.primitiveB:face.axialLength);
    if(axial<=0.0)return 12; uint base=mesh.mesh(meshId).vertexCount;
    foreach(row;0..2)foreach(i;0..segments){if((i&31u)==0u&&cancellationRequested(token))return WC_TESSELLATION_CANCELLED;bool ok=false;auto point=evaluateFace(brep,face.id,2.0*WC_PI*cast(double)i/cast(double)segments,row==0?0.0:axial,&ok);if(!ok||!mesh.addVertex(meshId,meshPoint(point,options.unitScale)))return 13;}
    auto reverse=options.reverseWinding!=face.reversed;
    foreach(i;0..segments){if((i&31u)==0u&&cancellationRequested(token))return WC_TESSELLATION_CANCELLED;auto next=(i+1)%segments;if(!triangle(mesh,meshId,base+i,base+next,base+segments+next,reverse)||!triangle(mesh,meshId,base+i,base+segments+next,base+segments+i,reverse))return 14;} return 0;
}

private int tessellateSphereFace(MeshArena* mesh,MeshId meshId,BRepArena* brep,const BRepFace* face,const OpenScadExportOptions* options,const(CancellationToken)* token) nothrow @nogc
{
    auto segments=segmentsForRadius(face.radius,options); auto stacks=segments/2; if(stacks<4)stacks=4; uint base=mesh.mesh(meshId).vertexCount;
    foreach(row;0..stacks+1)foreach(i;0..segments){if((i&31u)==0u&&cancellationRequested(token))return WC_TESSELLATION_CANCELLED;auto v=-WC_PI*0.5+WC_PI*cast(double)row/cast(double)stacks;bool ok=false;auto point=evaluateFace(brep,face.id,2.0*WC_PI*cast(double)i/cast(double)segments,v,&ok);if(!ok||!mesh.addVertex(meshId,meshPoint(point,options.unitScale)))return 15;}
    auto reverse=options.reverseWinding!=face.reversed; foreach(row;0..stacks)foreach(i;0..segments){if((i&31u)==0u&&cancellationRequested(token))return WC_TESSELLATION_CANCELLED;auto next=(i+1)%segments;auto a=base+row*segments+i,b=base+row*segments+next,c=base+(row+1)*segments+next,d=base+(row+1)*segments+i;if(!triangle(mesh,meshId,a,b,c,reverse)||!triangle(mesh,meshId,a,c,d,reverse))return 16;} return 0;
}

private int tessellateTorusFace(MeshArena* mesh,MeshId meshId,BRepArena* brep,const BRepFace* face,const OpenScadExportOptions* options,const(CancellationToken)* token) nothrow @nogc
{
    auto majorSegments=segmentsForRadius(face.radius+face.secondaryRadius,options); auto minorSegments=segmentsForRadius(face.secondaryRadius,options); uint base=mesh.mesh(meshId).vertexCount;
    foreach(v;0..minorSegments)foreach(u;0..majorSegments){if((u&31u)==0u&&cancellationRequested(token))return WC_TESSELLATION_CANCELLED;bool ok=false;auto point=evaluateFace(brep,face.id,2.0*WC_PI*cast(double)u/cast(double)majorSegments,2.0*WC_PI*cast(double)v/cast(double)minorSegments,&ok);if(!ok||!mesh.addVertex(meshId,meshPoint(point,options.unitScale)))return 17;}
    auto reverse=options.reverseWinding!=face.reversed; foreach(v;0..minorSegments){if(cancellationRequested(token))return WC_TESSELLATION_CANCELLED;auto vn=(v+1)%minorSegments;foreach(u;0..majorSegments){auto un=(u+1)%majorSegments;auto a=base+v*majorSegments+u,b=base+v*majorSegments+un,c=base+vn*majorSegments+un,d=base+vn*majorSegments+u;if(!triangle(mesh,meshId,a,b,c,reverse)||!triangle(mesh,meshId,a,c,d,reverse))return 18;}} return 0;
}

/* Tessellate from WaifuBRep topology rather than primitive bounding boxes.
 * Planar trimmed loops use ear clipping; full analytic surfaces use their
 * exact parametric evaluators; other trimmed curved/NURBS patches fall back to
 * a sampled boundary fan and remain explicitly a display/interchange mesh. */
int tessellateBRepSolidCancelable(MeshArena* mesh,BRepArena* brep,BRepId solidId,const OpenScadExportOptions* options,
                                  const(CancellationToken)* token,MeshId* result) nothrow @nogc
{
    if(mesh is null||brep is null||options is null||result is null)return 1; auto solid=brep.solid(solidId); if(solid is null||!solid.bounds.valid)return 2;
    auto id=mesh.beginMesh(); if(id==0)return 3; int rc=0;
    foreach(local;0..solid.faceCount)
    {
        if(cancellationRequested(token))return WC_TESSELLATION_CANCELLED;
        auto face=brep.face(solid.firstFace+cast(BRepId)local); if(face is null)return 4;
        final switch(face.surfaceKind)
        {
            case BRepSurfaceKind.plane:rc=tessellatePlanarFace(mesh,id,brep,face,options,token);break;
            case BRepSurfaceKind.cylinder:
            case BRepSurfaceKind.cone:rc=tessellateCylinderConeSide(mesh,id,brep,solid,face,options,token);break;
            case BRepSurfaceKind.sphere:rc=tessellateSphereFace(mesh,id,brep,face,options,token);break;
            case BRepSurfaceKind.torus:rc=tessellateTorusFace(mesh,id,brep,face,options,token);break;
            case BRepSurfaceKind.bspline:rc=tessellateBoundaryFan(mesh,id,brep,face,options,token);break;
            case BRepSurfaceKind.none:rc=20;break;
        }
        if(rc!=0)return rc;
    }
    if(options.centreEachBody){auto target=mesh.mesh(id);if(target !is null&&target.bounds.valid){auto cx=(target.bounds.minimum.x+target.bounds.maximum.x)*0.5,cy=(target.bounds.minimum.y+target.bounds.maximum.y)*0.5,cz=(target.bounds.minimum.z+target.bounds.maximum.z)*0.5;mesh.translateMesh(id,-cx,-cy,-cz);}}
    *result=id;return 0;
}

int tessellateBRepSolid(MeshArena* mesh,BRepArena* brep,BRepId solidId,const OpenScadExportOptions* options,MeshId* result) nothrow @nogc
{
    return tessellateBRepSolidCancelable(mesh,brep,solidId,options,null,result);
}

