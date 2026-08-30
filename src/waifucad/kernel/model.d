module waifucad.kernel.model;

import core.stdc.stdio : fprintf, stdout;
import waifucad.core.fixed_string : FixedString64;
import waifucad.core.jobs : hardwareThreadCount, CancellationToken, initialiseCancellation, cancel, isCancelled;
import waifucad.kernel.types : EntityId, Unit, FeatureKind, ExactGeometryStatus, OperandKind, Operand, Parameter, Feature, BoundingBox,
    WC_MAX_FEATURE_OPERANDS, SketchConstraint, SketchSolveReport, roleForKind, isRecommendedWorkflowKind;
import waifucad.kernel.expressions : evaluateExpression, ExpressionValue, WC_EXPRESSION_CYCLE, WC_EXPRESSION_UNKNOWN_NAME;
import waifucad.brep.types : BRepArena, BRepId;
import waifucad.mesh.types : MeshArena, MeshId;

// These capacities are bootstrap limits, not intended final document limits.
enum WC_MAX_PARAMETERS = 256;
enum WC_MAX_FEATURES = 1024;
enum WC_MAX_SKETCH_CONSTRAINTS = 512;

struct Model
{
    FixedString64 name;
    Parameter[WC_MAX_PARAMETERS] parameters;
    Feature[WC_MAX_FEATURES] features;
    SketchConstraint[WC_MAX_SKETCH_CONSTRAINTS] sketchConstraints;
    SketchSolveReport[WC_MAX_FEATURES] sketchSolveReports;
    BoundingBox[WC_MAX_FEATURES] previewBounds;
    int[WC_MAX_FEATURES] previewErrors;
    BRepArena exactGeometry;
    MeshArena dumbMeshes;
    BRepId[WC_MAX_FEATURES] exactSolidIds;
    ExactGeometryStatus[WC_MAX_FEATURES] exactStatus;
    int[WC_MAX_FEATURES] exactErrors;
    size_t parameterCount;
    size_t featureCount;
    size_t sketchConstraintCount;
    uint sketchConstraintErrorCount;
    EntityId nextId;
    uint workerCount; // Zero means automatically use the host's available cores.
    CancellationToken recomputeCancellation;

    void initialise(const(char)* modelName) nothrow @nogc
    {
        parameterCount = 0;
        featureCount = 0;
        sketchConstraintCount = 0;
        sketchConstraintErrorCount = 0;
        nextId = 1;
        workerCount = 0;
        initialiseCancellation(&recomputeCancellation);
        name.set(modelName);
        exactGeometry.clear();
        dumbMeshes.clear();
        foreach (i; 0 .. exactSolidIds.length)
        {
            sketchSolveReports[i] = SketchSolveReport.init;
            previewBounds[i] = BoundingBox.init;
            previewErrors[i] = 0;
            exactSolidIds[i] = 0;
            exactStatus[i] = ExactGeometryStatus.none;
            exactErrors[i] = 0;
        }

        /* Every part owns one immutable-at-the-history-root absolute CSYS.
           It is document baseline construction geometry rather than a GUI
           convenience, so batch/SCL/native front-ends all see the same frame. */
        Operand[9] absoluteCsys;
        absoluteCsys[0].kind = OperandKind.literal; absoluteCsys[0].literal = 0.0;
        absoluteCsys[1].kind = OperandKind.literal; absoluteCsys[1].literal = 0.0;
        absoluteCsys[2].kind = OperandKind.literal; absoluteCsys[2].literal = 0.0;
        absoluteCsys[3].kind = OperandKind.literal; absoluteCsys[3].literal = 1.0;
        absoluteCsys[4].kind = OperandKind.literal; absoluteCsys[4].literal = 0.0;
        absoluteCsys[5].kind = OperandKind.literal; absoluteCsys[5].literal = 0.0;
        absoluteCsys[6].kind = OperandKind.literal; absoluteCsys[6].literal = 0.0;
        absoluteCsys[7].kind = OperandKind.literal; absoluteCsys[7].literal = 1.0;
        absoluteCsys[8].kind = OperandKind.literal; absoluteCsys[8].literal = 0.0;
        auto absoluteId = addFeatureWithPayload("absolute_csys".ptr, FeatureKind.datumCsys, absoluteCsys.ptr, 9, "absolute".ptr);
        if (absoluteId != 0)
            features[0].dirty = false;
    }

    void beginRecompute() nothrow @nogc
    {
        initialiseCancellation(&recomputeCancellation);
    }

    void requestRecomputeCancellation() nothrow @nogc
    {
        cancel(&recomputeCancellation);
    }

    bool recomputeCancelled() const nothrow @nogc
    {
        return isCancelled(&recomputeCancellation);
    }

    EntityId findParameter(const(char)* parameterName) const nothrow @nogc
    {
        foreach (i; 0 .. parameterCount)
            if (parameters[i].name.equals(parameterName))
                return parameters[i].id;
        return 0;
    }

    Parameter* parameterById(EntityId id) nothrow @nogc
    {
        foreach (i; 0 .. parameterCount)
            if (parameters[i].id == id)
                return &parameters[i];
        return null;
    }

    EntityId findFeature(const(char)* featureName) const nothrow @nogc
    {
        foreach (i; 0 .. featureCount)
            if (features[i].name.equals(featureName))
                return features[i].id;
        return 0;
    }

    Feature* featureById(EntityId id) nothrow @nogc
    {
        foreach (i; 0 .. featureCount)
            if (features[i].id == id)
                return &features[i];
        return null;
    }

    size_t featureIndexById(EntityId id) const nothrow @nogc
    {
        foreach (i; 0 .. featureCount)
            if (features[i].id == id)
                return i;
        return featureCount;
    }

    SketchSolveReport* sketchSolveReport(EntityId sketchId) nothrow @nogc
    {
        auto index = featureIndexById(sketchId);
        if (index >= featureCount || features[index].kind != FeatureKind.sketch)
            return null;
        auto report = &sketchSolveReports[index];
        report.sketchId = sketchId;
        return report;
    }

    const(SketchSolveReport)* sketchSolveReportConst(EntityId sketchId) const nothrow @nogc
    {
        auto index = featureIndexById(sketchId);
        if (index >= featureCount || features[index].kind != FeatureKind.sketch)
            return null;
        return &sketchSolveReports[index];
    }

    EntityId addParameter(const(char)* parameterName, double value, Unit unit) nothrow @nogc
    {
        if (parameterCount >= parameters.length || findParameter(parameterName) != 0)
            return 0;
        auto slot = &parameters[parameterCount++];
        slot.id = nextId++;
        slot.name.set(parameterName);
        slot.value = value;
        slot.unit = unit;
        slot.expression.clear();
        slot.expressionDefined = false;
        slot.expressionError = 0;
        return slot.id;
    }

    bool setParameter(const(char)* parameterName, double value) nothrow @nogc
    {
        auto id = findParameter(parameterName);
        auto parameter = parameterById(id);
        if (parameter is null)
            return false;
        parameter.value = value;
        parameter.expression.clear();
        parameter.expressionDefined = false;
        parameter.expressionError = 0;
        markDependantsDirty(id, OperandKind.parameter);
        return true;
    }

    EntityId addExpressionParameter(const(char)* parameterName, Unit unit, const(char)* expression) nothrow @nogc
    {
        auto previousCount=parameterCount;
        auto previousNextId=nextId;
        auto id = addParameter(parameterName, 0.0, unit);
        auto parameter = parameterById(id);
        if (parameter is null) return 0;
        parameter.expression.set(expression);
        parameter.expressionDefined = true;
        parameter.expressionError = 0;
        if (evaluateParameterExpressions() != 0)
        {
            parameters[previousCount]=Parameter.init;
            parameterCount=previousCount;
            nextId=previousNextId;
            return 0;
        }
        return id;
    }

    bool setParameterExpression(const(char)* parameterName, const(char)* expression) nothrow @nogc
    {
        auto parameter = parameterById(findParameter(parameterName));
        if (parameter is null || expression is null) return false;
        auto previousExpression=parameter.expression;
        auto previousDefined=parameter.expressionDefined;
        auto previousError=parameter.expressionError;
        auto previousValue=parameter.value;
        parameter.expression.set(expression);
        parameter.expressionDefined = true;
        parameter.expressionError = 0;
        if (evaluateParameterExpressions() != 0)
        {
            parameter.expression=previousExpression;
            parameter.expressionDefined=previousDefined;
            parameter.expressionError=previousError;
            parameter.value=previousValue;
            return false;
        }
        markDependantsDirty(parameter.id, OperandKind.parameter);
        return true;
    }

    int evaluateParameterExpressions() nothrow @nogc
    {
        ubyte[WC_MAX_PARAMETERS] state;
        int firstError = 0;
        foreach (i; 0 .. parameterCount)
        {
            if (!parameters[i].expressionDefined) continue;
            auto oldValue = parameters[i].value;
            auto error = evaluateParameterRecursive(&this, i, state.ptr);
            if (error != 0 && firstError == 0) firstError = error;
            if (error == 0 && parameters[i].value != oldValue)
                markDependantsDirty(parameters[i].id, OperandKind.parameter);
        }
        return firstError;
    }

    EntityId addFeature(const(char)* featureName, FeatureKind kind, Operand* operands, ubyte operandCount) nothrow @nogc
    {
        if (featureCount >= features.length || operandCount > WC_MAX_FEATURE_OPERANDS || findFeature(featureName) != 0)
            return 0;

        ubyte depth = 0;
        foreach (i; 0 .. operandCount)
        {
            if (operands[i].kind == OperandKind.feature)
            {
                auto sourceIndex = featureIndexById(operands[i].featureId);
                // Bootstrap graph policy: features may only depend on an earlier feature.
                if (sourceIndex >= featureCount)
                    return 0;
                auto candidate = cast(uint)features[sourceIndex].dependencyDepth + 1u;
                if (candidate > 255u)
                    return 0;
                if (candidate > depth)
                    depth = cast(ubyte)candidate;
            }
        }

        auto slot = &features[featureCount++];
        slot.id = nextId++;
        slot.name.set(featureName);
        slot.kind = kind;
        slot.role = roleForKind(kind);
        slot.operandCount = operandCount;
        slot.dependencyDepth = depth;
        slot.dirty = true;
        slot.recommendedWorkflow = isRecommendedWorkflowKind(kind);
        slot.payload.clear();
        slot.payload2.clear();
        slot.meshId = 0;
        foreach (i; 0 .. operandCount)
            slot.operands[i] = operands[i];
        return slot.id;
    }

    EntityId addFeatureWithPayload(const(char)* featureName, FeatureKind kind, Operand* operands,
                                   ubyte operandCount, const(char)* payload,
                                   const(char)* payload2 = null) nothrow @nogc
    {
        auto id = addFeature(featureName, kind, operands, operandCount);
        auto feature = featureById(id);
        if (feature is null)
            return 0;
        feature.payload.set(payload);
        feature.payload2.set(payload2);
        return id;
    }


    /*
     * Atomically redefine an existing history feature while preserving its
     * stable EntityId/name and therefore all downstream references.  GUI
     * feature dialogues reach this only through the semantic SCL transaction
     * path; they never write feature storage directly.
     */
    bool redefineFeature(EntityId featureId, FeatureKind expectedKind,
                         Operand* operands, ubyte operandCount,
                         const(char)* payload = null,
                         const(char)* payload2 = null) nothrow @nogc
    {
        auto index = featureIndexById(featureId);
        if (index >= featureCount || operandCount > WC_MAX_FEATURE_OPERANDS)
            return false;
        auto current = &features[index];
        if (current.kind != expectedKind ||
            (current.kind == FeatureKind.datumCsys && current.name.equals("absolute_csys".ptr)))
            return false;

        ubyte[WC_MAX_FEATURES] proposedDepths;
        foreach (i; 0 .. index)
            proposedDepths[i] = features[i].dependencyDepth;

        ubyte depth = 0;
        foreach (i; 0 .. operandCount)
        {
            if (operands[i].kind != OperandKind.feature)
                continue;
            auto sourceIndex = featureIndexById(operands[i].featureId);
            // History references must remain strictly backward after an edit.
            if (sourceIndex >= index)
                return false;
            auto candidate = cast(uint)proposedDepths[sourceIndex] + 1u;
            if (candidate > 255u)
                return false;
            if (candidate > depth)
                depth = cast(ubyte)candidate;
        }
        proposedDepths[index] = depth;

        /*
         * Validate and calculate every later depth before changing the feature,
         * so a rejected edit is genuinely atomic.
         */
        foreach (later; index + 1 .. featureCount)
        {
            ubyte laterDepth = 0;
            foreach (j; 0 .. features[later].operandCount)
            {
                auto operand = &features[later].operands[j];
                if (operand.kind != OperandKind.feature)
                    continue;
                auto sourceIndex = featureIndexById(operand.featureId);
                if (sourceIndex >= later)
                    return false;
                auto candidate = cast(uint)proposedDepths[sourceIndex] + 1u;
                if (candidate > 255u)
                    return false;
                if (candidate > laterDepth)
                    laterDepth = cast(ubyte)candidate;
            }
            proposedDepths[later] = laterDepth;
        }

        auto replacement = *current;
        foreach (i; 0 .. replacement.operands.length)
            replacement.operands[i] = Operand.init;
        replacement.operandCount = operandCount;
        foreach (i; 0 .. operandCount)
            replacement.operands[i] = operands[i];
        replacement.dependencyDepth = proposedDepths[index];
        replacement.dirty = true;
        replacement.payload.set(payload);
        replacement.payload2.set(payload2);
        *current = replacement;
        foreach (later; index + 1 .. featureCount)
            features[later].dependencyDepth = proposedDepths[later];

        markDependantsDirty(featureId, OperandKind.feature);
        return true;
    }


    EntityId addDumbMeshFeature(const(char)* featureName, MeshId meshId, const(char)* sourcePath = null) nothrow @nogc
    {
        auto mesh = dumbMeshes.mesh(meshId);
        if (mesh is null || !mesh.bounds.valid)
            return 0;
        Operand[6] operands;
        foreach (i; 0 .. operands.length)
            operands[i].kind = OperandKind.literal;
        operands[0].literal = mesh.bounds.minimum.x;
        operands[1].literal = mesh.bounds.minimum.y;
        operands[2].literal = mesh.bounds.minimum.z;
        operands[3].literal = mesh.bounds.maximum.x;
        operands[4].literal = mesh.bounds.maximum.y;
        operands[5].literal = mesh.bounds.maximum.z;
        auto id = addFeatureWithPayload(featureName, FeatureKind.dumbBody, operands.ptr, 6, sourcePath);
        auto feature = featureById(id);
        if (feature is null)
            return 0;
        feature.meshId = meshId;
        return id;
    }

    double resolveOperand(const Operand* operand) nothrow @nogc
    {
        if (operand.kind == OperandKind.literal)
            return operand.literal;
        if (operand.kind == OperandKind.parameter)
        {
            auto parameter = parameterById(operand.parameterId);
            return parameter is null ? 0.0 : parameter.value;
        }
        return 0.0;
    }

    BoundingBox* boundsForFeature(EntityId featureId) nothrow @nogc
    {
        auto index = featureIndexById(featureId);
        return index >= featureCount ? null : &previewBounds[index];
    }

    bool featureHasDependants(EntityId featureId) const nothrow @nogc
    {
        if (featureId == 0)
            return false;
        foreach (i; 0 .. featureCount)
            foreach (j; 0 .. features[i].operandCount)
                if (features[i].operands[j].kind == OperandKind.feature &&
                    features[i].operands[j].featureId == featureId)
                    return true;
        return false;
    }

    private void swapFeatureSlots(size_t a, size_t b) nothrow @nogc
    {
        if (a >= featureCount || b >= featureCount || a == b)
            return;
        auto feature = features[a]; features[a] = features[b]; features[b] = feature;
        auto report = sketchSolveReports[a]; sketchSolveReports[a] = sketchSolveReports[b]; sketchSolveReports[b] = report;
        auto bounds = previewBounds[a]; previewBounds[a] = previewBounds[b]; previewBounds[b] = bounds;
        auto previewError = previewErrors[a]; previewErrors[a] = previewErrors[b]; previewErrors[b] = previewError;
        auto solidId = exactSolidIds[a]; exactSolidIds[a] = exactSolidIds[b]; exactSolidIds[b] = solidId;
        auto status = exactStatus[a]; exactStatus[a] = exactStatus[b]; exactStatus[b] = status;
        auto exactError = exactErrors[a]; exactErrors[a] = exactErrors[b]; exactErrors[b] = exactError;
    }

    bool moveFeatureUp(EntityId featureId) nothrow @nogc
    {
        auto index = featureIndexById(featureId);
        if (index == 0 || index >= featureCount)
            return false;
        if (features[index - 1].kind == FeatureKind.datumCsys && features[index - 1].name.equals("absolute_csys".ptr))
            return false;
        auto previousId = features[index - 1].id;
        foreach (j; 0 .. features[index].operandCount)
            if (features[index].operands[j].kind == OperandKind.feature &&
                features[index].operands[j].featureId == previousId)
                return false;
        swapFeatureSlots(index, index - 1);
        markAllDirty();
        return true;
    }

    bool moveFeatureDown(EntityId featureId) nothrow @nogc
    {
        auto index = featureIndexById(featureId);
        if (index >= featureCount || index + 1 >= featureCount ||
            (features[index].kind == FeatureKind.datumCsys && features[index].name.equals("absolute_csys".ptr)))
            return false;
        foreach (j; 0 .. features[index + 1].operandCount)
            if (features[index + 1].operands[j].kind == OperandKind.feature &&
                features[index + 1].operands[j].featureId == featureId)
                return false;
        swapFeatureSlots(index, index + 1);
        markAllDirty();
        return true;
    }

    private size_t mappedFeaturePosition(size_t oldIndex, size_t fromIndex, size_t toIndex) const nothrow @nogc
    {
        if (oldIndex == fromIndex)
            return toIndex;
        if (fromIndex < toIndex)
        {
            if (oldIndex > fromIndex && oldIndex <= toIndex)
                return oldIndex - 1;
        }
        else if (toIndex < fromIndex)
        {
            if (oldIndex >= toIndex && oldIndex < fromIndex)
                return oldIndex + 1;
        }
        return oldIndex;
    }

    private bool canMoveFeatureToIndex(size_t fromIndex, size_t toIndex) const nothrow @nogc
    {
        if (fromIndex >= featureCount || toIndex >= featureCount)
            return false;
        if (fromIndex == toIndex)
            return true;
        if (fromIndex == 0 || toIndex == 0)
            return false;
        if (features[fromIndex].kind == FeatureKind.datumCsys && features[fromIndex].name.equals("absolute_csys".ptr))
            return false;

        foreach (i; 0 .. featureCount)
        {
            auto dependentPosition = mappedFeaturePosition(i, fromIndex, toIndex);
            foreach (j; 0 .. features[i].operandCount)
            {
                if (features[i].operands[j].kind != OperandKind.feature)
                    continue;
                auto dependencyIndex = featureIndexById(features[i].operands[j].featureId);
                if (dependencyIndex >= featureCount)
                    return false;
                auto dependencyPosition = mappedFeaturePosition(dependencyIndex, fromIndex, toIndex);
                if (dependencyPosition >= dependentPosition)
                    return false;
            }
        }
        return true;
    }

    private bool moveFeatureToIndex(EntityId featureId, size_t toIndex) nothrow @nogc
    {
        auto fromIndex = featureIndexById(featureId);
        if (!canMoveFeatureToIndex(fromIndex, toIndex))
            return false;
        while (fromIndex > toIndex)
        {
            swapFeatureSlots(fromIndex, fromIndex - 1);
            --fromIndex;
        }
        while (fromIndex < toIndex)
        {
            swapFeatureSlots(fromIndex, fromIndex + 1);
            ++fromIndex;
        }
        markAllDirty();
        return true;
    }

    bool moveFeatureBefore(EntityId featureId, EntityId targetFeatureId) nothrow @nogc
    {
        auto fromIndex = featureIndexById(featureId);
        auto targetIndex = featureIndexById(targetFeatureId);
        if (fromIndex >= featureCount || targetIndex >= featureCount || featureId == targetFeatureId)
            return false;
        auto toIndex = fromIndex < targetIndex ? targetIndex - 1 : targetIndex;
        return moveFeatureToIndex(featureId, toIndex);
    }

    bool moveFeatureAfter(EntityId featureId, EntityId targetFeatureId) nothrow @nogc
    {
        auto fromIndex = featureIndexById(featureId);
        auto targetIndex = featureIndexById(targetFeatureId);
        if (fromIndex >= featureCount || targetIndex >= featureCount || featureId == targetFeatureId)
            return false;
        auto toIndex = fromIndex < targetIndex ? targetIndex : targetIndex + 1;
        if (toIndex >= featureCount)
            toIndex = featureCount - 1;
        return moveFeatureToIndex(featureId, toIndex);
    }

    bool deleteFeature(EntityId featureId) nothrow @nogc
    {
        auto index = featureIndexById(featureId);
        if (index >= featureCount || featureHasDependants(featureId) ||
            (features[index].kind == FeatureKind.datumCsys && features[index].name.equals("absolute_csys".ptr)))
            return false;

        size_t writeConstraint = 0;
        foreach (i; 0 .. sketchConstraintCount)
        {
            auto constraint = sketchConstraints[i];
            if (constraint.sketchId == featureId || constraint.firstFeatureId == featureId || constraint.secondFeatureId == featureId)
                continue;
            if (writeConstraint != i)
                sketchConstraints[writeConstraint] = constraint;
            ++writeConstraint;
        }
        foreach (i; writeConstraint .. sketchConstraintCount)
            sketchConstraints[i] = SketchConstraint.init;
        sketchConstraintCount = writeConstraint;

        foreach (i; index + 1 .. featureCount)
        {
            features[i - 1] = features[i];
            sketchSolveReports[i - 1] = sketchSolveReports[i];
            previewBounds[i - 1] = previewBounds[i];
            previewErrors[i - 1] = previewErrors[i];
            exactSolidIds[i - 1] = exactSolidIds[i];
            exactStatus[i - 1] = exactStatus[i];
            exactErrors[i - 1] = exactErrors[i];
        }
        --featureCount;
        features[featureCount] = Feature.init;
        sketchSolveReports[featureCount] = SketchSolveReport.init;
        previewBounds[featureCount] = BoundingBox.init;
        previewErrors[featureCount] = 0;
        exactSolidIds[featureCount] = 0;
        exactStatus[featureCount] = ExactGeometryStatus.none;
        exactErrors[featureCount] = 0;
        markAllDirty();
        return true;
    }

    void markDependantsDirty(EntityId changedId, OperandKind changedKind) nothrow @nogc
    {
        bool changed;
        do
        {
            changed = false;
            foreach (i; 0 .. featureCount)
            {
                auto feature = &features[i];
                if (feature.dirty)
                    continue;
                foreach (j; 0 .. feature.operandCount)
                {
                    auto operand = &feature.operands[j];
                    bool depends = false;
                    if (changedKind == OperandKind.parameter && operand.kind == OperandKind.parameter)
                        depends = operand.parameterId == changedId;
                    if (operand.kind == OperandKind.feature)
                    {
                        auto source = featureById(operand.featureId);
                        depends = (changedKind == OperandKind.feature && changedId != 0 && operand.featureId == changedId) ||
                                  (source !is null && source.dirty);
                    }

                    if (depends)
                    {
                        feature.dirty = true;
                        changed = true;
                        break;
                    }
                }
            }
            // After the first scan, dirty feature propagation is sufficient.
            changedKind = OperandKind.feature;
            changedId = 0;
        }
        while (changed);
    }

    void markAllDirty() nothrow @nogc
    {
        foreach (i; 0 .. featureCount)
            features[i].dirty = true;
    }

    uint effectiveWorkerCount() nothrow @nogc
    {
        return workerCount == 0 ? hardwareThreadCount() : workerCount;
    }

    void dump() nothrow @nogc
    {
        fprintf(stdout, "Model: %s\n", name.ptr());
        fprintf(stdout, "Worker threads: %u%s\n", effectiveWorkerCount(), workerCount == 0 ? " (automatic)".ptr : "".ptr);
        fprintf(stdout, "Parameters: %u\n", cast(uint)parameterCount);
        foreach (i; 0 .. parameterCount)
            fprintf(stdout, "  #%u %s = %.6f\n", parameters[i].id, parameters[i].name.ptr(), parameters[i].value);
        fprintf(stdout, "Features: %u\n", cast(uint)featureCount);
        fprintf(stdout, "WaifuBRep exact solids: %u\n", cast(uint)exactGeometry.solidCount);
        fprintf(stdout, "Dumb meshes: %u vertices=%u triangles=%u\n", cast(uint)dumbMeshes.meshCount, cast(uint)dumbMeshes.vertexCount, cast(uint)dumbMeshes.triangleCount);
        foreach (i; 0 .. featureCount)
        {
            auto bounds = &previewBounds[i];
            fprintf(stdout, "  #%u %s kind=%u role=%u preferred=%u depth=%u dirty=%u", features[i].id,
                    features[i].name.ptr(), cast(uint)features[i].kind, cast(uint)features[i].role,
                    features[i].recommendedWorkflow ? 1u : 0u,
                    cast(uint)features[i].dependencyDepth, features[i].dirty ? 1u : 0u);
            if (bounds.valid)
                fprintf(stdout, " bounds=[%.3f %.3f %.3f]..[%.3f %.3f %.3f]", bounds.minX, bounds.minY, bounds.minZ, bounds.maxX, bounds.maxY, bounds.maxZ);
            if (features[i].payload.length != 0)
                fprintf(stdout, " payload=\"%s\"", features[i].payload.ptr());
            if (features[i].payload2.length != 0)
                fprintf(stdout, " payload2=\"%s\"", features[i].payload2.ptr());
            if (features[i].meshId != 0)
            {
                auto mesh = dumbMeshes.mesh(features[i].meshId);
                if (mesh !is null)
                    fprintf(stdout, " dumb_mesh=%u mesh_vertices=%u mesh_triangles=%u mesh_format=%s",
                            features[i].meshId, mesh.vertexCount, mesh.triangleCount, mesh.sourceFormat.ptr());
                else
                    fprintf(stdout, " dumb_mesh=%u", features[i].meshId);
            }
            if (previewErrors[i] != 0)
                fprintf(stdout, " preview_error=%d", previewErrors[i]);
            final switch (exactStatus[i])
            {
                case ExactGeometryStatus.none:
                    break;
                case ExactGeometryStatus.exact:
                    fprintf(stdout, " brep=exact solid=%u", exactSolidIds[i]);
                    break;
                case ExactGeometryStatus.previewOnly:
                    fprintf(stdout, " brep=preview-only");
                    break;
                case ExactGeometryStatus.failed:
                    fprintf(stdout, " brep=failed error=%d", exactErrors[i]);
                    break;
            }
            fprintf(stdout, "\n");
        }
    }
}




private struct ParameterExpressionContext
{
    Model* model;
    ubyte* state;
    int nestedError;
}

private size_t parameterIndexByName(Model* model, const(char)* name) nothrow @nogc
{
    if (model is null || name is null) return WC_MAX_PARAMETERS;
    foreach (i; 0 .. model.parameterCount)
        if (model.parameters[i].name.equals(name)) return i;
    return WC_MAX_PARAMETERS;
}

private int evaluateParameterRecursive(Model* model, size_t index, ubyte* state) nothrow @nogc;

private bool expressionParameterLookup(void* opaque, const(char)* name, double* value, Unit* unit) nothrow @nogc
{
    auto context = cast(ParameterExpressionContext*)opaque;
    if (context is null || context.model is null || context.state is null || value is null || unit is null)
        return false;
    auto index = parameterIndexByName(context.model, name);
    if (index >= context.model.parameterCount) return false;
    if (context.model.parameters[index].expressionDefined)
    {
        auto nested=evaluateParameterRecursive(context.model,index,context.state);
        if(nested!=0){context.nestedError=nested;return false;}
    }
    *value = context.model.parameters[index].value;
    *unit = context.model.parameters[index].unit;
    return true;
}

private int evaluateParameterRecursive(Model* model, size_t index, ubyte* state) nothrow @nogc
{
    if (model is null || state is null || index >= model.parameterCount) return 1;
    if (state[index] == 2) return model.parameters[index].expressionError;
    if (state[index] == 1)
    {
        model.parameters[index].expressionError = WC_EXPRESSION_CYCLE;
        return WC_EXPRESSION_CYCLE;
    }
    auto parameter = &model.parameters[index];
    if (!parameter.expressionDefined)
    {
        state[index] = 2;
        parameter.expressionError = 0;
        return 0;
    }
    state[index] = 1;
    ParameterExpressionContext context;
    context.model = model;
    context.state = state;
    auto result = evaluateExpression(parameter.expression.ptr(), &expressionParameterLookup, &context, parameter.unit);
    if(result.error==WC_EXPRESSION_UNKNOWN_NAME && context.nestedError!=0) result.error=context.nestedError;
    parameter.expressionError = result.error;
    if (result.error == 0) parameter.value = result.value;
    state[index] = 2;
    return result.error;
}


