module waifucad.kernel.waifubrep_backend;

import core.stdc.math : fabs, sqrt;
import waifucad.brep.kernel : makeBox, makeBoxAt, makeCylinderAt, makeSphereAt, makeConeFrustumAt, makeTorusAt;
import waifucad.brep.advanced : makePrism, makeProfilePrism, makeLinearLoft, makeAxisymmetricPolygonRevolve, makeBoxShellAt, makeBoxCavity, intersectAxisAlignedBoxes, uniteAxisAlignedBoxesIfRectangular;
import waifucad.brep.transform : transformSolidRigid;
import waifucad.brep.geometry : add, subtract, scale, dot, cross, length, normalise;
import waifucad.brep.types : BRepId, BRepPersistentId, BRepPrimitiveKind, BRepVec3, BRepLineageKind, BRepProfileSegment;
import waifucad.brep.naming : assignPrimitivePersistentTopology;
import waifucad.brep.validate : validateClosedSolid;
import waifucad.kernel.backend_api : GeometryBackendV1, WC_GEOMETRY_ABI_V1;
import waifucad.kernel.builtin_preview : builtinPreviewBackend;
import waifucad.kernel.model : Model;
import waifucad.kernel.sketch_solver : solveSketchConstraints, WC_SKETCH_SOLVE_CANCELLED;
import waifucad.kernel.profiles : ProfileRegion, ProfileRegionKind, resolveProfile;
import waifucad.kernel.datums : DatumFrame, datumAxis;
import waifucad.kernel.types : ExactGeometryStatus, Feature, FeatureKind, OperandKind;


private enum double WC_EXACT_TOL = 1.0e-8;

private bool axisFrame(BRepVec3 origin, BRepVec3 axisInput, BRepVec3 preferredX, DatumFrame* frame) nothrow @nogc
{
    if(frame is null)return false; bool zOk=false; auto z=normalise(axisInput,&zOk); if(!zOk)return false;
    auto xCandidate=subtract(preferredX,scale(z,dot(preferredX,z))); bool xOk=false; auto x=normalise(xCandidate,&xOk);
    if(!xOk)
    {
        auto fallback=fabs(z.x)<0.8?BRepVec3(1,0,0):BRepVec3(0,1,0);
        x=normalise(subtract(fallback,scale(z,dot(fallback,z))),&xOk); if(!xOk)return false;
    }
    bool yOk=false; auto y=normalise(cross(z,x),&yOk); if(!yOk)return false;
    frame.origin=origin; frame.xAxis=x; frame.yAxis=y; frame.zAxis=z; frame.valid=true; return true;
}

private BRepId exactExtrude(Model* model, const Feature* feature) nothrow @nogc
{
    if(model is null||feature is null||feature.operandCount<2||feature.operands[0].kind!=OperandKind.feature)return 0;
    ProfileRegion profile; if(!resolveProfile(model,feature.operands[0].featureId,&profile))return 0;
    auto distance=model.resolveOperand(&feature.operands[1]); auto twist=feature.operandCount>=3?model.resolveOperand(&feature.operands[2]):0.0;
    auto centred=feature.operandCount>=5&&model.resolveOperand(&feature.operands[4])!=0.0;
    if(fabs(distance)<=WC_EXACT_TOL||fabs(twist)>WC_EXACT_TOL)return 0;
    auto extrusion=scale(profile.frame.zAxis,distance);
    if(profile.kind==ProfileRegionKind.polygon)
    {
        BRepVec3[48] points; foreach(i;0..profile.pointCount) points[i]=centred?subtract(profile.points[i],scale(extrusion,0.5)):profile.points[i];
        return makePrism(&model.exactGeometry,points.ptr,profile.pointCount,extrusion);
    }
    if(profile.kind==ProfileRegionKind.mixed)
    {
        BRepProfileSegment[48] segments;
        foreach(i;0..profile.segmentCount)
        {
            segments[i]=profile.segments[i];
            if(centred)
            {
                segments[i].start=subtract(segments[i].start,scale(extrusion,0.5));
                segments[i].finish=subtract(segments[i].finish,scale(extrusion,0.5));
                segments[i].centre=subtract(segments[i].centre,scale(extrusion,0.5));
            }
        }
        return makeProfilePrism(&model.exactGeometry,segments.ptr,profile.segmentCount,extrusion);
    }
    if(profile.kind==ProfileRegionKind.circle)
    {
        auto height=fabs(distance); auto direction=distance>=0.0?profile.frame.zAxis:scale(profile.frame.zAxis,-1.0);
        auto origin=centred?subtract(profile.frame.origin,scale(direction,height*0.5)):profile.frame.origin;
        DatumFrame target; if(!axisFrame(origin,direction,profile.frame.xAxis,&target))return 0;
        auto id=makeCylinderAt(&model.exactGeometry,profile.radius,height,0,0,0); if(id==0)return 0;
        return transformSolidRigid(&model.exactGeometry,id,target.origin,target.xAxis,target.yAxis,target.zAxis)?id:0;
    }
    return 0;
}

private bool freeLinePath(Model* model, uint featureId, BRepVec3* start, BRepVec3* finish) nothrow @nogc
{
    if(model is null||start is null||finish is null)return false; auto path=model.featureById(featureId);
    if(path is null||path.kind!=FeatureKind.freeLine||path.operandCount<6)return false;
    *start=BRepVec3(model.resolveOperand(&path.operands[0]),model.resolveOperand(&path.operands[1]),model.resolveOperand(&path.operands[2]));
    *finish=BRepVec3(model.resolveOperand(&path.operands[3]),model.resolveOperand(&path.operands[4]),model.resolveOperand(&path.operands[5])); return length(subtract(*finish,*start))>WC_EXACT_TOL;
}

private BRepId exactSweep(Model* model, const Feature* feature) nothrow @nogc
{
    if(model is null||feature is null||feature.operandCount<2||feature.operands[0].kind!=OperandKind.feature||feature.operands[1].kind!=OperandKind.feature)return 0;
    ProfileRegion profile; if(!resolveProfile(model,feature.operands[0].featureId,&profile))return 0;
    BRepVec3 start,finish; if(!freeLinePath(model,feature.operands[1].featureId,&start,&finish))return 0; auto extrusion=subtract(finish,start);
    if(profile.kind==ProfileRegionKind.polygon)
    {
        auto shift=subtract(start,profile.frame.origin); BRepVec3[48] points; foreach(i;0..profile.pointCount)points[i]=add(profile.points[i],shift);
        return makePrism(&model.exactGeometry,points.ptr,profile.pointCount,extrusion);
    }
    if(profile.kind==ProfileRegionKind.circle)
    {
        bool dOk=false; auto direction=normalise(extrusion,&dOk); if(!dOk||fabs(fabs(dot(direction,profile.frame.zAxis))-1.0)>WC_EXACT_TOL)return 0;
        DatumFrame target; if(!axisFrame(start,direction,profile.frame.xAxis,&target))return 0; auto height=length(extrusion);
        auto id=makeCylinderAt(&model.exactGeometry,profile.radius,height,0,0,0); if(id==0)return 0;
        return transformSolidRigid(&model.exactGeometry,id,target.origin,target.xAxis,target.yAxis,target.zAxis)?id:0;
    }
    return 0;
}

private BRepId exactLoft(Model* model, const Feature* feature) nothrow @nogc
{
    if(model is null||feature is null||feature.operandCount<2||feature.operands[0].kind!=OperandKind.feature||feature.operands[1].kind!=OperandKind.feature)return 0;
    ProfileRegion first,second; if(!resolveProfile(model,feature.operands[0].featureId,&first)||!resolveProfile(model,feature.operands[1].featureId,&second))return 0;
    if(first.kind==ProfileRegionKind.polygon&&second.kind==ProfileRegionKind.polygon&&first.pointCount==second.pointCount)
        return makeLinearLoft(&model.exactGeometry,first.points.ptr,second.points.ptr,first.pointCount);
    if(first.kind==ProfileRegionKind.circle&&second.kind==ProfileRegionKind.circle)
    {
        auto delta=subtract(second.frame.origin,first.frame.origin); auto height=length(delta); if(height<=WC_EXACT_TOL)return 0;
        bool dOk=false; auto axis=normalise(delta,&dOk); if(!dOk||fabs(fabs(dot(axis,first.frame.zAxis))-1.0)>WC_EXACT_TOL||fabs(fabs(dot(axis,second.frame.zAxis))-1.0)>WC_EXACT_TOL)return 0;
        DatumFrame target; if(!axisFrame(first.frame.origin,axis,first.frame.xAxis,&target))return 0;
        auto id=makeConeFrustumAt(&model.exactGeometry,first.radius,second.radius,height,0,0,0); if(id==0)return 0;
        return transformSolidRigid(&model.exactGeometry,id,target.origin,target.xAxis,target.yAxis,target.zAxis)?id:0;
    }
    return 0;
}

private BRepId exactRevolve(Model* model, const Feature* feature) nothrow @nogc
{
    if(model is null||feature is null||feature.operandCount<2||feature.operands[0].kind!=OperandKind.feature)return 0;
    ProfileRegion profile; if(!resolveProfile(model,feature.operands[0].featureId,&profile))return 0;
    BRepVec3 axisOrigin=BRepVec3(0,0,0),axisDirection=BRepVec3(0,0,1); double angle=0.0;
    uint angleIndex=1;
    if(feature.operands[1].kind==OperandKind.feature)
    {
        if(!datumAxis(model,feature.operands[1].featureId,&axisOrigin,&axisDirection)||feature.operandCount<3)return 0; angleIndex=2;
    }
    angle=model.resolveOperand(&feature.operands[angleIndex]); if(fabs(fabs(angle)-360.0)>WC_EXACT_TOL)return 0;
    if(fabs(dot(profile.frame.zAxis,axisDirection))>WC_EXACT_TOL)return 0; // revolution axis must lie in profile plane
    auto centreRel=subtract(profile.frame.origin,axisOrigin); auto axial=dot(centreRel,axisDirection); auto axisPoint=add(axisOrigin,scale(axisDirection,axial));
    auto radialVector=subtract(profile.frame.origin,axisPoint); auto major=length(radialVector);
    if(profile.kind==ProfileRegionKind.circle)
    {
        if(major<=WC_EXACT_TOL)
            return makeSphereAt(&model.exactGeometry,profile.radius,profile.frame.origin.x,profile.frame.origin.y,profile.frame.origin.z);
        if(major<=profile.radius+WC_EXACT_TOL)return 0;
        DatumFrame target; if(!axisFrame(axisPoint,axisDirection,radialVector,&target))return 0;
        auto id=makeTorusAt(&model.exactGeometry,major,profile.radius,0,0,0); if(id==0)return 0;
        return transformSolidRigid(&model.exactGeometry,id,target.origin,target.xAxis,target.yAxis,target.zAxis)?id:0;
    }
    if(profile.kind==ProfileRegionKind.polygon)
    {
        BRepVec3 radialBasis; bool haveRadial=false; BRepVec3[48] radialAxial;
        foreach(i;0..profile.pointCount)
        {
            auto rel=subtract(profile.points[i],axisOrigin); auto z=dot(rel,axisDirection); auto radial=subtract(rel,scale(axisDirection,z)); auto radius=length(radial);
            if(radius>WC_EXACT_TOL && !haveRadial){bool ok=false; radialBasis=normalise(radial,&ok); if(!ok)return 0; haveRadial=true;}
        }
        if(!haveRadial)return 0;
        foreach(i;0..profile.pointCount)
        {
            auto rel=subtract(profile.points[i],axisOrigin); auto z=dot(rel,axisDirection); auto radial=subtract(rel,scale(axisDirection,z));
            auto signedRadius=dot(radial,radialBasis); auto offAxis=subtract(radial,scale(radialBasis,signedRadius));
            if(length(offAxis)>WC_EXACT_TOL || signedRadius < -WC_EXACT_TOL)return 0;
            radialAxial[i]=BRepVec3(signedRadius<0.0?0.0:signedRadius,0.0,z);
        }
        auto id=makeAxisymmetricPolygonRevolve(&model.exactGeometry,radialAxial.ptr,profile.pointCount); if(id==0)return 0;
        DatumFrame target; if(!axisFrame(axisOrigin,axisDirection,radialBasis,&target))return 0;
        return transformSolidRigid(&model.exactGeometry,id,target.origin,target.xAxis,target.yAxis,target.zAxis)?id:0;
    }
    return 0;
}

/*
 * Exact-kernel bootstrap. Preview bounds are recomputed first in parallel;
 * exact topology is then rebuilt deterministically. The serial exact stage is
 * deliberate until per-worker topology arenas and merge semantics are defined.
 */
extern(C) private int recomputeWaifuBRep(Model* model) nothrow @nogc
{
    if (model is null)
        return 1;

    model.beginRecompute();
    auto expressionResult = model.evaluateParameterExpressions();
    if (expressionResult != 0) return 300 + expressionResult;
    auto constraintResult = solveSketchConstraints(model);
    if (constraintResult == WC_SKETCH_SOLVE_CANCELLED) return 504;
    if (constraintResult != 0) return 400 + constraintResult;

    auto preview = builtinPreviewBackend();
    auto previewResult = preview.recompute(model);
    if (previewResult != 0)
        return previewResult;

    model.exactGeometry.clear();
    foreach (i; 0 .. model.featureCount)
    {
        if(model.recomputeCancelled()) return 504;
        model.exactSolidIds[i] = 0;
        model.exactErrors[i] = 0;
        model.exactStatus[i] = ExactGeometryStatus.previewOnly;

        auto feature = &model.features[i];
        BRepId solidId = 0;
        bool ownsTopology = true;
        BRepPersistentId lineageParentA=0;
        BRepPersistentId lineageParentB=0;
        BRepLineageKind lineageKind=BRepLineageKind.none;
        final switch (feature.kind)
        {
            case FeatureKind.box:
                if (feature.operandCount < 3)
                {
                    model.exactStatus[i] = ExactGeometryStatus.failed;
                    model.exactErrors[i] = 10;
                    continue;
                }
                {
                    auto width = model.resolveOperand(&feature.operands[0]);
                    auto depth = model.resolveOperand(&feature.operands[1]);
                    auto height = model.resolveOperand(&feature.operands[2]);
                    if (feature.operandCount >= 4)
                    {
                        auto centred = model.resolveOperand(&feature.operands[3]) != 0.0;
                        auto centreX = centred ? 0.0 : width * 0.5;
                        auto centreY = centred ? 0.0 : depth * 0.5;
                        auto baseZ = centred ? -height * 0.5 : 0.0;
                        solidId = makeBoxAt(&model.exactGeometry, width, depth, height,
                                            centreX, centreY, baseZ);
                    }
                    else
                        solidId = makeBox(&model.exactGeometry, width, depth, height);
                }
                break;

            case FeatureKind.cylinder:
                if (feature.operandCount < 2)
                {
                    model.exactStatus[i] = ExactGeometryStatus.failed;
                    model.exactErrors[i] = 12;
                    continue;
                }
                {
                    auto radius = model.resolveOperand(&feature.operands[0]);
                    auto height = model.resolveOperand(&feature.operands[1]);
                    auto centred = feature.operandCount >= 3 && model.resolveOperand(&feature.operands[2]) != 0.0;
                    if (feature.operandCount >= 4 && model.resolveOperand(&feature.operands[3]) != 0.0)
                        radius *= 0.5;
                    auto baseZ = centred ? -height * 0.5 : 0.0;
                    solidId = makeCylinderAt(&model.exactGeometry, radius, height, 0.0, 0.0, baseZ);
                }
                break;

            case FeatureKind.sphere:
                if (feature.operandCount < 1)
                {
                    model.exactStatus[i] = ExactGeometryStatus.failed;
                    model.exactErrors[i] = 14;
                    continue;
                }
                {
                    auto radius = model.resolveOperand(&feature.operands[0]);
                    if (feature.operandCount >= 2 && model.resolveOperand(&feature.operands[1]) != 0.0)
                        radius *= 0.5;
                    solidId = makeSphereAt(&model.exactGeometry, radius, 0.0, 0.0, 0.0);
                }
                break;

            case FeatureKind.torus:
                if(feature.operandCount<2) { model.exactStatus[i]=ExactGeometryStatus.failed; model.exactErrors[i]=17; continue; }
                {
                    auto major=model.resolveOperand(&feature.operands[0]); auto minor=model.resolveOperand(&feature.operands[1]);
                    solidId=makeTorusAt(&model.exactGeometry,major,minor,0.0,0.0,0.0);
                }
                break;

            case FeatureKind.coneFrustum:
                if (feature.operandCount < 3)
                {
                    model.exactStatus[i] = ExactGeometryStatus.failed;
                    model.exactErrors[i] = 16;
                    continue;
                }
                {
                    auto radius1 = model.resolveOperand(&feature.operands[0]);
                    auto radius2 = model.resolveOperand(&feature.operands[1]);
                    auto height = model.resolveOperand(&feature.operands[2]);
                    auto centred = feature.operandCount >= 4 && model.resolveOperand(&feature.operands[3]) != 0.0;
                    if (feature.operandCount >= 5 && model.resolveOperand(&feature.operands[4]) != 0.0)
                    {
                        radius1 *= 0.5;
                        radius2 *= 0.5;
                    }
                    auto baseZ = centred ? -height * 0.5 : 0.0;
                    solidId = makeConeFrustumAt(&model.exactGeometry, radius1, radius2, height,
                                                0.0, 0.0, baseZ);
                }
                break;

            case FeatureKind.extrude:
                solidId=exactExtrude(model,feature);
                if(solidId==0) continue;
                break;

            case FeatureKind.revolve:
                solidId=exactRevolve(model,feature);
                if(solidId==0) continue;
                break;

            case FeatureKind.sweep:
                solidId=exactSweep(model,feature);
                if(solidId==0) continue;
                break;

            case FeatureKind.loft:
                solidId=exactLoft(model,feature);
                if(solidId==0) continue;
                break;

            case FeatureKind.translate:
                if (feature.operandCount < 4 || feature.operands[0].kind != OperandKind.feature)
                    continue;
                {
                    auto sourceIndex = model.featureIndexById(feature.operands[0].featureId);
                    if (sourceIndex >= i || model.exactStatus[sourceIndex] != ExactGeometryStatus.exact)
                        continue;
                    auto sourceSolid = model.exactGeometry.solid(model.exactSolidIds[sourceIndex]);
                    if (sourceSolid is null || !sourceSolid.bounds.valid)
                        continue;
                    auto dx = model.resolveOperand(&feature.operands[1]);
                    auto dy = model.resolveOperand(&feature.operands[2]);
                    auto dz = model.resolveOperand(&feature.operands[3]);
                    auto centreX = (sourceSolid.bounds.minimum.x + sourceSolid.bounds.maximum.x) * 0.5 + dx;
                    auto centreY = (sourceSolid.bounds.minimum.y + sourceSolid.bounds.maximum.y) * 0.5 + dy;
                    auto baseZ = sourceSolid.bounds.minimum.z + dz;
                    if (sourceSolid.primitiveKind == BRepPrimitiveKind.box)
                        solidId = makeBoxAt(&model.exactGeometry, sourceSolid.primitiveA, sourceSolid.primitiveB, sourceSolid.primitiveC,
                                            centreX, centreY, baseZ);
                    else if (sourceSolid.primitiveKind == BRepPrimitiveKind.cylinder)
                        solidId = makeCylinderAt(&model.exactGeometry, sourceSolid.primitiveA, sourceSolid.primitiveB,
                                                 centreX, centreY, baseZ);
                    else if (sourceSolid.primitiveKind == BRepPrimitiveKind.sphere)
                    {
                        auto centreZ = (sourceSolid.bounds.minimum.z + sourceSolid.bounds.maximum.z) * 0.5 + dz;
                        solidId = makeSphereAt(&model.exactGeometry, sourceSolid.primitiveA, centreX, centreY, centreZ);
                    }
                    else if (sourceSolid.primitiveKind == BRepPrimitiveKind.coneFrustum)
                        solidId = makeConeFrustumAt(&model.exactGeometry, sourceSolid.primitiveA, sourceSolid.primitiveB,
                                                    sourceSolid.primitiveC, centreX, centreY, baseZ);
                    else
                        continue;
                }
                break;


            case FeatureKind.booleanUnion:
            case FeatureKind.booleanSubtract:
            case FeatureKind.booleanIntersect:
                if(feature.operandCount<2||feature.operands[0].kind!=OperandKind.feature||feature.operands[1].kind!=OperandKind.feature)continue;
                {
                    auto firstIndex=model.featureIndexById(feature.operands[0].featureId); auto secondIndex=model.featureIndexById(feature.operands[1].featureId);
                    if(firstIndex>=i||secondIndex>=i||model.exactStatus[firstIndex]!=ExactGeometryStatus.exact||model.exactStatus[secondIndex]!=ExactGeometryStatus.exact)continue;
                    auto firstSolid=model.exactGeometry.solid(model.exactSolidIds[firstIndex]); auto secondSolid=model.exactGeometry.solid(model.exactSolidIds[secondIndex]);
                    if(firstSolid is null||secondSolid is null)continue;
                    lineageParentA=firstSolid.persistentId; lineageParentB=secondSolid.persistentId;
                    if(feature.kind==FeatureKind.booleanIntersect)
                    {
                        solidId=intersectAxisAlignedBoxes(&model.exactGeometry,firstSolid,secondSolid); lineageKind=BRepLineageKind.booleanIntersection;
                    }
                    else if(feature.kind==FeatureKind.booleanUnion)
                    {
                        solidId=uniteAxisAlignedBoxesIfRectangular(&model.exactGeometry,firstSolid,secondSolid); lineageKind=BRepLineageKind.booleanUnion;
                    }
                    else
                    {
                        if(firstSolid.primitiveKind==BRepPrimitiveKind.box&&secondSolid.primitiveKind==BRepPrimitiveKind.box)
                            solidId=makeBoxCavity(&model.exactGeometry,&firstSolid.bounds,&secondSolid.bounds);
                        lineageKind=BRepLineageKind.booleanSubtract;
                    }
                    if(solidId==0)continue;
                }
                break;

            case FeatureKind.shell:
                if(feature.operandCount<2||feature.operands[0].kind!=OperandKind.feature)continue;
                {
                    auto sourceIndex=model.featureIndexById(feature.operands[0].featureId); if(sourceIndex>=i||model.exactStatus[sourceIndex]!=ExactGeometryStatus.exact)continue;
                    auto sourceSolid=model.exactGeometry.solid(model.exactSolidIds[sourceIndex]); if(sourceSolid is null||sourceSolid.primitiveKind!=BRepPrimitiveKind.box)continue;
                    auto thickness=model.resolveOperand(&feature.operands[1]); if(thickness<=0.0)continue;
                    auto centreX=(sourceSolid.bounds.minimum.x+sourceSolid.bounds.maximum.x)*0.5; auto centreY=(sourceSolid.bounds.minimum.y+sourceSolid.bounds.maximum.y)*0.5;
                    solidId=makeBoxShellAt(&model.exactGeometry,sourceSolid.primitiveA,sourceSolid.primitiveB,sourceSolid.primitiveC,thickness,centreX,centreY,sourceSolid.bounds.minimum.z);
                    if(solidId==0)continue; lineageParentA=sourceSolid.persistentId; lineageKind=BRepLineageKind.generated;
                }
                break;
            case FeatureKind.colour:
            case FeatureKind.displayModifier:
            case FeatureKind.renderBarrier:
                if (feature.operandCount < 1 || feature.operands[0].kind != OperandKind.feature ||
                    (feature.kind == FeatureKind.displayModifier && feature.operandCount != 1))
                    continue;
                {
                    auto sourceIndex = model.featureIndexById(feature.operands[0].featureId);
                    if (sourceIndex >= i || model.exactStatus[sourceIndex] != ExactGeometryStatus.exact)
                        continue;
                    solidId = model.exactSolidIds[sourceIndex];
                    ownsTopology = false;
                }
                break;

            /* These are all valid WaifuCAD operations, but WaifuBRep does not
               yet claim exact topology for them. Keep the distinction visible. */
            case FeatureKind.none:
            case FeatureKind.sketch:
            case FeatureKind.sketchLine:
            case FeatureKind.sketchArc:
            case FeatureKind.sketchCircle:
            case FeatureKind.sketchRectangle:
            case FeatureKind.sketchPolygon:
            case FeatureKind.sketchText:
            case FeatureKind.datumPlane:
            case FeatureKind.datumAxis:
            case FeatureKind.datumCsys:
            case FeatureKind.freePoint:
            case FeatureKind.freeLine:
            case FeatureKind.freeArc:
            case FeatureKind.freeCircle:
            case FeatureKind.freeSpline:
            case FeatureKind.dumbBody:
            case FeatureKind.import2d:
            case FeatureKind.import3d:
            case FeatureKind.heightSurface:
            case FeatureKind.polyhedron:
            case FeatureKind.circle2d:
            case FeatureKind.square2d:
            case FeatureKind.polygon2d:
            case FeatureKind.text2d:
            case FeatureKind.rotate:
            case FeatureKind.rotateAxis:
            case FeatureKind.scale:
            case FeatureKind.resize:
            case FeatureKind.mirror:
            case FeatureKind.multMatrix:
            case FeatureKind.offset2d:
            case FeatureKind.projection:
            case FeatureKind.hull:
            case FeatureKind.minkowski:
            case FeatureKind.fillet:
            case FeatureKind.chamfer:
                continue;
        }

        if (solidId == 0)
        {
            model.exactStatus[i] = ExactGeometryStatus.failed;
            model.exactErrors[i] = 20;
            continue;
        }
        auto validation = validateClosedSolid(&model.exactGeometry, solidId);
        if (validation != 0)
        {
            model.exactStatus[i] = ExactGeometryStatus.failed;
            model.exactErrors[i] = 100 + validation;
            continue;
        }
        if (ownsTopology && !assignPrimitivePersistentTopology(&model.exactGeometry, solidId, feature.id))
        {
            model.exactStatus[i] = ExactGeometryStatus.failed;
            model.exactErrors[i] = 180;
            continue;
        }
        if(ownsTopology && lineageKind!=BRepLineageKind.none)
        {
            auto resultSolid=model.exactGeometry.solid(solidId);
            if(resultSolid !is null && resultSolid.persistentId!=0 && lineageParentA!=0)
                model.exactGeometry.addLineage(resultSolid.persistentId,lineageParentA,lineageParentB,lineageKind);
        }
        model.exactSolidIds[i] = solidId;
        model.exactStatus[i] = ExactGeometryStatus.exact;
    }
    return 0;
}

GeometryBackendV1 waifuBRepBackend() nothrow @nogc
{
    GeometryBackendV1 backend;
    backend.abiVersion = WC_GEOMETRY_ABI_V1;
    backend.name = "waifubrep-native-v4".ptr;
    backend.recompute = &recomputeWaifuBRep;
    return backend;
}



