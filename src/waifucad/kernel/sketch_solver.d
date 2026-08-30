module waifucad.kernel.sketch_solver;

import core.stdc.math : fabs, sqrt, atan2, cos, sin;
import waifucad.kernel.model : Model, WC_MAX_SKETCH_CONSTRAINTS;
import waifucad.kernel.types : EntityId, Feature, FeatureKind, Operand, OperandKind,
    SketchConstraint, SketchConstraintKind, SketchConstraintStatus, SketchSolveReport;
import waifucad.kernel.sketch_nonlinear : refineSketchNonlinear, analyseSketchJacobian;

private enum double WC_SKETCH_TOLERANCE = 1.0e-8;
private enum double WC_SKETCH_SOLVE_TOLERANCE = 1.0e-7;
private enum double WC_PI = 3.14159265358979323846264338327950288;
enum WC_SKETCH_SOLVE_CANCELLED = 90;

private bool linePoint(Model* model, Feature* feature, ubyte pointIndex, double* x, double* y) nothrow @nogc
{
    if (model is null || feature is null || x is null || y is null ||
        feature.kind != FeatureKind.sketchLine || feature.operandCount < 5 || pointIndex > 1)
        return false;
    auto offset = pointIndex == 0 ? 1u : 3u;
    *x = model.resolveOperand(&feature.operands[offset]);
    *y = model.resolveOperand(&feature.operands[offset + 1]);
    return true;
}

private bool setLiteral(Operand* operand, double value) nothrow @nogc
{
    if (operand is null || operand.kind != OperandKind.literal) return false;
    operand.literal = value;
    return true;
}

private bool setLinePoint(Feature* feature, ubyte pointIndex, double x, double y) nothrow @nogc
{
    if (feature is null || feature.kind != FeatureKind.sketchLine ||
        feature.operandCount < 5 || pointIndex > 1)
        return false;
    auto offset = pointIndex == 0 ? 1u : 3u;
    if (feature.operands[offset].kind != OperandKind.literal ||
        feature.operands[offset + 1].kind != OperandKind.literal)
        return false;
    feature.operands[offset].literal = x;
    feature.operands[offset + 1].literal = y;
    feature.dirty = true;
    return true;
}

private bool curveCentreRadius(Model* model, Feature* feature,
                               double* x, double* y, double* radius) nothrow @nogc
{
    if(model is null || feature is null || x is null || y is null || radius is null) return false;
    if(feature.kind == FeatureKind.sketchCircle)
    {
        if(feature.operandCount == 2)
        {
            *x = 0.0; *y = 0.0; *radius = model.resolveOperand(&feature.operands[1]);
            return *radius > 0.0;
        }
        if(feature.operandCount >= 4)
        {
            *x = model.resolveOperand(&feature.operands[1]);
            *y = model.resolveOperand(&feature.operands[2]);
            *radius = model.resolveOperand(&feature.operands[3]);
            return *radius > 0.0;
        }
    }
    if(feature.kind == FeatureKind.sketchArc && feature.operandCount >= 6)
    {
        *x = model.resolveOperand(&feature.operands[1]);
        *y = model.resolveOperand(&feature.operands[2]);
        *radius = model.resolveOperand(&feature.operands[3]);
        return *radius > 0.0;
    }
    return false;
}

private bool setCurveCentre(Feature* feature, double x, double y) nothrow @nogc
{
    if(feature is null) return false;
    if(feature.kind == FeatureKind.sketchCircle && feature.operandCount == 2)
        return fabs(x) <= WC_SKETCH_TOLERANCE && fabs(y) <= WC_SKETCH_TOLERANCE;
    if((feature.kind == FeatureKind.sketchCircle && feature.operandCount >= 4) ||
       (feature.kind == FeatureKind.sketchArc && feature.operandCount >= 6))
    {
        if(!setLiteral(&feature.operands[1],x) || !setLiteral(&feature.operands[2],y)) return false;
        feature.dirty = true;
        return true;
    }
    return false;
}

private uint curveRadiusIndex(const Feature* feature) nothrow @nogc
{
    if(feature is null) return uint.max;
    if(feature.kind == FeatureKind.sketchCircle)
        return feature.operandCount >= 4 ? 3u : (feature.operandCount >= 2 ? 1u : uint.max);
    if(feature.kind == FeatureKind.sketchArc && feature.operandCount >= 4) return 3u;
    return uint.max;
}

private double lineLength(Model* model, Feature* feature, bool* ok) nothrow @nogc
{
    double x0=0,y0=0,x1=0,y1=0;
    *ok = linePoint(model, feature, 0, &x0, &y0) && linePoint(model, feature, 1, &x1, &y1);
    if (!*ok) return 0.0;
    auto dx=x1-x0; auto dy=y1-y0;
    return sqrt(dx*dx+dy*dy);
}

private bool featureBelongsToSketch(Feature* feature, EntityId sketchId) nothrow @nogc
{
    return feature !is null && feature.operandCount != 0 &&
           feature.operands[0].kind == OperandKind.feature &&
           feature.operands[0].featureId == sketchId;
}

SketchConstraint* findSketchConstraint(Model* model, const(char)* name) nothrow @nogc
{
    if (model is null || name is null) return null;
    foreach (i; 0 .. model.sketchConstraintCount)
        if (model.sketchConstraints[i].name.equals(name)) return &model.sketchConstraints[i];
    return null;
}

EntityId addSketchConstraint(Model* model, const(char)* name, SketchConstraintKind kind,
                             EntityId sketchId, EntityId firstFeatureId, ubyte firstPoint,
                             EntityId secondFeatureId, ubyte secondPoint, double value) nothrow @nogc
{
    if (model is null || name is null || model.sketchConstraintCount >= WC_MAX_SKETCH_CONSTRAINTS ||
        findSketchConstraint(model,name) !is null)
        return 0;
    auto sketch = model.featureById(sketchId);
    auto first = model.featureById(firstFeatureId);
    auto second = secondFeatureId == 0 ? null : model.featureById(secondFeatureId);
    if (sketch is null || sketch.kind != FeatureKind.sketch || !featureBelongsToSketch(first, sketchId) ||
        (secondFeatureId != 0 && !featureBelongsToSketch(second, sketchId)))
        return 0;
    auto slot = &model.sketchConstraints[model.sketchConstraintCount++];
    slot.id = model.nextId++;
    slot.name.set(name);
    slot.kind = kind;
    slot.sketchId = sketchId;
    slot.firstFeatureId = firstFeatureId;
    slot.secondFeatureId = secondFeatureId;
    slot.firstPoint = firstPoint;
    slot.secondPoint = secondPoint;
    slot.value = value;
    slot.referenceX = 0.0;
    slot.referenceY = 0.0;
    slot.residual = 0.0;
    slot.status = SketchConstraintStatus.pending;
    slot.rankContribution = 0;
    slot.rankRedundant = false;
    slot.enabled = true;
    if (kind == SketchConstraintKind.fixPoint)
    {
        if (!linePoint(model, first, firstPoint, &slot.referenceX, &slot.referenceY))
        {
            --model.sketchConstraintCount;
            --model.nextId;
            return 0;
        }
    }
    first.dirty = true;
    if (second !is null) second.dirty = true;
    return slot.id;
}

private double wrapAngle(double value) nothrow @nogc
{
    while(value > WC_PI) value -= 2.0*WC_PI;
    while(value < -WC_PI) value += 2.0*WC_PI;
    return value;
}

private bool lineUnit(Model* model, Feature* feature, double* dx, double* dy, double* lengthOut) nothrow @nogc
{
    double x0=0,y0=0,x1=0,y1=0;
    if(dx is null || dy is null || lengthOut is null ||
       !linePoint(model,feature,0,&x0,&y0) || !linePoint(model,feature,1,&x1,&y1)) return false;
    auto vx=x1-x0; auto vy=y1-y0; auto len=sqrt(vx*vx+vy*vy);
    if(len<=WC_SKETCH_TOLERANCE) return false;
    *dx=vx/len; *dy=vy/len; *lengthOut=len; return true;
}

private bool applyTangent(Model* model, Feature* line, ubyte pointIndex, Feature* curve) nothrow @nogc
{
    if(model is null || line is null || curve is null || line.kind != FeatureKind.sketchLine || pointIndex > 1) return false;
    double px=0,py=0,qx=0,qy=0,cx=0,cy=0,radius=0;
    if(!linePoint(model,line,pointIndex,&px,&py) ||
       !linePoint(model,line,cast(ubyte)(pointIndex==0?1:0),&qx,&qy) ||
       !curveCentreRadius(model,curve,&cx,&cy,&radius)) return false;
    auto rx=px-cx; auto ry=py-cy; auto radialLength=sqrt(rx*rx+ry*ry);
    if(radialLength<=WC_SKETCH_TOLERANCE)
    {
        auto qdx=qx-px; auto qdy=qy-py; auto qlen=sqrt(qdx*qdx+qdy*qdy);
        if(qlen<=WC_SKETCH_TOLERANCE) return false;
        rx=-qdy/qlen; ry=qdx/qlen; radialLength=1.0;
    }
    rx/=radialLength; ry/=radialLength;
    auto targetX=cx+rx*radius; auto targetY=cy+ry*radius;
    auto lineDx=qx-px; auto lineDy=qy-py; auto lineLengthValue=sqrt(lineDx*lineDx+lineDy*lineDy);
    if(lineLengthValue<=WC_SKETCH_TOLERANCE) return false;
    auto tangentX=-ry; auto tangentY=rx;
    if(lineDx*tangentX+lineDy*tangentY<0.0){tangentX=-tangentX;tangentY=-tangentY;}
    if(!setLinePoint(line,pointIndex,targetX,targetY)) return false;
    return setLinePoint(line,cast(ubyte)(pointIndex==0?1:0),
                        targetX+tangentX*lineLengthValue,targetY+tangentY*lineLengthValue);
}

private bool applyCurveCurveTangent(Model* model, Feature* first, Feature* second) nothrow @nogc
{
    if(model is null || first is null || second is null)return false;
    double ax=0.0,ay=0.0,ar=0.0,bx=0.0,by=0.0,br=0.0;
    if(!curveCentreRadius(model,first,&ax,&ay,&ar) || !curveCentreRadius(model,second,&bx,&by,&br))return false;
    auto dx=bx-ax,dy=by-ay;
    auto distance=sqrt(dx*dx+dy*dy);
    auto target=ar+br;
    if(fabs(distance-target)<=WC_SKETCH_TOLERANCE)return true;
    if(distance<=WC_SKETCH_TOLERANCE){dx=1.0;dy=0.0;distance=1.0;}
    return setCurveCentre(second,ax+dx*target/distance,ay+dy*target/distance);
}

private bool applySymmetry(Model* model, Feature* segment, Feature* axisLine) nothrow @nogc
{
    if(model is null || segment is null || axisLine is null || segment.kind != FeatureKind.sketchLine || axisLine.kind != FeatureKind.sketchLine) return false;
    double ax0=0,ay0=0,ax1=0,ay1=0,bx0=0,by0=0,bx1=0,by1=0;
    if(!linePoint(model,segment,0,&ax0,&ay0) || !linePoint(model,segment,1,&ax1,&ay1) ||
       !linePoint(model,axisLine,0,&bx0,&by0) || !linePoint(model,axisLine,1,&bx1,&by1)) return false;
    auto axisX=bx1-bx0; auto axisY=by1-by0; auto axisLength=sqrt(axisX*axisX+axisY*axisY);
    if(axisLength<=WC_SKETCH_TOLERANCE) return false;
    axisX/=axisLength; axisY/=axisLength;
    auto midX=(ax0+ax1)*0.5; auto midY=(ay0+ay1)*0.5;
    auto along=(midX-bx0)*axisX+(midY-by0)*axisY;
    auto centreX=bx0+along*axisX; auto centreY=by0+along*axisY;
    auto halfX=(ax1-ax0)*0.5; auto halfY=(ay1-ay0)*0.5; auto halfLength=sqrt(halfX*halfX+halfY*halfY);
    if(halfLength<=WC_SKETCH_TOLERANCE) return false;
    auto normalX=-axisY; auto normalY=axisX;
    if(halfX*normalX+halfY*normalY<0.0){normalX=-normalX;normalY=-normalY;}
    return setLinePoint(segment,0,centreX-normalX*halfLength,centreY-normalY*halfLength) &&
           setLinePoint(segment,1,centreX+normalX*halfLength,centreY+normalY*halfLength);
}

private bool applyConstraint(Model* model, SketchConstraint* c) nothrow @nogc
{
    auto a = model.featureById(c.firstFeatureId);
    auto b = c.secondFeatureId == 0 ? null : model.featureById(c.secondFeatureId);
    if (a is null) return false;
    double ax0=0,ay0=0,ax1=0,ay1=0,bx0=0,by0=0,bx1=0,by1=0;
    bool aLine = linePoint(model,a,0,&ax0,&ay0) && linePoint(model,a,1,&ax1,&ay1);
    bool bLine = b !is null && linePoint(model,b,0,&bx0,&by0) && linePoint(model,b,1,&bx1,&by1);

    final switch (c.kind)
    {
        case SketchConstraintKind.horizontal:
            if (!aLine) return false;
            if (fabs(ay1-ay0) <= WC_SKETCH_TOLERANCE) return true;
            return setLinePoint(a,1,ax1,ay0);
        case SketchConstraintKind.vertical:
            if (!aLine) return false;
            if (fabs(ax1-ax0) <= WC_SKETCH_TOLERANCE) return true;
            return setLinePoint(a,1,ax0,ay1);
        case SketchConstraintKind.coincident:
            if (!aLine || !bLine) return false;
            {
                auto ax = c.firstPoint == 0 ? ax0 : ax1;
                auto ay = c.firstPoint == 0 ? ay0 : ay1;
                if (fabs(ax-(c.secondPoint==0?bx0:bx1))<=WC_SKETCH_TOLERANCE &&
                    fabs(ay-(c.secondPoint==0?by0:by1))<=WC_SKETCH_TOLERANCE) return true;
                return setLinePoint(b,c.secondPoint,ax,ay);
            }
        case SketchConstraintKind.distance:
            if (!aLine) return false;
            {
                auto sx = c.firstPoint == 0 ? ax0 : ax1;
                auto sy = c.firstPoint == 0 ? ay0 : ay1;
                double tx=0,ty=0;
                Feature* targetFeature = b is null ? a : b;
                ubyte targetPoint = b is null ? cast(ubyte)(c.firstPoint == 0 ? 1 : 0) : c.secondPoint;
                if (!linePoint(model,targetFeature,targetPoint,&tx,&ty)) return false;
                auto dx=tx-sx; auto dy=ty-sy; auto len=sqrt(dx*dx+dy*dy);
                if (fabs(len-c.value)<=WC_SKETCH_TOLERANCE) return true;
                if (len <= WC_SKETCH_TOLERANCE) { dx=1.0; dy=0.0; len=1.0; }
                return setLinePoint(targetFeature,targetPoint,sx+dx*c.value/len,sy+dy*c.value/len);
            }
        case SketchConstraintKind.equalLength:
            if (!aLine || !bLine) return false;
            {
                bool ok=false; auto target=lineLength(model,a,&ok); if(!ok) return false;
                auto dx=bx1-bx0; auto dy=by1-by0; auto len=sqrt(dx*dx+dy*dy);
                if (fabs(len-target)<=WC_SKETCH_TOLERANCE) return true;
                if (len<=WC_SKETCH_TOLERANCE) { dx=1;dy=0;len=1; }
                return setLinePoint(b,1,bx0+dx*target/len,by0+dy*target/len);
            }
        case SketchConstraintKind.parallel:
        case SketchConstraintKind.perpendicular:
            if (!aLine || !bLine) return false;
            {
                auto adx=ax1-ax0; auto ady=ay1-ay0; auto al=sqrt(adx*adx+ady*ady);
                auto bdx=bx1-bx0; auto bdy=by1-by0; auto bl=sqrt(bdx*bdx+bdy*bdy);
                if (al<=WC_SKETCH_TOLERANCE || bl<=WC_SKETCH_TOLERANCE) return false;
                adx/=al; ady/=al;
                if (c.kind == SketchConstraintKind.perpendicular) { auto temporary=adx; adx=-ady; ady=temporary; }
                if (bdx*adx+bdy*ady < 0.0) { adx=-adx; ady=-ady; }
                auto crossResidual=fabs((bdx/bl)*ady-(bdy/bl)*adx);
                if (crossResidual<=WC_SKETCH_TOLERANCE) return true;
                return setLinePoint(b,1,bx0+adx*bl,by0+ady*bl);
            }
        case SketchConstraintKind.angle:
            if(!aLine || !bLine) return false;
            {
                auto adx=ax1-ax0, ady=ay1-ay0; auto al=sqrt(adx*adx+ady*ady);
                auto bdx=bx1-bx0, bdy=by1-by0; auto bl=sqrt(bdx*bdx+bdy*bdy);
                if(al<=WC_SKETCH_TOLERANCE || bl<=WC_SKETCH_TOLERANCE) return false;
                auto target=atan2(ady,adx)+c.value*WC_PI/180.0;
                auto tx=bx0+cos(target)*bl, ty=by0+sin(target)*bl;
                if(fabs(tx-bx1)<=WC_SKETCH_TOLERANCE && fabs(ty-by1)<=WC_SKETCH_TOLERANCE) return true;
                return setLinePoint(b,1,tx,ty);
            }
        case SketchConstraintKind.midpoint:
            if(!aLine || !bLine) return false;
            {
                auto mx=(bx0+bx1)*0.5, my=(by0+by1)*0.5;
                auto px=c.firstPoint==0?ax0:ax1, py=c.firstPoint==0?ay0:ay1;
                if(fabs(px-mx)<=WC_SKETCH_TOLERANCE && fabs(py-my)<=WC_SKETCH_TOLERANCE) return true;
                return setLinePoint(a,c.firstPoint,mx,my);
            }
        case SketchConstraintKind.concentric:
            {
                double acx=0,acy=0,ar=0,bcx=0,bcy=0,br=0;
                if(!curveCentreRadius(model,a,&acx,&acy,&ar) || !curveCentreRadius(model,b,&bcx,&bcy,&br)) return false;
                if(fabs(acx-bcx)<=WC_SKETCH_TOLERANCE && fabs(acy-bcy)<=WC_SKETCH_TOLERANCE) return true;
                return setCurveCentre(b,acx,acy);
            }
        case SketchConstraintKind.equalRadius:
            {
                double acx=0,acy=0,ar=0,bcx=0,bcy=0,br=0;
                if(!curveCentreRadius(model,a,&acx,&acy,&ar) || !curveCentreRadius(model,b,&bcx,&bcy,&br)) return false;
                if(fabs(ar-br)<=WC_SKETCH_TOLERANCE) return true;
                auto index=curveRadiusIndex(b); if(index==uint.max || !setLiteral(&b.operands[index],ar)) return false;
                b.dirty=true; return true;
            }
        case SketchConstraintKind.radius:
        case SketchConstraintKind.diameter:
            if (a.kind != FeatureKind.sketchCircle && a.kind != FeatureKind.sketchArc) return false;
            {
                auto radiusIndex = curveRadiusIndex(a); if(radiusIndex==uint.max) return false;
                auto target = c.kind == SketchConstraintKind.diameter ? c.value*0.5 : c.value;
                auto current=model.resolveOperand(&a.operands[radiusIndex]);
                if (fabs(current-target)<=WC_SKETCH_TOLERANCE) return true;
                if (!setLiteral(&a.operands[radiusIndex],target)) return false;
                a.dirty=true; return true;
            }
        case SketchConstraintKind.tangent:
            if(aLine)return applyTangent(model,a,c.firstPoint,b);
            if(bLine)return applyTangent(model,b,c.secondPoint,a);
            return applyCurveCurveTangent(model,a,b);
        case SketchConstraintKind.symmetry:
            return applySymmetry(model,a,b);
        case SketchConstraintKind.fixPoint:
            if (!aLine) return false;
            {
                auto x=c.firstPoint==0?ax0:ax1; auto y=c.firstPoint==0?ay0:ay1;
                if (fabs(x-c.referenceX)<=WC_SKETCH_TOLERANCE && fabs(y-c.referenceY)<=WC_SKETCH_TOLERANCE) return true;
                return setLinePoint(a,c.firstPoint,c.referenceX,c.referenceY);
            }
    }
}

private bool constraintResidual(Model* model, const SketchConstraint* c, double* residual) nothrow @nogc
{
    if(model is null || c is null || residual is null) return false;
    auto a=model.featureById(c.firstFeatureId); auto b=c.secondFeatureId==0?null:model.featureById(c.secondFeatureId);
    if(a is null) return false;
    double ax0=0,ay0=0,ax1=0,ay1=0,bx0=0,by0=0,bx1=0,by1=0;
    bool aLine=linePoint(model,a,0,&ax0,&ay0)&&linePoint(model,a,1,&ax1,&ay1);
    bool bLine=b !is null&&linePoint(model,b,0,&bx0,&by0)&&linePoint(model,b,1,&bx1,&by1);
    *residual=0.0;
    final switch(c.kind)
    {
        case SketchConstraintKind.horizontal: if(!aLine)return false; *residual=fabs(ay1-ay0); return true;
        case SketchConstraintKind.vertical: if(!aLine)return false; *residual=fabs(ax1-ax0); return true;
        case SketchConstraintKind.coincident:
            if(!aLine||!bLine)return false;
            {auto dx=(c.firstPoint==0?ax0:ax1)-(c.secondPoint==0?bx0:bx1);auto dy=(c.firstPoint==0?ay0:ay1)-(c.secondPoint==0?by0:by1);*residual=sqrt(dx*dx+dy*dy);return true;}
        case SketchConstraintKind.distance:
            if(!aLine)return false;
            {auto sx=c.firstPoint==0?ax0:ax1,sy=c.firstPoint==0?ay0:ay1;double tx=0,ty=0;auto target=b is null?a:b;ubyte point=b is null?cast(ubyte)(c.firstPoint==0?1:0):c.secondPoint;if(!linePoint(model,target,point,&tx,&ty))return false;auto dx=tx-sx,dy=ty-sy;*residual=fabs(sqrt(dx*dx+dy*dy)-c.value);return true;}
        case SketchConstraintKind.equalLength:
            if(!aLine||!bLine)return false;
            {auto al=sqrt((ax1-ax0)*(ax1-ax0)+(ay1-ay0)*(ay1-ay0));auto bl=sqrt((bx1-bx0)*(bx1-bx0)+(by1-by0)*(by1-by0));*residual=fabs(al-bl);return true;}
        case SketchConstraintKind.parallel:
        case SketchConstraintKind.perpendicular:
            if(!aLine||!bLine)return false;
            {double adx=0,ady=0,al=0,bdx=0,bdy=0,bl=0;if(!lineUnit(model,a,&adx,&ady,&al)||!lineUnit(model,b,&bdx,&bdy,&bl))return false;*residual=c.kind==SketchConstraintKind.parallel?fabs(adx*bdy-ady*bdx):fabs(adx*bdx+ady*bdy);return true;}
        case SketchConstraintKind.angle:
            if(!aLine||!bLine)return false;
            {auto aa=atan2(ay1-ay0,ax1-ax0),ba=atan2(by1-by0,bx1-bx0);*residual=fabs(wrapAngle((ba-aa)-c.value*WC_PI/180.0));return true;}
        case SketchConstraintKind.midpoint:
            if(!aLine||!bLine)return false;
            {auto dx=(c.firstPoint==0?ax0:ax1)-(bx0+bx1)*0.5,dy=(c.firstPoint==0?ay0:ay1)-(by0+by1)*0.5;*residual=sqrt(dx*dx+dy*dy);return true;}
        case SketchConstraintKind.concentric:
            {double acx=0,acy=0,ar=0,bcx=0,bcy=0,br=0;if(!curveCentreRadius(model,a,&acx,&acy,&ar)||!curveCentreRadius(model,b,&bcx,&bcy,&br))return false;auto dx=acx-bcx,dy=acy-bcy;*residual=sqrt(dx*dx+dy*dy);return true;}
        case SketchConstraintKind.equalRadius:
            {double acx=0,acy=0,ar=0,bcx=0,bcy=0,br=0;if(!curveCentreRadius(model,a,&acx,&acy,&ar)||!curveCentreRadius(model,b,&bcx,&bcy,&br))return false;*residual=fabs(ar-br);return true;}
        case SketchConstraintKind.radius:
        case SketchConstraintKind.diameter:
            {double cx=0,cy=0,r=0;if(!curveCentreRadius(model,a,&cx,&cy,&r))return false;auto target=c.kind==SketchConstraintKind.diameter?c.value*0.5:c.value;*residual=fabs(r-target);return true;}
        case SketchConstraintKind.tangent:
            if(b is null)return false;
            if(aLine)
            {double cx=0,cy=0,r=0;if(!curveCentreRadius(model,b,&cx,&cy,&r))return false;auto px=c.firstPoint==0?ax0:ax1,py=c.firstPoint==0?ay0:ay1;auto rx=px-cx,ry=py-cy;auto rl=sqrt(rx*rx+ry*ry);double dx=0,dy=0,ll=0;if(rl<=WC_SKETCH_TOLERANCE||!lineUnit(model,a,&dx,&dy,&ll))return false;rx/=rl;ry/=rl;*residual=fabs(rl-r)+fabs(dx*rx+dy*ry);return true;}
            if(bLine)
            {double cx=0,cy=0,r=0;if(!curveCentreRadius(model,a,&cx,&cy,&r))return false;auto px=c.secondPoint==0?bx0:bx1,py=c.secondPoint==0?by0:by1;auto rx=px-cx,ry=py-cy;auto rl=sqrt(rx*rx+ry*ry);double dx=0,dy=0,ll=0;if(rl<=WC_SKETCH_TOLERANCE||!lineUnit(model,b,&dx,&dy,&ll))return false;rx/=rl;ry/=rl;*residual=fabs(rl-r)+fabs(dx*rx+dy*ry);return true;}
            {double acx=0,acy=0,ar=0,bcx=0,bcy=0,br=0;if(!curveCentreRadius(model,a,&acx,&acy,&ar)||!curveCentreRadius(model,b,&bcx,&bcy,&br))return false;auto dx=bcx-acx,dy=bcy-acy;*residual=fabs(sqrt(dx*dx+dy*dy)-(ar+br));return true;}
        case SketchConstraintKind.symmetry:
            if(!aLine||!bLine)return false;
            {double axisX=0,axisY=0,axisLength=0;if(!lineUnit(model,b,&axisX,&axisY,&axisLength))return false;auto midX=(ax0+ax1)*0.5,midY=(ay0+ay1)*0.5;auto relX=midX-bx0,relY=midY-by0;auto normalDistance=fabs(relX*(-axisY)+relY*axisX);double segX=0,segY=0,segLength=0;if(!lineUnit(model,a,&segX,&segY,&segLength))return false;*residual=normalDistance+fabs(segX*axisX+segY*axisY);return true;}
        case SketchConstraintKind.fixPoint:
            if(!aLine)return false;
            {auto dx=(c.firstPoint==0?ax0:ax1)-c.referenceX,dy=(c.firstPoint==0?ay0:ay1)-c.referenceY;*residual=sqrt(dx*dx+dy*dy);return true;}
    }
}

private uint constraintEquationCount(Model* model, const SketchConstraint* constraint) nothrow @nogc
{
    if(model is null || constraint is null)return 0;
    if(constraint.kind==SketchConstraintKind.tangent)
    {
        auto first=model.featureById(constraint.firstFeatureId);
        auto second=model.featureById(constraint.secondFeatureId);
        if(first is null || second is null)return 0;
        if(first.kind==FeatureKind.sketchLine || second.kind==FeatureKind.sketchLine)return 2;
        return 1;
    }
    final switch(constraint.kind)
    {
        case SketchConstraintKind.coincident:
        case SketchConstraintKind.midpoint:
        case SketchConstraintKind.concentric:
        case SketchConstraintKind.fixPoint:
        case SketchConstraintKind.symmetry:
            return 2;
        case SketchConstraintKind.tangent:
            return 1; // Handled above; retained for exhaustive final switch.
        case SketchConstraintKind.horizontal:
        case SketchConstraintKind.vertical:
        case SketchConstraintKind.distance:
        case SketchConstraintKind.equalLength:
        case SketchConstraintKind.parallel:
        case SketchConstraintKind.perpendicular:
        case SketchConstraintKind.angle:
        case SketchConstraintKind.equalRadius:
        case SketchConstraintKind.radius:
        case SketchConstraintKind.diameter:
            return 1;
    }
}

private uint mutableDegreesOfFreedom(Model* model, EntityId sketchId) nothrow @nogc
{
    if(model is null)return 0; uint total=0;
    foreach(i;0..model.featureCount)
    {
        auto feature=&model.features[i]; if(!featureBelongsToSketch(feature,sketchId))continue;
        switch(feature.kind)
        {
            case FeatureKind.sketchLine:
            case FeatureKind.sketchArc:
            case FeatureKind.sketchCircle:
            case FeatureKind.sketchRectangle:
            case FeatureKind.sketchPolygon:
            case FeatureKind.sketchText:
                foreach(op;1..feature.operandCount) if(feature.operands[op].kind==OperandKind.literal) ++total;
                break;
            default: break;
        }
    }
    return total;
}

private bool samePair(const SketchConstraint* a,const SketchConstraint* b) nothrow @nogc
{
    if(a is null||b is null)return false;
    return (a.firstFeatureId==b.firstFeatureId&&a.secondFeatureId==b.secondFeatureId&&a.firstPoint==b.firstPoint&&a.secondPoint==b.secondPoint) ||
           (a.firstFeatureId==b.secondFeatureId&&a.secondFeatureId==b.firstFeatureId&&a.firstPoint==b.secondPoint&&a.secondPoint==b.firstPoint);
}

private bool sameTarget(const SketchConstraint* a,const SketchConstraint* b) nothrow @nogc
{
    if(a is null||b is null||a.sketchId!=b.sketchId)return false;
    if(a.kind==SketchConstraintKind.parallel||a.kind==SketchConstraintKind.perpendicular||a.kind==SketchConstraintKind.equalLength||
       a.kind==SketchConstraintKind.concentric||a.kind==SketchConstraintKind.equalRadius||a.kind==SketchConstraintKind.symmetry)
        return samePair(a,b);
    return a.firstFeatureId==b.firstFeatureId&&a.secondFeatureId==b.secondFeatureId&&a.firstPoint==b.firstPoint&&a.secondPoint==b.secondPoint;
}

private bool drivingValueKind(SketchConstraintKind kind) nothrow @nogc
{
    return kind==SketchConstraintKind.distance||kind==SketchConstraintKind.angle||kind==SketchConstraintKind.radius||kind==SketchConstraintKind.diameter;
}

private double effectiveRadiusValue(const SketchConstraint* c) nothrow @nogc
{
    if(c is null)return 0.0; return c.kind==SketchConstraintKind.diameter?c.value*0.5:c.value;
}

private void classifyConstraints(Model* model) nothrow @nogc
{
    foreach(i;0..model.sketchConstraintCount)
    {
        auto current=&model.sketchConstraints[i];
        current.residual=0.0;
        if(!current.enabled)continue;
        auto first=model.featureById(current.firstFeatureId); auto second=current.secondFeatureId==0?null:model.featureById(current.secondFeatureId);
        if(first is null||!featureBelongsToSketch(first,current.sketchId)||(current.secondFeatureId!=0&&(second is null||!featureBelongsToSketch(second,current.sketchId))))
        {current.status=SketchConstraintStatus.invalid;continue;}
        current.status=SketchConstraintStatus.pending;
        foreach(j;0..i)
        {
            auto previous=&model.sketchConstraints[j]; if(!previous.enabled||previous.sketchId!=current.sketchId||previous.status==SketchConstraintStatus.invalid)continue;
            if(previous.kind==current.kind&&sameTarget(previous,current))
            {
                if(drivingValueKind(current.kind)&&fabs(previous.value-current.value)>WC_SKETCH_SOLVE_TOLERANCE)
                {previous.status=SketchConstraintStatus.conflicting;current.status=SketchConstraintStatus.conflicting;break;}
                if(current.kind==SketchConstraintKind.fixPoint&&(fabs(previous.referenceX-current.referenceX)>WC_SKETCH_SOLVE_TOLERANCE||fabs(previous.referenceY-current.referenceY)>WC_SKETCH_SOLVE_TOLERANCE))
                {previous.status=SketchConstraintStatus.conflicting;current.status=SketchConstraintStatus.conflicting;break;}
                current.status=SketchConstraintStatus.redundant;break;
            }
            if(previous.firstFeatureId==current.firstFeatureId)
            {
                bool radiusPair=(previous.kind==SketchConstraintKind.radius||previous.kind==SketchConstraintKind.diameter)&&(current.kind==SketchConstraintKind.radius||current.kind==SketchConstraintKind.diameter);
                if(radiusPair)
                {
                    if(fabs(effectiveRadiusValue(previous)-effectiveRadiusValue(current))<=WC_SKETCH_SOLVE_TOLERANCE) current.status=SketchConstraintStatus.redundant;
                    else {previous.status=SketchConstraintStatus.conflicting;current.status=SketchConstraintStatus.conflicting;}
                    break;
                }
                bool hv=(previous.kind==SketchConstraintKind.horizontal&&current.kind==SketchConstraintKind.vertical)||(previous.kind==SketchConstraintKind.vertical&&current.kind==SketchConstraintKind.horizontal);
                if(hv)
                {
                    bool ok=false; if(lineLength(model,first,&ok)>WC_SKETCH_SOLVE_TOLERANCE&&ok){previous.status=SketchConstraintStatus.conflicting;current.status=SketchConstraintStatus.conflicting;break;}
                }
            }
            bool parallelPerpendicular=((previous.kind==SketchConstraintKind.parallel&&current.kind==SketchConstraintKind.perpendicular)||(previous.kind==SketchConstraintKind.perpendicular&&current.kind==SketchConstraintKind.parallel));
            if(parallelPerpendicular&&samePair(previous,current)){previous.status=SketchConstraintStatus.conflicting;current.status=SketchConstraintStatus.conflicting;break;}
        }
    }
}

private void resetReports(Model* model) nothrow @nogc
{
    foreach(i;0..model.featureCount)
    {
        if(model.features[i].kind!=FeatureKind.sketch)continue;
        auto report=&model.sketchSolveReports[i]; *report=SketchSolveReport.init; report.sketchId=model.features[i].id;
        report.initialDegreesOfFreedom=mutableDegreesOfFreedom(model,report.sketchId);
    }
}

private void finaliseReports(Model* model,uint iterations) nothrow @nogc
{
    if(model is null)return;
    foreach(i;0..model.featureCount)
    {
        if(model.features[i].kind!=FeatureKind.sketch)continue;
        auto report=&model.sketchSolveReports[i]; report.iterations=iterations; report.maxResidual=0.0;
        foreach(cIndex;0..model.sketchConstraintCount)
        {
            auto c=&model.sketchConstraints[cIndex]; if(!c.enabled||c.sketchId!=report.sketchId)continue;
            final switch(c.status)
            {
                case SketchConstraintStatus.satisfied: ++report.satisfiedCount; report.independentEquationCount+=constraintEquationCount(model,c); break;
                case SketchConstraintStatus.unsatisfied: ++report.unsatisfiedCount; report.independentEquationCount+=constraintEquationCount(model,c); break;
                case SketchConstraintStatus.redundant: ++report.redundantCount; break;
                case SketchConstraintStatus.conflicting: ++report.conflictingCount; break;
                case SketchConstraintStatus.invalid: ++report.invalidCount; break;
                case SketchConstraintStatus.pending: break;
            }
            if(c.residual>report.maxResidual)report.maxResidual=c.residual;
        }
        auto analysis=analyseSketchJacobian(model,report.sketchId);
        report.totalEquationCount=analysis.equationCount;
        report.jacobianRank=analysis.rank;
        report.rankDeficiency=analysis.rankDeficiency;
        report.rankAnalysisTruncated=analysis.truncated;
        if(!analysis.truncated) report.independentEquationCount=analysis.rank;
        report.remainingDegreesOfFreedom=report.initialDegreesOfFreedom>report.independentEquationCount?report.initialDegreesOfFreedom-report.independentEquationCount:0;
        report.underConstrained=report.remainingDegreesOfFreedom!=0;
        report.overConstrained=report.conflictingCount!=0 || (!analysis.truncated && report.totalEquationCount>report.jacobianRank && report.jacobianRank>=report.initialDegreesOfFreedom);
        report.converged=report.unsatisfiedCount==0&&report.conflictingCount==0&&report.invalidCount==0&&report.maxResidual<=WC_SKETCH_SOLVE_TOLERANCE;
        report.fullyConstrained=report.converged&&!report.underConstrained&&!report.rankAnalysisTruncated;
    }
}

int solveSketchConstraints(Model* model) nothrow @nogc
{
    if (model is null) return 1;
    resetReports(model);
    classifyConstraints(model);
    uint iterations=0;
    foreach (iteration; 0 .. 64)
    {
        if(model.recomputeCancelled())return WC_SKETCH_SOLVE_CANCELLED;
        iterations=cast(uint)iteration+1u;
        foreach (i; 0 .. model.sketchConstraintCount)
        {
            if(model.recomputeCancelled())return WC_SKETCH_SOLVE_CANCELLED;
            auto c=&model.sketchConstraints[i];
            if (!c.enabled || c.status==SketchConstraintStatus.redundant || c.status==SketchConstraintStatus.conflicting || c.status==SketchConstraintStatus.invalid) continue;
            if (!applyConstraint(model,c)) c.status=SketchConstraintStatus.invalid;
        }
        double maxResidual=0.0;
        foreach(i;0..model.sketchConstraintCount)
        {
            auto c=&model.sketchConstraints[i];
            if(!c.enabled||c.status==SketchConstraintStatus.redundant||c.status==SketchConstraintStatus.conflicting||c.status==SketchConstraintStatus.invalid)continue;
            double residual=0.0; if(!constraintResidual(model,c,&residual)){c.status=SketchConstraintStatus.invalid;continue;}
            c.residual=residual; if(residual>maxResidual)maxResidual=residual;
        }
        if(maxResidual<=WC_SKETCH_SOLVE_TOLERANCE)break;
    }

    foreach(featureIndex;0..model.featureCount)
    {
        if(model.features[featureIndex].kind!=FeatureKind.sketch)continue;
        auto analysis=refineSketchNonlinear(model,model.features[featureIndex].id);
        if(analysis.cancelled)return WC_SKETCH_SOLVE_CANCELLED;
        auto report=model.sketchSolveReport(model.features[featureIndex].id);
        if(report !is null)report.nonlinearIterations=analysis.nonlinearIterations;
    }

    model.sketchConstraintErrorCount=0;
    foreach (i; 0 .. model.sketchConstraintCount)
    {
        auto c=&model.sketchConstraints[i]; if (!c.enabled) continue;
        if(c.status==SketchConstraintStatus.redundant) { double residual=0.0; if(constraintResidual(model,c,&residual))c.residual=residual; continue; }
        if(c.status==SketchConstraintStatus.conflicting||c.status==SketchConstraintStatus.invalid){++model.sketchConstraintErrorCount;continue;}
        double residual=0.0;
        if(!constraintResidual(model,c,&residual)){c.status=SketchConstraintStatus.invalid;c.residual=0.0;++model.sketchConstraintErrorCount;continue;}
        c.residual=residual;
        if(residual<=WC_SKETCH_SOLVE_TOLERANCE)c.status=SketchConstraintStatus.satisfied;
        else {c.status=SketchConstraintStatus.unsatisfied;++model.sketchConstraintErrorCount;}
    }
    finaliseReports(model,iterations);
    return cast(int)model.sketchConstraintErrorCount;
}

