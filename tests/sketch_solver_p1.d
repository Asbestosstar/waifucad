module tests.sketch_solver_p1;

import core.stdc.math : fabs;
import waifucad.kernel.model : Model;
import waifucad.kernel.sketch_solver : addSketchConstraint, solveSketchConstraints, WC_SKETCH_SOLVE_CANCELLED;
import waifucad.kernel.types : FeatureKind, Operand, OperandKind, SketchConstraintKind, SketchConstraintStatus;

private Operand literal(double value) nothrow @nogc
{
    Operand result; result.kind=OperandKind.literal; result.literal=value; return result;
}

private Operand featureRef(uint id) nothrow @nogc
{
    Operand result; result.kind=OperandKind.feature; result.featureId=id; return result;
}

private uint addLine(Model* model,uint sketchId,const(char)* name,double x0,double y0,double x1,double y1) nothrow @nogc
{
    Operand[5] values=[featureRef(sketchId),literal(x0),literal(y0),literal(x1),literal(y1)];
    return model.addFeature(name,FeatureKind.sketchLine,values.ptr,5);
}

private uint addCircle(Model* model,uint sketchId,const(char)* name,double x,double y,double radius) nothrow @nogc
{
    Operand[4] values=[featureRef(sketchId),literal(x),literal(y),literal(radius)];
    return model.addFeature(name,FeatureKind.sketchCircle,values.ptr,4);
}

extern(C) int main()
{
    // Duplicate horizontal constraints are reported as redundant and do not
    // consume another degree of freedom.
    Model redundant; redundant.initialise("redundant".ptr);
    auto sketch=redundant.addFeature("s".ptr,FeatureKind.sketch,null,0);
    auto line=addLine(&redundant,sketch,"line".ptr,0,0,10,2);
    if(sketch==0||line==0)return 10;
    if(addSketchConstraint(&redundant,"h1".ptr,SketchConstraintKind.horizontal,sketch,line,0,0,0,0)==0)return 11;
    if(addSketchConstraint(&redundant,"h2".ptr,SketchConstraintKind.horizontal,sketch,line,0,0,0,0)==0)return 12;
    if(solveSketchConstraints(&redundant)!=0)return 13;
    if(redundant.sketchConstraints[0].status!=SketchConstraintStatus.satisfied||redundant.sketchConstraints[1].status!=SketchConstraintStatus.redundant)return 14;
    auto report=redundant.sketchSolveReportConst(sketch); if(report is null||report.redundantCount!=1||report.initialDegreesOfFreedom!=4||report.remainingDegreesOfFreedom!=3||!report.converged)return 15;
    if(report.jacobianRank!=1||report.rankDeficiency!=3||report.rankAnalysisTruncated||!redundant.sketchConstraints[1].rankRedundant)return 16;

    // Tangency combines endpoint-on-curve and tangent-direction equations.
    Model tangent; tangent.initialise("tangent".ptr);
    auto ts=tangent.addFeature("s".ptr,FeatureKind.sketch,null,0);
    auto tl=addLine(&tangent,ts,"line".ptr,5,0,5,3);
    auto circle=addCircle(&tangent,ts,"circle".ptr,0,0,5);
    if(addSketchConstraint(&tangent,"tan".ptr,SketchConstraintKind.tangent,ts,tl,0,circle,0,0)==0)return 20;
    if(solveSketchConstraints(&tangent)!=0||tangent.sketchConstraints[0].status!=SketchConstraintStatus.satisfied||tangent.sketchConstraints[0].residual>1.0e-7)return 21;


    // Curve-to-curve tangency is a one-equation external tangency condition.
    // The projection path moves the second curve centre while preserving both radii.
    Model curveTangent; curveTangent.initialise("curve-tangent".ptr);
    auto cts=curveTangent.addFeature("s".ptr,FeatureKind.sketch,null,0);
    auto cta=addCircle(&curveTangent,cts,"a".ptr,0,0,5);
    auto ctb=addCircle(&curveTangent,cts,"b".ptr,20,0,3);
    if(addSketchConstraint(&curveTangent,"tan".ptr,SketchConstraintKind.tangent,cts,cta,0,ctb,0,0)==0)return 22;
    if(solveSketchConstraints(&curveTangent)!=0||curveTangent.sketchConstraints[0].status!=SketchConstraintStatus.satisfied||curveTangent.sketchConstraints[0].residual>1.0e-7)return 23;
    auto curveReport=curveTangent.sketchSolveReportConst(cts);
    if(curveReport is null||curveReport.totalEquationCount!=1||curveReport.independentEquationCount!=1)return 24;

    // Symmetry projects one line segment so its midpoint lies on the axis and
    // its endpoints are mirrored across that axis.
    Model symmetric; symmetric.initialise("symmetry".ptr);
    auto ss=symmetric.addFeature("s".ptr,FeatureKind.sketch,null,0);
    auto segment=addLine(&symmetric,ss,"segment".ptr,-4,-2,3,3);
    auto axis=addLine(&symmetric,ss,"axis".ptr,0,-10,0,10);
    if(addSketchConstraint(&symmetric,"sym".ptr,SketchConstraintKind.symmetry,ss,segment,0,axis,0,0)==0)return 30;
    if(solveSketchConstraints(&symmetric)!=0||symmetric.sketchConstraints[0].status!=SketchConstraintStatus.satisfied||symmetric.sketchConstraints[0].residual>1.0e-7)return 31;

    // Obvious contradictory directional constraints are classified before the
    // projection loop instead of oscillating for all iterations.
    Model conflicting; conflicting.initialise("conflict".ptr);
    auto cs=conflicting.addFeature("s".ptr,FeatureKind.sketch,null,0);
    auto cl=addLine(&conflicting,cs,"line".ptr,0,0,10,2);
    addSketchConstraint(&conflicting,"h".ptr,SketchConstraintKind.horizontal,cs,cl,0,0,0,0);
    addSketchConstraint(&conflicting,"v".ptr,SketchConstraintKind.vertical,cs,cl,0,0,0,0);
    if(solveSketchConstraints(&conflicting)==0)return 40;
    auto conflictReport=conflicting.sketchSolveReportConst(cs); if(conflictReport is null||conflictReport.conflictingCount!=2||conflictReport.converged)return 41;

    // Cancellation is checked inside the solver, not only between exact
    // features in the outer recompute loop.
    Model cancelled; cancelled.initialise("cancelled".ptr);
    auto xs=cancelled.addFeature("s".ptr,FeatureKind.sketch,null,0);
    auto xl=addLine(&cancelled,xs,"line".ptr,0,0,10,2);
    addSketchConstraint(&cancelled,"h".ptr,SketchConstraintKind.horizontal,xs,xl,0,0,0,0);
    cancelled.requestRecomputeCancellation();
    if(solveSketchConstraints(&cancelled)!=WC_SKETCH_SOLVE_CANCELLED)return 50;
    return 0;
}

