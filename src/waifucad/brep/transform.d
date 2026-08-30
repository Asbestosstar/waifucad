module waifucad.brep.transform;

import core.stdc.math : sqrt;
import waifucad.brep.geometry : add, scale, normalise;
import waifucad.brep.types;

private BRepVec3 transformPoint(BRepVec3 p, BRepVec3 origin, BRepVec3 xAxis, BRepVec3 yAxis, BRepVec3 zAxis) nothrow @nogc
{
    return add(origin,add(add(scale(xAxis,p.x),scale(yAxis,p.y)),scale(zAxis,p.z)));
}

private BRepVec3 transformDirection(BRepVec3 p, BRepVec3 xAxis, BRepVec3 yAxis, BRepVec3 zAxis) nothrow @nogc
{
    return add(add(scale(xAxis,p.x),scale(yAxis,p.y)),scale(zAxis,p.z));
}

bool transformSolidRigid(BRepArena* arena, BRepId solidId, BRepVec3 origin,
                         BRepVec3 xAxis, BRepVec3 yAxis, BRepVec3 zAxis) nothrow @nogc
{
    auto solid=arena is null?null:arena.solid(solidId); if(solid is null)return false;
    foreach(i;0..solid.vertexCount) { auto v=arena.vertex(solid.firstVertex+cast(BRepId)i); if(v is null)return false; v.point=transformPoint(v.point,origin,xAxis,yAxis,zAxis); }
    foreach(i;0..solid.edgeCount)
    {
        auto e=arena.edge(solid.firstEdge+cast(BRepId)i); if(e is null)return false;
        e.origin=transformPoint(e.origin,origin,xAxis,yAxis,zAxis); e.axis=transformDirection(e.axis,xAxis,yAxis,zAxis); e.referenceDirection=transformDirection(e.referenceDirection,xAxis,yAxis,zAxis);
    }
    foreach(i;0..solid.faceCount)
    {
        auto f=arena.face(solid.firstFace+cast(BRepId)i); if(f is null)return false;
        f.origin=transformPoint(f.origin,origin,xAxis,yAxis,zAxis); f.normal=transformDirection(f.normal,xAxis,yAxis,zAxis); f.axis=transformDirection(f.axis,xAxis,yAxis,zAxis); f.referenceDirection=transformDirection(f.referenceDirection,xAxis,yAxis,zAxis);
    }
    solid.bounds.valid=false;
    if(solid.primitiveKind==BRepPrimitiveKind.sphere)
    {
        auto centre=origin; auto radius=solid.primitiveA;
        solid.bounds.minimum=BRepVec3(centre.x-radius,centre.y-radius,centre.z-radius);
        solid.bounds.maximum=BRepVec3(centre.x+radius,centre.y+radius,centre.z+radius); solid.bounds.valid=true; return true;
    }
    if(solid.primitiveKind==BRepPrimitiveKind.torus)
    {
        BRepFace* torusFace=null; foreach(i;0..solid.faceCount){auto f=arena.face(solid.firstFace+cast(BRepId)i);if(f !is null&&f.surfaceKind==BRepSurfaceKind.torus){torusFace=f;break;}}
        if(torusFace is null)return false; bool axisOk=false; auto unitAxis=normalise(torusFace.axis,&axisOk); if(!axisOk)return false;
        auto extent=solid.primitiveA+solid.primitiveB; auto tube=solid.primitiveB;
        auto ex=sqrt(extent*extent*(1.0-unitAxis.x*unitAxis.x)+tube*tube*unitAxis.x*unitAxis.x);
        auto ey=sqrt(extent*extent*(1.0-unitAxis.y*unitAxis.y)+tube*tube*unitAxis.y*unitAxis.y);
        auto ez=sqrt(extent*extent*(1.0-unitAxis.z*unitAxis.z)+tube*tube*unitAxis.z*unitAxis.z);
        auto centre=torusFace.origin; solid.bounds.minimum=BRepVec3(centre.x-ex,centre.y-ey,centre.z-ez); solid.bounds.maximum=BRepVec3(centre.x+ex,centre.y+ey,centre.z+ez); solid.bounds.valid=true; return true;
    }
    if(solid.primitiveKind==BRepPrimitiveKind.cylinder||solid.primitiveKind==BRepPrimitiveKind.coneFrustum)
    {
        BRepFace* side=null; foreach(i;0..solid.faceCount) { auto f=arena.face(solid.firstFace+cast(BRepId)i); if(f !is null&&(f.surfaceKind==BRepSurfaceKind.cylinder||f.surfaceKind==BRepSurfaceKind.cone)){side=f;break;} }
        if(side is null)return false; auto r=solid.primitiveKind==BRepPrimitiveKind.cylinder?solid.primitiveA:(solid.primitiveA>solid.primitiveB?solid.primitiveA:solid.primitiveB);
        auto height=solid.primitiveKind==BRepPrimitiveKind.cylinder?solid.primitiveB:solid.primitiveC; auto base=side.origin; auto top=add(base,scale(side.axis,height));
        auto ex=r*sqrt(1.0-side.axis.x*side.axis.x); auto ey=r*sqrt(1.0-side.axis.y*side.axis.y); auto ez=r*sqrt(1.0-side.axis.z*side.axis.z);
        solid.bounds.minimum=BRepVec3((base.x<top.x?base.x:top.x)-ex,(base.y<top.y?base.y:top.y)-ey,(base.z<top.z?base.z:top.z)-ez);
        solid.bounds.maximum=BRepVec3((base.x>top.x?base.x:top.x)+ex,(base.y>top.y?base.y:top.y)+ey,(base.z>top.z?base.z:top.z)+ez); solid.bounds.valid=true;
        return true;
    }
    foreach(i;0..solid.vertexCount)
    {
        auto p=arena.vertex(solid.firstVertex+cast(BRepId)i).point;
        if(!solid.bounds.valid){solid.bounds.minimum=p;solid.bounds.maximum=p;solid.bounds.valid=true;}
        else { if(p.x<solid.bounds.minimum.x)solid.bounds.minimum.x=p.x;if(p.y<solid.bounds.minimum.y)solid.bounds.minimum.y=p.y;if(p.z<solid.bounds.minimum.z)solid.bounds.minimum.z=p.z;
               if(p.x>solid.bounds.maximum.x)solid.bounds.maximum.x=p.x;if(p.y>solid.bounds.maximum.y)solid.bounds.maximum.y=p.y;if(p.z>solid.bounds.maximum.z)solid.bounds.maximum.z=p.z; }
    }
    return solid.bounds.valid;
}

