module waifucad.brep.advanced;

import core.stdc.math : fabs, cos, sin, atan2;
import waifucad.brep.builder;
import waifucad.brep.geometry : add, subtract, cross, dot, length, normalise, scale, pointsNearlyEqual;
import waifucad.brep.kernel : makeBoxAt;
import waifucad.brep.types;

private enum double WC_ADV_TOL = 1.0e-8;

private BRepId abortAdvanced(BRepArena* arena, BRepArenaMark mark) nothrow @nogc
{
    rollbackArena(arena, mark);
    return 0;
}

private bool addPolygonFace(BRepArena* arena, BRepId shellId, const(BRepId)* vertices,
                            uint count, BRepVec3 normal, bool reverseOrder) nothrow @nogc
{
    if(arena is null || vertices is null || count<3) return false;
    bool nOk=false; normal=normalise(normal,&nOk); if(!nOk) return false;
    auto referenceDirection=subtract(arena.vertex(vertices[reverseOrder?count-1:0]).point,
                                     arena.vertex(vertices[reverseOrder?count-2:1]).point);
    bool rOk=false; referenceDirection=normalise(referenceDirection,&rOk); if(!rOk) return false;
    auto faceId=addPlaneFace(arena,shellId,arena.vertex(vertices[0]).point,normal,referenceDirection);
    auto loopId=addLoop(arena,faceId); if(faceId==0||loopId==0) return false;
    BRepId[64] coedges;
    if(count>coedges.length) return false;
    foreach(i;0..count)
    {
        auto ia=reverseOrder?(count-1-i):i;
        auto ib=reverseOrder?(count-1-((i+1)%count)):((i+1)%count);
        auto a=vertices[ia]; auto b=vertices[ib]; auto edgeId=findLineEdge(arena,a,b);
        if(edgeId==0) edgeId=addLineEdge(arena,a,b); auto edge=arena.edge(edgeId); if(edge is null) return false;
        coedges[i]=addCoedge(arena,loopId,edgeId,!(edge.startVertex==a&&edge.endVertex==b)); if(coedges[i]==0) return false;
    }
    if(!closeLoop(arena,loopId,coedges.ptr,count)) return false; arena.face(faceId).outerLoop=loopId; return true;
}

BRepId makeLinearLoft(BRepArena* arena, const(BRepVec3)* firstPoints, const(BRepVec3)* secondPoints, uint count) nothrow @nogc
{
    if(arena is null||firstPoints is null||secondPoints is null||count<3||count>48) return 0;
    auto mark=markArena(arena);
    auto n0=cross(subtract(firstPoints[1],firstPoints[0]),subtract(firstPoints[2],firstPoints[0]));
    auto n1=cross(subtract(secondPoints[1],secondPoints[0]),subtract(secondPoints[2],secondPoints[0]));
    bool n0ok=false,n1ok=false; n0=normalise(n0,&n0ok); n1=normalise(n1,&n1ok); if(!n0ok||!n1ok) return 0;
    auto centreDelta=subtract(secondPoints[0],firstPoints[0]);
    if(dot(n0,centreDelta)<0.0) n0=scale(n0,-1.0);
    if(dot(n1,centreDelta)<0.0) n1=scale(n1,-1.0);
    auto solidId=addSolid(arena,BRepPrimitiveKind.generic); auto shellId=addShell(arena,solidId); if(solidId==0||shellId==0) return abortAdvanced(arena,mark);
    BRepId[48] bottom; BRepId[48] top;
    foreach(i;0..count) { bottom[i]=addVertex(arena,firstPoints[i]); top[i]=addVertex(arena,secondPoints[i]); if(bottom[i]==0||top[i]==0) return abortAdvanced(arena,mark); }
    if(!addPolygonFace(arena,shellId,bottom.ptr,count,scale(n0,-1.0),true)) return abortAdvanced(arena,mark);
    if(!addPolygonFace(arena,shellId,top.ptr,count,n1,false)) return abortAdvanced(arena,mark);
    foreach(i;0..count)
    {
        auto j=(i+1)%count;
        BRepVec3[4] side=[firstPoints[i],firstPoints[j],secondPoints[j],secondPoints[i]];
        auto sideNormal=cross(subtract(side[1],side[0]),subtract(side[3],side[0]));
        bool sOk=false; auto unit=normalise(sideNormal,&sOk); if(!sOk) return abortAdvanced(arena,mark);
        if(fabs(dot(unit,subtract(side[2],side[0])))>WC_ADV_TOL) return abortAdvanced(arena,mark);
        BRepId[4] ids=[bottom[i],bottom[j],top[j],top[i]];
        if(!addPolygonFace(arena,shellId,ids.ptr,4,unit,false)) return abortAdvanced(arena,mark);
    }
    auto solid=arena.solid(solidId); auto shell=arena.shell(shellId); if(solid is null||shell is null) return abortAdvanced(arena,mark);
    solid.firstVertex=cast(BRepId)(mark.vertices+1); solid.vertexCount=cast(uint)(arena.vertexCount-mark.vertices);
    solid.firstEdge=cast(BRepId)(mark.edges+1); solid.edgeCount=cast(uint)(arena.edgeCount-mark.edges);
    solid.firstFace=cast(BRepId)(mark.faces+1); solid.faceCount=cast(uint)(arena.faceCount-mark.faces);
    solid.bounds.valid=false;
    foreach(i;0..count)
    {
        BRepVec3[2] points=[firstPoints[i],secondPoints[i]];
        foreach(p;points)
        {
            if(!solid.bounds.valid) { solid.bounds.minimum=p; solid.bounds.maximum=p; solid.bounds.valid=true; }
            else { if(p.x<solid.bounds.minimum.x)solid.bounds.minimum.x=p.x; if(p.y<solid.bounds.minimum.y)solid.bounds.minimum.y=p.y; if(p.z<solid.bounds.minimum.z)solid.bounds.minimum.z=p.z;
                   if(p.x>solid.bounds.maximum.x)solid.bounds.maximum.x=p.x; if(p.y>solid.bounds.maximum.y)solid.bounds.maximum.y=p.y; if(p.z>solid.bounds.maximum.z)solid.bounds.maximum.z=p.z; }
        }
    }
    shell.firstFace=solid.firstFace; shell.faceCount=solid.faceCount; shell.closed=true; return solidId;
}

BRepId makePrism(BRepArena* arena, const(BRepVec3)* profilePoints, uint count, BRepVec3 extrusion) nothrow @nogc
{
    if(profilePoints is null||count<3||count>48||length(extrusion)<=WC_ADV_TOL) return 0;
    BRepVec3[48] top; foreach(i;0..count) top[i]=add(profilePoints[i],extrusion);
    return makeLinearLoft(arena,profilePoints,top.ptr,count);
}


private void expandBounds(BRepBounds* bounds,BRepVec3 point) nothrow @nogc
{
    if(bounds is null)return;
    if(!bounds.valid){bounds.minimum=point;bounds.maximum=point;bounds.valid=true;return;}
    if(point.x<bounds.minimum.x)bounds.minimum.x=point.x;if(point.y<bounds.minimum.y)bounds.minimum.y=point.y;if(point.z<bounds.minimum.z)bounds.minimum.z=point.z;
    if(point.x>bounds.maximum.x)bounds.maximum.x=point.x;if(point.y>bounds.maximum.y)bounds.maximum.y=point.y;if(point.z>bounds.maximum.z)bounds.maximum.z=point.z;
}

private double normaliseParameter(double value) nothrow @nogc
{
    while(value<0.0)value+=2.0*WC_REV_PI;while(value>=2.0*WC_REV_PI)value-=2.0*WC_REV_PI;return value;
}

private void expandArcBounds(BRepBounds* bounds,const(BRepProfileSegment)* segment,BRepVec3 centreOffset) nothrow @nogc
{
    if(bounds is null||segment is null||segment.kind!=BRepProfileSegmentKind.circularArc)return;
    auto centre=add(segment.centre,centreOffset);bool axisOk=false,refOk=false;
    auto axis=normalise(segment.axis,&axisOk);auto u=normalise(segment.referenceDirection,&refOk);if(!axisOk||!refOk)return;
    auto v=cross(axis,u);bool vOk=false;v=normalise(v,&vOk);if(!vOk)return;
    double[8] candidates;uint count=0;candidates[count++]=0.0;candidates[count++]=segment.parameterEnd;
    double[3] uc=[u.x,u.y,u.z];double[3] vc=[v.x,v.y,v.z];
    foreach(component;0..3)
    {
        if(fabs(uc[component])<=WC_ADV_TOL&&fabs(vc[component])<=WC_ADV_TOL)continue;
        auto base=normaliseParameter(atan2(vc[component],uc[component]));auto opposite=normaliseParameter(base+WC_REV_PI);
        if(base<=segment.parameterEnd+WC_ADV_TOL)candidates[count++]=base;
        if(opposite<=segment.parameterEnd+WC_ADV_TOL)candidates[count++]=opposite;
    }
    foreach(i;0..count)
    {
        auto t=candidates[i];auto radial=add(scale(u,cos(t)),scale(v,sin(t)));
        expandBounds(bounds,add(centre,scale(radial,segment.radius)));
    }
}

/* Exact extrusion of one closed mixed line/circular-arc profile. The cap trims
 * reuse analytic line/arc edges and every circular-arc segment generates one
 * cylindrical side face. This deliberately handles one unambiguous outer loop
 * only; holes and multiple regions remain a separate region-selection problem. */
BRepId makeProfilePrism(BRepArena* arena,const(BRepProfileSegment)* segments,uint count,BRepVec3 extrusion) nothrow @nogc
{
    if(arena is null||segments is null||count<2||count>48||length(extrusion)<=WC_ADV_TOL)return 0;
    foreach(i;0..count)
    {
        auto next=(i+1)%count;
        if(!pointsNearlyEqual(segments[i].finish,segments[next].start,1.0e-7))return 0;
        if(segments[i].kind==BRepProfileSegmentKind.circularArc&&(segments[i].radius<=0.0||segments[i].parameterEnd<=0.0))return 0;
    }
    auto mark=markArena(arena);bool axisOk=false;auto extrusionAxis=normalise(extrusion,&axisOk);if(!axisOk)return 0;
    auto solidId=addSolid(arena,BRepPrimitiveKind.generic);auto shellId=addShell(arena,solidId);if(solidId==0||shellId==0)return abortAdvanced(arena,mark);
    BRepId[48] bottomVertices;BRepId[48] topVertices;BRepId[48] bottomEdges;BRepId[48] topEdges;BRepId[48] verticalEdges;
    foreach(i;0..count)
    {
        bottomVertices[i]=addVertex(arena,segments[i].start);topVertices[i]=addVertex(arena,add(segments[i].start,extrusion));
        if(bottomVertices[i]==0||topVertices[i]==0)return abortAdvanced(arena,mark);
    }
    foreach(i;0..count)
    {
        auto next=(i+1)%count;auto segment=&segments[i];
        if(segment.kind==BRepProfileSegmentKind.line)
        {
            bottomEdges[i]=addLineEdge(arena,bottomVertices[i],bottomVertices[next]);
            topEdges[i]=addLineEdge(arena,topVertices[i],topVertices[next]);
        }
        else
        {
            bottomEdges[i]=addCircleArcEdge(arena,bottomVertices[i],bottomVertices[next],segment.centre,segment.axis,segment.referenceDirection,segment.radius,0.0,segment.parameterEnd);
            topEdges[i]=addCircleArcEdge(arena,topVertices[i],topVertices[next],add(segment.centre,extrusion),segment.axis,segment.referenceDirection,segment.radius,0.0,segment.parameterEnd);
        }
        verticalEdges[i]=addLineEdge(arena,bottomVertices[i],topVertices[i]);
        if(bottomEdges[i]==0||topEdges[i]==0||verticalEdges[i]==0)return abortAdvanced(arena,mark);
    }

    BRepVec3 reference=segments[0].kind==BRepProfileSegmentKind.circularArc?segments[0].referenceDirection:subtract(segments[0].finish,segments[0].start);
    bool refOk=false;reference=normalise(reference,&refOk);if(!refOk)return abortAdvanced(arena,mark);
    auto bottomFace=addPlaneFace(arena,shellId,segments[0].start,scale(extrusionAxis,-1.0),reference);
    auto topFace=addPlaneFace(arena,shellId,add(segments[0].start,extrusion),extrusionAxis,reference);
    if(bottomFace==0||topFace==0)return abortAdvanced(arena,mark);
    auto bottomLoop=addLoop(arena,bottomFace);auto topLoop=addLoop(arena,topFace);if(bottomLoop==0||topLoop==0)return abortAdvanced(arena,mark);
    BRepId[48] bottomCoedges;BRepId[48] topCoedges;
    foreach(i;0..count)
    {
        auto reverseIndex=count-1-i;
        bottomCoedges[i]=addCoedge(arena,bottomLoop,bottomEdges[reverseIndex],true);
        topCoedges[i]=addCoedge(arena,topLoop,topEdges[i],false);
        if(bottomCoedges[i]==0||topCoedges[i]==0)return abortAdvanced(arena,mark);
    }
    if(!closeLoop(arena,bottomLoop,bottomCoedges.ptr,count)||!closeLoop(arena,topLoop,topCoedges.ptr,count))return abortAdvanced(arena,mark);
    arena.face(bottomFace).outerLoop=bottomLoop;arena.face(topFace).outerLoop=topLoop;

    foreach(i;0..count)
    {
        auto next=(i+1)%count;auto segment=&segments[i];BRepId faceId=0;
        if(segment.kind==BRepProfileSegmentKind.line)
        {
            auto tangent=subtract(segment.finish,segment.start);auto sideNormal=cross(tangent,extrusion);bool normalOk=false;sideNormal=normalise(sideNormal,&normalOk);if(!normalOk)return abortAdvanced(arena,mark);
            faceId=addPlaneFace(arena,shellId,segment.start,sideNormal,normalise(tangent,&normalOk));if(!normalOk||faceId==0)return abortAdvanced(arena,mark);
        }
        else
        {
            faceId=addCylinderFace(arena,shellId,segment.centre,extrusionAxis,segment.referenceDirection,segment.radius);if(faceId==0)return abortAdvanced(arena,mark);
            arena.face(faceId).axialLength=length(extrusion);
        }
        auto loopId=addLoop(arena,faceId);if(loopId==0)return abortAdvanced(arena,mark);
        BRepId[4] ring;
        ring[0]=addCoedge(arena,loopId,bottomEdges[i],false);
        ring[1]=addCoedge(arena,loopId,verticalEdges[next],false);
        ring[2]=addCoedge(arena,loopId,topEdges[i],true);
        ring[3]=addCoedge(arena,loopId,verticalEdges[i],true);
        foreach(k;0..4)if(ring[k]==0)return abortAdvanced(arena,mark);
        if(!closeLoop(arena,loopId,ring.ptr,4))return abortAdvanced(arena,mark);arena.face(faceId).outerLoop=loopId;
    }
    auto solid=arena.solid(solidId);auto shell=arena.shell(shellId);if(solid is null||shell is null)return abortAdvanced(arena,mark);
    solid.firstVertex=cast(BRepId)(mark.vertices+1);solid.vertexCount=cast(uint)(arena.vertexCount-mark.vertices);
    solid.firstEdge=cast(BRepId)(mark.edges+1);solid.edgeCount=cast(uint)(arena.edgeCount-mark.edges);
    solid.firstFace=cast(BRepId)(mark.faces+1);solid.faceCount=cast(uint)(arena.faceCount-mark.faces);
    solid.bounds.valid=false;
    foreach(i;0..count)
    {
        expandBounds(&solid.bounds,segments[i].start);expandBounds(&solid.bounds,add(segments[i].start,extrusion));
        if(segments[i].kind==BRepProfileSegmentKind.circularArc)
        {
            expandArcBounds(&solid.bounds,&segments[i],BRepVec3(0,0,0));
            expandArcBounds(&solid.bounds,&segments[i],extrusion);
        }
    }
    shell.firstFace=solid.firstFace;shell.faceCount=solid.faceCount;shell.closed=true;return solidId;
}

private BRepId coalesceBoxesAsCavity(BRepArena* arena, BRepId outerId, BRepId innerId, double thicknessHint) nothrow @nogc
{
    auto outer=arena.solid(outerId); auto inner=arena.solid(innerId); if(outer is null||inner is null||innerId!=arena.solidCount) return 0;
    auto innerShell=arena.shell(inner.shell); if(innerShell is null) return 0;
    innerShell.solid=outer.id;
    foreach(i;0..inner.faceCount) { auto face=arena.face(inner.firstFace+cast(BRepId)i); if(face is null)return 0; face.reversed=!face.reversed; }
    outer.shellCount=2; outer.firstShell=outer.shell; outer.vertexCount+=inner.vertexCount; outer.edgeCount+=inner.edgeCount; outer.faceCount+=inner.faceCount;
    outer.primitiveKind=BRepPrimitiveKind.boxShell; outer.primitiveD=thicknessHint; --arena.solidCount; return outerId;
}

BRepId makeBoxShellAt(BRepArena* arena,double width,double depth,double height,double thickness,double centreX,double centreY,double baseZ) nothrow @nogc
{
    if(arena is null||thickness<=0.0||width<=2*thickness||depth<=2*thickness||height<=2*thickness) return 0;
    auto mark=markArena(arena); auto outer=makeBoxAt(arena,width,depth,height,centreX,centreY,baseZ); if(outer==0)return 0;
    auto inner=makeBoxAt(arena,width-2*thickness,depth-2*thickness,height-2*thickness,centreX,centreY,baseZ+thickness);
    if(inner==0) return abortAdvanced(arena,mark); auto result=coalesceBoxesAsCavity(arena,outer,inner,thickness); if(result==0)return abortAdvanced(arena,mark); return result;
}

BRepId makeBoxCavity(BRepArena* arena,const BRepBounds* outerBounds,const BRepBounds* innerBounds) nothrow @nogc
{
    if(arena is null||outerBounds is null||innerBounds is null||!outerBounds.valid||!innerBounds.valid) return 0;
    if(innerBounds.minimum.x<=outerBounds.minimum.x||innerBounds.maximum.x>=outerBounds.maximum.x||
       innerBounds.minimum.y<=outerBounds.minimum.y||innerBounds.maximum.y>=outerBounds.maximum.y||
       innerBounds.minimum.z<=outerBounds.minimum.z||innerBounds.maximum.z>=outerBounds.maximum.z) return 0;
    auto mark=markArena(arena);
    auto ow=outerBounds.maximum.x-outerBounds.minimum.x, od=outerBounds.maximum.y-outerBounds.minimum.y, oh=outerBounds.maximum.z-outerBounds.minimum.z;
    auto ocx=(outerBounds.minimum.x+outerBounds.maximum.x)*0.5, ocy=(outerBounds.minimum.y+outerBounds.maximum.y)*0.5;
    auto outer=makeBoxAt(arena,ow,od,oh,ocx,ocy,outerBounds.minimum.z); if(outer==0)return 0;
    auto iw=innerBounds.maximum.x-innerBounds.minimum.x, idp=innerBounds.maximum.y-innerBounds.minimum.y, ih=innerBounds.maximum.z-innerBounds.minimum.z;
    auto icx=(innerBounds.minimum.x+innerBounds.maximum.x)*0.5, icy=(innerBounds.minimum.y+innerBounds.maximum.y)*0.5;
    auto inner=makeBoxAt(arena,iw,idp,ih,icx,icy,innerBounds.minimum.z); if(inner==0)return abortAdvanced(arena,mark);
    auto result=coalesceBoxesAsCavity(arena,outer,inner,0.0); if(result==0)return abortAdvanced(arena,mark); return result;
}

BRepId intersectAxisAlignedBoxes(BRepArena* arena,const BRepSolid* a,const BRepSolid* b) nothrow @nogc
{
    if(arena is null||a is null||b is null||a.primitiveKind!=BRepPrimitiveKind.box||b.primitiveKind!=BRepPrimitiveKind.box) return 0;
    auto minX=a.bounds.minimum.x>b.bounds.minimum.x?a.bounds.minimum.x:b.bounds.minimum.x;
    auto minY=a.bounds.minimum.y>b.bounds.minimum.y?a.bounds.minimum.y:b.bounds.minimum.y;
    auto minZ=a.bounds.minimum.z>b.bounds.minimum.z?a.bounds.minimum.z:b.bounds.minimum.z;
    auto maxX=a.bounds.maximum.x<b.bounds.maximum.x?a.bounds.maximum.x:b.bounds.maximum.x;
    auto maxY=a.bounds.maximum.y<b.bounds.maximum.y?a.bounds.maximum.y:b.bounds.maximum.y;
    auto maxZ=a.bounds.maximum.z<b.bounds.maximum.z?a.bounds.maximum.z:b.bounds.maximum.z;
    if(maxX-minX<=WC_ADV_TOL||maxY-minY<=WC_ADV_TOL||maxZ-minZ<=WC_ADV_TOL)return 0;
    return makeBoxAt(arena,maxX-minX,maxY-minY,maxZ-minZ,(minX+maxX)*0.5,(minY+maxY)*0.5,minZ);
}

BRepId uniteAxisAlignedBoxesIfRectangular(BRepArena* arena,const BRepSolid* a,const BRepSolid* b) nothrow @nogc
{
    if(arena is null||a is null||b is null||a.primitiveKind!=BRepPrimitiveKind.box||b.primitiveKind!=BRepPrimitiveKind.box)return 0;
    bool sameX=fabs(a.bounds.minimum.x-b.bounds.minimum.x)<=WC_ADV_TOL&&fabs(a.bounds.maximum.x-b.bounds.maximum.x)<=WC_ADV_TOL;
    bool sameY=fabs(a.bounds.minimum.y-b.bounds.minimum.y)<=WC_ADV_TOL&&fabs(a.bounds.maximum.y-b.bounds.maximum.y)<=WC_ADV_TOL;
    bool sameZ=fabs(a.bounds.minimum.z-b.bounds.minimum.z)<=WC_ADV_TOL&&fabs(a.bounds.maximum.z-b.bounds.maximum.z)<=WC_ADV_TOL;
    if(cast(uint)sameX+cast(uint)sameY+cast(uint)sameZ<2u)return 0;
    // A rectangular union may extend along at most one axis, and the two
    // intervals on that axis must overlap or touch. Bridging a real gap would
    // invent material and is therefore not an exact boolean.
    if(!sameX && (a.bounds.maximum.x < b.bounds.minimum.x-WC_ADV_TOL || b.bounds.maximum.x < a.bounds.minimum.x-WC_ADV_TOL)) return 0;
    if(!sameY && (a.bounds.maximum.y < b.bounds.minimum.y-WC_ADV_TOL || b.bounds.maximum.y < a.bounds.minimum.y-WC_ADV_TOL)) return 0;
    if(!sameZ && (a.bounds.maximum.z < b.bounds.minimum.z-WC_ADV_TOL || b.bounds.maximum.z < a.bounds.minimum.z-WC_ADV_TOL)) return 0;
    auto minX=a.bounds.minimum.x<b.bounds.minimum.x?a.bounds.minimum.x:b.bounds.minimum.x; auto maxX=a.bounds.maximum.x>b.bounds.maximum.x?a.bounds.maximum.x:b.bounds.maximum.x;
    auto minY=a.bounds.minimum.y<b.bounds.minimum.y?a.bounds.minimum.y:b.bounds.minimum.y; auto maxY=a.bounds.maximum.y>b.bounds.maximum.y?a.bounds.maximum.y:b.bounds.maximum.y;
    auto minZ=a.bounds.minimum.z<b.bounds.minimum.z?a.bounds.minimum.z:b.bounds.minimum.z; auto maxZ=a.bounds.maximum.z>b.bounds.maximum.z?a.bounds.maximum.z:b.bounds.maximum.z;
    return makeBoxAt(arena,maxX-minX,maxY-minY,maxZ-minZ,(minX+maxX)*0.5,(minY+maxY)*0.5,minZ);
}

private enum double WC_REV_PI = 3.14159265358979323846264338327950288;

/* Exact full revolution of a closed polygon represented in a radial/axial
 * half-plane: point.x is radius >= 0, point.z is axial co-ordinate. Every
 * line segment revolves to an analytic plane/cylinder/cone face. The result
 * supports annular planar faces through multiple face loops. */
BRepId makeAxisymmetricPolygonRevolve(BRepArena* arena, const(BRepVec3)* radialAxialPoints, uint count) nothrow @nogc
{
    if(arena is null || radialAxialPoints is null || count < 3 || count > 48) return 0;
    auto mark=markArena(arena);
    double area=0.0, maximumRadius=0.0, minimumRadius=0.0, minimumZ=0.0, maximumZ=0.0;
    foreach(i;0..count)
    {
        auto p=radialAxialPoints[i]; auto q=radialAxialPoints[(i+1)%count];
        if(p.x < -WC_ADV_TOL || fabs(p.y)>WC_ADV_TOL) return 0;
        area += p.x*q.z-q.x*p.z;
        auto radius=p.x<0.0?0.0:p.x; if(radius>maximumRadius)maximumRadius=radius;
        if(i==0){minimumRadius=radius;minimumZ=maximumZ=p.z;}else{if(radius<minimumRadius)minimumRadius=radius;if(p.z<minimumZ)minimumZ=p.z;if(p.z>maximumZ)maximumZ=p.z;}
    }
    if(fabs(area)<=WC_ADV_TOL || maximumRadius<=WC_ADV_TOL || maximumZ-minimumZ<=WC_ADV_TOL) return 0;
    auto orientation=area>0.0?1.0:-1.0;
    auto solidId=addSolid(arena,BRepPrimitiveKind.generic); if(solidId==0)return 0;
    auto shellId=addShell(arena,solidId); if(shellId==0)return abortAdvanced(arena,mark);
    auto zAxis=BRepVec3(0,0,1), xAxis=BRepVec3(1,0,0);
    BRepId[48] vertices; BRepId[48] circles;
    foreach(i;0..count)
    {
        auto p=radialAxialPoints[i]; auto radius=p.x<WC_ADV_TOL?0.0:p.x;
        vertices[i]=addVertex(arena,radius>0.0?BRepVec3(radius,0,p.z):BRepVec3(0,0,p.z));
        if(vertices[i]==0)return abortAdvanced(arena,mark);
        if(radius>0.0)
        {
            circles[i]=addCircleEdge(arena,vertices[i],BRepVec3(0,0,p.z),zAxis,xAxis,radius,0.0,2.0*WC_REV_PI);
            if(circles[i]==0)return abortAdvanced(arena,mark);
        }
    }

    foreach(i;0..count)
    {
        auto j=(i+1)%count; auto a=radialAxialPoints[i]; auto b=radialAxialPoints[j];
        auto ra=a.x<WC_ADV_TOL?0.0:a.x, rb=b.x<WC_ADV_TOL?0.0:b.x; auto dz=b.z-a.z, dr=rb-ra;
        if(ra<=WC_ADV_TOL && rb<=WC_ADV_TOL) continue; // swept axis segment has zero area
        if(fabs(dz)<=WC_ADV_TOL)
        {
            // Radial segment -> disk or annular plane.
            auto desiredNormalZ=orientation*(-dr);
            auto faceId=addPlaneFace(arena,shellId,BRepVec3(0,0,a.z),desiredNormalZ>=0.0?zAxis:scale(zAxis,-1.0),xAxis);
            if(faceId==0)return abortAdvanced(arena,mark);
            BRepId outerCircle=ra>rb?circles[i]:circles[j]; BRepId innerCircle=ra>rb?circles[j]:circles[i];
            BRepId outerVertex=ra>rb?vertices[i]:vertices[j];
            auto outerLoop=addLoop(arena,faceId); if(outerLoop==0)return abortAdvanced(arena,mark);
            auto outerEdge=arena.edge(outerCircle); if(outerEdge is null)return abortAdvanced(arena,mark);
            bool outerReversed = outerCircle==circles[i] ? false : true;
            auto outerCoedge=addCoedge(arena,outerLoop,outerCircle,outerReversed); BRepId[1] ring=[outerCoedge];
            if(outerCoedge==0||!closeLoop(arena,outerLoop,ring.ptr,1))return abortAdvanced(arena,mark);
            arena.face(faceId).outerLoop=outerLoop;
            if(innerCircle!=0)
            {
                auto innerLoop=addLoop(arena,faceId); if(innerLoop==0)return abortAdvanced(arena,mark);
                bool innerReversed = innerCircle==circles[i] ? false : true;
                auto innerCoedge=addCoedge(arena,innerLoop,innerCircle,innerReversed); BRepId[1] innerRing=[innerCoedge];
                if(innerCoedge==0||!closeLoop(arena,innerLoop,innerRing.ptr,1))return abortAdvanced(arena,mark);
            }
            continue;
        }

        auto axis=dz>0.0?zAxis:scale(zAxis,-1.0); auto height=fabs(dz); BRepId faceId=0;
        if(fabs(dr)<=WC_ADV_TOL)
        {
            faceId=addCylinderFace(arena,shellId,BRepVec3(0,0,a.z),axis,xAxis,ra);
            if(faceId!=0) arena.face(faceId).axialLength=height;
        }
        else
            faceId=addConeFace(arena,shellId,BRepVec3(0,0,a.z),axis,xAxis,ra,rb,height);
        if(faceId==0)return abortAdvanced(arena,mark);
        if(orientation*dz<0.0)arena.face(faceId).reversed=true;
        auto seam=addLineEdge(arena,vertices[i],vertices[j]); if(seam==0)return abortAdvanced(arena,mark);
        auto loopId=addLoop(arena,faceId); if(loopId==0)return abortAdvanced(arena,mark);
        BRepId[4] ring; uint n=0;
        ring[n++]=addCoedge(arena,loopId,seam,false);
        if(circles[j]!=0)ring[n++]=addCoedge(arena,loopId,circles[j],true);
        ring[n++]=addCoedge(arena,loopId,seam,true);
        if(circles[i]!=0)ring[n++]=addCoedge(arena,loopId,circles[i],false);
        foreach(k;0..n)if(ring[k]==0)return abortAdvanced(arena,mark);
        if(!closeLoop(arena,loopId,ring.ptr,n))return abortAdvanced(arena,mark); arena.face(faceId).outerLoop=loopId;
    }

    auto solid=arena.solid(solidId); auto shell=arena.shell(shellId); if(solid is null||shell is null)return abortAdvanced(arena,mark);
    solid.firstVertex=cast(BRepId)(mark.vertices+1); solid.vertexCount=cast(uint)(arena.vertexCount-mark.vertices);
    solid.firstEdge=cast(BRepId)(mark.edges+1); solid.edgeCount=cast(uint)(arena.edgeCount-mark.edges);
    solid.firstFace=cast(BRepId)(mark.faces+1); solid.faceCount=cast(uint)(arena.faceCount-mark.faces);
    solid.genus=minimumRadius>WC_ADV_TOL?1u:0u;
    solid.bounds.minimum=BRepVec3(-maximumRadius,-maximumRadius,minimumZ); solid.bounds.maximum=BRepVec3(maximumRadius,maximumRadius,maximumZ); solid.bounds.valid=true;
    shell.firstFace=solid.firstFace; shell.faceCount=solid.faceCount; shell.closed=true;
    return solidId;
}

