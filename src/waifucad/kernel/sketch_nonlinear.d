module waifucad.kernel.sketch_nonlinear;

import core.stdc.math : fabs, sqrt, atan2;
import waifucad.kernel.model : Model;
import waifucad.kernel.types : EntityId, Feature, FeatureKind, OperandKind,
    SketchConstraint, SketchConstraintKind, SketchConstraintStatus;

// Fixed BetterC workspaces keep the solver allocation-free while covering
// substantially larger sketches than the original bootstrap diagnostic window.
enum WC_SKETCH_JACOBIAN_MAX_VARIABLES = 128;
enum WC_SKETCH_JACOBIAN_MAX_EQUATIONS = 256;
enum WC_SKETCH_NONLINEAR_MAX_ITERATIONS = 8;
private enum double WC_SKETCH_JACOBIAN_EPSILON = 1.0e-6;
private enum double WC_SKETCH_JACOBIAN_RANK_TOLERANCE = 1.0e-8;
private enum double WC_SKETCH_NONLINEAR_DAMPING = 1.0e-6;
private enum double WC_SKETCH_NONLINEAR_STEP_LIMIT = 10.0;
private enum double WC_PI = 3.14159265358979323846264338327950288;

struct SketchJacobianAnalysis
{
    uint variableCount;
    uint equationCount;
    uint rank;
    uint rankDeficiency;
    uint nonlinearIterations;
    double residualNorm;
    bool truncated;
    bool cancelled;
}

private bool featureBelongsToSketch(const Feature* feature, EntityId sketchId) nothrow @nogc
{
    return feature !is null && feature.operandCount != 0 &&
           feature.operands[0].kind == OperandKind.feature &&
           feature.operands[0].featureId == sketchId;
}

private bool linePoint(Model* model, Feature* feature, ubyte pointIndex,
                       double* x, double* y) nothrow @nogc
{
    if(model is null || feature is null || x is null || y is null ||
       feature.kind != FeatureKind.sketchLine || feature.operandCount < 5 || pointIndex > 1)
        return false;
    auto offset = pointIndex == 0 ? 1u : 3u;
    *x = model.resolveOperand(&feature.operands[offset]);
    *y = model.resolveOperand(&feature.operands[offset + 1]);
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
            *x=0.0; *y=0.0; *radius=model.resolveOperand(&feature.operands[1]);
            return *radius > 0.0;
        }
        if(feature.operandCount >= 4)
        {
            *x=model.resolveOperand(&feature.operands[1]);
            *y=model.resolveOperand(&feature.operands[2]);
            *radius=model.resolveOperand(&feature.operands[3]);
            return *radius > 0.0;
        }
    }
    if(feature.kind == FeatureKind.sketchArc && feature.operandCount >= 6)
    {
        *x=model.resolveOperand(&feature.operands[1]);
        *y=model.resolveOperand(&feature.operands[2]);
        *radius=model.resolveOperand(&feature.operands[3]);
        return *radius > 0.0;
    }
    return false;
}

private bool lineUnit(Model* model, Feature* feature, double* dx, double* dy) nothrow @nogc
{
    double x0=0.0,y0=0.0,x1=0.0,y1=0.0;
    if(dx is null || dy is null || !linePoint(model,feature,0,&x0,&y0) || !linePoint(model,feature,1,&x1,&y1)) return false;
    auto vx=x1-x0, vy=y1-y0; auto length=sqrt(vx*vx+vy*vy);
    if(length<=1.0e-12)return false;
    *dx=vx/length; *dy=vy/length; return true;
}

private double wrapAngle(double value) nothrow @nogc
{
    while(value > WC_PI) value -= 2.0*WC_PI;
    while(value < -WC_PI) value += 2.0*WC_PI;
    return value;
}

private uint constraintComponents(Model* model, const SketchConstraint* c,
                                  double* output, uint capacity) nothrow @nogc
{
    if(model is null || c is null || output is null || capacity == 0 || !c.enabled) return 0;
    auto a=model.featureById(c.firstFeatureId);
    auto b=c.secondFeatureId==0 ? null : model.featureById(c.secondFeatureId);
    if(a is null)return 0;
    double ax0=0,ay0=0,ax1=0,ay1=0,bx0=0,by0=0,bx1=0,by1=0;
    bool aLine=linePoint(model,a,0,&ax0,&ay0)&&linePoint(model,a,1,&ax1,&ay1);
    bool bLine=b !is null&&linePoint(model,b,0,&bx0,&by0)&&linePoint(model,b,1,&bx1,&by1);

    final switch(c.kind)
    {
        case SketchConstraintKind.horizontal:
            if(!aLine)return 0; output[0]=ay1-ay0; return 1;
        case SketchConstraintKind.vertical:
            if(!aLine)return 0; output[0]=ax1-ax0; return 1;
        case SketchConstraintKind.coincident:
            if(!aLine||!bLine||capacity<2)return 0;
            output[0]=(c.firstPoint==0?ax0:ax1)-(c.secondPoint==0?bx0:bx1);
            output[1]=(c.firstPoint==0?ay0:ay1)-(c.secondPoint==0?by0:by1); return 2;
        case SketchConstraintKind.distance:
            if(!aLine)return 0;
            {
                auto sx=c.firstPoint==0?ax0:ax1, sy=c.firstPoint==0?ay0:ay1;
                double tx=0,ty=0; auto target=b is null?a:b;
                ubyte point=b is null?cast(ubyte)(c.firstPoint==0?1:0):c.secondPoint;
                if(!linePoint(model,target,point,&tx,&ty))return 0;
                auto dx=tx-sx,dy=ty-sy; output[0]=sqrt(dx*dx+dy*dy)-c.value; return 1;
            }
        case SketchConstraintKind.equalLength:
            if(!aLine||!bLine)return 0;
            {
                auto adx=ax1-ax0,ady=ay1-ay0,bdx=bx1-bx0,bdy=by1-by0;
                output[0]=sqrt(bdx*bdx+bdy*bdy)-sqrt(adx*adx+ady*ady); return 1;
            }
        case SketchConstraintKind.parallel:
        case SketchConstraintKind.perpendicular:
            if(!aLine||!bLine)return 0;
            {
                double adx=0,ady=0,bdx=0,bdy=0;
                if(!lineUnit(model,a,&adx,&ady)||!lineUnit(model,b,&bdx,&bdy))return 0;
                output[0]=c.kind==SketchConstraintKind.parallel ? adx*bdy-ady*bdx : adx*bdx+ady*bdy;
                return 1;
            }
        case SketchConstraintKind.angle:
            if(!aLine||!bLine)return 0;
            {
                auto aa=atan2(ay1-ay0,ax1-ax0), ba=atan2(by1-by0,bx1-bx0);
                output[0]=wrapAngle(ba-aa-c.value*WC_PI/180.0); return 1;
            }
        case SketchConstraintKind.midpoint:
            if(!aLine||!bLine||capacity<2)return 0;
            output[0]=(c.firstPoint==0?ax0:ax1)-(bx0+bx1)*0.5;
            output[1]=(c.firstPoint==0?ay0:ay1)-(by0+by1)*0.5; return 2;
        case SketchConstraintKind.concentric:
            if(capacity<2)return 0;
            {
                double acx=0,acy=0,ar=0,bcx=0,bcy=0,br=0;
                if(!curveCentreRadius(model,a,&acx,&acy,&ar)||!curveCentreRadius(model,b,&bcx,&bcy,&br))return 0;
                output[0]=bcx-acx; output[1]=bcy-acy; return 2;
            }
        case SketchConstraintKind.equalRadius:
            {
                double acx=0,acy=0,ar=0,bcx=0,bcy=0,br=0;
                if(!curveCentreRadius(model,a,&acx,&acy,&ar)||!curveCentreRadius(model,b,&bcx,&bcy,&br))return 0;
                output[0]=br-ar; return 1;
            }
        case SketchConstraintKind.radius:
        case SketchConstraintKind.diameter:
            {
                double cx=0,cy=0,r=0;if(!curveCentreRadius(model,a,&cx,&cy,&r))return 0;
                output[0]=r-(c.kind==SketchConstraintKind.diameter?c.value*0.5:c.value); return 1;
            }
        case SketchConstraintKind.tangent:
            if(b is null)return 0;
            if(aLine)
            {
                if(capacity<2)return 0;
                double cx=0,cy=0,r=0;if(!curveCentreRadius(model,b,&cx,&cy,&r))return 0;
                auto px=c.firstPoint==0?ax0:ax1, py=c.firstPoint==0?ay0:ay1;
                auto rx=px-cx,ry=py-cy,rl=sqrt(rx*rx+ry*ry); if(rl<=1.0e-12)return 0;
                double dx=0,dy=0;if(!lineUnit(model,a,&dx,&dy))return 0; rx/=rl;ry/=rl;
                output[0]=rl-r; output[1]=dx*rx+dy*ry; return 2;
            }
            if(bLine)
            {
                if(capacity<2)return 0;
                double cx=0,cy=0,r=0;if(!curveCentreRadius(model,a,&cx,&cy,&r))return 0;
                auto px=c.secondPoint==0?bx0:bx1, py=c.secondPoint==0?by0:by1;
                auto rx=px-cx,ry=py-cy,rl=sqrt(rx*rx+ry*ry); if(rl<=1.0e-12)return 0;
                double dx=0,dy=0;if(!lineUnit(model,b,&dx,&dy))return 0; rx/=rl;ry/=rl;
                output[0]=rl-r; output[1]=dx*rx+dy*ry; return 2;
            }
            {
                double acx=0,acy=0,ar=0,bcx=0,bcy=0,br=0;
                if(!curveCentreRadius(model,a,&acx,&acy,&ar)||!curveCentreRadius(model,b,&bcx,&bcy,&br))return 0;
                auto dx=bcx-acx,dy=bcy-acy;
                output[0]=sqrt(dx*dx+dy*dy)-(ar+br);
                return 1;
            }
        case SketchConstraintKind.symmetry:
            if(!aLine||!bLine||capacity<2)return 0;
            {
                double axisX=0,axisY=0;if(!lineUnit(model,b,&axisX,&axisY))return 0;
                auto midX=(ax0+ax1)*0.5,midY=(ay0+ay1)*0.5;
                output[0]=(midX-bx0)*(-axisY)+(midY-by0)*axisX;
                double segX=0,segY=0;if(!lineUnit(model,a,&segX,&segY))return 0;
                output[1]=segX*axisX+segY*axisY; return 2;
            }
        case SketchConstraintKind.fixPoint:
            if(!aLine||capacity<2)return 0;
            output[0]=(c.firstPoint==0?ax0:ax1)-c.referenceX;
            output[1]=(c.firstPoint==0?ay0:ay1)-c.referenceY; return 2;
    }
}

private void markSketchGeometryDirty(Model* model, EntityId sketchId) nothrow @nogc
{
    if(model is null)return;
    foreach(i;0..model.featureCount)
        if(featureBelongsToSketch(&model.features[i],sketchId)) model.features[i].dirty=true;
}

private uint gatherVariables(Model* model, EntityId sketchId,
                             double** variables, uint capacity, bool* truncated) nothrow @nogc
{
    if(model is null || variables is null || truncated is null)return 0;
    uint count=0; *truncated=false;
    foreach(i;0..model.featureCount)
    {
        auto feature=&model.features[i]; if(!featureBelongsToSketch(feature,sketchId))continue;
        foreach(op;1..feature.operandCount)
        {
            if(feature.operands[op].kind!=OperandKind.literal)continue;
            if(count>=capacity){*truncated=true;return count;}
            variables[count++]=&feature.operands[op].literal;
        }
    }
    return count;
}

private uint gatherResiduals(Model* model, EntityId sketchId, double* residuals,
                             SketchConstraint** owners, uint capacity, bool* truncated) nothrow @nogc
{
    if(model is null || residuals is null || truncated is null)return 0;
    uint count=0; *truncated=false;
    foreach(i;0..model.sketchConstraintCount)
    {
        auto c=&model.sketchConstraints[i];
        if(!c.enabled||c.sketchId!=sketchId||c.status==SketchConstraintStatus.invalid||c.status==SketchConstraintStatus.conflicting||c.status==SketchConstraintStatus.redundant)continue;
        double[2] values; auto componentCount=constraintComponents(model,c,values.ptr,2);
        if(componentCount==0)continue;
        foreach(component;0..componentCount)
        {
            if(count>=capacity){*truncated=true;return count;}
            residuals[count]=values[component]; if(owners !is null)owners[count]=c; ++count;
        }
    }
    return count;
}

private double residualNorm(const(double)* values, uint count) nothrow @nogc
{
    double sum=0.0; foreach(i;0..count)sum+=values[i]*values[i]; return sqrt(sum);
}

private uint matrixRankPivotedMgs(double* matrix, uint rows, uint columns, uint stride) nothrow @nogc
{
    if(matrix is null || rows == 0 || columns == 0)return 0;
    double[WC_SKETCH_JACOBIAN_MAX_VARIABLES] columnNormSquared;
    foreach(column;0..columns)
    {
        double normSquared=0.0;
        foreach(row;0..rows)normSquared+=matrix[row*stride+column]*matrix[row*stride+column];
        columnNormSquared[column]=normSquared;
    }

    uint rank=0;
    double referenceNorm=0.0;
    auto maximumRank=rows<columns?rows:columns;
    foreach(step;0..maximumRank)
    {
        uint pivot=step; double bestSquared=0.0;
        foreach(column;step..columns)
        {
            if(columnNormSquared[column]>bestSquared){bestSquared=columnNormSquared[column];pivot=column;}
        }
        auto bestNorm=sqrt(bestSquared);
        if(step==0)referenceNorm=bestNorm;
        auto threshold=WC_SKETCH_JACOBIAN_RANK_TOLERANCE;
        auto relativeThreshold=referenceNorm*1.0e-9;
        if(relativeThreshold>threshold)threshold=relativeThreshold;
        if(bestNorm<=threshold)break;

        if(pivot!=step)
        {
            foreach(row;0..rows)
            {
                auto temporary=matrix[row*stride+step];
                matrix[row*stride+step]=matrix[row*stride+pivot];
                matrix[row*stride+pivot]=temporary;
            }
            auto normTemporary=columnNormSquared[step];
            columnNormSquared[step]=columnNormSquared[pivot];
            columnNormSquared[pivot]=normTemporary;
        }

        foreach(row;0..rows)matrix[row*stride+step]/=bestNorm;
        ++rank;

        foreach(column;step+1..columns)
        {
            // Two modified Gram-Schmidt passes reduce loss of orthogonality for
            // nearly dependent constraint rows without requiring heap storage.
            foreach(pass;0..2)
            {
                double projection=0.0;
                foreach(row;0..rows)projection+=matrix[row*stride+step]*matrix[row*stride+column];
                foreach(row;0..rows)matrix[row*stride+column]-=projection*matrix[row*stride+step];
            }
            double normSquared=0.0;
            foreach(row;0..rows)normSquared+=matrix[row*stride+column]*matrix[row*stride+column];
            columnNormSquared[column]=normSquared;
        }
    }
    return rank;
}

private bool buildJacobian(Model* model, EntityId sketchId, double** variables, uint variableCount,
                           double* residuals, SketchConstraint** owners, uint equationCount,
                           double* jacobian, uint stride) nothrow @nogc
{
    if(model is null||variables is null||residuals is null||jacobian is null)return false;
    foreach(column;0..variableCount)
    {
        if(model.recomputeCancelled())return false;
        auto pointer=variables[column]; auto original=*pointer;
        auto step=WC_SKETCH_JACOBIAN_EPSILON*(fabs(original)>1.0?fabs(original):1.0);
        *pointer=original+step;
        double[WC_SKETCH_JACOBIAN_MAX_EQUATIONS] perturbed; bool truncated=false;
        auto count=gatherResiduals(model,sketchId,perturbed.ptr,null,WC_SKETCH_JACOBIAN_MAX_EQUATIONS,&truncated);
        *pointer=original;
        if(truncated||count!=equationCount)return false;
        foreach(row;0..equationCount)jacobian[row*stride+column]=(perturbed[row]-residuals[row])/step;
    }
    return true;
}

private bool solveLinear(double* matrix, double* rhs, uint count, double* solution) nothrow @nogc
{
    if(matrix is null||rhs is null||solution is null)return false;
    foreach(i;0..count)solution[i]=0.0;
    foreach(column;0..count)
    {
        uint pivot=column; double best=fabs(matrix[column*WC_SKETCH_JACOBIAN_MAX_VARIABLES+column]);
        foreach(row;column+1..count)
        {
            auto value=fabs(matrix[row*WC_SKETCH_JACOBIAN_MAX_VARIABLES+column]);
            if(value>best){best=value;pivot=row;}
        }
        if(best<=1.0e-14)return false;
        if(pivot!=column)
        {
            foreach(c;column..count){auto temp=matrix[column*WC_SKETCH_JACOBIAN_MAX_VARIABLES+c];matrix[column*WC_SKETCH_JACOBIAN_MAX_VARIABLES+c]=matrix[pivot*WC_SKETCH_JACOBIAN_MAX_VARIABLES+c];matrix[pivot*WC_SKETCH_JACOBIAN_MAX_VARIABLES+c]=temp;}
            auto r=rhs[column];rhs[column]=rhs[pivot];rhs[pivot]=r;
        }
        auto divisor=matrix[column*WC_SKETCH_JACOBIAN_MAX_VARIABLES+column];
        foreach(c;column..count)matrix[column*WC_SKETCH_JACOBIAN_MAX_VARIABLES+c]/=divisor; rhs[column]/=divisor;
        foreach(row;0..count)
        {
            if(row==column)continue;auto factor=matrix[row*WC_SKETCH_JACOBIAN_MAX_VARIABLES+column];
            if(fabs(factor)<=1.0e-14)continue;
            foreach(c;column..count)matrix[row*WC_SKETCH_JACOBIAN_MAX_VARIABLES+c]-=factor*matrix[column*WC_SKETCH_JACOBIAN_MAX_VARIABLES+c];
            rhs[row]-=factor*rhs[column];
        }
    }
    foreach(i;0..count)solution[i]=rhs[i]; return true;
}

SketchJacobianAnalysis analyseSketchJacobian(Model* model, EntityId sketchId) nothrow @nogc
{
    SketchJacobianAnalysis result;
    if(model is null)return result;
    double*[WC_SKETCH_JACOBIAN_MAX_VARIABLES] variables; bool variableTruncated=false;
    result.variableCount=gatherVariables(model,sketchId,variables.ptr,WC_SKETCH_JACOBIAN_MAX_VARIABLES,&variableTruncated);
    double[WC_SKETCH_JACOBIAN_MAX_EQUATIONS] residuals; SketchConstraint*[WC_SKETCH_JACOBIAN_MAX_EQUATIONS] owners; bool equationTruncated=false;
    result.equationCount=gatherResiduals(model,sketchId,residuals.ptr,owners.ptr,WC_SKETCH_JACOBIAN_MAX_EQUATIONS,&equationTruncated);
    result.truncated=variableTruncated||equationTruncated;
    result.residualNorm=residualNorm(residuals.ptr,result.equationCount);
    if(model.recomputeCancelled()){result.cancelled=true;return result;}
    if(result.variableCount==0||result.equationCount==0)return result;
    double[WC_SKETCH_JACOBIAN_MAX_EQUATIONS*WC_SKETCH_JACOBIAN_MAX_VARIABLES] jacobian;
    if(!buildJacobian(model,sketchId,variables.ptr,result.variableCount,residuals.ptr,owners.ptr,result.equationCount,jacobian.ptr,WC_SKETCH_JACOBIAN_MAX_VARIABLES))
    {result.cancelled=model.recomputeCancelled();return result;}
    double[WC_SKETCH_JACOBIAN_MAX_EQUATIONS*WC_SKETCH_JACOBIAN_MAX_VARIABLES] rankMatrix;
    foreach(i;0..result.equationCount*WC_SKETCH_JACOBIAN_MAX_VARIABLES)rankMatrix[i]=jacobian[i];
    result.rank=matrixRankPivotedMgs(rankMatrix.ptr,result.equationCount,result.variableCount,WC_SKETCH_JACOBIAN_MAX_VARIABLES);
    result.rankDeficiency=result.variableCount>result.rank?result.variableCount-result.rank:0;

    // Incremental row-space rank contribution is exposed per constraint. This
    // supplements, rather than replaces, semantic duplicate/conflict checks.
    foreach(i;0..model.sketchConstraintCount){auto c=&model.sketchConstraints[i];if(c.sketchId==sketchId){c.rankContribution=0;c.rankRedundant=false;}}
    double[WC_SKETCH_JACOBIAN_MAX_VARIABLES*WC_SKETCH_JACOBIAN_MAX_VARIABLES] basis;
    uint basisCount=0;
    foreach(row;0..result.equationCount)
    {
        double[WC_SKETCH_JACOBIAN_MAX_VARIABLES] vector;
        foreach(column;0..result.variableCount)vector[column]=jacobian[row*WC_SKETCH_JACOBIAN_MAX_VARIABLES+column];
        foreach(pass;0..2)
        {
            foreach(b;0..basisCount)
            {
                double projection=0.0;foreach(column;0..result.variableCount)projection+=vector[column]*basis[b*WC_SKETCH_JACOBIAN_MAX_VARIABLES+column];
                foreach(column;0..result.variableCount)vector[column]-=projection*basis[b*WC_SKETCH_JACOBIAN_MAX_VARIABLES+column];
            }
        }
        double norm=0.0;foreach(column;0..result.variableCount)norm+=vector[column]*vector[column];norm=sqrt(norm);
        auto owner=owners[row];
        if(norm>WC_SKETCH_JACOBIAN_RANK_TOLERANCE&&basisCount<WC_SKETCH_JACOBIAN_MAX_VARIABLES)
        {
            foreach(column;0..result.variableCount)basis[basisCount*WC_SKETCH_JACOBIAN_MAX_VARIABLES+column]=vector[column]/norm;
            ++basisCount;if(owner !is null&&owner.rankContribution<ubyte.max)++owner.rankContribution;
        }
    }
    foreach(i;0..model.sketchConstraintCount)
    {
        auto c=&model.sketchConstraints[i];if(c.sketchId!=sketchId||!c.enabled)continue;
        if(c.status!=SketchConstraintStatus.invalid&&c.status!=SketchConstraintStatus.conflicting&&c.rankContribution==0)c.rankRedundant=true;
    }
    return result;
}

SketchJacobianAnalysis refineSketchNonlinear(Model* model, EntityId sketchId) nothrow @nogc
{
    auto result=analyseSketchJacobian(model,sketchId);
    if(model is null||result.cancelled||result.truncated||result.variableCount==0||result.equationCount==0)return result;
    double*[WC_SKETCH_JACOBIAN_MAX_VARIABLES] variables; bool truncated=false;
    auto variableCount=gatherVariables(model,sketchId,variables.ptr,WC_SKETCH_JACOBIAN_MAX_VARIABLES,&truncated); if(truncated)return result;
    foreach(iteration;0..WC_SKETCH_NONLINEAR_MAX_ITERATIONS)
    {
        if(model.recomputeCancelled()){result.cancelled=true;return result;}
        double[WC_SKETCH_JACOBIAN_MAX_EQUATIONS] residuals; bool equationTruncated=false;
        auto equationCount=gatherResiduals(model,sketchId,residuals.ptr,null,WC_SKETCH_JACOBIAN_MAX_EQUATIONS,&equationTruncated);
        if(equationTruncated||equationCount==0)return result;
        auto norm=residualNorm(residuals.ptr,equationCount); result.residualNorm=norm;
        if(norm<=1.0e-8)break;
        double[WC_SKETCH_JACOBIAN_MAX_EQUATIONS*WC_SKETCH_JACOBIAN_MAX_VARIABLES] jacobian;
        if(!buildJacobian(model,sketchId,variables.ptr,variableCount,residuals.ptr,null,equationCount,jacobian.ptr,WC_SKETCH_JACOBIAN_MAX_VARIABLES))
        {result.cancelled=model.recomputeCancelled();return result;}
        double[WC_SKETCH_JACOBIAN_MAX_VARIABLES*WC_SKETCH_JACOBIAN_MAX_VARIABLES] normal;
        double[WC_SKETCH_JACOBIAN_MAX_VARIABLES] rhs; double[WC_SKETCH_JACOBIAN_MAX_VARIABLES] delta;
        foreach(row;0..variableCount)
        {
            rhs[row]=0.0;
            foreach(column;0..variableCount)normal[row*WC_SKETCH_JACOBIAN_MAX_VARIABLES+column]=row==column?WC_SKETCH_NONLINEAR_DAMPING:0.0;
        }
        foreach(eq;0..equationCount)
        {
            foreach(row;0..variableCount)
            {
                auto jr=jacobian[eq*WC_SKETCH_JACOBIAN_MAX_VARIABLES+row]; rhs[row]-=jr*residuals[eq];
                foreach(column;0..variableCount)normal[row*WC_SKETCH_JACOBIAN_MAX_VARIABLES+column]+=jr*jacobian[eq*WC_SKETCH_JACOBIAN_MAX_VARIABLES+column];
            }
        }
        if(!solveLinear(normal.ptr,rhs.ptr,variableCount,delta.ptr))break;
        double scale=1.0;
        foreach(i;0..variableCount)if(fabs(delta[i])*scale>WC_SKETCH_NONLINEAR_STEP_LIMIT)scale=WC_SKETCH_NONLINEAR_STEP_LIMIT/fabs(delta[i]);
        foreach(i;0..variableCount)*variables[i]+=delta[i]*scale;
        markSketchGeometryDirty(model,sketchId);
        result.nonlinearIterations=cast(uint)iteration+1u;
    }
    auto finalAnalysis=analyseSketchJacobian(model,sketchId); finalAnalysis.nonlinearIterations=result.nonlinearIterations; return finalAnalysis;
}

