module waifucad.scl.getters;

import core.stdc.stdio : snprintf;
import core.stdc.stdlib : strtod, strtoull;
import core.stdc.string : strcmp, strlen;
import waifucad.brep.properties : massProperties;
import waifucad.brep.naming : edgeByPersistentId, faceByPersistentId, persistentTopologyKind, persistentTopologyOwner, persistentTopologySlot, solidByPersistentId, vertexByPersistentId;
import waifucad.brep.types : BRepCurveKind, BRepLineageKind, BRepPersistentId, BRepPrimitiveKind, BRepSurfaceKind, BRepTopologyKind, BRepVec3;
import waifucad.core.jobs : hardwareThreadCount, persistentWorkerCount;
import waifucad.journal.backend_api : ScriptContext;
import waifucad.journal.script_runtime : ScriptValueKind;
import waifucad.kernel.datums : DatumFrame, datumAxis, datumFeatureFrame;
import waifucad.kernel.types : ExactGeometryStatus, Feature, FeatureKind, ModellingRole, OperandKind, Parameter, SketchConstraint, SketchConstraintKind, SketchConstraintStatus, Unit;
import waifucad.scl.tokenise : Tokens;
import waifucad.sections.pmi.types : PmiAnnotation, PmiAnnotationKind;

// Returned by executeGetter when a command is not part of the read-only getter surface.
enum WC_GETTER_NOT_HANDLED = -1;

private bool parseIndex(const(char)* text, size_t* value) nothrow @nogc
{
    if (text is null || value is null)
        return false;
    const(char)* end = null;
    auto parsed = strtod(text, &end);
    if (end is text || *end != 0 || parsed < 0.0)
        return false;
    auto converted = cast(size_t)parsed;
    if (cast(double)converted != parsed)
        return false;
    *value = converted;
    return true;
}

private bool resolveIndex(ScriptContext* context, const(char)* text, size_t* value) nothrow @nogc
{
    if (context is null || text is null || value is null)
        return false;
    auto variable = context.runtime.find(text);
    if (variable !is null)
    {
        double numeric = 0.0;
        if (variable.value.asNumber(&numeric) && numeric >= 0.0)
        {
            auto converted = cast(size_t)numeric;
            if (cast(double)converted == numeric)
            {
                *value = converted;
                return true;
            }
        }
    }
    return parseIndex(text, value);
}

private const(char)* resolvedName(ScriptContext* context, const(char)* token) nothrow @nogc
{
    if (context is null || token is null)
        return token;
    auto variable = context.runtime.find(token);
    if (variable !is null && variable.value.kind == ScriptValueKind.string)
        return variable.value.stringValue.ptr();
    return token;
}

private Parameter* parameterByName(ScriptContext* context, const(char)* token) nothrow @nogc
{
    if (context is null || context.model is null || token is null)
        return null;
    auto name = resolvedName(context, token);
    return context.model.parameterById(context.model.findParameter(name));
}

private Feature* featureByName(ScriptContext* context, const(char)* token) nothrow @nogc
{
    if (context is null || context.model is null || token is null)
        return null;
    auto name = resolvedName(context, token);
    return context.model.featureById(context.model.findFeature(name));
}

private PmiAnnotation* pmiByName(ScriptContext* context, const(char)* token) nothrow @nogc
{
    if (context is null || context.pmi is null || token is null)
        return null;
    return context.pmi.findByName(resolvedName(context, token));
}

private const(char)* unitName(Unit unit) nothrow @nogc
{
    final switch (unit)
    {
        case Unit.unitless: return "unitless".ptr;
        case Unit.millimetre: return "mm".ptr;
        case Unit.degree: return "deg".ptr;
    }
}

private const(char)* operandKindName(OperandKind kind) nothrow @nogc
{
    final switch (kind)
    {
        case OperandKind.literal: return "literal".ptr;
        case OperandKind.parameter: return "parameter".ptr;
        case OperandKind.feature: return "feature".ptr;
    }
}

private const(char)* exactStatusName(ExactGeometryStatus status) nothrow @nogc
{
    final switch (status)
    {
        case ExactGeometryStatus.none: return "none".ptr;
        case ExactGeometryStatus.exact: return "exact".ptr;
        case ExactGeometryStatus.previewOnly: return "preview_only".ptr;
        case ExactGeometryStatus.failed: return "failed".ptr;
    }
}

private const(char)* modellingRoleName(ModellingRole role) nothrow @nogc
{
    final switch (role)
    {
        case ModellingRole.none: return "none".ptr;
        case ModellingRole.preferredParametric: return "preferred_parametric".ptr;
        case ModellingRole.sketchGeometry: return "sketch_geometry".ptr;
        case ModellingRole.directParametric: return "direct_parametric".ptr;
        case ModellingRole.roughCurve: return "rough_curve".ptr;
        case ModellingRole.dumbBody: return "dumb_body".ptr;
        case ModellingRole.displayOnly: return "display_only".ptr;
    }
}

private const(char)* featureKindName(FeatureKind kind) nothrow @nogc
{
    final switch (kind)
    {
        case FeatureKind.none: return "none".ptr;
        case FeatureKind.sketch: return "sketch".ptr;
        case FeatureKind.sketchLine: return "sketch_line".ptr;
        case FeatureKind.sketchArc: return "sketch_arc".ptr;
        case FeatureKind.sketchCircle: return "sketch_circle".ptr;
        case FeatureKind.sketchRectangle: return "sketch_rectangle".ptr;
        case FeatureKind.sketchPolygon: return "sketch_polygon".ptr;
        case FeatureKind.sketchText: return "sketch_text".ptr;
        case FeatureKind.datumPlane: return "datum_plane".ptr;
        case FeatureKind.datumAxis: return "datum_axis".ptr;
        case FeatureKind.datumCsys: return "datum_csys".ptr;
        case FeatureKind.extrude: return "extrude".ptr;
        case FeatureKind.revolve: return "revolve".ptr;
        case FeatureKind.sweep: return "sweep".ptr;
        case FeatureKind.loft: return "loft".ptr;
        case FeatureKind.freePoint: return "free_point".ptr;
        case FeatureKind.freeLine: return "free_line".ptr;
        case FeatureKind.freeArc: return "free_arc".ptr;
        case FeatureKind.freeCircle: return "free_circle".ptr;
        case FeatureKind.freeSpline: return "free_spline".ptr;
        case FeatureKind.dumbBody: return "dumb_body".ptr;
        case FeatureKind.import2d: return "import2d".ptr;
        case FeatureKind.import3d: return "import3d".ptr;
        case FeatureKind.heightSurface: return "height_surface".ptr;
        case FeatureKind.box: return "box".ptr;
        case FeatureKind.cylinder: return "cylinder".ptr;
        case FeatureKind.sphere: return "sphere".ptr;
        case FeatureKind.coneFrustum: return "cone_frustum".ptr;
        case FeatureKind.torus: return "torus".ptr;
        case FeatureKind.polyhedron: return "polyhedron".ptr;
        case FeatureKind.circle2d: return "circle2d".ptr;
        case FeatureKind.square2d: return "square2d".ptr;
        case FeatureKind.polygon2d: return "polygon2d".ptr;
        case FeatureKind.text2d: return "text2d".ptr;
        case FeatureKind.translate: return "translate".ptr;
        case FeatureKind.rotate: return "rotate".ptr;
        case FeatureKind.rotateAxis: return "rotate_axis".ptr;
        case FeatureKind.scale: return "scale".ptr;
        case FeatureKind.resize: return "resize".ptr;
        case FeatureKind.mirror: return "mirror".ptr;
        case FeatureKind.multMatrix: return "multmatrix".ptr;
        case FeatureKind.colour: return "colour".ptr;
        case FeatureKind.displayModifier: return "display_modifier".ptr;
        case FeatureKind.offset2d: return "offset2d".ptr;
        case FeatureKind.projection: return "projection".ptr;
        case FeatureKind.hull: return "hull".ptr;
        case FeatureKind.minkowski: return "minkowski".ptr;
        case FeatureKind.booleanUnion: return "union".ptr;
        case FeatureKind.booleanSubtract: return "subtract".ptr;
        case FeatureKind.booleanIntersect: return "intersect".ptr;
        case FeatureKind.renderBarrier: return "render".ptr;
        case FeatureKind.fillet: return "fillet".ptr;
        case FeatureKind.chamfer: return "chamfer".ptr;
        case FeatureKind.shell: return "shell".ptr;
    }
}


private const(char)* sketchConstraintKindName(SketchConstraintKind kind) nothrow @nogc
{
    final switch(kind)
    {
        case SketchConstraintKind.coincident:return "coincident".ptr;
        case SketchConstraintKind.horizontal:return "horizontal".ptr;
        case SketchConstraintKind.vertical:return "vertical".ptr;
        case SketchConstraintKind.distance:return "distance".ptr;
        case SketchConstraintKind.equalLength:return "equal_length".ptr;
        case SketchConstraintKind.parallel:return "parallel".ptr;
        case SketchConstraintKind.perpendicular:return "perpendicular".ptr;
        case SketchConstraintKind.angle:return "angle".ptr;
        case SketchConstraintKind.midpoint:return "midpoint".ptr;
        case SketchConstraintKind.concentric:return "concentric".ptr;
        case SketchConstraintKind.equalRadius:return "equal_radius".ptr;
        case SketchConstraintKind.radius:return "radius".ptr;
        case SketchConstraintKind.diameter:return "diameter".ptr;
        case SketchConstraintKind.tangent:return "tangent".ptr;
        case SketchConstraintKind.symmetry:return "symmetry".ptr;
        case SketchConstraintKind.fixPoint:return "fix_point".ptr;
    }
}

private const(char)* sketchConstraintStatusName(SketchConstraintStatus status) nothrow @nogc
{
    final switch(status)
    {
        case SketchConstraintStatus.pending:return "pending".ptr;
        case SketchConstraintStatus.satisfied:return "satisfied".ptr;
        case SketchConstraintStatus.unsatisfied:return "unsatisfied".ptr;
        case SketchConstraintStatus.redundant:return "redundant".ptr;
        case SketchConstraintStatus.conflicting:return "conflicting".ptr;
        case SketchConstraintStatus.invalid:return "invalid".ptr;
    }
}

private const(char)* lineageKindName(BRepLineageKind kind) nothrow @nogc
{
    final switch(kind)
    {
        case BRepLineageKind.none:return "none".ptr;
        case BRepLineageKind.split:return "split".ptr;
        case BRepLineageKind.merge:return "merge".ptr;
        case BRepLineageKind.booleanIntersection:return "boolean_intersection".ptr;
        case BRepLineageKind.booleanUnion:return "boolean_union".ptr;
        case BRepLineageKind.booleanSubtract:return "boolean_subtract".ptr;
        case BRepLineageKind.generated:return "generated".ptr;
    }
}

private const(char)* primitiveKindName(BRepPrimitiveKind kind) nothrow @nogc
{
    final switch (kind)
    {
        case BRepPrimitiveKind.generic: return "generic".ptr;
        case BRepPrimitiveKind.box: return "box".ptr;
        case BRepPrimitiveKind.cylinder: return "cylinder".ptr;
        case BRepPrimitiveKind.sphere: return "sphere".ptr;
        case BRepPrimitiveKind.coneFrustum: return "cone_frustum".ptr;
        case BRepPrimitiveKind.torus: return "torus".ptr;
        case BRepPrimitiveKind.boxShell: return "box_shell".ptr;
    }
}


private const(char)* topologyKindName(BRepTopologyKind kind) nothrow @nogc
{
    final switch (kind)
    {
        case BRepTopologyKind.none: return "none".ptr;
        case BRepTopologyKind.solidBody: return "body".ptr;
        case BRepTopologyKind.face: return "face".ptr;
        case BRepTopologyKind.edge: return "edge".ptr;
        case BRepTopologyKind.vertex: return "vertex".ptr;
    }
}


private const(char)* curveKindName(BRepCurveKind kind) nothrow @nogc
{
    final switch (kind)
    {
        case BRepCurveKind.none: return "none".ptr;
        case BRepCurveKind.line: return "line".ptr;
        case BRepCurveKind.circle: return "circle".ptr;
        case BRepCurveKind.ellipse: return "ellipse".ptr;
        case BRepCurveKind.bspline: return "bspline".ptr;
    }
}

private const(char)* surfaceKindName(BRepSurfaceKind kind) nothrow @nogc
{
    final switch (kind)
    {
        case BRepSurfaceKind.none: return "none".ptr;
        case BRepSurfaceKind.plane: return "plane".ptr;
        case BRepSurfaceKind.cylinder: return "cylinder".ptr;
        case BRepSurfaceKind.cone: return "cone".ptr;
        case BRepSurfaceKind.sphere: return "sphere".ptr;
        case BRepSurfaceKind.torus: return "torus".ptr;
        case BRepSurfaceKind.bspline: return "bspline".ptr;
    }
}

private bool parsePersistentId(ScriptContext* context, const(char)* token, BRepPersistentId* value) nothrow @nogc
{
    if (context is null || token is null || value is null)
        return false;
    auto text = resolvedName(context, token);
    const(char)* end = null;
    auto parsed = strtoull(text, &end, 0);
    if (end is text || *end != 0 || parsed == 0)
        return false;
    *value = cast(BRepPersistentId)parsed;
    return true;
}

private bool setPersistentId(ScriptContext* context, Tokens* tokens, BRepPersistentId value) nothrow @nogc
{
    if (tokens.count < 2 || value == 0)
        return false;
    char[24] buffer;
    if (snprintf(buffer.ptr, cast(int)buffer.length, "0x%016llx".ptr, cast(ulong)value) <= 0)
        return false;
    return context.runtime.setString(tokens.values[1], buffer.ptr);
}

private const(char)* pmiKindName(PmiAnnotationKind kind) nothrow @nogc
{
    final switch (kind)
    {
        case PmiAnnotationKind.none: return "none".ptr;
        case PmiAnnotationKind.note: return "note".ptr;
        case PmiAnnotationKind.linearDimension: return "linear_dimension".ptr;
        case PmiAnnotationKind.angularDimension: return "angular_dimension".ptr;
        case PmiAnnotationKind.radialDimension: return "radial_dimension".ptr;
        case PmiAnnotationKind.diameterDimension: return "diameter_dimension".ptr;
        case PmiAnnotationKind.datumFeature: return "datum_feature".ptr;
        case PmiAnnotationKind.featureControlFrame: return "feature_control_frame".ptr;
        case PmiAnnotationKind.surfaceTexture: return "surface_texture".ptr;
        case PmiAnnotationKind.weldSymbol: return "weld_symbol".ptr;
        case PmiAnnotationKind.centreline: return "centreline".ptr;
        case PmiAnnotationKind.annotationPlane: return "annotation_plane".ptr;
    }
}

private bool setNumber(ScriptContext* context, Tokens* tokens, double value) nothrow @nogc
{
    return tokens.count >= 2 && context.runtime.setNumber(tokens.values[1], value);
}

private bool setBoolean(ScriptContext* context, Tokens* tokens, bool value) nothrow @nogc
{
    return tokens.count >= 2 && context.runtime.setBoolean(tokens.values[1], value);
}

private bool setString(ScriptContext* context, Tokens* tokens, const(char)* value) nothrow @nogc
{
    return tokens.count >= 2 && context.runtime.setString(tokens.values[1], value is null ? "".ptr : value);
}

private bool setList(ScriptContext* context, Tokens* tokens, const(double)* values, uint count) nothrow @nogc
{
    return tokens.count >= 2 && context.runtime.setList(tokens.values[1], values, count);
}

private bool featureIndex(ScriptContext* context, Feature* feature, size_t* index) nothrow @nogc
{
    if (context is null || context.model is null || feature is null || index is null)
        return false;
    auto found = context.model.featureIndexById(feature.id);
    if (found >= context.model.featureCount)
        return false;
    *index = found;
    return true;
}

private size_t parameterDependantCount(ScriptContext* context, uint parameterId) nothrow @nogc
{
    size_t count = 0;
    foreach (i; 0 .. context.model.featureCount)
    {
        auto feature = &context.model.features[i];
        foreach (j; 0 .. feature.operandCount)
            if (feature.operands[j].kind == OperandKind.parameter && feature.operands[j].parameterId == parameterId)
            {
                ++count;
                break;
            }
    }
    return count;
}

private Feature* parameterDependantAt(ScriptContext* context, uint parameterId, size_t requested) nothrow @nogc
{
    size_t seen = 0;
    foreach (i; 0 .. context.model.featureCount)
    {
        auto feature = &context.model.features[i];
        bool depends = false;
        foreach (j; 0 .. feature.operandCount)
            if (feature.operands[j].kind == OperandKind.parameter && feature.operands[j].parameterId == parameterId)
            {
                depends = true;
                break;
            }
        if (!depends)
            continue;
        if (seen++ == requested)
            return feature;
    }
    return null;
}

private size_t featureDependantCount(ScriptContext* context, uint featureId) nothrow @nogc
{
    size_t count = 0;
    foreach (i; 0 .. context.model.featureCount)
    {
        auto feature = &context.model.features[i];
        foreach (j; 0 .. feature.operandCount)
            if (feature.operands[j].kind == OperandKind.feature && feature.operands[j].featureId == featureId)
            {
                ++count;
                break;
            }
    }
    return count;
}

private Feature* featureDependantAt(ScriptContext* context, uint featureId, size_t requested) nothrow @nogc
{
    size_t seen = 0;
    foreach (i; 0 .. context.model.featureCount)
    {
        auto feature = &context.model.features[i];
        bool depends = false;
        foreach (j; 0 .. feature.operandCount)
            if (feature.operands[j].kind == OperandKind.feature && feature.operands[j].featureId == featureId)
            {
                depends = true;
                break;
            }
        if (!depends)
            continue;
        if (seen++ == requested)
            return feature;
    }
    return null;
}

/*
 * Read-only model-inspection commands for scripts and AI providers. Every
 * getter stores its result in a ScriptRuntime variable supplied as the first
 * argument. They never return raw model pointers and are deliberately not
 * journalled by the interpreter because they do not mutate document state.
 *
 * Enumeration indices are zero-based and are inspection cursors only. They
 * must never be persisted as topology-selection references; persistent
 * topological naming remains a separate kernel task.
 */
int executeGetter(ScriptContext* context, Tokens* tokens) nothrow @nogc
{
    if (context is null || context.model is null || tokens is null || tokens.count == 0)
        return WC_GETTER_NOT_HANDLED;
    auto command = tokens.values[0];
    if (command is null || strlen(command) < 4 || command[0] != 'g' || command[1] != 'e' || command[2] != 't' || command[3] != '_')
        return WC_GETTER_NOT_HANDLED;

    // Model-level discovery.
    if (strcmp(command, "get_model_name".ptr) == 0)
        return setString(context, tokens, context.model.name.ptr()) ? 0 : 500;
    if (strcmp(command, "get_parameter_count".ptr) == 0)
        return setNumber(context, tokens, cast(double)context.model.parameterCount) ? 0 : 501;
    if (strcmp(command, "get_feature_count".ptr) == 0)
        return setNumber(context, tokens, cast(double)context.model.featureCount) ? 0 : 502;
    if (strcmp(command, "get_sketch_constraint_count".ptr) == 0)
        return setNumber(context,tokens,cast(double)context.model.sketchConstraintCount)?0:663;
    if (strcmp(command, "get_model_nurbs_curve_count".ptr) == 0)
        return setNumber(context,tokens,cast(double)context.model.exactGeometry.nurbsCurveCount)?0:664;
    if (strcmp(command, "get_model_nurbs_surface_count".ptr) == 0)
        return setNumber(context,tokens,cast(double)context.model.exactGeometry.nurbsSurfaceCount)?0:665;
    if (strcmp(command, "get_topology_lineage_count".ptr) == 0)
        return setNumber(context,tokens,cast(double)context.model.exactGeometry.lineageCount)?0:666;
    if (strcmp(command, "get_model_worker_count".ptr) == 0)
        return setNumber(context, tokens, cast(double)context.model.effectiveWorkerCount()) ? 0 : 503;
    if (strcmp(command, "get_model_requested_worker_count".ptr) == 0)
        return setNumber(context, tokens, cast(double)context.model.workerCount) ? 0 : 660;
    if (strcmp(command, "get_model_hardware_thread_count".ptr) == 0)
        return setNumber(context, tokens, cast(double)hardwareThreadCount()) ? 0 : 661;
    if (strcmp(command, "get_model_persistent_worker_count".ptr) == 0)
        return setNumber(context, tokens, cast(double)persistentWorkerCount()) ? 0 : 662;
    if (strcmp(command, "get_model_recompute_cancelled".ptr) == 0)
        return setBoolean(context, tokens, context.model.recomputeCancelled()) ? 0 : 694;
    if (strcmp(command, "get_model_exact_solid_count".ptr) == 0)
        return setNumber(context, tokens, cast(double)context.model.exactGeometry.solidCount) ? 0 : 504;
    if (strcmp(command, "get_model_mesh_count".ptr) == 0)
        return setNumber(context, tokens, cast(double)context.model.dumbMeshes.meshCount) ? 0 : 505;
    if (strcmp(command, "get_model_brep_counts".ptr) == 0)
    {
        double[7] values = [
            cast(double)context.model.exactGeometry.vertexCount,
            cast(double)context.model.exactGeometry.edgeCount,
            cast(double)context.model.exactGeometry.coedgeCount,
            cast(double)context.model.exactGeometry.loopCount,
            cast(double)context.model.exactGeometry.faceCount,
            cast(double)context.model.exactGeometry.shellCount,
            cast(double)context.model.exactGeometry.solidCount
        ];
        return setList(context, tokens, values.ptr, 7) ? 0 : 506;
    }
    if (strcmp(command, "get_model_mesh_totals".ptr) == 0)
    {
        double[3] values = [cast(double)context.model.dumbMeshes.meshCount,
                            cast(double)context.model.dumbMeshes.vertexCount,
                            cast(double)context.model.dumbMeshes.triangleCount];
        return setList(context, tokens, values.ptr, 3) ? 0 : 507;
    }

    // Parameter enumeration and relationships.
    if (strcmp(command, "get_parameter_name".ptr) == 0)
    {
        if (tokens.count < 3) return 508;
        size_t index = 0;
        if (!resolveIndex(context, tokens.values[2], &index) || index >= context.model.parameterCount) return 509;
        return setString(context, tokens, context.model.parameters[index].name.ptr()) ? 0 : 510;
    }
    if (strcmp(command, "get_parameter_exists".ptr) == 0)
    {
        if (tokens.count < 3) return 511;
        return setBoolean(context, tokens, parameterByName(context, tokens.values[2]) !is null) ? 0 : 512;
    }
    if (strcmp(command, "get_parameter_id".ptr) == 0 || strcmp(command, "get_parameter_value".ptr) == 0 ||
        strcmp(command, "get_parameter_unit".ptr) == 0 || strcmp(command, "get_parameter_dependant_count".ptr) == 0 ||
        strcmp(command, "get_parameter_is_expression".ptr) == 0 || strcmp(command, "get_parameter_expression".ptr) == 0 ||
        strcmp(command, "get_parameter_expression_error".ptr) == 0)
    {
        if (tokens.count < 3) return 513;
        auto parameter = parameterByName(context, tokens.values[2]);
        if (parameter is null) return 514;
        if (strcmp(command, "get_parameter_id".ptr) == 0)
            return setNumber(context, tokens, cast(double)parameter.id) ? 0 : 515;
        if (strcmp(command, "get_parameter_value".ptr) == 0)
            return setNumber(context, tokens, parameter.value) ? 0 : 516;
        if (strcmp(command, "get_parameter_unit".ptr) == 0)
            return setString(context, tokens, unitName(parameter.unit)) ? 0 : 517;
        if (strcmp(command, "get_parameter_is_expression".ptr) == 0)
            return setBoolean(context,tokens,parameter.expressionDefined)?0:667;
        if (strcmp(command, "get_parameter_expression".ptr) == 0)
            return setString(context,tokens,parameter.expressionDefined?parameter.expression.ptr():"".ptr)?0:668;
        if (strcmp(command, "get_parameter_expression_error".ptr) == 0)
            return setNumber(context,tokens,cast(double)parameter.expressionError)?0:669;
        return setNumber(context, tokens, cast(double)parameterDependantCount(context, parameter.id)) ? 0 : 518;
    }
    if (strcmp(command, "get_parameter_dependant_name".ptr) == 0)
    {
        if (tokens.count < 4) return 519;
        auto parameter = parameterByName(context, tokens.values[2]);
        size_t index = 0;
        if (parameter is null || !resolveIndex(context, tokens.values[3], &index)) return 520;
        auto feature = parameterDependantAt(context, parameter.id, index);
        if (feature is null) return 521;
        return setString(context, tokens, feature.name.ptr()) ? 0 : 522;
    }


    // Persistent sketch constraints and datum construction geometry.
    if(strcmp(command,"get_sketch_constraint_name".ptr)==0)
    {
        if(tokens.count<3)return 670; size_t index=0; if(!resolveIndex(context,tokens.values[2],&index)||index>=context.model.sketchConstraintCount)return 671;
        return setString(context,tokens,context.model.sketchConstraints[index].name.ptr())?0:672;
    }
    if(strcmp(command,"get_sketch_constraint_exists".ptr)==0)
    {
        if(tokens.count<3)return 673; bool found=false; foreach(i;0..context.model.sketchConstraintCount)if(context.model.sketchConstraints[i].name.equals(resolvedName(context,tokens.values[2]))){found=true;break;}
        return setBoolean(context,tokens,found)?0:674;
    }
    if(strcmp(command,"get_sketch_constraint_kind".ptr)==0||strcmp(command,"get_sketch_constraint_status".ptr)==0||
       strcmp(command,"get_sketch_constraint_value".ptr)==0||strcmp(command,"get_sketch_constraint_enabled".ptr)==0||
       strcmp(command,"get_sketch_constraint_sketch_name".ptr)==0||strcmp(command,"get_sketch_constraint_first_feature_name".ptr)==0||
       strcmp(command,"get_sketch_constraint_second_feature_name".ptr)==0||strcmp(command,"get_sketch_constraint_points".ptr)==0||
       strcmp(command,"get_sketch_constraint_residual".ptr)==0||strcmp(command,"get_sketch_constraint_rank_contribution".ptr)==0||
       strcmp(command,"get_sketch_constraint_rank_redundant".ptr)==0)
    {
        if(tokens.count<3)return 675; const(char)* name=resolvedName(context,tokens.values[2]); SketchConstraint* constraint=null;
        foreach(i;0..context.model.sketchConstraintCount)if(context.model.sketchConstraints[i].name.equals(name)){constraint=&context.model.sketchConstraints[i];break;}
        if(constraint is null)return 676;
        if(strcmp(command,"get_sketch_constraint_kind".ptr)==0)return setString(context,tokens,sketchConstraintKindName(constraint.kind))?0:677;
        if(strcmp(command,"get_sketch_constraint_status".ptr)==0)return setString(context,tokens,sketchConstraintStatusName(constraint.status))?0:678;
        if(strcmp(command,"get_sketch_constraint_value".ptr)==0)return setNumber(context,tokens,constraint.value)?0:679;
        if(strcmp(command,"get_sketch_constraint_enabled".ptr)==0)return setBoolean(context,tokens,constraint.enabled)?0:680;
        if(strcmp(command,"get_sketch_constraint_residual".ptr)==0)return setNumber(context,tokens,constraint.residual)?0:695;
        if(strcmp(command,"get_sketch_constraint_rank_contribution".ptr)==0)return setNumber(context,tokens,cast(double)constraint.rankContribution)?0:711;
        if(strcmp(command,"get_sketch_constraint_rank_redundant".ptr)==0)return setBoolean(context,tokens,constraint.rankRedundant)?0:712;
        if(strcmp(command,"get_sketch_constraint_points".ptr)==0){double[2] values=[constraint.firstPoint,constraint.secondPoint];return setList(context,tokens,values.ptr,2)?0:681;}
        uint id=constraint.sketchId; if(strcmp(command,"get_sketch_constraint_first_feature_name".ptr)==0)id=constraint.firstFeatureId; else if(strcmp(command,"get_sketch_constraint_second_feature_name".ptr)==0)id=constraint.secondFeatureId;
        auto feature=context.model.featureById(id); return setString(context,tokens,feature is null?"".ptr:feature.name.ptr())?0:682;
    }
    if(strcmp(command,"get_sketch_initial_dof".ptr)==0||strcmp(command,"get_sketch_dof".ptr)==0||
       strcmp(command,"get_sketch_constraint_equation_count".ptr)==0||strcmp(command,"get_sketch_satisfied_constraint_count".ptr)==0||
       strcmp(command,"get_sketch_redundant_constraint_count".ptr)==0||strcmp(command,"get_sketch_conflicting_constraint_count".ptr)==0||
       strcmp(command,"get_sketch_invalid_constraint_count".ptr)==0||strcmp(command,"get_sketch_unsatisfied_constraint_count".ptr)==0||
       strcmp(command,"get_sketch_solve_iterations".ptr)==0||strcmp(command,"get_sketch_max_residual".ptr)==0||
       strcmp(command,"get_sketch_solve_converged".ptr)==0||strcmp(command,"get_sketch_fully_constrained".ptr)==0||
       strcmp(command,"get_sketch_total_equation_count".ptr)==0||strcmp(command,"get_sketch_jacobian_rank".ptr)==0||
       strcmp(command,"get_sketch_rank_deficiency".ptr)==0||strcmp(command,"get_sketch_nonlinear_iterations".ptr)==0||
       strcmp(command,"get_sketch_under_constrained".ptr)==0||strcmp(command,"get_sketch_over_constrained".ptr)==0||
       strcmp(command,"get_sketch_rank_analysis_truncated".ptr)==0)
    {
        if(tokens.count<3)return 696;
        auto sketch=featureByName(context,tokens.values[2]);
        if(sketch is null||sketch.kind!=FeatureKind.sketch)return 697;
        auto report=context.model.sketchSolveReportConst(sketch.id);
        if(report is null)return 698;
        if(strcmp(command,"get_sketch_initial_dof".ptr)==0)return setNumber(context,tokens,cast(double)report.initialDegreesOfFreedom)?0:699;
        if(strcmp(command,"get_sketch_dof".ptr)==0)return setNumber(context,tokens,cast(double)report.remainingDegreesOfFreedom)?0:700;
        if(strcmp(command,"get_sketch_constraint_equation_count".ptr)==0)return setNumber(context,tokens,cast(double)report.independentEquationCount)?0:701;
        if(strcmp(command,"get_sketch_satisfied_constraint_count".ptr)==0)return setNumber(context,tokens,cast(double)report.satisfiedCount)?0:702;
        if(strcmp(command,"get_sketch_redundant_constraint_count".ptr)==0)return setNumber(context,tokens,cast(double)report.redundantCount)?0:703;
        if(strcmp(command,"get_sketch_conflicting_constraint_count".ptr)==0)return setNumber(context,tokens,cast(double)report.conflictingCount)?0:704;
        if(strcmp(command,"get_sketch_invalid_constraint_count".ptr)==0)return setNumber(context,tokens,cast(double)report.invalidCount)?0:705;
        if(strcmp(command,"get_sketch_unsatisfied_constraint_count".ptr)==0)return setNumber(context,tokens,cast(double)report.unsatisfiedCount)?0:706;
        if(strcmp(command,"get_sketch_solve_iterations".ptr)==0)return setNumber(context,tokens,cast(double)report.iterations)?0:707;
        if(strcmp(command,"get_sketch_max_residual".ptr)==0)return setNumber(context,tokens,report.maxResidual)?0:708;
        if(strcmp(command,"get_sketch_solve_converged".ptr)==0)return setBoolean(context,tokens,report.converged)?0:709;
        if(strcmp(command,"get_sketch_fully_constrained".ptr)==0)return setBoolean(context,tokens,report.fullyConstrained)?0:710;
        if(strcmp(command,"get_sketch_total_equation_count".ptr)==0)return setNumber(context,tokens,cast(double)report.totalEquationCount)?0:713;
        if(strcmp(command,"get_sketch_jacobian_rank".ptr)==0)return setNumber(context,tokens,cast(double)report.jacobianRank)?0:714;
        if(strcmp(command,"get_sketch_rank_deficiency".ptr)==0)return setNumber(context,tokens,cast(double)report.rankDeficiency)?0:715;
        if(strcmp(command,"get_sketch_nonlinear_iterations".ptr)==0)return setNumber(context,tokens,cast(double)report.nonlinearIterations)?0:716;
        if(strcmp(command,"get_sketch_under_constrained".ptr)==0)return setBoolean(context,tokens,report.underConstrained)?0:717;
        if(strcmp(command,"get_sketch_over_constrained".ptr)==0)return setBoolean(context,tokens,report.overConstrained)?0:718;
        return setBoolean(context,tokens,report.rankAnalysisTruncated)?0:719;
    }
    if(strcmp(command,"get_datum_frame_origin".ptr)==0||strcmp(command,"get_datum_frame_x_axis".ptr)==0||
       strcmp(command,"get_datum_frame_y_axis".ptr)==0||strcmp(command,"get_datum_frame_z_axis".ptr)==0)
    {
        if(tokens.count<3)return 683; auto feature=featureByName(context,tokens.values[2]); DatumFrame frame;
        if(feature is null||!datumFeatureFrame(context.model,feature.id,&frame))return 684; BRepVec3 value=frame.origin;
        if(strcmp(command,"get_datum_frame_x_axis".ptr)==0)value=frame.xAxis; else if(strcmp(command,"get_datum_frame_y_axis".ptr)==0)value=frame.yAxis; else if(strcmp(command,"get_datum_frame_z_axis".ptr)==0)value=frame.zAxis;
        double[3] values=[value.x,value.y,value.z]; return setList(context,tokens,values.ptr,3)?0:685;
    }
    if(strcmp(command,"get_datum_axis_origin".ptr)==0||strcmp(command,"get_datum_axis_direction".ptr)==0)
    {
        if(tokens.count<3)return 686; auto feature=featureByName(context,tokens.values[2]); BRepVec3 origin,direction;
        if(feature is null||!datumAxis(context.model,feature.id,&origin,&direction))return 687; auto value=strcmp(command,"get_datum_axis_origin".ptr)==0?origin:direction;
        double[3] values=[value.x,value.y,value.z]; return setList(context,tokens,values.ptr,3)?0:688;
    }

    if(strcmp(command,"get_topology_lineage_result".ptr)==0||strcmp(command,"get_topology_lineage_parent_a".ptr)==0||
       strcmp(command,"get_topology_lineage_parent_b".ptr)==0||strcmp(command,"get_topology_lineage_kind".ptr)==0)
    {
        if(tokens.count<3)return 689; size_t index=0; if(!resolveIndex(context,tokens.values[2],&index)||index>=context.model.exactGeometry.lineageCount)return 690;
        auto item=&context.model.exactGeometry.lineage[index]; if(strcmp(command,"get_topology_lineage_kind".ptr)==0)return setString(context,tokens,lineageKindName(item.kind))?0:691;
        auto id=item.result; if(strcmp(command,"get_topology_lineage_parent_a".ptr)==0)id=item.parentA; else if(strcmp(command,"get_topology_lineage_parent_b".ptr)==0)id=item.parentB;
        if(id==0)return setString(context,tokens,"none".ptr)?0:692; return setPersistentId(context,tokens,id)?0:693;
    }

    // Feature enumeration and graph metadata.
    if (strcmp(command, "get_feature_name".ptr) == 0)
    {
        if (tokens.count < 3) return 523;
        size_t index = 0;
        if (!resolveIndex(context, tokens.values[2], &index) || index >= context.model.featureCount) return 524;
        return setString(context, tokens, context.model.features[index].name.ptr()) ? 0 : 525;
    }
    if (strcmp(command, "get_feature_exists".ptr) == 0)
    {
        if (tokens.count < 3) return 526;
        return setBoolean(context, tokens, featureByName(context, tokens.values[2]) !is null) ? 0 : 527;
    }
    if (strcmp(command, "get_feature_id".ptr) == 0 || strcmp(command, "get_feature_index".ptr) == 0 ||
        strcmp(command, "get_feature_kind".ptr) == 0 || strcmp(command, "get_feature_role".ptr) == 0 ||
        strcmp(command, "get_feature_dirty".ptr) == 0 || strcmp(command, "get_feature_recommended".ptr) == 0 ||
        strcmp(command, "get_feature_dependency_depth".ptr) == 0 || strcmp(command, "get_feature_operand_count".ptr) == 0 ||
        strcmp(command, "get_feature_dependant_count".ptr) == 0 || strcmp(command, "get_feature_payload".ptr) == 0 ||
        strcmp(command, "get_feature_payload2".ptr) == 0 || strcmp(command, "get_feature_mesh_id".ptr) == 0 ||
        strcmp(command, "get_feature_geometry_status".ptr) == 0 || strcmp(command, "get_feature_exact_solid_id".ptr) == 0 ||
        strcmp(command, "get_feature_preview_error".ptr) == 0 || strcmp(command, "get_feature_exact_error".ptr) == 0)
    {
        if (tokens.count < 3) return 528;
        auto feature = featureByName(context, tokens.values[2]);
        if (feature is null) return 529;
        size_t index = 0;
        if (!featureIndex(context, feature, &index)) return 530;
        if (strcmp(command, "get_feature_id".ptr) == 0) return setNumber(context, tokens, cast(double)feature.id) ? 0 : 531;
        if (strcmp(command, "get_feature_index".ptr) == 0) return setNumber(context, tokens, cast(double)index) ? 0 : 532;
        if (strcmp(command, "get_feature_kind".ptr) == 0) return setString(context, tokens, featureKindName(feature.kind)) ? 0 : 533;
        if (strcmp(command, "get_feature_role".ptr) == 0) return setString(context, tokens, modellingRoleName(feature.role)) ? 0 : 534;
        if (strcmp(command, "get_feature_dirty".ptr) == 0) return setBoolean(context, tokens, feature.dirty) ? 0 : 535;
        if (strcmp(command, "get_feature_recommended".ptr) == 0) return setBoolean(context, tokens, feature.recommendedWorkflow) ? 0 : 536;
        if (strcmp(command, "get_feature_dependency_depth".ptr) == 0) return setNumber(context, tokens, cast(double)feature.dependencyDepth) ? 0 : 537;
        if (strcmp(command, "get_feature_operand_count".ptr) == 0) return setNumber(context, tokens, cast(double)feature.operandCount) ? 0 : 538;
        if (strcmp(command, "get_feature_dependant_count".ptr) == 0) return setNumber(context, tokens, cast(double)featureDependantCount(context, feature.id)) ? 0 : 539;
        if (strcmp(command, "get_feature_payload".ptr) == 0) return setString(context, tokens, feature.payload.ptr()) ? 0 : 540;
        if (strcmp(command, "get_feature_payload2".ptr) == 0) return setString(context, tokens, feature.payload2.ptr()) ? 0 : 541;
        if (strcmp(command, "get_feature_mesh_id".ptr) == 0) return setNumber(context, tokens, cast(double)feature.meshId) ? 0 : 542;
        if (strcmp(command, "get_feature_geometry_status".ptr) == 0) return setString(context, tokens, exactStatusName(context.model.exactStatus[index])) ? 0 : 543;
        if (strcmp(command, "get_feature_exact_solid_id".ptr) == 0) return setNumber(context, tokens, cast(double)context.model.exactSolidIds[index]) ? 0 : 544;
        if (strcmp(command, "get_feature_preview_error".ptr) == 0) return setNumber(context, tokens, cast(double)context.model.previewErrors[index]) ? 0 : 545;
        return setNumber(context, tokens, cast(double)context.model.exactErrors[index]) ? 0 : 546;
    }
    if (strcmp(command, "get_feature_dependant_name".ptr) == 0)
    {
        if (tokens.count < 4) return 547;
        auto feature = featureByName(context, tokens.values[2]);
        size_t requested = 0;
        if (feature is null || !resolveIndex(context, tokens.values[3], &requested)) return 548;
        auto dependant = featureDependantAt(context, feature.id, requested);
        if (dependant is null) return 549;
        return setString(context, tokens, dependant.name.ptr()) ? 0 : 550;
    }

    // Feature operands. Operand indices are feature-graph indices, not topology references.
    if (strcmp(command, "get_feature_operand_kind".ptr) == 0 || strcmp(command, "get_feature_operand_name".ptr) == 0 ||
        strcmp(command, "get_feature_operand_value".ptr) == 0 || strcmp(command, "get_feature_operand_entity_id".ptr) == 0)
    {
        if (tokens.count < 4) return 551;
        auto feature = featureByName(context, tokens.values[2]);
        size_t operandIndex = 0;
        if (feature is null || !resolveIndex(context, tokens.values[3], &operandIndex) || operandIndex >= feature.operandCount) return 552;
        auto operand = &feature.operands[operandIndex];
        if (strcmp(command, "get_feature_operand_kind".ptr) == 0)
            return setString(context, tokens, operandKindName(operand.kind)) ? 0 : 553;
        if (strcmp(command, "get_feature_operand_entity_id".ptr) == 0)
        {
            double id = operand.kind == OperandKind.parameter ? cast(double)operand.parameterId :
                        operand.kind == OperandKind.feature ? cast(double)operand.featureId : 0.0;
            return setNumber(context, tokens, id) ? 0 : 554;
        }
        if (strcmp(command, "get_feature_operand_value".ptr) == 0)
        {
            if (operand.kind == OperandKind.literal) return setNumber(context, tokens, operand.literal) ? 0 : 555;
            if (operand.kind == OperandKind.parameter)
            {
                auto parameter = context.model.parameterById(operand.parameterId);
                if (parameter is null) return 556;
                return setNumber(context, tokens, parameter.value) ? 0 : 557;
            }
            return setNumber(context, tokens, cast(double)operand.featureId) ? 0 : 558;
        }
        if (operand.kind == OperandKind.parameter)
        {
            auto parameter = context.model.parameterById(operand.parameterId);
            if (parameter is null) return 559;
            return setString(context, tokens, parameter.name.ptr()) ? 0 : 560;
        }
        if (operand.kind == OperandKind.feature)
        {
            auto source = context.model.featureById(operand.featureId);
            if (source is null) return 561;
            return setString(context, tokens, source.name.ptr()) ? 0 : 562;
        }
        return setString(context, tokens, "".ptr) ? 0 : 563;
    }

    // Geometry state and bounds. Exact data is never fabricated from preview bounds.
    if (strcmp(command, "get_feature_preview_bounds_valid".ptr) == 0 || strcmp(command, "get_feature_preview_bounds".ptr) == 0 ||
        strcmp(command, "get_feature_exact_bounds_valid".ptr) == 0 || strcmp(command, "get_feature_exact_bounds".ptr) == 0 ||
        strcmp(command, "get_feature_bounds_source".ptr) == 0 || strcmp(command, "get_feature_bounds".ptr) == 0 ||
        strcmp(command, "get_feature_exact_primitive_kind".ptr) == 0 || strcmp(command, "get_feature_exact_topology_counts".ptr) == 0 ||
        strcmp(command, "get_feature_exact_shell_count".ptr) == 0 || strcmp(command, "get_feature_exact_genus".ptr) == 0 ||
        strcmp(command, "get_feature_volume".ptr) == 0 || strcmp(command, "get_feature_surface_area".ptr) == 0 ||
        strcmp(command, "get_feature_centre_of_mass".ptr) == 0)
    {
        if (tokens.count < 3) return 564;
        auto feature = featureByName(context, tokens.values[2]);
        size_t index = 0;
        if (feature is null || !featureIndex(context, feature, &index)) return 565;
        auto preview = &context.model.previewBounds[index];
        auto solidId = context.model.exactSolidIds[index];
        auto solid = solidId == 0 ? null : context.model.exactGeometry.solid(solidId);
        bool exactBoundsValid = context.model.exactStatus[index] == ExactGeometryStatus.exact && solid !is null && solid.bounds.valid;

        if (strcmp(command, "get_feature_preview_bounds_valid".ptr) == 0)
            return setBoolean(context, tokens, preview.valid) ? 0 : 566;
        if (strcmp(command, "get_feature_exact_bounds_valid".ptr) == 0)
            return setBoolean(context, tokens, exactBoundsValid) ? 0 : 567;
        if (strcmp(command, "get_feature_bounds_source".ptr) == 0)
            return setString(context, tokens, exactBoundsValid ? "exact".ptr : (preview.valid ? "preview".ptr : "none".ptr)) ? 0 : 568;
        if (strcmp(command, "get_feature_preview_bounds".ptr) == 0)
        {
            if (!preview.valid) return 569;
            double[6] values = [preview.minX, preview.minY, preview.minZ, preview.maxX, preview.maxY, preview.maxZ];
            return setList(context, tokens, values.ptr, 6) ? 0 : 570;
        }
        if (strcmp(command, "get_feature_exact_bounds".ptr) == 0)
        {
            if (!exactBoundsValid) return 571;
            double[6] values = [solid.bounds.minimum.x, solid.bounds.minimum.y, solid.bounds.minimum.z,
                                solid.bounds.maximum.x, solid.bounds.maximum.y, solid.bounds.maximum.z];
            return setList(context, tokens, values.ptr, 6) ? 0 : 572;
        }
        if (strcmp(command, "get_feature_bounds".ptr) == 0)
        {
            if (exactBoundsValid)
            {
                double[6] values = [solid.bounds.minimum.x, solid.bounds.minimum.y, solid.bounds.minimum.z,
                                    solid.bounds.maximum.x, solid.bounds.maximum.y, solid.bounds.maximum.z];
                return setList(context, tokens, values.ptr, 6) ? 0 : 573;
            }
            if (!preview.valid) return 574;
            double[6] values = [preview.minX, preview.minY, preview.minZ, preview.maxX, preview.maxY, preview.maxZ];
            return setList(context, tokens, values.ptr, 6) ? 0 : 575;
        }
        if (!exactBoundsValid) return 576;
        if (strcmp(command, "get_feature_exact_primitive_kind".ptr) == 0)
            return setString(context, tokens, primitiveKindName(solid.primitiveKind)) ? 0 : 577;
        if (strcmp(command, "get_feature_exact_topology_counts".ptr) == 0)
        {
            double[3] values = [cast(double)solid.vertexCount, cast(double)solid.edgeCount, cast(double)solid.faceCount];
            return setList(context, tokens, values.ptr, 3) ? 0 : 578;
        }
        if(strcmp(command,"get_feature_exact_shell_count".ptr)==0)return setNumber(context,tokens,cast(double)solid.shellCount)?0:695;
        if(strcmp(command,"get_feature_exact_genus".ptr)==0)return setNumber(context,tokens,cast(double)solid.genus)?0:696;
        auto properties = massProperties(&context.model.exactGeometry, solidId);
        if (!properties.valid) return 579;
        if (strcmp(command, "get_feature_volume".ptr) == 0)
            return setNumber(context, tokens, properties.volume) ? 0 : 580;
        if (strcmp(command, "get_feature_surface_area".ptr) == 0)
            return setNumber(context, tokens, properties.surfaceArea) ? 0 : 581;
        double[3] centre = [properties.centreOfMass.x, properties.centreOfMass.y, properties.centreOfMass.z];
        return setList(context, tokens, centre.ptr, 3) ? 0 : 582;
    }


    // Persistent exact-topology inspection. Persistent IDs are strings so the
    // full 64-bit identity is never rounded through ScriptRuntime doubles.
    if (strcmp(command, "get_feature_persistent_body_id".ptr) == 0 ||
        strcmp(command, "get_feature_face_persistent_id".ptr) == 0 ||
        strcmp(command, "get_feature_edge_persistent_id".ptr) == 0 ||
        strcmp(command, "get_feature_vertex_persistent_id".ptr) == 0)
    {
        if (tokens.count < 3) return 620;
        auto feature = featureByName(context, tokens.values[2]);
        size_t featureIndexValue = 0;
        if (feature is null || !featureIndex(context, feature, &featureIndexValue) ||
            context.model.exactStatus[featureIndexValue] != ExactGeometryStatus.exact) return 621;
        auto solid = context.model.exactGeometry.solid(context.model.exactSolidIds[featureIndexValue]);
        if (solid is null || solid.persistentId == 0) return 622;
        if (strcmp(command, "get_feature_persistent_body_id".ptr) == 0)
            return setPersistentId(context, tokens, solid.persistentId) ? 0 : 623;
        if (tokens.count < 4) return 624;
        size_t local = 0;
        if (!resolveIndex(context, tokens.values[3], &local)) return 625;
        if (strcmp(command, "get_feature_face_persistent_id".ptr) == 0)
        {
            if (local >= solid.faceCount) return 626;
            auto item = context.model.exactGeometry.face(solid.firstFace + cast(uint)local);
            return item !is null && setPersistentId(context, tokens, item.persistentId) ? 0 : 627;
        }
        if (strcmp(command, "get_feature_edge_persistent_id".ptr) == 0)
        {
            if (local >= solid.edgeCount) return 628;
            auto item = context.model.exactGeometry.edge(solid.firstEdge + cast(uint)local);
            return item !is null && setPersistentId(context, tokens, item.persistentId) ? 0 : 629;
        }
        if (local >= solid.vertexCount) return 630;
        auto item = context.model.exactGeometry.vertex(solid.firstVertex + cast(uint)local);
        return item !is null && setPersistentId(context, tokens, item.persistentId) ? 0 : 631;
    }

    if (strcmp(command, "get_topology_exists".ptr) == 0 || strcmp(command, "get_topology_kind".ptr) == 0 ||
        strcmp(command, "get_topology_owner_feature_id".ptr) == 0 || strcmp(command, "get_topology_owner_feature_name".ptr) == 0 ||
        strcmp(command, "get_topology_semantic_slot".ptr) == 0 || strcmp(command, "get_topology_vertex_point".ptr) == 0 ||
        strcmp(command, "get_topology_vertex_tolerance".ptr) == 0 || strcmp(command, "get_topology_edge_start_vertex_id".ptr) == 0 ||
        strcmp(command, "get_topology_edge_end_vertex_id".ptr) == 0 || strcmp(command, "get_topology_edge_curve_kind".ptr) == 0 ||
        strcmp(command, "get_topology_edge_radius".ptr) == 0 || strcmp(command, "get_topology_edge_parameter_range".ptr) == 0 ||
        strcmp(command, "get_topology_face_surface_kind".ptr) == 0 || strcmp(command, "get_topology_face_origin".ptr) == 0 ||
        strcmp(command, "get_topology_face_axis".ptr) == 0 || strcmp(command, "get_topology_face_radius".ptr) == 0 ||
        strcmp(command, "get_topology_face_secondary_radius".ptr) == 0 || strcmp(command, "get_topology_face_loop_count".ptr) == 0)
    {
        if (tokens.count < 3) return 632;
        BRepPersistentId persistentId = 0;
        if (!parsePersistentId(context, tokens.values[2], &persistentId)) return 633;
        auto kind = persistentTopologyKind(persistentId);
        auto solid = solidByPersistentId(&context.model.exactGeometry, persistentId);
        auto face = faceByPersistentId(&context.model.exactGeometry, persistentId);
        auto edge = edgeByPersistentId(&context.model.exactGeometry, persistentId);
        auto vertex = vertexByPersistentId(&context.model.exactGeometry, persistentId);
        bool exists = solid !is null || face !is null || edge !is null || vertex !is null;
        if (strcmp(command, "get_topology_exists".ptr) == 0)
            return setBoolean(context, tokens, exists) ? 0 : 634;
        if (!exists || kind == BRepTopologyKind.none) return 635;
        if (strcmp(command, "get_topology_kind".ptr) == 0)
            return setString(context, tokens, topologyKindName(kind)) ? 0 : 636;
        if (strcmp(command, "get_topology_owner_feature_id".ptr) == 0)
            return setNumber(context, tokens, cast(double)persistentTopologyOwner(persistentId)) ? 0 : 637;
        if (strcmp(command, "get_topology_owner_feature_name".ptr) == 0)
        {
            auto owner = context.model.featureById(persistentTopologyOwner(persistentId));
            if (owner is null) return 646;
            return setString(context, tokens, owner.name.ptr()) ? 0 : 647;
        }
        if (strcmp(command, "get_topology_semantic_slot".ptr) == 0)
        {
            uint semanticSlot = 0;
            if (!persistentTopologySlot(persistentId, &semanticSlot)) return 638;
            return setNumber(context, tokens, cast(double)semanticSlot) ? 0 : 639;
        }
        if (strcmp(command, "get_topology_vertex_point".ptr) == 0)
        {
            if (vertex is null) return 640;
            double[3] values = [vertex.point.x, vertex.point.y, vertex.point.z];
            return setList(context, tokens, values.ptr, 3) ? 0 : 641;
        }
        if (strcmp(command, "get_topology_vertex_tolerance".ptr) == 0)
        {
            if (vertex is null) return 648;
            return setNumber(context, tokens, vertex.tolerance) ? 0 : 649;
        }
        if (strcmp(command, "get_topology_edge_start_vertex_id".ptr) == 0 ||
            strcmp(command, "get_topology_edge_end_vertex_id".ptr) == 0)
        {
            if (edge is null) return 642;
            auto vertexId = strcmp(command, "get_topology_edge_start_vertex_id".ptr) == 0 ? edge.startVertex : edge.endVertex;
            auto endpoint = context.model.exactGeometry.vertex(vertexId);
            return endpoint !is null && setPersistentId(context, tokens, endpoint.persistentId) ? 0 : 643;
        }
        if (strcmp(command, "get_topology_edge_curve_kind".ptr) == 0)
        {
            if (edge is null) return 650;
            return setString(context, tokens, curveKindName(edge.curveKind)) ? 0 : 651;
        }
        if (strcmp(command, "get_topology_edge_radius".ptr) == 0)
        {
            if (edge is null) return 652;
            return setNumber(context, tokens, edge.radius) ? 0 : 653;
        }
        if (strcmp(command, "get_topology_edge_parameter_range".ptr) == 0)
        {
            if (edge is null) return 654;
            double[2] values = [edge.parameterStart, edge.parameterEnd];
            return setList(context, tokens, values.ptr, 2) ? 0 : 655;
        }
        if (face is null) return 644;
        if (strcmp(command, "get_topology_face_surface_kind".ptr) == 0)
            return setString(context, tokens, surfaceKindName(face.surfaceKind)) ? 0 : 645;
        if (strcmp(command, "get_topology_face_origin".ptr) == 0)
        {
            double[3] values = [face.origin.x, face.origin.y, face.origin.z];
            return setList(context, tokens, values.ptr, 3) ? 0 : 656;
        }
        if (strcmp(command, "get_topology_face_axis".ptr) == 0)
        {
            double[3] values = [face.axis.x, face.axis.y, face.axis.z];
            return setList(context, tokens, values.ptr, 3) ? 0 : 657;
        }
        if (strcmp(command, "get_topology_face_radius".ptr) == 0)
            return setNumber(context, tokens, face.radius) ? 0 : 658;
        if(strcmp(command,"get_topology_face_loop_count".ptr)==0)return setNumber(context,tokens,cast(double)face.loopCount)?0:697;
        return setNumber(context, tokens, face.secondaryRadius) ? 0 : 659;
    }

    // Dumb-mesh metadata for imported/non-associative bodies.
    if (strcmp(command, "get_feature_mesh_vertex_count".ptr) == 0 || strcmp(command, "get_feature_mesh_triangle_count".ptr) == 0 ||
        strcmp(command, "get_feature_mesh_source".ptr) == 0 || strcmp(command, "get_feature_mesh_format".ptr) == 0 ||
        strcmp(command, "get_feature_mesh_closed_hint".ptr) == 0 || strcmp(command, "get_feature_mesh_convexity".ptr) == 0)
    {
        if (tokens.count < 3) return 583;
        auto feature = featureByName(context, tokens.values[2]);
        if (feature is null || feature.meshId == 0) return 584;
        auto mesh = context.model.dumbMeshes.mesh(feature.meshId);
        if (mesh is null) return 585;
        if (strcmp(command, "get_feature_mesh_vertex_count".ptr) == 0) return setNumber(context, tokens, cast(double)mesh.vertexCount) ? 0 : 586;
        if (strcmp(command, "get_feature_mesh_triangle_count".ptr) == 0) return setNumber(context, tokens, cast(double)mesh.triangleCount) ? 0 : 587;
        if (strcmp(command, "get_feature_mesh_source".ptr) == 0) return setString(context, tokens, mesh.sourcePath.ptr()) ? 0 : 588;
        if (strcmp(command, "get_feature_mesh_format".ptr) == 0) return setString(context, tokens, mesh.sourceFormat.ptr()) ? 0 : 589;
        if (strcmp(command, "get_feature_mesh_closed_hint".ptr) == 0) return setBoolean(context, tokens, mesh.closedHint) ? 0 : 590;
        return setNumber(context, tokens, cast(double)mesh.convexityHint) ? 0 : 591;
    }

    // PMI inspection. Current subentity fields are exposed only as diagnostics;
    // they are not stable topology references and must not be persisted by AI tools.
    if (strcmp(command, "get_pmi_count".ptr) == 0)
        return setNumber(context, tokens, context.pmi is null ? 0.0 : cast(double)context.pmi.count) ? 0 : 592;
    if (strcmp(command, "get_pmi_name".ptr) == 0)
    {
        if (context.pmi is null || tokens.count < 3) return 593;
        size_t index = 0;
        if (!resolveIndex(context, tokens.values[2], &index) || index >= context.pmi.count) return 594;
        return setString(context, tokens, context.pmi.annotations[index].name.ptr()) ? 0 : 595;
    }
    if (strcmp(command, "get_pmi_exists".ptr) == 0)
    {
        if (tokens.count < 3) return 596;
        return setBoolean(context, tokens, pmiByName(context, tokens.values[2]) !is null) ? 0 : 597;
    }
    if (strcmp(command, "get_pmi_id".ptr) == 0 || strcmp(command, "get_pmi_kind".ptr) == 0 ||
        strcmp(command, "get_pmi_text".ptr) == 0 || strcmp(command, "get_pmi_visible".ptr) == 0 ||
        strcmp(command, "get_pmi_associative".ptr) == 0 || strcmp(command, "get_pmi_feature_id".ptr) == 0 ||
        strcmp(command, "get_pmi_feature_name".ptr) == 0 || strcmp(command, "get_pmi_subentity_kind".ptr) == 0 ||
        strcmp(command, "get_pmi_subentity_index".ptr) == 0)
    {
        if (tokens.count < 3) return 598;
        auto item = pmiByName(context, tokens.values[2]);
        if (item is null) return 599;
        if (strcmp(command, "get_pmi_id".ptr) == 0) return setNumber(context, tokens, cast(double)item.id) ? 0 : 600;
        if (strcmp(command, "get_pmi_kind".ptr) == 0) return setString(context, tokens, pmiKindName(item.kind)) ? 0 : 601;
        if (strcmp(command, "get_pmi_text".ptr) == 0) return setString(context, tokens, item.text.ptr()) ? 0 : 602;
        if (strcmp(command, "get_pmi_visible".ptr) == 0) return setBoolean(context, tokens, item.visible) ? 0 : 603;
        if (strcmp(command, "get_pmi_associative".ptr) == 0) return setBoolean(context, tokens, item.associative) ? 0 : 604;
        if (strcmp(command, "get_pmi_feature_id".ptr) == 0) return setNumber(context, tokens, cast(double)item.association.featureId) ? 0 : 605;
        if (strcmp(command, "get_pmi_subentity_kind".ptr) == 0) return setNumber(context, tokens, cast(double)item.association.subentityKind) ? 0 : 606;
        if (strcmp(command, "get_pmi_subentity_index".ptr) == 0) return setNumber(context, tokens, cast(double)item.association.subentityIndex) ? 0 : 607;
        if (!item.associative || item.association.featureId == 0) return setString(context, tokens, "".ptr) ? 0 : 608;
        auto feature = context.model.featureById(item.association.featureId);
        return setString(context, tokens, feature is null ? "".ptr : feature.name.ptr()) ? 0 : 609;
    }

    // Any command that starts with get_ belongs to this central read-only
    // namespace. Treat an unknown getter as an error rather than journalling it.
    return 610;
}

