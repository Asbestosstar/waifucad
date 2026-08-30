module waifucad.kernel.profiles;

import core.stdc.ctype : isspace;
import core.stdc.stdlib : strtod;
import core.stdc.math : fabs, cos, sin;
import waifucad.brep.types : BRepVec3, BRepProfileSegment, BRepProfileSegmentKind;
import waifucad.kernel.datums : DatumFrame, framePoint, principalFrame, sketchFrame;
import waifucad.kernel.model : Model;
import waifucad.kernel.types : EntityId, Feature, FeatureKind, OperandKind;

enum ProfileRegionKind : ubyte { none, polygon, circle, mixed }
enum WC_PROFILE_MAX_POINTS = 48;

struct ProfileRegion
{
    ProfileRegionKind kind;
    DatumFrame frame;
    BRepVec3[WC_PROFILE_MAX_POINTS] points;
    uint pointCount;
    BRepProfileSegment[WC_PROFILE_MAX_POINTS] segments;
    uint segmentCount;
    double radius;
    bool valid;
}

private bool parse2dPoints(const(char)* text, const DatumFrame* frame, BRepVec3* points, uint* count) nothrow @nogc
{
    if(text is null||frame is null||points is null||count is null)return false;
    const(char)* cursor=text; uint n=0;
    while(*cursor!=0)
    {
        while(*cursor!=0&&(isspace(cast(ubyte)*cursor)||*cursor=='['||*cursor==']'||*cursor==';'||*cursor==','))++cursor;
        if(*cursor==0)break;
        const(char)* end=null; auto x=strtod(cursor,&end); if(end is cursor)return false; cursor=end;
        while(*cursor!=0&&isspace(cast(ubyte)*cursor))++cursor; if(*cursor!=',')return false; ++cursor;
        while(*cursor!=0&&isspace(cast(ubyte)*cursor))++cursor; auto y=strtod(cursor,&end); if(end is cursor)return false; cursor=end;
        if(n>=WC_PROFILE_MAX_POINTS)return false; points[n++]=framePoint(frame,x,y);
        while(*cursor!=0&&isspace(cast(ubyte)*cursor))++cursor;
        if(*cursor==',')++cursor;
        else if(*cursor==';')++cursor;
        else if(*cursor==']')++cursor;
    }
    *count=n; return n>=3;
}


private bool near2(double ax,double ay,double bx,double by) nothrow @nogc
{
    return fabs(ax-bx)<=1.0e-8 && fabs(ay-by)<=1.0e-8;
}

/* Build one closed polygonal region from the line entities owned by a sketch.
 * Entity order is irrelevant; endpoints are chained by tolerant coincidence. */
private bool resolveSketchLineLoop(Model* model, EntityId sketchId, const DatumFrame* frame, ProfileRegion* result) nothrow @nogc
{
    if(model is null||frame is null||result is null)return false;
    EntityId[WC_PROFILE_MAX_POINTS] ids; bool[WC_PROFILE_MAX_POINTS] used; uint lineCount=0;
    foreach(i;0..model.featureCount)
    {
        auto child=&model.features[i];
        if(child.kind!=FeatureKind.sketchLine||child.operandCount<5||child.operands[0].featureId!=sketchId)continue;
        if(lineCount>=WC_PROFILE_MAX_POINTS)return false; ids[lineCount++]=child.id;
    }
    if(lineCount<3)return false;
    auto first=model.featureById(ids[0]);
    double firstX=model.resolveOperand(&first.operands[1]), firstY=model.resolveOperand(&first.operands[2]);
    double currentX=model.resolveOperand(&first.operands[3]), currentY=model.resolveOperand(&first.operands[4]);
    result.points[0]=framePoint(frame,firstX,firstY); result.points[1]=framePoint(frame,currentX,currentY); uint pointCount=2; used[0]=true;
    foreach(step;1..lineCount)
    {
        bool found=false;
        foreach(candidate;0..lineCount)
        {
            if(used[candidate])continue; auto line=model.featureById(ids[candidate]);
            auto x0=model.resolveOperand(&line.operands[1]), y0=model.resolveOperand(&line.operands[2]);
            auto x1=model.resolveOperand(&line.operands[3]), y1=model.resolveOperand(&line.operands[4]);
            double nextX=0,nextY=0; bool match=false;
            if(near2(currentX,currentY,x0,y0)){nextX=x1;nextY=y1;match=true;}
            else if(near2(currentX,currentY,x1,y1)){nextX=x0;nextY=y0;match=true;}
            if(!match)continue; used[candidate]=true; found=true; currentX=nextX; currentY=nextY;
            if(step+1<lineCount)
            {
                if(pointCount>=WC_PROFILE_MAX_POINTS)return false; result.points[pointCount++]=framePoint(frame,currentX,currentY);
            }
            break;
        }
        if(!found)return false;
    }
    if(!near2(currentX,currentY,firstX,firstY))return false;
    foreach(i;0..lineCount)if(!used[i])return false;
    result.frame=*frame; result.kind=ProfileRegionKind.polygon; result.pointCount=pointCount; result.valid=true; return true;
}

private bool arcSegment(Model* model, const Feature* feature, const DatumFrame* frame,
                        BRepProfileSegment* segment) nothrow @nogc
{
    if(model is null||feature is null||frame is null||segment is null||feature.kind!=FeatureKind.sketchArc||feature.operandCount<6)return false;
    auto cx=model.resolveOperand(&feature.operands[1]), cy=model.resolveOperand(&feature.operands[2]);
    auto radius=model.resolveOperand(&feature.operands[3]); auto startDeg=model.resolveOperand(&feature.operands[4]); auto endDeg=model.resolveOperand(&feature.operands[5]);
    auto deltaDeg=endDeg-startDeg; if(radius<=0.0||fabs(deltaDeg)<=1.0e-10||fabs(deltaDeg)>360.0+1.0e-8)return false;
    auto startRad=startDeg*3.14159265358979323846264338327950288/180.0;
    auto endRad=endDeg*3.14159265358979323846264338327950288/180.0;
    auto sx=cx+radius*cos(startRad), sy=cy+radius*sin(startRad);
    auto ex=cx+radius*cos(endRad), ey=cy+radius*sin(endRad);
    segment.kind=BRepProfileSegmentKind.circularArc;
    segment.start=framePoint(frame,sx,sy); segment.finish=framePoint(frame,ex,ey); segment.centre=framePoint(frame,cx,cy);
    segment.axis=deltaDeg>=0.0?frame.zAxis:BRepVec3(-frame.zAxis.x,-frame.zAxis.y,-frame.zAxis.z);
    auto radial=BRepVec3(segment.start.x-segment.centre.x,segment.start.y-segment.centre.y,segment.start.z-segment.centre.z);
    segment.referenceDirection=BRepVec3(radial.x/radius,radial.y/radius,radial.z/radius);
    segment.radius=radius; segment.parameterEnd=fabs(deltaDeg)*3.14159265358979323846264338327950288/180.0;
    return true;
}

private bool lineSegment(Model* model,const Feature* feature,const DatumFrame* frame,BRepProfileSegment* segment) nothrow @nogc
{
    if(model is null||feature is null||frame is null||segment is null||feature.kind!=FeatureKind.sketchLine||feature.operandCount<5)return false;
    segment.kind=BRepProfileSegmentKind.line;
    segment.start=framePoint(frame,model.resolveOperand(&feature.operands[1]),model.resolveOperand(&feature.operands[2]));
    segment.finish=framePoint(frame,model.resolveOperand(&feature.operands[3]),model.resolveOperand(&feature.operands[4]));
    return true;
}

private double pointDistance2(BRepVec3 a,BRepVec3 b) nothrow @nogc
{
    auto dx=a.x-b.x,dy=a.y-b.y,dz=a.z-b.z;return dx*dx+dy*dy+dz*dz;
}

private void reverseSegment(BRepProfileSegment* segment) nothrow @nogc
{
    auto temporary=segment.start;segment.start=segment.finish;segment.finish=temporary;
    if(segment.kind==BRepProfileSegmentKind.circularArc)
    {
        segment.axis=BRepVec3(-segment.axis.x,-segment.axis.y,-segment.axis.z);
        auto radial=BRepVec3(segment.start.x-segment.centre.x,segment.start.y-segment.centre.y,segment.start.z-segment.centre.z);
        segment.referenceDirection=BRepVec3(radial.x/segment.radius,radial.y/segment.radius,radial.z/segment.radius);
    }
}

private bool resolveSketchMixedLoop(Model* model,EntityId sketchId,const DatumFrame* frame,ProfileRegion* result) nothrow @nogc
{
    if(model is null||frame is null||result is null)return false;
    BRepProfileSegment[WC_PROFILE_MAX_POINTS] source;bool[WC_PROFILE_MAX_POINTS] used;uint count=0;bool hasArc=false;
    foreach(i;0..model.featureCount)
    {
        auto feature=&model.features[i];if(feature.operandCount==0||feature.operands[0].kind!=OperandKind.feature||feature.operands[0].featureId!=sketchId)continue;
        BRepProfileSegment segment;bool ok=false;
        if(feature.kind==FeatureKind.sketchLine)ok=lineSegment(model,feature,frame,&segment);
        else if(feature.kind==FeatureKind.sketchArc){ok=arcSegment(model,feature,frame,&segment);hasArc=true;}
        else continue;
        if(!ok||count>=source.length)return false;source[count++]=segment;
    }
    if(!hasArc||count<2)return false;
    result.segments[0]=source[0];used[0]=true;auto first=result.segments[0].start;auto current=result.segments[0].finish;
    foreach(step;1..count)
    {
        bool found=false;
        foreach(candidate;0..count)
        {
            if(used[candidate])continue;auto segment=source[candidate];
            if(pointDistance2(current,segment.start)<=1.0e-16){}
            else if(pointDistance2(current,segment.finish)<=1.0e-16)reverseSegment(&segment);
            else continue;
            result.segments[step]=segment;used[candidate]=true;current=segment.finish;found=true;break;
        }
        if(!found)return false;
    }
    if(pointDistance2(current,first)>1.0e-16)return false;
    result.frame=*frame;result.kind=ProfileRegionKind.mixed;result.segmentCount=count;result.valid=true;return true;
}

bool resolveProfile(Model* model, EntityId featureId, ProfileRegion* result) nothrow @nogc
{
    if(model is null||result is null)return false; *result=ProfileRegion.init;
    auto feature=model.featureById(featureId); if(feature is null)return false;
    DatumFrame frame;
    if(feature.kind==FeatureKind.sketch)
    {
        if(!sketchFrame(model,feature.id,&frame))return false;
        EntityId regionChild=0; uint regionChildren=0; uint chainChildren=0;
        foreach(i;0..model.featureCount)
        {
            auto child=&model.features[i]; if(child.operandCount==0||child.operands[0].featureId!=feature.id)continue;
            if(child.kind==FeatureKind.sketchCircle||child.kind==FeatureKind.sketchRectangle||child.kind==FeatureKind.sketchPolygon){regionChild=child.id;++regionChildren;}
            else if(child.kind==FeatureKind.sketchLine||child.kind==FeatureKind.sketchArc)++chainChildren;
        }
        if(regionChildren==1&&chainChildren==0)return resolveProfile(model,regionChild,result);
        if(regionChildren==0)
        {
            if(resolveSketchMixedLoop(model,feature.id,&frame,result))return true;
            return resolveSketchLineLoop(model,feature.id,&frame,result);
        }
        return false; // Multiple regions/holes require explicit region selection.
    }
    if(feature.kind==FeatureKind.sketchRectangle||feature.kind==FeatureKind.sketchCircle||feature.kind==FeatureKind.sketchPolygon)
    {
        if(feature.operandCount==0||!sketchFrame(model,feature.operands[0].featureId,&frame))return false;
    }
    else
    {
        if(!principalFrame("XY".ptr,&frame))return false;
    }
    result.frame=frame;
    if(feature.kind==FeatureKind.sketchCircle||feature.kind==FeatureKind.circle2d)
    {
        uint index=feature.kind==FeatureKind.sketchCircle?(feature.operandCount>=4?3u:1u):0u; if(feature.operandCount<=index)return false;
        auto radius=model.resolveOperand(&feature.operands[index]); if(feature.kind==FeatureKind.circle2d&&feature.operandCount>=2&&model.resolveOperand(&feature.operands[1])!=0.0)radius*=0.5;
        if(radius<=0.0)return false;
        if(feature.kind==FeatureKind.sketchCircle && feature.operandCount>=4)
        {
            auto cx=model.resolveOperand(&feature.operands[1]), cy=model.resolveOperand(&feature.operands[2]);
            result.frame.origin=framePoint(&frame,cx,cy);
        }
        result.kind=ProfileRegionKind.circle; result.radius=radius; result.valid=true; return true;
    }
    if(feature.kind==FeatureKind.sketchRectangle||feature.kind==FeatureKind.square2d)
    {
        double minX; double minY; double maxX; double maxY;
        if(feature.kind==FeatureKind.sketchRectangle && feature.operandCount>=5)
        {
            auto originX=model.resolveOperand(&feature.operands[1]); auto originY=model.resolveOperand(&feature.operands[2]);
            auto width=model.resolveOperand(&feature.operands[3]); auto height=model.resolveOperand(&feature.operands[4]); if(width<=0.0||height<=0.0)return false;
            minX=originX; minY=originY; maxX=originX+width; maxY=originY+height;
        }
        else
        {
            uint offset=feature.kind==FeatureKind.sketchRectangle?1u:0u; if(feature.operandCount<offset+2)return false;
            auto width=model.resolveOperand(&feature.operands[offset]); auto height=model.resolveOperand(&feature.operands[offset+1]); if(width<=0.0||height<=0.0)return false;
            auto centred=feature.operandCount>offset+2&&model.resolveOperand(&feature.operands[offset+2])!=0.0;
            minX=centred?-width*0.5:0.0; maxX=centred?width*0.5:width; minY=centred?-height*0.5:0.0; maxY=centred?height*0.5:height;
        }
        result.points[0]=framePoint(&frame,minX,minY); result.points[1]=framePoint(&frame,maxX,minY); result.points[2]=framePoint(&frame,maxX,maxY); result.points[3]=framePoint(&frame,minX,maxY);
        result.pointCount=4; result.kind=ProfileRegionKind.polygon; result.valid=true; return true;
    }
    if(feature.kind==FeatureKind.sketchPolygon||feature.kind==FeatureKind.polygon2d)
    {
        uint count=0; if(!parse2dPoints(feature.payload.ptr(),&frame,result.points.ptr,&count))return false;
        result.pointCount=count; result.kind=ProfileRegionKind.polygon; result.valid=true; return true;
    }
    return false;
}

