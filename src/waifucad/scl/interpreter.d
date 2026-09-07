module waifucad.scl.interpreter;

import core.stdc.ctype : isspace;
import core.stdc.stdio : FILE, fopen, fclose, fgets, fprintf, snprintf, stderr, stdout;
import core.stdc.stdlib : strtod;
import core.stdc.string : strcmp, strlen;
import waifucad.journal.backend_api : ScriptContext;
import waifucad.journal.script_runtime : ScriptValue, ScriptValueKind, ScriptCallableKind, WC_SCRIPT_MAX_LIST_VALUES;
import waifucad.scl.runtime_ops : applyBinaryOperator, applyUnaryOperator, applyMathFunction, typeTest;
import waifucad.kernel.types : EntityId, Unit, FeatureKind, Operand, OperandKind, SketchConstraintKind, WC_MAX_FEATURE_OPERANDS;
import waifucad.kernel.sketch_solver : addSketchConstraint;
import waifucad.kernel.waifubrep_backend : waifuBRepBackend;
import waifucad.interchange.openscad.options : OpenScadImportOptions, OpenScadImportEngine, OpenScadBackend,
    OpenScadExportOptions, OpenScadExportScope, OpenScadExportFallback;
import waifucad.interchange.openscad.importer : importOpenScad;
import waifucad.interchange.openscad.exporter : exportOpenScad;
import waifucad.scl.tokenise : Tokens, tokenise;
import waifucad.scl.ruby_syntax : WC_SCL_LINE, normaliseRubyStyleLine;
import waifucad.scl.getters : executeGetter, WC_GETTER_NOT_HANDLED;
import waifucad.sections.pmi.types : PmiAnnotationKind, PmiAssociation;
import waifucad.brep.naming : faceByPersistentId, persistentTopologyOwner;
import waifucad.brep.types : BRepSurfaceKind;

enum WC_SCL_MAX_CHILDREN = 16;
private enum WC_PI = 3.14159265358979323846264338327950288;

private bool parseUnsigned64(const(char)* text, ulong* value) nothrow @nogc
{
    if (text is null || value is null || *text == 0) return false;
    ulong result = 0;
    auto cursor = text;
    while (*cursor != 0)
    {
        if (*cursor < '0' || *cursor > '9') return false;
        auto digit = cast(ulong)(*cursor - '0');
        if (result > (ulong.max - digit) / 10UL) return false;
        result = result * 10UL + digit;
        ++cursor;
    }
    if (result == 0) return false;
    *value = result;
    return true;
}

private Unit parseUnit(const(char)* text) nothrow @nogc
{
    if (text is null)
        return Unit.unitless;
    if (strcmp(text, "mm".ptr) == 0)
        return Unit.millimetre;
    if (strcmp(text, "deg".ptr) == 0)
        return Unit.degree;
    return Unit.unitless;
}

private bool parseSketchConstraintKind(const(char)* text, SketchConstraintKind* kind) nothrow @nogc
{
    if (text is null || kind is null) return false;
    if (strcmp(text,"coincident".ptr)==0) *kind=SketchConstraintKind.coincident;
    else if (strcmp(text,"horizontal".ptr)==0) *kind=SketchConstraintKind.horizontal;
    else if (strcmp(text,"vertical".ptr)==0) *kind=SketchConstraintKind.vertical;
    else if (strcmp(text,"distance".ptr)==0) *kind=SketchConstraintKind.distance;
    else if (strcmp(text,"equal_length".ptr)==0) *kind=SketchConstraintKind.equalLength;
    else if (strcmp(text,"parallel".ptr)==0) *kind=SketchConstraintKind.parallel;
    else if (strcmp(text,"perpendicular".ptr)==0) *kind=SketchConstraintKind.perpendicular;
    else if (strcmp(text,"angle".ptr)==0) *kind=SketchConstraintKind.angle;
    else if (strcmp(text,"midpoint".ptr)==0) *kind=SketchConstraintKind.midpoint;
    else if (strcmp(text,"concentric".ptr)==0) *kind=SketchConstraintKind.concentric;
    else if (strcmp(text,"equal_radius".ptr)==0) *kind=SketchConstraintKind.equalRadius;
    else if (strcmp(text,"radius".ptr)==0) *kind=SketchConstraintKind.radius;
    else if (strcmp(text,"diameter".ptr)==0) *kind=SketchConstraintKind.diameter;
    else if (strcmp(text,"tangent".ptr)==0) *kind=SketchConstraintKind.tangent;
    else if (strcmp(text,"symmetry".ptr)==0 || strcmp(text,"symmetric".ptr)==0) *kind=SketchConstraintKind.symmetry;
    else if (strcmp(text,"fix".ptr)==0 || strcmp(text,"fix_point".ptr)==0) *kind=SketchConstraintKind.fixPoint;
    else return false;
    return true;
}

private bool parseNumber(const(char)* text, double* value) nothrow @nogc
{
    if (text is null || value is null)
        return false;
    if (strcmp(text, "PI".ptr) == 0)
    {
        *value = WC_PI;
        return true;
    }
    if (strcmp(text, "true".ptr) == 0)
    {
        *value = 1.0;
        return true;
    }
    if (strcmp(text, "false".ptr) == 0)
    {
        *value = 0.0;
        return true;
    }
    const(char)* end = null;
    auto parsed = strtod(text, &end);
    if (end is text || *end != 0)
        return false;
    *value = parsed;
    return true;
}


private bool parsePmiKind(const(char)* text, PmiAnnotationKind* kind) nothrow @nogc
{
    if (text is null || kind is null) return false;
    if (strcmp(text, "note".ptr) == 0) *kind = PmiAnnotationKind.note;
    else if (strcmp(text, "linear_dimension".ptr) == 0) *kind = PmiAnnotationKind.linearDimension;
    else if (strcmp(text, "angular_dimension".ptr) == 0) *kind = PmiAnnotationKind.angularDimension;
    else if (strcmp(text, "radial_dimension".ptr) == 0) *kind = PmiAnnotationKind.radialDimension;
    else if (strcmp(text, "diameter_dimension".ptr) == 0) *kind = PmiAnnotationKind.diameterDimension;
    else if (strcmp(text, "datum_feature".ptr) == 0) *kind = PmiAnnotationKind.datumFeature;
    else if (strcmp(text, "feature_control_frame".ptr) == 0) *kind = PmiAnnotationKind.featureControlFrame;
    else if (strcmp(text, "surface_texture".ptr) == 0) *kind = PmiAnnotationKind.surfaceTexture;
    else if (strcmp(text, "weld_symbol".ptr) == 0) *kind = PmiAnnotationKind.weldSymbol;
    else if (strcmp(text, "centreline".ptr) == 0) *kind = PmiAnnotationKind.centreline;
    else if (strcmp(text, "annotation_plane".ptr) == 0) *kind = PmiAnnotationKind.annotationPlane;
    else return false;
    return true;
}

private bool parseUnsignedNumber(const(char)* text, uint* value) nothrow @nogc
{
    if (value is null) return false;
    double parsed = 0.0;
    if (!parseNumber(text, &parsed) || parsed < 0.0 || parsed > 4294967295.0) return false;
    auto converted = cast(uint)parsed;
    if (cast(double)converted != parsed) return false;
    *value = converted;
    return true;
}

private Operand literalOperand(double value) nothrow @nogc
{
    Operand operand;
    operand.kind = OperandKind.literal;
    operand.literal = value;
    return operand;
}

private Operand parseValueOperand(ScriptContext* context, const(char)* text, bool* ok) nothrow @nogc
{
    Operand operand;
    double literal = 0.0;
    if (parseNumber(text, &literal))
    {
        operand = literalOperand(literal);
        *ok = true;
        return operand;
    }

    auto parameterId = context.model.findParameter(text);
    if (parameterId != 0)
    {
        operand.kind = OperandKind.parameter;
        operand.parameterId = parameterId;
        *ok = true;
        return operand;
    }

    auto scriptVariable = context.runtime.find(text);
    if (scriptVariable !is null)
    {
        double runtimeNumber = 0.0;
        if (scriptVariable.value.asNumber(&runtimeNumber))
        {
            operand = literalOperand(runtimeNumber);
            *ok = true;
            return operand;
        }
    }
    *ok = false;
    return operand;
}

private const(char)* resolveObjectName(ScriptContext* context, const(char)* token) nothrow @nogc
{
    if (context is null || token is null)
        return token;
    auto variable = context.runtime.find(token);
    if (variable !is null && variable.value.kind == ScriptValueKind.string)
        return variable.value.stringValue.ptr();
    return token;
}

private Operand parseFeatureOperand(ScriptContext* context, const(char)* text, bool* ok) nothrow @nogc
{
    Operand operand;
    auto resolved = resolveObjectName(context, text);
    auto featureId = context.model.findFeature(resolved);
    if (featureId != 0)
    {
        operand.kind = OperandKind.feature;
        operand.featureId = featureId;
        *ok = true;
        return operand;
    }
    *ok = false;
    return operand;
}

private bool parseValues(ScriptContext* context, Tokens* tokens, size_t firstToken,
                         Operand* output, uint count) nothrow @nogc
{
    if (tokens is null || output is null || tokens.count < firstToken + count)
        return false;
    foreach (i; 0 .. count)
    {
        bool ok = false;
        output[i] = parseValueOperand(context, tokens.values[firstToken + i], &ok);
        if (!ok)
            return false;
    }
    return true;
}

private int addUnaryFeatureWithAmount(ScriptContext* context, Tokens* tokens, FeatureKind kind, int malformedCode) nothrow @nogc
{
    if (tokens.count < 4)
        return malformedCode;
    Operand[2] operands;
    bool ok = false;
    operands[0] = parseFeatureOperand(context, tokens.values[2], &ok);
    if (!ok)
        return malformedCode + 1;
    operands[1] = parseValueOperand(context, tokens.values[3], &ok);
    if (!ok)
        return malformedCode + 2;
    return context.model.addFeature(resolveObjectName(context, tokens.values[1]), kind, operands.ptr, 2) == 0 ? malformedCode + 3 : 0;
}

private int addBinaryFeature(ScriptContext* context, Tokens* tokens, FeatureKind kind, int malformedCode) nothrow @nogc
{
    if (tokens.count < 4)
        return malformedCode;
    Operand[2] operands;
    bool ok = false;
    operands[0] = parseFeatureOperand(context, tokens.values[2], &ok);
    if (!ok)
        return malformedCode + 1;
    operands[1] = parseFeatureOperand(context, tokens.values[3], &ok);
    if (!ok)
        return malformedCode + 2;
    return context.model.addFeature(resolveObjectName(context, tokens.values[1]), kind, operands.ptr, 2) == 0 ? malformedCode + 3 : 0;
}

private bool parsePointListBounds(const(char)* text, uint dimensions, double* minimums, double* maximums) nothrow @nogc
{
    if (text is null || minimums is null || maximums is null || dimensions < 2 || dimensions > 3)
        return false;

    const(char)* cursor = text;
    uint component = 0;
    bool havePoint = false;
    double[3] point;
    while (*cursor != 0)
    {
        while (*cursor != 0 && (isspace(cast(ubyte)*cursor) || *cursor == ';' || *cursor == '[' || *cursor == ']'))
            ++cursor;
        if (*cursor == 0)
            break;

        const(char)* end = null;
        auto value = strtod(cursor, &end);
        if (end is cursor)
            return false;
        point[component++] = value;
        cursor = end;
        while (*cursor != 0 && isspace(cast(ubyte)*cursor))
            ++cursor;
        if (component < dimensions)
        {
            if (*cursor != ',')
                return false;
            ++cursor;
            continue;
        }

        if (!havePoint)
        {
            foreach (axis; 0 .. dimensions)
            {
                minimums[axis] = point[axis];
                maximums[axis] = point[axis];
            }
            havePoint = true;
        }
        else
        {
            foreach (axis; 0 .. dimensions)
            {
                if (point[axis] < minimums[axis]) minimums[axis] = point[axis];
                if (point[axis] > maximums[axis]) maximums[axis] = point[axis];
            }
        }
        component = 0;
        while (*cursor != 0 && isspace(cast(ubyte)*cursor))
            ++cursor;
        if (*cursor == ';' || *cursor == ',')
            ++cursor;
    }
    return havePoint && component == 0;
}

private int addPolygonFeature(ScriptContext* context, Tokens* tokens, FeatureKind kind,
                              bool belongsToSketch, int errorBase) nothrow @nogc
{
    auto payloadIndex = belongsToSketch ? 3u : 2u;
    if (tokens.count <= payloadIndex)
        return errorBase;

    double[3] minima;
    double[3] maxima;
    if (!parsePointListBounds(tokens.values[payloadIndex], 2, minima.ptr, maxima.ptr))
        return errorBase + 1;

    Operand[5] operands;
    uint operandCount = 4;
    uint offset = 0;
    if (belongsToSketch)
    {
        bool ok = false;
        operands[0] = parseFeatureOperand(context, tokens.values[2], &ok);
        if (!ok) return errorBase + 2;
        offset = 1;
        operandCount = 5;
    }
    operands[offset + 0] = literalOperand(minima[0]);
    operands[offset + 1] = literalOperand(minima[1]);
    operands[offset + 2] = literalOperand(maxima[0]);
    operands[offset + 3] = literalOperand(maxima[1]);
    auto paths = tokens.count > payloadIndex + 1 ? tokens.values[payloadIndex + 1] : null;
    return context.model.addFeatureWithPayload(resolveObjectName(context, tokens.values[1]), kind, operands.ptr, cast(ubyte)operandCount,
                                               tokens.values[payloadIndex], paths) == 0 ? errorBase + 3 : 0;
}

private int addTransform3(ScriptContext* context, Tokens* tokens, FeatureKind kind, int errorBase) nothrow @nogc
{
    if (tokens.count < 6)
        return errorBase;
    Operand[4] operands;
    bool ok = false;
    operands[0] = parseFeatureOperand(context, tokens.values[2], &ok);
    if (!ok) return errorBase + 1;
    if (!parseValues(context, tokens, 3, &operands[1], 3)) return errorBase + 2;
    return context.model.addFeature(resolveObjectName(context, tokens.values[1]), kind, operands.ptr, 4) == 0 ? errorBase + 3 : 0;
}

private int addDisplayModifier(ScriptContext* context, Tokens* tokens, const(char)* modifier, int errorBase) nothrow @nogc
{
    if (tokens.count < 3)
        return errorBase;
    Operand operand;
    bool ok = false;
    operand = parseFeatureOperand(context, tokens.values[2], &ok);
    if (!ok) return errorBase + 1;
    return context.model.addFeatureWithPayload(resolveObjectName(context, tokens.values[1]), FeatureKind.displayModifier, &operand, 1, modifier) == 0
        ? errorBase + 2 : 0;
}

private bool resolveScriptValue(ScriptContext* context, const(char)* text, ScriptValue* output) nothrow @nogc
{
    if (context is null || text is null || output is null)
        return false;
    if (strcmp(text, "undef".ptr) == 0)
    {
        output.clear();
        return true;
    }
    if (strcmp(text, "true".ptr) == 0)
    {
        *output = ScriptValue.fromBoolean(true);
        return true;
    }
    if (strcmp(text, "false".ptr) == 0)
    {
        *output = ScriptValue.fromBoolean(false);
        return true;
    }
    double number = 0.0;
    if (parseNumber(text, &number))
    {
        *output = ScriptValue.fromNumber(number);
        return true;
    }
    auto variable = context.runtime.find(text);
    if (variable !is null)
    {
        *output = variable.value;
        return true;
    }
    auto parameter = context.model.parameterById(context.model.findParameter(text));
    if (parameter !is null)
    {
        *output = ScriptValue.fromNumber(parameter.value);
        return true;
    }
    return false;
}

private bool appendText(char* buffer, size_t capacity, size_t* used, const(char)* text) nothrow @nogc
{
    if (buffer is null || used is null || text is null || *used >= capacity)
        return false;
    auto length = strlen(text);
    if (*used + length + 1 > capacity)
        return false;
    foreach (i; 0 .. length)
        buffer[*used + i] = text[i];
    *used += length;
    buffer[*used] = 0;
    return true;
}

private bool valueToText(const ScriptValue* value, char* buffer, size_t capacity) nothrow @nogc
{
    if (value is null || buffer is null || capacity == 0)
        return false;
    buffer[0] = 0;
    final switch (value.kind)
    {
        case ScriptValueKind.undef:
            return snprintf(buffer, capacity, "%s", "undef".ptr) > 0;
        case ScriptValueKind.boolean:
            return snprintf(buffer, capacity, "%s", value.booleanValue ? "true".ptr : "false".ptr) > 0;
        case ScriptValueKind.number:
            return snprintf(buffer, capacity, "%.15g", value.numberValue) > 0;
        case ScriptValueKind.string:
            return snprintf(buffer, capacity, "%s", value.stringValue.ptr()) >= 0;
        case ScriptValueKind.list:
        {
            size_t used = 0;
            if (!appendText(buffer, capacity, &used, "[".ptr)) return false;
            foreach (i; 0 .. value.listCount)
            {
                char[64] numberText;
                if (snprintf(numberText.ptr, numberText.length, "%.15g", value.listValues[i]) < 0) return false;
                if (i != 0 && !appendText(buffer, capacity, &used, ",".ptr)) return false;
                if (!appendText(buffer, capacity, &used, numberText.ptr)) return false;
            }
            return appendText(buffer, capacity, &used, "]".ptr);
        }
    }
}

private bool buildNestedCommand(Tokens* tokens, size_t start, char* buffer, size_t capacity) nothrow @nogc
{
    if (tokens is null || buffer is null || capacity == 0 || start >= tokens.count)
        return false;
    size_t used = 0;
    buffer[0] = 0;
    foreach (i; start .. tokens.count)
    {
        if (i != start && !appendText(buffer, capacity, &used, " ".ptr)) return false;
        if (!appendText(buffer, capacity, &used, "\"".ptr)) return false;
        if (!appendText(buffer, capacity, &used, tokens.values[i])) return false;
        if (!appendText(buffer, capacity, &used, "\"".ptr)) return false;
    }
    return true;
}

private bool joinTokens(Tokens* tokens, size_t start, char* buffer, size_t capacity) nothrow @nogc
{
    if (tokens is null || buffer is null || capacity == 0)
        return false;
    size_t used = 0;
    buffer[0] = 0;
    foreach (i; start .. tokens.count)
    {
        if (i != start && !appendText(buffer, capacity, &used, "|".ptr))
            return false;
        if (!appendText(buffer, capacity, &used, tokens.values[i]))
            return false;
    }
    return true;
}

private int executeCallableBody(ScriptContext* context, const(char)* scriptBody) nothrow @nogc
{
    if (context is null || scriptBody is null)
        return 360;
    char[512] storage;
    auto length = strlen(scriptBody);
    if (length + 1 > storage.length)
        return 361;
    foreach (i; 0 .. length + 1)
        storage[i] = scriptBody[i];

    char* statement = storage.ptr;
    char* cursor = storage.ptr;
    while (true)
    {
        if (*cursor == ';' || *cursor == 0)
        {
            auto atEnd = *cursor == 0;
            *cursor = 0;
            while (*statement != 0 && isspace(cast(ubyte)*statement))
                ++statement;
            if (*statement != 0)
            {
                auto recording = context.recordCommands;
                context.recordCommands = false;
                auto result = executeLine(context, statement);
                context.recordCommands = recording;
                if (result != 0)
                    return result;
            }
            if (atEnd)
                break;
            statement = cursor + 1;
        }
        ++cursor;
    }
    return 0;
}

private int executeTokens(ScriptContext* context, Tokens* tokens, const(char)* originalLine) nothrow @nogc
{
    if (tokens.count == 0)
        return 0;

    auto command = tokens.values[0];
    if (strcmp(command, "waifucad".ptr) == 0)
        return 0;

    // Read-only getters write only to the script runtime. They intentionally do
    // not enter the semantic model journal, which records document mutations.
    auto getterResult = executeGetter(context, tokens);
    if (getterResult != WC_GETTER_NOT_HANDLED)
        return getterResult;

    /*
     * Journal transport/control is application state rather than document
     * geometry, so these commands deliberately do not record themselves.
     * Replaying a journal also suppresses recording of the replayed lines to
     * prevent a journal from recursively copying itself into an active one.
     */
    if (strcmp(command, "journal_start".ptr) == 0)
    {
        if (tokens.count < 2) return 900;
        if (context.journal is null) return 901;
        context.recordCommands = false;
        if (!context.journal.start(tokens.values[1])) return 902;
        context.recordCommands = true;
        return 0;
    }
    if (strcmp(command, "journal_stop".ptr) == 0)
    {
        if (context.journal is null) return 903;
        context.recordCommands = false;
        context.journal.stop();
        return 0;
    }
    if (strcmp(command, "journal_run".ptr) == 0)
    {
        if (tokens.count < 2) return 904;
        auto wasRecording = context.recordCommands;
        context.recordCommands = false;
        auto result = executeFile(context, tokens.values[1]);
        context.recordCommands = wasRecording && context.journal !is null && context.journal.recording;
        return result;
    }

    /* Run Script expands through the same interpreter transaction path.  Do
       not journal the include wrapper as well as every command inside it. */
    if (strcmp(command, "include".ptr) == 0)
    {
        if (tokens.count < 2) return 252;
        return executeFile(context, tokens.values[1]);
    }
    if (strcmp(command, "use".ptr) == 0)
    {
        if (tokens.count < 2) return 253;
        return executeUseFile(context, tokens.values[1]);
    }

    if (context.recordCommands && context.journal !is null)
        context.journal.record(originalLine);

    if (strcmp(command, "model".ptr) == 0)
    {
        if (tokens.count < 2) return 20;
        auto workers = context.model.workerCount;
        context.model.initialise(tokens.values[1]);
        context.model.workerCount = workers;
        return 0;
    }

    if (strcmp(command, "feature_edit".ptr) == 0)
    {
        /*
         * feature_edit NAME KIND ARGS...
         *
         * This is the semantic transaction used by data-driven feature
         * dialogues.  It preserves NAME/EntityId and rewrites the complete
         * supported definition atomically through Model.redefineFeature.
         */
        if (tokens.count < 4) return 820;
        auto id = context.model.findFeature(resolveObjectName(context, tokens.values[1]));
        if (id == 0) return 821;
        auto current = context.model.featureById(id);
        if (current is null) return 822;
        auto kindText = tokens.values[2];
        Operand[WC_MAX_FEATURE_OPERANDS] operands;
        ubyte operandCount = 0;
        FeatureKind expected = FeatureKind.none;
        bool ok = false;

        if (strcmp(kindText, "extrude".ptr) == 0)
        {
            if (tokens.count != 9) return 823;
            expected = FeatureKind.extrude; operandCount = 6;
            operands[0] = parseFeatureOperand(context, tokens.values[3], &ok);
            if (!ok || !parseValues(context, tokens, 4, &operands[1], 5)) return 824;
        }
        else if (strcmp(kindText, "revolve".ptr) == 0)
        {
            if (tokens.count != 6) return 825;
            expected = FeatureKind.revolve; operandCount = 3;
            operands[0] = parseFeatureOperand(context, tokens.values[3], &ok);
            if (!ok || !parseValues(context, tokens, 4, &operands[1], 2)) return 826;
        }
        else if (strcmp(kindText, "sweep".ptr) == 0 || strcmp(kindText, "loft".ptr) == 0 ||
                 strcmp(kindText, "union".ptr) == 0 || strcmp(kindText, "subtract".ptr) == 0 ||
                 strcmp(kindText, "intersect".ptr) == 0)
        {
            if (tokens.count != 5) return 827;
            if (strcmp(kindText, "sweep".ptr) == 0) expected = FeatureKind.sweep;
            else if (strcmp(kindText, "loft".ptr) == 0) expected = FeatureKind.loft;
            else if (strcmp(kindText, "union".ptr) == 0) expected = FeatureKind.booleanUnion;
            else if (strcmp(kindText, "subtract".ptr) == 0) expected = FeatureKind.booleanSubtract;
            else expected = FeatureKind.booleanIntersect;
            operandCount = 2;
            operands[0] = parseFeatureOperand(context, tokens.values[3], &ok);
            if (!ok) return 828;
            operands[1] = parseFeatureOperand(context, tokens.values[4], &ok);
            if (!ok) return 829;
        }
        else if (strcmp(kindText, "fillet".ptr) == 0 || strcmp(kindText, "chamfer".ptr) == 0 ||
                 strcmp(kindText, "shell".ptr) == 0)
        {
            if (tokens.count != 5) return 830;
            if (strcmp(kindText, "fillet".ptr) == 0) expected = FeatureKind.fillet;
            else if (strcmp(kindText, "chamfer".ptr) == 0) expected = FeatureKind.chamfer;
            else expected = FeatureKind.shell;
            operandCount = 2;
            operands[0] = parseFeatureOperand(context, tokens.values[3], &ok);
            if (!ok) return 831;
            operands[1] = parseValueOperand(context, tokens.values[4], &ok);
            if (!ok) return 832;
        }
        else if (strcmp(kindText, "line".ptr) == 0 || strcmp(kindText, "arc".ptr) == 0 ||
                 strcmp(kindText, "curve_circle".ptr) == 0 || strcmp(kindText, "spline_bbox".ptr) == 0)
        {
            if (strcmp(kindText, "curve_circle".ptr) == 0)
            {
                if (tokens.count != 7) return 833;
                expected = FeatureKind.freeCircle; operandCount = 4;
                if (!parseValues(context, tokens, 3, operands.ptr, 4)) return 834;
            }
            else
            {
                if (tokens.count != 9) return 835;
                expected = strcmp(kindText, "line".ptr) == 0 ? FeatureKind.freeLine :
                           (strcmp(kindText, "arc".ptr) == 0 ? FeatureKind.freeArc : FeatureKind.freeSpline);
                operandCount = 6;
                if (!parseValues(context, tokens, 3, operands.ptr, 6)) return 836;
            }
        }
        else if (strcmp(kindText, "datum_plane".ptr) == 0)
        {
            if (tokens.count != 12) return 837;
            expected = FeatureKind.datumPlane; operandCount = 9;
            if (!parseValues(context, tokens, 3, operands.ptr, 9)) return 838;
        }
        else if (strcmp(kindText, "datum_axis".ptr) == 0)
        {
            if (tokens.count != 9) return 839;
            expected = FeatureKind.datumAxis; operandCount = 6;
            if (!parseValues(context, tokens, 3, operands.ptr, 6)) return 840;
        }
        else if (strcmp(kindText, "datum_csys".ptr) == 0)
        {
            if (tokens.count != 12) return 841;
            expected = FeatureKind.datumCsys; operandCount = 9;
            if (!parseValues(context, tokens, 3, operands.ptr, 9)) return 842;
        }
        else
            return 843;

        if (current.kind != expected) return 844;
        return context.model.redefineFeature(id, expected, operands.ptr, operandCount) ? 0 : 845;
    }

    if (strcmp(command, "feature_delete".ptr) == 0)
    {
        if (tokens.count < 2) return 801;
        auto id = context.model.findFeature(resolveObjectName(context, tokens.values[1]));
        if (id == 0) return 802;
        return context.model.deleteFeature(id) ? 0 : 803;
    }
    if (strcmp(command, "feature_move_up".ptr) == 0)
    {
        if (tokens.count < 2) return 804;
        auto id = context.model.findFeature(resolveObjectName(context, tokens.values[1]));
        if (id == 0) return 805;
        return context.model.moveFeatureUp(id) ? 0 : 806;
    }
    if (strcmp(command, "feature_move_down".ptr) == 0)
    {
        if (tokens.count < 2) return 807;
        auto id = context.model.findFeature(resolveObjectName(context, tokens.values[1]));
        if (id == 0) return 808;
        return context.model.moveFeatureDown(id) ? 0 : 809;
    }
    if (strcmp(command, "feature_move_before".ptr) == 0)
    {
        if (tokens.count < 3) return 810;
        auto id = context.model.findFeature(resolveObjectName(context, tokens.values[1]));
        auto targetId = context.model.findFeature(resolveObjectName(context, tokens.values[2]));
        if (id == 0 || targetId == 0) return 811;
        return context.model.moveFeatureBefore(id, targetId) ? 0 : 812;
    }
    if (strcmp(command, "feature_move_after".ptr) == 0)
    {
        if (tokens.count < 3) return 813;
        auto id = context.model.findFeature(resolveObjectName(context, tokens.values[1]));
        auto targetId = context.model.findFeature(resolveObjectName(context, tokens.values[2]));
        if (id == 0 || targetId == 0) return 814;
        return context.model.moveFeatureAfter(id, targetId) ? 0 : 815;
    }

    if (strcmp(command, "param".ptr) == 0)
    {
        if (tokens.count < 3) return 21;
        double value = 0.0;
        if (!parseNumber(tokens.values[2], &value)) return 22;
        auto unit = tokens.count >= 4 ? parseUnit(tokens.values[3]) : Unit.unitless;
        return context.model.addParameter(tokens.values[1], value, unit) == 0 ? 23 : 0;
    }

    if (strcmp(command, "param_expr".ptr) == 0)
    {
        // param_expr NAME UNIT "EXPRESSION"
        if (tokens.count < 4) return 27;
        auto unit = parseUnit(tokens.values[2]);
        auto id = context.model.addExpressionParameter(tokens.values[1], unit, tokens.values[3]);
        return id == 0 ? 28 : 0;
    }
    if (strcmp(command, "set_expr".ptr) == 0)
    {
        // set_expr NAME "EXPRESSION"
        if (tokens.count < 3) return 29;
        return context.model.setParameterExpression(tokens.values[1], tokens.values[2]) ? 0 : 30;
    }

    if (strcmp(command, "set".ptr) == 0)
    {
        if (tokens.count < 3) return 24;
        double value = 0.0;
        if (!parseNumber(tokens.values[2], &value)) return 25;
        return context.model.setParameter(tokens.values[1], value) ? 0 : 26;
    }


    // PMI is document data owned by the PMI Section, not modelling history.
    // These semantic commands are journalled exactly like modelling mutations.
    if (strcmp(command, "pmi_add".ptr) == 0)
    {
        // pmi_add KIND NAME TEXT [FEATURE|none] [SUBENTITY_KIND] [SUBENTITY_INDEX]
        if (context.pmi is null || tokens.count < 4) return 330;
        PmiAnnotationKind kind;
        if (!parsePmiKind(tokens.values[1], &kind)) return 331;
        if (context.pmi.findByName(tokens.values[2]) !is null) return 332;

        PmiAssociation association;
        bool associative = false;
        if (tokens.count >= 5 && strcmp(tokens.values[4], "none".ptr) != 0)
        {
            auto featureId = context.model.findFeature(resolveObjectName(context, tokens.values[4]));
            if (featureId == 0) return 333;
            association.featureId = featureId;
            associative = true;
            if (tokens.count >= 6 && !parseUnsignedNumber(tokens.values[5], &association.subentityKind)) return 334;
            if (tokens.count >= 7 && !parseUnsignedNumber(tokens.values[6], &association.subentityIndex)) return 335;
        }
        return context.pmi.add(kind, tokens.values[2], tokens.values[3], association, associative) == 0 ? 336 : 0;
    }
    if (strcmp(command, "pmi_text".ptr) == 0)
    {
        if (context.pmi is null || tokens.count < 3) return 337;
        return context.pmi.setText(tokens.values[1], tokens.values[2]) ? 0 : 338;
    }
    if (strcmp(command, "pmi_visible".ptr) == 0)
    {
        if (context.pmi is null || tokens.count < 3) return 339;
        bool visible;
        if (strcmp(tokens.values[2], "true".ptr) == 0 || strcmp(tokens.values[2], "1".ptr) == 0) visible = true;
        else if (strcmp(tokens.values[2], "false".ptr) == 0 || strcmp(tokens.values[2], "0".ptr) == 0) visible = false;
        else return 340;
        return context.pmi.setVisible(tokens.values[1], visible) ? 0 : 341;
    }
    if (strcmp(command, "pmi_delete".ptr) == 0)
    {
        if (context.pmi is null || tokens.count < 2) return 342;
        return context.pmi.removeByName(tokens.values[1]) ? 0 : 343;
    }

    // Deterministic script-runtime operations. These provide the data,
    // operator, mathematical and flow-control capabilities needed by the
    // OpenSCAD parity contract without coupling the CAD kernel to OpenSCAD syntax.
    if (strcmp(command, "var".ptr) == 0 || strcmp(command, "let_value".ptr) == 0)
    {
        if (tokens.count < 3) return 270;
        ScriptValue value;
        if (!resolveScriptValue(context, tokens.values[2], &value))
            value = ScriptValue.fromString(tokens.values[2]);
        return context.runtime.set(tokens.values[1], value) ? 0 : 271;
    }
    if (strcmp(command, "module".ptr) == 0 || strcmp(command, "function".ptr) == 0)
    {
        if (tokens.count < 4) return 272;
        double rawCount = 0.0;
        if (!parseNumber(tokens.values[2], &rawCount) || rawCount < 0.0 || rawCount > 8.0) return 273;
        auto kind = strcmp(command, "function".ptr) == 0 ? ScriptCallableKind.functionBlock : ScriptCallableKind.moduleBlock;
        return context.runtime.defineCallable(tokens.values[1], kind, cast(ubyte)rawCount, tokens.values[3]) ? 0 : 274;
    }
    if (strcmp(command, "call".ptr) == 0 || strcmp(command, "call_function".ptr) == 0)
    {
        auto functionCall = strcmp(command, "call_function".ptr) == 0;
        auto nameIndex = functionCall ? 2u : 1u;
        auto argumentStart = functionCall ? 3u : 2u;
        if (tokens.count <= nameIndex) return 275;
        auto callable = context.runtime.findCallable(tokens.values[nameIndex]);
        if (callable is null || (functionCall && callable.kind != ScriptCallableKind.functionBlock) ||
            (!functionCall && callable.kind != ScriptCallableKind.moduleBlock)) return 276;

        auto argumentEnd = argumentStart + callable.argumentCount;
        if (tokens.count < argumentEnd) return 276;
        size_t childStart = argumentEnd;
        uint childCount = 0;
        if (tokens.count > argumentEnd)
        {
            if (strcmp(tokens.values[argumentEnd], "--children".ptr) != 0) return 276;
            childStart = argumentEnd + 1;
            childCount = cast(uint)(tokens.count - childStart);
            if (functionCall || childCount > WC_SCL_MAX_CHILDREN) return 276;
        }

        foreach (i; 0 .. callable.argumentCount)
        {
            ScriptValue value;
            if (!resolveScriptValue(context, tokens.values[argumentStart + i], &value))
                value = ScriptValue.fromString(resolveObjectName(context, tokens.values[argumentStart + i]));
            char[8] argumentName;
            snprintf(argumentName.ptr, argumentName.length, "$%u", cast(uint)i + 1u);
            if (!context.runtime.set(argumentName.ptr, value)) return 277;
        }
        context.runtime.setNumber("$argc".ptr, callable.argumentCount);

        ScriptValue previousChildren;
        bool hadPreviousChildren = false;
        auto previousChildrenSlot = context.runtime.find("$children".ptr);
        if (previousChildrenSlot !is null)
        {
            previousChildren = previousChildrenSlot.value;
            hadPreviousChildren = true;
        }
        ScriptValue[WC_SCL_MAX_CHILDREN] previousChildValues;
        bool[WC_SCL_MAX_CHILDREN] hadPreviousChildValues;
        foreach (i; 0 .. WC_SCL_MAX_CHILDREN)
        {
            char[12] childName;
            snprintf(childName.ptr, childName.length, "$child%u", cast(uint)i);
            auto previous = context.runtime.find(childName.ptr);
            if (previous !is null)
            {
                previousChildValues[i] = previous.value;
                hadPreviousChildValues[i] = true;
            }
        }

        context.runtime.setNumber("$children".ptr, childCount);
        foreach (i; 0 .. childCount)
        {
            char[12] childName;
            snprintf(childName.ptr, childName.length, "$child%u", cast(uint)i);
            context.runtime.setString(childName.ptr, resolveObjectName(context, tokens.values[childStart + i]));
        }
        foreach (i; childCount .. WC_SCL_MAX_CHILDREN)
        {
            char[12] childName;
            snprintf(childName.ptr, childName.length, "$child%u", cast(uint)i);
            ScriptValue empty;
            empty.clear();
            context.runtime.set(childName.ptr, empty);
        }

        if (!context.runtime.pushCall(tokens.values[nameIndex])) return 277;
        auto result = executeCallableBody(context, callable.scriptBody.ptr());
        context.runtime.popCall();

        ScriptValue functionResult;
        bool haveFunctionResult = false;
        if (functionCall && result == 0)
        {
            auto returnValue = context.runtime.find("$result".ptr);
            if (returnValue !is null)
            {
                functionResult = returnValue.value;
                haveFunctionResult = true;
            }
        }

        if (hadPreviousChildren)
            context.runtime.set("$children".ptr, previousChildren);
        else
        {
            ScriptValue empty;
            empty.clear();
            context.runtime.set("$children".ptr, empty);
        }
        foreach (i; 0 .. WC_SCL_MAX_CHILDREN)
        {
            char[12] childName;
            snprintf(childName.ptr, childName.length, "$child%u", cast(uint)i);
            if (hadPreviousChildValues[i])
                context.runtime.set(childName.ptr, previousChildValues[i]);
            else
            {
                ScriptValue empty;
                empty.clear();
                context.runtime.set(childName.ptr, empty);
            }
        }

        if (result != 0) return result;
        if (functionCall)
        {
            if (!haveFunctionResult || tokens.count < 2) return 278;
            return context.runtime.set(tokens.values[1], functionResult) ? 0 : 279;
        }
        return 0;
    }
    if (strcmp(command, "children".ptr) == 0)
    {
        // `children OUT` exposes every child supplied to `call ... --children ...`;
        // `children OUT INDEX` selects one. Multiple children remain a grouped
        // pass-through feature until exact union semantics are requested explicitly.
        if (tokens.count < 2) return 280;
        uint firstIndex = 0;
        uint count = 0;
        if (tokens.count >= 3)
        {
            double rawIndex = 0.0;
            if (!parseNumber(tokens.values[2], &rawIndex) || rawIndex < 0.0 || rawIndex >= WC_SCL_MAX_CHILDREN)
                return 281;
            firstIndex = cast(uint)rawIndex;
            count = 1;
        }
        else
        {
            auto childCountValue = context.runtime.find("$children".ptr);
            double rawCount = 0.0;
            if (childCountValue is null || !childCountValue.value.asNumber(&rawCount) ||
                rawCount < 0.0 || rawCount > WC_SCL_MAX_CHILDREN) return 282;
            count = cast(uint)rawCount;
        }
        if (count == 0) return 282;

        Operand[WC_SCL_MAX_CHILDREN] sources;
        foreach (i; 0 .. count)
        {
            char[12] childName;
            snprintf(childName.ptr, childName.length, "$child%u", firstIndex + i);
            auto child = context.runtime.find(childName.ptr);
            if (child is null || child.value.kind != ScriptValueKind.string) return 282;
            auto featureId = context.model.findFeature(child.value.stringValue.ptr());
            if (featureId == 0) return 283;
            sources[i].kind = OperandKind.feature;
            sources[i].featureId = featureId;
        }
        return context.model.addFeatureWithPayload(resolveObjectName(context, tokens.values[1]), FeatureKind.displayModifier,
                                                   sources.ptr, cast(ubyte)count, "children".ptr) == 0 ? 284 : 0;
    }

    if (strcmp(command, "list".ptr) == 0)
    {
        if (tokens.count < 2 || tokens.count - 2 > WC_SCRIPT_MAX_LIST_VALUES) return 272;
        double[WC_SCRIPT_MAX_LIST_VALUES] values;
        uint count = 0;
        foreach (i; 2 .. tokens.count)
        {
            ScriptValue value;
            double number = 0.0;
            if (!resolveScriptValue(context, tokens.values[i], &value) || !value.asNumber(&number)) return 273;
            values[count++] = number;
        }
        return context.runtime.setList(tokens.values[1], values.ptr, count) ? 0 : 274;
    }
    if (strcmp(command, "range".ptr) == 0)
    {
        if (tokens.count < 5) return 274;
        ScriptValue startValue;
        ScriptValue stepValue;
        ScriptValue endValue;
        double start = 0.0;
        double step = 0.0;
        double end = 0.0;
        if (!resolveScriptValue(context, tokens.values[2], &startValue) || !startValue.asNumber(&start) ||
            !resolveScriptValue(context, tokens.values[3], &stepValue) || !stepValue.asNumber(&step) ||
            !resolveScriptValue(context, tokens.values[4], &endValue) || !endValue.asNumber(&end) || step == 0.0) return 275;
        double[WC_SCRIPT_MAX_LIST_VALUES] values;
        uint count = 0;
        for (double value = start; (step > 0.0 ? value <= end : value >= end); value += step)
        {
            if (count >= WC_SCRIPT_MAX_LIST_VALUES) return 276;
            values[count++] = value;
        }
        return context.runtime.setList(tokens.values[1], values.ptr, count) ? 0 : 277;
    }
    if (strcmp(command, "each".ptr) == 0)
    {
        if (tokens.count < 3) return 278;
        auto source = context.runtime.find(tokens.values[2]);
        if (source is null || source.value.kind != ScriptValueKind.list) return 279;
        return context.runtime.setList(tokens.values[1], source.value.listValues.ptr, source.value.listCount) ? 0 : 280;
    }
    if (strcmp(command, "list_append".ptr) == 0)
    {
        if (tokens.count < 3) return 275;
        auto variable = context.runtime.find(tokens.values[1]);
        ScriptValue value;
        double number = 0.0;
        if (variable is null || variable.value.kind != ScriptValueKind.list ||
            variable.value.listCount >= WC_SCRIPT_MAX_LIST_VALUES ||
            !resolveScriptValue(context, tokens.values[2], &value) || !value.asNumber(&number)) return 276;
        variable.value.listValues[variable.value.listCount++] = number;
        return 0;
    }
    if (strcmp(command, "index".ptr) == 0 || strcmp(command, "component".ptr) == 0)
    {
        if (tokens.count < 4) return 277;
        auto listVariable = context.runtime.find(tokens.values[2]);
        if (listVariable is null || listVariable.value.kind != ScriptValueKind.list) return 278;
        uint index = 0;
        if (strcmp(command, "component".ptr) == 0)
        {
            if (strcmp(tokens.values[3], "x".ptr) == 0) index = 0;
            else if (strcmp(tokens.values[3], "y".ptr) == 0) index = 1;
            else if (strcmp(tokens.values[3], "z".ptr) == 0) index = 2;
            else return 279;
        }
        else
        {
            double rawIndex = 0.0;
            if (!parseNumber(tokens.values[3], &rawIndex) || rawIndex < 0.0) return 280;
            index = cast(uint)rawIndex;
        }
        if (index >= listVariable.value.listCount) return 281;
        return context.runtime.setNumber(tokens.values[1], listVariable.value.listValues[index]) ? 0 : 282;
    }
    if (strcmp(command, "calc".ptr) == 0)
    {
        if (tokens.count < 5) return 283;
        ScriptValue left;
        ScriptValue right;
        ScriptValue result;
        if (!resolveScriptValue(context, tokens.values[2], &left) ||
            !resolveScriptValue(context, tokens.values[4], &right) ||
            !applyBinaryOperator(tokens.values[3], left, right, &result)) return 284;
        return context.runtime.set(tokens.values[1], result) ? 0 : 285;
    }
    if (strcmp(command, "unary".ptr) == 0)
    {
        if (tokens.count < 4) return 286;
        ScriptValue input;
        ScriptValue result;
        if (!resolveScriptValue(context, tokens.values[3], &input) ||
            !applyUnaryOperator(tokens.values[2], input, &result)) return 287;
        return context.runtime.set(tokens.values[1], result) ? 0 : 288;
    }
    if (strcmp(command, "ternary".ptr) == 0)
    {
        if (tokens.count < 5) return 289;
        ScriptValue condition;
        ScriptValue yesValue;
        ScriptValue noValue;
        if (!resolveScriptValue(context, tokens.values[2], &condition) ||
            !resolveScriptValue(context, tokens.values[3], &yesValue) ||
            !resolveScriptValue(context, tokens.values[4], &noValue)) return 290;
        return context.runtime.set(tokens.values[1], condition.truthy() ? yesValue : noValue) ? 0 : 291;
    }
    if (strcmp(command, "math".ptr) == 0)
    {
        if (tokens.count < 4 || tokens.count - 3 > 8) return 292;
        ScriptValue[8] arguments;
        uint count = 0;
        foreach (i; 3 .. tokens.count)
            if (!resolveScriptValue(context, tokens.values[i], &arguments[count++])) return 293;
        ScriptValue result;
        auto functionName = tokens.values[2];
        if (strcmp(functionName, "len".ptr) == 0 && count == 1)
        {
            if (arguments[0].kind == ScriptValueKind.list)
                result = ScriptValue.fromNumber(arguments[0].listCount);
            else if (arguments[0].kind == ScriptValueKind.string)
                result = ScriptValue.fromNumber(arguments[0].stringValue.length);
            else return 294;
        }
        else if ((strcmp(functionName, "min".ptr) == 0 || strcmp(functionName, "max".ptr) == 0) && count >= 1)
        {
            double best = 0.0;
            if (!arguments[0].asNumber(&best)) return 295;
            foreach (i; 1 .. count)
            {
                double value = 0.0;
                if (!arguments[i].asNumber(&value)) return 296;
                if (strcmp(functionName, "min".ptr) == 0 ? value < best : value > best)
                    best = value;
            }
            result = ScriptValue.fromNumber(best);
        }
        else if (!applyMathFunction(functionName, arguments.ptr, count, &result)) return 297;
        return context.runtime.set(tokens.values[1], result) ? 0 : 298;
    }
    if (strcmp(command, "type_test".ptr) == 0)
    {
        if (tokens.count < 4) return 299;
        ScriptValue value;
        if (strcmp(tokens.values[2], "is_function".ptr) == 0)
            return context.runtime.setBoolean(tokens.values[1], context.runtime.findCallable(tokens.values[3]) !is null) ? 0 : 300;
        if (!resolveScriptValue(context, tokens.values[3], &value))
            value = ScriptValue.fromString(tokens.values[3]);
        return context.runtime.setBoolean(tokens.values[1], typeTest(tokens.values[2], &value)) ? 0 : 300;
    }
    if (strcmp(command, "concat".ptr) == 0)
    {
        if (tokens.count < 4) return 301;
        auto left = context.runtime.find(tokens.values[2]);
        auto right = context.runtime.find(tokens.values[3]);
        if (left is null || right is null || left.value.kind != ScriptValueKind.list || right.value.kind != ScriptValueKind.list ||
            left.value.listCount + right.value.listCount > WC_SCRIPT_MAX_LIST_VALUES) return 302;
        double[WC_SCRIPT_MAX_LIST_VALUES] values;
        uint count = 0;
        foreach (i; 0 .. left.value.listCount) values[count++] = left.value.listValues[i];
        foreach (i; 0 .. right.value.listCount) values[count++] = right.value.listValues[i];
        return context.runtime.setList(tokens.values[1], values.ptr, count) ? 0 : 303;
    }
    if (strcmp(command, "lookup".ptr) == 0)
    {
        // Table is a flat [x0,y0,x1,y1,...] list. Linear interpolation mirrors
        // OpenSCAD lookup behaviour for numeric tables while staying allocation-free.
        if (tokens.count < 4) return 304;
        ScriptValue keyValue;
        double key = 0.0;
        auto table = context.runtime.find(tokens.values[3]);
        if (!resolveScriptValue(context, tokens.values[2], &keyValue) || !keyValue.asNumber(&key) ||
            table is null || table.value.kind != ScriptValueKind.list || table.value.listCount < 2 ||
            (table.value.listCount & 1u) != 0) return 305;
        auto pairs = table.value.listCount / 2;
        double result = table.value.listValues[1];
        if (key <= table.value.listValues[0]) result = table.value.listValues[1];
        else if (key >= table.value.listValues[(pairs - 1) * 2]) result = table.value.listValues[(pairs - 1) * 2 + 1];
        else
        {
            foreach (pair; 0 .. pairs - 1)
            {
                auto x0 = table.value.listValues[pair * 2];
                auto y0 = table.value.listValues[pair * 2 + 1];
                auto x1 = table.value.listValues[(pair + 1) * 2];
                auto y1 = table.value.listValues[(pair + 1) * 2 + 1];
                if (key >= x0 && key <= x1)
                {
                    auto t = x1 == x0 ? 0.0 : (key - x0) / (x1 - x0);
                    result = y0 + (y1 - y0) * t;
                    break;
                }
            }
        }
        return context.runtime.setNumber(tokens.values[1], result) ? 0 : 306;
    }
    if (strcmp(command, "str".ptr) == 0)
    {
        if (tokens.count < 3) return 307;
        char[256] combined;
        combined[0] = 0;
        size_t used = 0;
        foreach (i; 2 .. tokens.count)
        {
            ScriptValue value;
            char[256] fragment;
            if (resolveScriptValue(context, tokens.values[i], &value))
            {
                if (!valueToText(&value, fragment.ptr, fragment.length)) return 308;
                if (!appendText(combined.ptr, combined.length, &used, fragment.ptr)) return 309;
            }
            else if (!appendText(combined.ptr, combined.length, &used, tokens.values[i])) return 310;
        }
        return context.runtime.setString(tokens.values[1], combined.ptr) ? 0 : 311;
    }
    if (strcmp(command, "chr".ptr) == 0)
    {
        if (tokens.count < 3) return 312;
        ScriptValue codeValue;
        double rawCode = 0.0;
        if (!resolveScriptValue(context, tokens.values[2], &codeValue) || !codeValue.asNumber(&rawCode) ||
            rawCode < 0.0 || rawCode > 1114111.0) return 313;
        auto code = cast(uint)rawCode;
        if (code >= 0xD800u && code <= 0xDFFFu) return 313;
        char[5] text;
        uint length = 0;
        if (code <= 0x7Fu)
            text[length++] = cast(char)code;
        else if (code <= 0x7FFu)
        {
            text[length++] = cast(char)(0xC0u | (code >> 6));
            text[length++] = cast(char)(0x80u | (code & 0x3Fu));
        }
        else if (code <= 0xFFFFu)
        {
            text[length++] = cast(char)(0xE0u | (code >> 12));
            text[length++] = cast(char)(0x80u | ((code >> 6) & 0x3Fu));
            text[length++] = cast(char)(0x80u | (code & 0x3Fu));
        }
        else
        {
            text[length++] = cast(char)(0xF0u | (code >> 18));
            text[length++] = cast(char)(0x80u | ((code >> 12) & 0x3Fu));
            text[length++] = cast(char)(0x80u | ((code >> 6) & 0x3Fu));
            text[length++] = cast(char)(0x80u | (code & 0x3Fu));
        }
        text[length] = 0;
        return context.runtime.setString(tokens.values[1], text.ptr) ? 0 : 314;
    }
    if (strcmp(command, "ord".ptr) == 0)
    {
        if (tokens.count < 3) return 315;
        auto variable = context.runtime.find(tokens.values[2]);
        const(char)* text = variable !is null && variable.value.kind == ScriptValueKind.string
            ? variable.value.stringValue.ptr() : tokens.values[2];
        if (text is null || *text == 0) return 316;
        auto first = cast(ubyte)text[0];
        uint code = 0;
        uint length = 0;
        if (first <= 0x7Fu) { code = first; length = 1; }
        else if ((first & 0xE0u) == 0xC0u) { code = first & 0x1Fu; length = 2; }
        else if ((first & 0xF0u) == 0xE0u) { code = first & 0x0Fu; length = 3; }
        else if ((first & 0xF8u) == 0xF0u) { code = first & 0x07u; length = 4; }
        else return 316;
        foreach (i; 1 .. length)
        {
            auto next = cast(ubyte)text[i];
            if (next == 0 || (next & 0xC0u) != 0x80u) return 316;
            code = (code << 6) | (next & 0x3Fu);
        }
        if ((length == 2 && code < 0x80u) || (length == 3 && code < 0x800u) ||
            (length == 4 && code < 0x10000u) || code > 0x10FFFFu ||
            (code >= 0xD800u && code <= 0xDFFFu)) return 316;
        return context.runtime.setNumber(tokens.values[1], cast(double)code) ? 0 : 317;
    }
    if (strcmp(command, "search".ptr) == 0)
    {
        if (tokens.count < 4) return 318;
        ScriptValue needleValue;
        double needle = 0.0;
        auto haystack = context.runtime.find(tokens.values[3]);
        if (!resolveScriptValue(context, tokens.values[2], &needleValue) || !needleValue.asNumber(&needle) ||
            haystack is null || haystack.value.kind != ScriptValueKind.list) return 319;
        double[WC_SCRIPT_MAX_LIST_VALUES] matches;
        uint count = 0;
        foreach (i; 0 .. haystack.value.listCount)
            if (haystack.value.listValues[i] == needle)
                matches[count++] = cast(double)i;
        return context.runtime.setList(tokens.values[1], matches.ptr, count) ? 0 : 320;
    }
    if (strcmp(command, "version".ptr) == 0)
    {
        if (tokens.count < 2) return 321;
        double[3] versionValues = [0.2, 0.0, 0.0];
        return context.runtime.setList(tokens.values[1], versionValues.ptr, 3) ? 0 : 322;
    }
    if (strcmp(command, "version_num".ptr) == 0)
    {
        if (tokens.count < 2) return 323;
        return context.runtime.setNumber(tokens.values[1], 20000.0) ? 0 : 324;
    }
    if (strcmp(command, "parent_module".ptr) == 0)
    {
        if (tokens.count < 2) return 325;
        uint index = 0;
        if (tokens.count >= 3)
        {
            double rawIndex = 0.0;
            if (!parseNumber(tokens.values[2], &rawIndex) || rawIndex < 0.0) return 326;
            index = cast(uint)rawIndex;
        }
        auto parent = context.runtime.parentCall(index);
        if (parent is null)
        {
            ScriptValue undefined;
            undefined.clear();
            return context.runtime.set(tokens.values[1], undefined) ? 0 : 327;
        }
        return context.runtime.setString(tokens.values[1], parent) ? 0 : 328;
    }
    if (strcmp(command, "norm".ptr) == 0)
    {
        if (tokens.count < 3) return 327;
        auto vector = context.runtime.find(tokens.values[2]);
        if (vector is null || vector.value.kind != ScriptValueKind.list) return 328;
        double sum = 0.0;
        foreach (i; 0 .. vector.value.listCount) sum += vector.value.listValues[i] * vector.value.listValues[i];
        ScriptValue[1] argument;
        argument[0] = ScriptValue.fromNumber(sum);
        ScriptValue result;
        if (!applyMathFunction("sqrt".ptr, argument.ptr, 1, &result)) return 329;
        return context.runtime.set(tokens.values[1], result) ? 0 : 330;
    }
    if (strcmp(command, "cross".ptr) == 0)
    {
        if (tokens.count < 4) return 331;
        auto a = context.runtime.find(tokens.values[2]);
        auto b = context.runtime.find(tokens.values[3]);
        if (a is null || b is null || a.value.kind != ScriptValueKind.list || b.value.kind != ScriptValueKind.list ||
            a.value.listCount != 3 || b.value.listCount != 3) return 332;
        double[3] result = [
            a.value.listValues[1] * b.value.listValues[2] - a.value.listValues[2] * b.value.listValues[1],
            a.value.listValues[2] * b.value.listValues[0] - a.value.listValues[0] * b.value.listValues[2],
            a.value.listValues[0] * b.value.listValues[1] - a.value.listValues[1] * b.value.listValues[0]
        ];
        return context.runtime.setList(tokens.values[1], result.ptr, 3) ? 0 : 333;
    }
    if (strcmp(command, "rands".ptr) == 0)
    {
        if (tokens.count < 5) return 334;
        ScriptValue minimumValue;
        ScriptValue maximumValue;
        ScriptValue countValue;
        double minValue = 0.0;
        double maxValue = 0.0;
        double rawCount = 0.0;
        if (!resolveScriptValue(context, tokens.values[2], &minimumValue) || !minimumValue.asNumber(&minValue) ||
            !resolveScriptValue(context, tokens.values[3], &maximumValue) || !maximumValue.asNumber(&maxValue) ||
            !resolveScriptValue(context, tokens.values[4], &countValue) || !countValue.asNumber(&rawCount) ||
            rawCount < 0.0 || rawCount > WC_SCRIPT_MAX_LIST_VALUES) return 335;
        if (tokens.count >= 6)
        {
            ScriptValue seedValue;
            double seed = 0.0;
            if (!resolveScriptValue(context, tokens.values[5], &seedValue) || !seedValue.asNumber(&seed)) return 336;
            context.runtime.randomState = cast(ulong)seed + 0x9e3779b97f4a7c15UL;
        }
        double[WC_SCRIPT_MAX_LIST_VALUES] values;
        auto count = cast(uint)rawCount;
        foreach (i; 0 .. count)
        {
            auto raw = context.runtime.nextRandom();
            auto unit = cast(double)(raw >> 11) / 9007199254740992.0;
            values[i] = minValue + (maxValue - minValue) * unit;
        }
        return context.runtime.setList(tokens.values[1], values.ptr, count) ? 0 : 337;
    }
    if (strcmp(command, "echo_value".ptr) == 0)
    {
        if (tokens.count < 2) return 338;
        ScriptValue value;
        if (!resolveScriptValue(context, tokens.values[1], &value)) return 339;
        char[512] text;
        if (!valueToText(&value, text.ptr, text.length)) return 340;
        fprintf(stdout, "%s\n", text.ptr);
        return 0;
    }
    if (strcmp(command, "if".ptr) == 0)
    {
        if (tokens.count < 3) return 341;
        ScriptValue condition;
        if (!resolveScriptValue(context, tokens.values[1], &condition)) return 342;
        if (!condition.truthy()) return 0;
        char[WC_SCL_LINE] nested;
        if (!buildNestedCommand(tokens, 2, nested.ptr, nested.length)) return 343;
        auto recording = context.recordCommands;
        context.recordCommands = false;
        auto result = executeLine(context, nested.ptr);
        context.recordCommands = recording;
        return result;
    }
    if (strcmp(command, "let".ptr) == 0)
    {
        if (tokens.count < 4) return 344;
        ScriptValue value;
        if (!resolveScriptValue(context, tokens.values[2], &value)) return 345;
        auto previous = context.runtime.find(tokens.values[1]);
        ScriptValue previousValue;
        bool hadPrevious = previous !is null;
        if (hadPrevious) previousValue = previous.value;
        if (!context.runtime.set(tokens.values[1], value)) return 346;
        char[WC_SCL_LINE] nested;
        if (!buildNestedCommand(tokens, 3, nested.ptr, nested.length)) return 347;
        auto recording = context.recordCommands;
        context.recordCommands = false;
        auto result = executeLine(context, nested.ptr);
        context.recordCommands = recording;
        if (hadPrevious) context.runtime.set(tokens.values[1], previousValue);
        return result;
    }
    if (strcmp(command, "for".ptr) == 0 || strcmp(command, "intersection_for".ptr) == 0)
    {
        if (tokens.count < 6) return 348;
        ScriptValue startValue;
        ScriptValue stepValue;
        ScriptValue endValue;
        double start = 0.0;
        double step = 0.0;
        double end = 0.0;
        if (!resolveScriptValue(context, tokens.values[2], &startValue) || !startValue.asNumber(&start) ||
            !resolveScriptValue(context, tokens.values[3], &stepValue) || !stepValue.asNumber(&step) ||
            !resolveScriptValue(context, tokens.values[4], &endValue) || !endValue.asNumber(&end) || step == 0.0) return 349;
        char[WC_SCL_LINE] nestedTemplate;
        if (!buildNestedCommand(tokens, 5, nestedTemplate.ptr, nestedTemplate.length)) return 350;
        auto previous = context.runtime.find(tokens.values[1]);
        ScriptValue previousValue;
        bool hadPrevious = previous !is null;
        if (hadPrevious) previousValue = previous.value;
        uint iterations = 0;
        for (double value = start; (step > 0.0 ? value <= end : value >= end); value += step)
        {
            if (++iterations > 100000u) return 351;
            context.runtime.setNumber(tokens.values[1], value);
            char[WC_SCL_LINE] nested;
            size_t templateLength = strlen(nestedTemplate.ptr);
            if (templateLength + 1 > nested.length) return 352;
            foreach (i; 0 .. templateLength + 1) nested[i] = nestedTemplate[i];
            auto recording = context.recordCommands;
            context.recordCommands = false;
            auto result = executeLine(context, nested.ptr);
            context.recordCommands = recording;
            if (result != 0) return result;
        }
        if (hadPrevious) context.runtime.set(tokens.values[1], previousValue);
        return 0;
    }

    // Preferred NX-like sketch workflow.
    if (strcmp(command, "datum_plane".ptr) == 0)
    {
        // datum_plane NAME ox oy oz nx ny nz [xx xy xz]
        if (tokens.count != 8 && tokens.count != 11) return 360;
        Operand[9] operands;
        auto count = tokens.count == 11 ? 9u : 6u;
        if (!parseValues(context,tokens,2,operands.ptr,count)) return 361;
        return context.model.addFeature(resolveObjectName(context,tokens.values[1]),FeatureKind.datumPlane,operands.ptr,cast(ubyte)count)==0?362:0;
    }
    if (strcmp(command, "datum_axis".ptr) == 0)
    {
        // datum_axis NAME ox oy oz dx dy dz
        if (tokens.count != 8) return 363;
        Operand[6] operands;
        if (!parseValues(context,tokens,2,operands.ptr,6)) return 364;
        return context.model.addFeature(resolveObjectName(context,tokens.values[1]),FeatureKind.datumAxis,operands.ptr,6)==0?365:0;
    }
    if (strcmp(command, "datum_csys".ptr) == 0 || strcmp(command, "csys".ptr) == 0)
    {
        // datum_csys NAME origin(3) x-axis(3) y-axis(3)
        if (tokens.count != 11) return 366;
        Operand[9] operands;
        if (!parseValues(context,tokens,2,operands.ptr,9)) return 367;
        return context.model.addFeature(resolveObjectName(context,tokens.values[1]),FeatureKind.datumCsys,operands.ptr,9)==0?368:0;
    }

    if (strcmp(command, "datum_plane_from_csys".ptr) == 0)
    {
        // datum_plane_from_csys NAME CSYS XY|YZ|XZ
        if(tokens.count != 4) return 388; bool ok=false; auto support=parseFeatureOperand(context,tokens.values[2],&ok); if(!ok) return 389;
        auto feature=context.model.featureById(support.featureId); if(feature is null || feature.kind!=FeatureKind.datumCsys) return 390;
        if(strcmp(tokens.values[3],"XY".ptr)!=0 && strcmp(tokens.values[3],"YZ".ptr)!=0 && strcmp(tokens.values[3],"XZ".ptr)!=0 &&
           strcmp(tokens.values[3],"xy".ptr)!=0 && strcmp(tokens.values[3],"yz".ptr)!=0 && strcmp(tokens.values[3],"xz".ptr)!=0) return 391;
        return context.model.addFeatureWithPayload(resolveObjectName(context,tokens.values[1]),FeatureKind.datumPlane,&support,1,tokens.values[3])==0?392:0;
    }
    if (strcmp(command, "datum_plane_from_face".ptr) == 0)
    {
        // datum_plane_from_face NAME OWNER_FEATURE PERSISTENT_FACE_ID
        if (tokens.count != 4) return 408;
        bool ok = false;
        auto support = parseFeatureOperand(context, tokens.values[2], &ok);
        if (!ok) return 409;
        ulong persistentId = 0;
        if (!parseUnsigned64(tokens.values[3], &persistentId) || persistentTopologyOwner(persistentId) != support.featureId) return 410;
        auto face = faceByPersistentId(&context.model.exactGeometry, persistentId);
        if (face is null || face.surfaceKind != BRepSurfaceKind.plane) return 411;
        return context.model.addFeatureWithPayload(resolveObjectName(context,tokens.values[1]), FeatureKind.datumPlane,
            &support, 1, "face".ptr, tokens.values[3]) == 0 ? 412 : 0;
    }
    if (strcmp(command, "datum_plane_offset".ptr) == 0)
    {
        // datum_plane_offset NAME PLANE DISTANCE
        if(tokens.count != 4) return 393; Operand[2] operands; bool ok=false; operands[0]=parseFeatureOperand(context,tokens.values[2],&ok); if(!ok) return 394;
        auto feature=context.model.featureById(operands[0].featureId); if(feature is null || feature.kind!=FeatureKind.datumPlane) return 395;
        operands[1]=parseValueOperand(context,tokens.values[3],&ok); if(!ok) return 396;
        return context.model.addFeatureWithPayload(resolveObjectName(context,tokens.values[1]),FeatureKind.datumPlane,operands.ptr,2,"offset".ptr)==0?397:0;
    }
    if (strcmp(command, "datum_axis_from_csys".ptr) == 0)
    {
        // datum_axis_from_csys NAME CSYS X|Y|Z
        if(tokens.count != 4) return 398; bool ok=false; auto support=parseFeatureOperand(context,tokens.values[2],&ok); if(!ok) return 399;
        auto feature=context.model.featureById(support.featureId); if(feature is null || feature.kind!=FeatureKind.datumCsys) return 400;
        auto axis=tokens.values[3]; if(strcmp(axis,"X".ptr)!=0&&strcmp(axis,"Y".ptr)!=0&&strcmp(axis,"Z".ptr)!=0&&strcmp(axis,"x".ptr)!=0&&strcmp(axis,"y".ptr)!=0&&strcmp(axis,"z".ptr)!=0)return 401;
        return context.model.addFeatureWithPayload(resolveObjectName(context,tokens.values[1]),FeatureKind.datumAxis,&support,1,axis)==0?402:0;
    }
    if (strcmp(command, "datum_csys_from".ptr) == 0)
    {
        // datum_csys_from NAME CSYS_OR_PLANE DX DY DZ (local co-ordinates)
        if(tokens.count != 6) return 403; Operand[4] operands; bool ok=false; operands[0]=parseFeatureOperand(context,tokens.values[2],&ok); if(!ok) return 404;
        auto feature=context.model.featureById(operands[0].featureId); if(feature is null || (feature.kind!=FeatureKind.datumCsys&&feature.kind!=FeatureKind.datumPlane)) return 405;
        if(!parseValues(context,tokens,3,&operands[1],3)) return 406;
        return context.model.addFeatureWithPayload(resolveObjectName(context,tokens.values[1]),FeatureKind.datumCsys,operands.ptr,4,"from".ptr)==0?407:0;
    }

    if (strcmp(command, "sketch".ptr) == 0)
    {
        if (tokens.count < 3) return 30;

        /* Direct CSYS-plane support: sketch NAME CSYS XY|YZ|XZ.
           The sketch depends on the CSYS directly; no sketch_support datum is
           inserted into modelling history. */
        if (tokens.count == 4)
        {
            bool ok = false;
            auto support = parseFeatureOperand(context, tokens.values[2], &ok);
            if (!ok) return 31;
            auto feature = context.model.featureById(support.featureId);
            if (feature is null || feature.kind != FeatureKind.datumCsys) return 31;
            auto plane = tokens.values[3];
            if (strcmp(plane, "XY".ptr) != 0 && strcmp(plane, "YZ".ptr) != 0 && strcmp(plane, "XZ".ptr) != 0 &&
                strcmp(plane, "xy".ptr) != 0 && strcmp(plane, "yz".ptr) != 0 && strcmp(plane, "xz".ptr) != 0) return 31;
            return context.model.addFeatureWithPayload(resolveObjectName(context, tokens.values[1]),
                FeatureKind.sketch, &support, 1, plane) == 0 ? 31 : 0;
        }

        /* Direct exact planar-face support: sketch NAME OWNER face PERSISTENT_ID. */
        if (tokens.count == 5 && strcmp(tokens.values[3], "face".ptr) == 0)
        {
            bool ok = false;
            auto support = parseFeatureOperand(context, tokens.values[2], &ok);
            if (!ok) return 31;
            ulong persistentId = 0;
            if (!parseUnsigned64(tokens.values[4], &persistentId) ||
                persistentTopologyOwner(persistentId) != support.featureId) return 31;
            auto face = faceByPersistentId(&context.model.exactGeometry, persistentId);
            if (face is null || face.surfaceKind != BRepSurfaceKind.plane) return 31;
            return context.model.addFeatureWithPayload(resolveObjectName(context, tokens.values[1]),
                FeatureKind.sketch, &support, 1, "face".ptr, tokens.values[4]) == 0 ? 31 : 0;
        }

        if (tokens.count != 3) return 30;
        auto supportName = resolveObjectName(context,tokens.values[2]);
        auto supportId = context.model.findFeature(supportName);
        if (supportId != 0)
        {
            auto support = context.model.featureById(supportId);
            if (support is null || support.kind != FeatureKind.datumPlane) return 31;
            Operand operand; operand.kind=OperandKind.feature; operand.featureId=supportId;
            return context.model.addFeatureWithPayload(resolveObjectName(context,tokens.values[1]),FeatureKind.sketch,&operand,1,supportName)==0?31:0;
        }
        return context.model.addFeatureWithPayload(resolveObjectName(context, tokens.values[1]), FeatureKind.sketch, null, 0, tokens.values[2]) == 0 ? 31 : 0;
    }
    if (strcmp(command, "end_sketch".ptr) == 0)
        return 0;
    if (strcmp(command, "sketch_line".ptr) == 0)
    {
        if (tokens.count < 7) return 32;
        Operand[5] operands;
        bool ok = false;
        operands[0] = parseFeatureOperand(context, tokens.values[2], &ok);
        if (!ok || !parseValues(context, tokens, 3, &operands[1], 4)) return 33;
        return context.model.addFeature(resolveObjectName(context, tokens.values[1]), FeatureKind.sketchLine, operands.ptr, 5) == 0 ? 34 : 0;
    }
    if (strcmp(command, "sketch_arc".ptr) == 0)
    {
        if (tokens.count < 8) return 35;
        Operand[6] operands;
        bool ok = false;
        operands[0] = parseFeatureOperand(context, tokens.values[2], &ok);
        if (!ok || !parseValues(context, tokens, 3, &operands[1], 5)) return 36;
        return context.model.addFeature(resolveObjectName(context, tokens.values[1]), FeatureKind.sketchArc, operands.ptr, 6) == 0 ? 37 : 0;
    }
    if (strcmp(command, "sketch_circle".ptr) == 0)
    {
        if (tokens.count < 4) return 38;
        Operand[2] operands;
        bool ok = false;
        operands[0] = parseFeatureOperand(context, tokens.values[2], &ok);
        if (!ok) return 39;
        operands[1] = parseValueOperand(context, tokens.values[3], &ok);
        if (!ok) return 40;
        return context.model.addFeature(resolveObjectName(context, tokens.values[1]), FeatureKind.sketchCircle, operands.ptr, 2) == 0 ? 41 : 0;
    }
    if (strcmp(command, "sketch_circle_at".ptr) == 0)
    {
        // sketch_circle_at NAME SKETCH CX CY R
        if (tokens.count < 6) return 381;
        Operand[4] operands;
        bool ok = false;
        operands[0] = parseFeatureOperand(context, tokens.values[2], &ok);
        if (!ok || !parseValues(context, tokens, 3, &operands[1], 3)) return 382;
        return context.model.addFeature(resolveObjectName(context, tokens.values[1]), FeatureKind.sketchCircle, operands.ptr, 4) == 0 ? 383 : 0;
    }
    if (strcmp(command, "sketch_rect".ptr) == 0 || strcmp(command, "sketch_square".ptr) == 0)
    {
        if (tokens.count < 5) return 42;
        Operand[4] operands;
        bool ok = false;
        operands[0] = parseFeatureOperand(context, tokens.values[2], &ok);
        if (!ok || !parseValues(context, tokens, 3, &operands[1], 2)) return 43;
        operands[3] = tokens.count >= 6 ? parseValueOperand(context, tokens.values[5], &ok) : literalOperand(0.0);
        if (tokens.count >= 6 && !ok) return 44;
        return context.model.addFeature(resolveObjectName(context, tokens.values[1]), FeatureKind.sketchRectangle, operands.ptr, 4) == 0 ? 45 : 0;
    }
    if (strcmp(command, "sketch_rect_at".ptr) == 0)
    {
        // sketch_rect_at NAME SKETCH X Y WIDTH HEIGHT
        if (tokens.count < 7) return 810;
        Operand[5] operands;
        bool ok = false;
        operands[0] = parseFeatureOperand(context, tokens.values[2], &ok);
        if (!ok || !parseValues(context, tokens, 3, &operands[1], 4)) return 811;
        return context.model.addFeature(resolveObjectName(context, tokens.values[1]), FeatureKind.sketchRectangle, operands.ptr, 5) == 0 ? 812 : 0;
    }
    if (strcmp(command, "sketch_polygon".ptr) == 0)
        return addPolygonFeature(context, tokens, FeatureKind.sketchPolygon, true, 46);
    if (strcmp(command, "sketch_text".ptr) == 0)
    {
        if (tokens.count < 5) return 50;
        Operand[2] operands;
        bool ok = false;
        operands[0] = parseFeatureOperand(context, tokens.values[2], &ok);
        if (!ok) return 51;
        operands[1] = parseValueOperand(context, tokens.values[4], &ok);
        if (!ok) return 52;
        auto font = tokens.count >= 6 ? tokens.values[5] : null;
        return context.model.addFeatureWithPayload(resolveObjectName(context, tokens.values[1]), FeatureKind.sketchText, operands.ptr, 2,
                                                   tokens.values[3], font) == 0 ? 53 : 0;
    }

    if (strcmp(command, "sketch_constraint".ptr) == 0)
    {
        // Compact forms:
        // horizontal/vertical/fix: KIND NAME SKETCH ENTITY [POINT]
        // radius/diameter: KIND NAME SKETCH ENTITY VALUE
        // equal_length/parallel/perpendicular/symmetry: KIND NAME SKETCH A B
        // tangent: KIND NAME SKETCH LINE LINE_POINT CURVE
        // coincident: KIND NAME SKETCH A APOINT B BPOINT
        // distance: KIND NAME SKETCH A APOINT B BPOINT VALUE
        if (tokens.count < 5) return 369;
        SketchConstraintKind kind;
        if (!parseSketchConstraintKind(tokens.values[1],&kind)) return 370;
        auto sketchId=context.model.findFeature(resolveObjectName(context,tokens.values[3]));
        auto firstId=context.model.findFeature(resolveObjectName(context,tokens.values[4]));
        if (sketchId==0 || firstId==0) return 371;
        uint firstPoint=0, secondPoint=0; EntityId secondId=0; double value=0.0;
        if (kind==SketchConstraintKind.horizontal || kind==SketchConstraintKind.vertical || kind==SketchConstraintKind.fixPoint)
        {
            if (tokens.count>=6 && !parseUnsignedNumber(tokens.values[5],&firstPoint)) return 372;
        }
        else if (kind==SketchConstraintKind.radius || kind==SketchConstraintKind.diameter)
        {
            if (tokens.count<6 || !parseNumber(tokens.values[5],&value)) return 373;
        }
        else if (kind==SketchConstraintKind.equalLength || kind==SketchConstraintKind.parallel || kind==SketchConstraintKind.perpendicular ||
                 kind==SketchConstraintKind.concentric || kind==SketchConstraintKind.equalRadius || kind==SketchConstraintKind.symmetry)
        {
            if (tokens.count<6) return 374;
            secondId=context.model.findFeature(resolveObjectName(context,tokens.values[5]));
            if (secondId==0) return 375;
        }
        else if (kind==SketchConstraintKind.tangent)
        {
            if(tokens.count<7 || !parseUnsignedNumber(tokens.values[5],&firstPoint)) return 388;
            secondId=context.model.findFeature(resolveObjectName(context,tokens.values[6]));
            if(secondId==0) return 389;
        }
        else if (kind==SketchConstraintKind.angle)
        {
            if(tokens.count<7) return 384;
            secondId=context.model.findFeature(resolveObjectName(context,tokens.values[5]));
            if(secondId==0 || !parseNumber(tokens.values[6],&value)) return 385;
        }
        else if (kind==SketchConstraintKind.midpoint)
        {
            // midpoint NAME SKETCH POINT_ENTITY POINT_INDEX LINE_ENTITY
            if(tokens.count<7 || !parseUnsignedNumber(tokens.values[5],&firstPoint)) return 386;
            secondId=context.model.findFeature(resolveObjectName(context,tokens.values[6]));
            if(secondId==0) return 387;
        }
        else if (kind==SketchConstraintKind.coincident)
        {
            if (tokens.count<8 || !parseUnsignedNumber(tokens.values[5],&firstPoint)) return 376;
            secondId=context.model.findFeature(resolveObjectName(context,tokens.values[6]));
            if (secondId==0 || !parseUnsignedNumber(tokens.values[7],&secondPoint)) return 377;
        }
        else if (kind==SketchConstraintKind.distance)
        {
            if (tokens.count<9 || !parseUnsignedNumber(tokens.values[5],&firstPoint)) return 378;
            secondId=context.model.findFeature(resolveObjectName(context,tokens.values[6]));
            if (secondId==0 || !parseUnsignedNumber(tokens.values[7],&secondPoint) || !parseNumber(tokens.values[8],&value)) return 379;
        }
        return addSketchConstraint(context.model,tokens.values[2],kind,sketchId,firstId,cast(ubyte)firstPoint,secondId,cast(ubyte)secondPoint,value)==0?380:0;
    }

    // NX-style rough curves outside sketches. They are intentionally legal but
    // tagged as non-preferred by FeatureKind/ModellingRole.
    if (strcmp(command, "point".ptr) == 0)
    {
        if (tokens.count < 5) return 60;
        Operand[3] operands;
        if (!parseValues(context, tokens, 2, operands.ptr, 3)) return 61;
        return context.model.addFeature(resolveObjectName(context, tokens.values[1]), FeatureKind.freePoint, operands.ptr, 3) == 0 ? 62 : 0;
    }
    if (strcmp(command, "line".ptr) == 0)
    {
        if (tokens.count < 8) return 63;
        Operand[6] operands;
        if (!parseValues(context, tokens, 2, operands.ptr, 6)) return 64;
        return context.model.addFeature(resolveObjectName(context, tokens.values[1]), FeatureKind.freeLine, operands.ptr, 6) == 0 ? 65 : 0;
    }
    if (strcmp(command, "arc".ptr) == 0)
    {
        if (tokens.count < 8) return 66;
        Operand[6] operands;
        if (!parseValues(context, tokens, 2, operands.ptr, 6)) return 67;
        return context.model.addFeature(resolveObjectName(context, tokens.values[1]), FeatureKind.freeArc, operands.ptr, 6) == 0 ? 68 : 0;
    }
    if (strcmp(command, "curve_circle".ptr) == 0)
    {
        if (tokens.count < 6) return 69;
        Operand[4] operands;
        if (!parseValues(context, tokens, 2, operands.ptr, 4)) return 70;
        return context.model.addFeature(resolveObjectName(context, tokens.values[1]), FeatureKind.freeCircle, operands.ptr, 4) == 0 ? 71 : 0;
    }
    if (strcmp(command, "spline_bbox".ptr) == 0)
    {
        if (tokens.count < 8) return 72;
        Operand[6] operands;
        if (!parseValues(context, tokens, 2, operands.ptr, 6)) return 73;
        auto payload = tokens.count >= 9 ? tokens.values[8] : null;
        return context.model.addFeatureWithPayload(resolveObjectName(context, tokens.values[1]), FeatureKind.freeSpline, operands.ptr, 6, payload) == 0 ? 74 : 0;
    }

    // OpenSCAD interchange is deliberately dumb-body-only. Import evaluates
    // SCAD geometry and stores a triangle mesh; export flattens model geometry
    // back to polyhedron() bodies rather than recreating parametric history.
    if (strcmp(command, "scad_import".ptr) == 0)
    {
        if (tokens.count < 3) return 75;
        OpenScadImportOptions options;
        options.setDefaults();
        if (tokens.count >= 4)
        {
            if (strcmp(tokens.values[3], "internal".ptr) == 0) options.engine = OpenScadImportEngine.internalRoundTrip;
            else if (strcmp(tokens.values[3], "external".ptr) == 0) options.engine = OpenScadImportEngine.externalCli;
            else if (strcmp(tokens.values[3], "auto".ptr) != 0) return 76;
        }
        bool ok = true;
        if (tokens.count >= 5) { double v=0; if(!parseNumber(tokens.values[4],&v)) return 77; options.unitScale=v; }
        if (tokens.count >= 6) { double v=0; if(!parseNumber(tokens.values[5],&v) || v<0) return 77; options.fn=cast(uint)v; }
        if (tokens.count >= 7) { double v=0; if(!parseNumber(tokens.values[6],&v)) return 77; options.fa=v; }
        if (tokens.count >= 8) { double v=0; if(!parseNumber(tokens.values[7],&v)) return 77; options.fs=v; }
        if (tokens.count >= 9)
        {
            if (strcmp(tokens.values[8], "manifold".ptr) == 0) options.backend=OpenScadBackend.manifold;
            else if (strcmp(tokens.values[8], "cgal".ptr) == 0) options.backend=OpenScadBackend.cgal;
            else if (strcmp(tokens.values[8], "auto".ptr) != 0) return 78;
        }
        if (tokens.count >= 10) { double v=0; if(!parseNumber(tokens.values[9],&v)) return 77; options.centreOnOrigin=v!=0.0; }
        if (tokens.count >= 11) { double v=0; if(!parseNumber(tokens.values[10],&v)) return 77; options.weldTolerance=v; }
        if (tokens.count >= 12) { double v=0; if(!parseNumber(tokens.values[11],&v)) return 77; options.requireClosedMesh=v!=0.0; }
        return importOpenScad(context.model, tokens.values[2], resolveObjectName(context,tokens.values[1]), &options);
    }
    if (strcmp(command, "scad_export".ptr) == 0)
    {
        if (tokens.count < 3) return 79;
        OpenScadExportOptions options;
        options.setDefaults();
        if (tokens.count >= 4)
        {
            if (strcmp(tokens.values[3], "all_dumb".ptr) == 0) options.exportScope=OpenScadExportScope.allDumbBodies;
            else if (strcmp(tokens.values[3], "all".ptr) == 0) options.exportScope=OpenScadExportScope.allBodies;
            else { options.exportScope=OpenScadExportScope.namedFeature; options.featureName.set(resolveObjectName(context,tokens.values[3])); }
        }
        else options.exportScope=OpenScadExportScope.allDumbBodies;
        bool ok = true;
        if (tokens.count >= 5) { double v=0; if(!parseNumber(tokens.values[4],&v)) return 79; options.precision=cast(uint)v; }
        if (tokens.count >= 6) { double v=0; if(!parseNumber(tokens.values[5],&v)) return 79; options.convexity=cast(uint)v; }
        if (tokens.count >= 7) { double v=0; if(!parseNumber(tokens.values[6],&v)) return 79; options.fn=cast(uint)v; }
        if (tokens.count >= 8) { double v=0; if(!parseNumber(tokens.values[7],&v)) return 79; options.fa=v; }
        if (tokens.count >= 9) { double v=0; if(!parseNumber(tokens.values[8],&v)) return 79; options.fs=v; }
        if (tokens.count >= 10) { double v=0; if(!parseNumber(tokens.values[9],&v)) return 79; options.unitScale=v; }
        if (tokens.count >= 11)
        {
            if (strcmp(tokens.values[10], "bbox".ptr) == 0) options.fallback=OpenScadExportFallback.boundingBox;
            else if (strcmp(tokens.values[10], "reject".ptr) != 0) return 79;
        }
        if (tokens.count >= 12) { double v=0; if(!parseNumber(tokens.values[11],&v)) return 79; options.centreEachBody=v!=0.0; }
        auto backend=waifuBRepBackend();
        auto rc=backend.recompute(context.model);
        return rc==0 ? exportOpenScad(context.model,tokens.values[2],&options) : rc;
    }

    // Explicit non-associative body escape hatch.
    if (strcmp(command, "dumb_body".ptr) == 0)
    {
        if (tokens.count < 8) return 80;
        Operand[6] operands;
        if (!parseValues(context, tokens, 2, operands.ptr, 6)) return 81;
        auto label = tokens.count >= 9 ? tokens.values[8] : "direct dumb body".ptr;
        return context.model.addFeatureWithPayload(resolveObjectName(context, tokens.values[1]), FeatureKind.dumbBody, operands.ptr, 6, label) == 0 ? 82 : 0;
    }

    // OpenSCAD-equivalent 2D primitives.
    if (strcmp(command, "circle".ptr) == 0 || strcmp(command, "circle_d".ptr) == 0)
    {
        if (tokens.count < 3) return 90;
        Operand[2] operands;
        bool ok = false;
        operands[0] = parseValueOperand(context, tokens.values[2], &ok);
        if (!ok) return 91;
        operands[1] = literalOperand(strcmp(command, "circle_d".ptr) == 0 ? 1.0 : 0.0);
        return context.model.addFeature(resolveObjectName(context, tokens.values[1]), FeatureKind.circle2d, operands.ptr, 2) == 0 ? 92 : 0;
    }
    if (strcmp(command, "square".ptr) == 0)
    {
        if (tokens.count < 3) return 93;
        Operand[3] operands;
        bool ok = false;
        operands[0] = parseValueOperand(context, tokens.values[2], &ok);
        if (!ok) return 94;

        // `square NAME SIZE [CENTRE]` and `square NAME WIDTH HEIGHT [CENTRE]`.
        // A boolean fourth token selects the scalar-size form unambiguously.
        bool scalarForm = tokens.count == 3 ||
                          (tokens.count == 4 && (strcmp(tokens.values[3], "true".ptr) == 0 ||
                                                 strcmp(tokens.values[3], "false".ptr) == 0));
        if (scalarForm)
        {
            operands[1] = operands[0];
            operands[2] = tokens.count >= 4 ? parseValueOperand(context, tokens.values[3], &ok) : literalOperand(0.0);
        }
        else
        {
            if (tokens.count < 4) return 94;
            operands[1] = parseValueOperand(context, tokens.values[3], &ok);
            if (!ok) return 94;
            operands[2] = tokens.count >= 5 ? parseValueOperand(context, tokens.values[4], &ok) : literalOperand(0.0);
        }
        if (!ok) return 95;
        return context.model.addFeature(resolveObjectName(context, tokens.values[1]), FeatureKind.square2d, operands.ptr, 3) == 0 ? 96 : 0;
    }
    if (strcmp(command, "polygon".ptr) == 0)
        return addPolygonFeature(context, tokens, FeatureKind.polygon2d, false, 97);
    if (strcmp(command, "text".ptr) == 0)
    {
        if (tokens.count < 4) return 101;
        Operand operand;
        bool ok = false;
        operand = parseValueOperand(context, tokens.values[3], &ok);
        if (!ok) return 102;
        char[256] attributes;
        if (tokens.count >= 5 && !joinTokens(tokens, 4, attributes.ptr, attributes.length)) return 102;
        // payload2 retains font|direction|language|script|halign|valign|spacing
        // in that order when supplied. Rendering backends may interpret them;
        // the model graph does not discard OpenSCAD text metadata.
        return context.model.addFeatureWithPayload(resolveObjectName(context, tokens.values[1]), FeatureKind.text2d, &operand, 1,
                                                   tokens.values[2], tokens.count >= 5 ? attributes.ptr : null) == 0 ? 103 : 0;
    }
    if (strcmp(command, "import2d".ptr) == 0)
    {
        if (tokens.count < 7) return 104;
        Operand[7] operands;
        if (!parseValues(context, tokens, 3, operands.ptr, 2)) return 105;
        operands[2] = literalOperand(0.0);
        if (!parseValues(context, tokens, 5, &operands[3], 2)) return 106;
        operands[5] = literalOperand(0.0);
        bool ok = true;
        operands[6] = tokens.count >= 8 ? parseValueOperand(context, tokens.values[7], &ok) : literalOperand(0.0); // convexity hint
        if (!ok) return 106;
        return context.model.addFeatureWithPayload(resolveObjectName(context, tokens.values[1]), FeatureKind.import2d, operands.ptr, 7,
                                                   tokens.values[2]) == 0 ? 107 : 0;
    }

    // OpenSCAD-equivalent 3D primitives/direct bodies.
    if (strcmp(command, "box".ptr) == 0)
    {
        if (tokens.count < 5) return 110;
        Operand[3] operands;
        if (!parseValues(context, tokens, 2, operands.ptr, 3)) return 111;
        return context.model.addFeature(resolveObjectName(context, tokens.values[1]), FeatureKind.box, operands.ptr, 3) == 0 ? 112 : 0;
    }
    if (strcmp(command, "cube".ptr) == 0)
    {
        if (tokens.count < 3) return 110;
        Operand[4] operands;
        bool ok = false;
        operands[0] = parseValueOperand(context, tokens.values[2], &ok);
        if (!ok) return 111;
        bool scalarForm = tokens.count == 3 ||
                          (tokens.count == 4 && (strcmp(tokens.values[3], "true".ptr) == 0 ||
                                                 strcmp(tokens.values[3], "false".ptr) == 0));
        if (scalarForm)
        {
            operands[1] = operands[0];
            operands[2] = operands[0];
            operands[3] = tokens.count >= 4 ? parseValueOperand(context, tokens.values[3], &ok) : literalOperand(0.0);
        }
        else
        {
            if (tokens.count < 5 || !parseValues(context, tokens, 3, &operands[1], 2)) return 111;
            operands[3] = tokens.count >= 6 ? parseValueOperand(context, tokens.values[5], &ok) : literalOperand(0.0);
        }
        if (!ok) return 111;
        return context.model.addFeature(resolveObjectName(context, tokens.values[1]), FeatureKind.box, operands.ptr, 4) == 0 ? 112 : 0;
    }
    if (strcmp(command, "cylinder".ptr) == 0 || strcmp(command, "cylinder_d".ptr) == 0)
    {
        if (tokens.count < 4) return 113;
        Operand[4] operands;
        if (!parseValues(context, tokens, 2, operands.ptr, 2)) return 114;
        bool ok = true;
        operands[2] = tokens.count >= 5 ? parseValueOperand(context, tokens.values[4], &ok) : literalOperand(0.0);
        operands[3] = literalOperand(strcmp(command, "cylinder_d".ptr) == 0 ? 1.0 : 0.0);
        if (!ok) return 114;
        return context.model.addFeature(resolveObjectName(context, tokens.values[1]), FeatureKind.cylinder, operands.ptr, 4) == 0 ? 115 : 0;
    }
    if (strcmp(command, "sphere".ptr) == 0 || strcmp(command, "sphere_d".ptr) == 0)
    {
        if (tokens.count < 3) return 116;
        Operand[2] operands;
        bool ok = false;
        operands[0] = parseValueOperand(context, tokens.values[2], &ok);
        operands[1] = literalOperand(strcmp(command, "sphere_d".ptr) == 0 ? 1.0 : 0.0);
        if (!ok) return 117;
        return context.model.addFeature(resolveObjectName(context, tokens.values[1]), FeatureKind.sphere, operands.ptr, 2) == 0 ? 118 : 0;
    }
    if (strcmp(command, "torus".ptr) == 0)
    {
        // torus NAME major_radius minor_radius
        if (tokens.count < 4) return 1180;
        Operand[2] operands;
        if (!parseValues(context,tokens,2,operands.ptr,2)) return 1181;
        return context.model.addFeature(resolveObjectName(context,tokens.values[1]),FeatureKind.torus,operands.ptr,2)==0?1182:0;
    }
    if (strcmp(command, "frustum".ptr) == 0 || strcmp(command, "cone".ptr) == 0 || strcmp(command, "frustum_d".ptr) == 0)
    {
        if (tokens.count < 5) return 119;
        Operand[5] operands;
        if (!parseValues(context, tokens, 2, operands.ptr, 3)) return 120;
        bool ok = true;
        operands[3] = tokens.count >= 6 ? parseValueOperand(context, tokens.values[5], &ok) : literalOperand(0.0);
        operands[4] = literalOperand(strcmp(command, "frustum_d".ptr) == 0 ? 1.0 : 0.0);
        if (!ok) return 120;
        return context.model.addFeature(resolveObjectName(context, tokens.values[1]), FeatureKind.coneFrustum, operands.ptr, 5) == 0 ? 121 : 0;
    }
    if (strcmp(command, "polyhedron".ptr) == 0)
    {
        if (tokens.count < 4) return 122;
        double[3] minima;
        double[3] maxima;
        if (!parsePointListBounds(tokens.values[2], 3, minima.ptr, maxima.ptr)) return 123;
        Operand[7] operands;
        operands[0] = literalOperand(minima[0]); operands[1] = literalOperand(minima[1]); operands[2] = literalOperand(minima[2]);
        operands[3] = literalOperand(maxima[0]); operands[4] = literalOperand(maxima[1]); operands[5] = literalOperand(maxima[2]);
        bool ok = true;
        operands[6] = tokens.count >= 5 ? parseValueOperand(context, tokens.values[4], &ok) : literalOperand(0.0); // convexity hint
        if (!ok) return 123;
        return context.model.addFeatureWithPayload(resolveObjectName(context, tokens.values[1]), FeatureKind.polyhedron, operands.ptr, 7,
                                                   tokens.values[2], tokens.values[3]) == 0 ? 124 : 0;
    }
    if (strcmp(command, "import3d".ptr) == 0 || strcmp(command, "import".ptr) == 0)
    {
        if (tokens.count < 9) return 125;
        Operand[7] operands;
        if (!parseValues(context, tokens, 3, operands.ptr, 6)) return 126;
        bool ok = true;
        operands[6] = tokens.count >= 10 ? parseValueOperand(context, tokens.values[9], &ok) : literalOperand(0.0); // convexity hint
        if (!ok) return 126;
        return context.model.addFeatureWithPayload(resolveObjectName(context, tokens.values[1]), FeatureKind.import3d, operands.ptr, 7,
                                                   tokens.values[2]) == 0 ? 127 : 0;
    }
    if (strcmp(command, "surface".ptr) == 0)
    {
        if (tokens.count < 9) return 128;
        Operand[8] operands;
        if (!parseValues(context, tokens, 3, operands.ptr, 6)) return 129;
        bool ok = true;
        operands[6] = tokens.count >= 10 ? parseValueOperand(context, tokens.values[9], &ok) : literalOperand(0.0); // centred
        if (!ok) return 129;
        operands[7] = tokens.count >= 11 ? parseValueOperand(context, tokens.values[10], &ok) : literalOperand(0.0); // convexity hint
        if (!ok) return 129;
        return context.model.addFeatureWithPayload(resolveObjectName(context, tokens.values[1]), FeatureKind.heightSurface, operands.ptr, 8,
                                                   tokens.values[2]) == 0 ? 130 : 0;
    }

    // Preferred feature family and OpenSCAD extrusion equivalents.
    if (strcmp(command, "extrude".ptr) == 0 || strcmp(command, "linear_extrude".ptr) == 0)
    {
        if (tokens.count < 4) return 140;
        Operand[6] operands;
        bool ok = false;
        operands[0] = parseFeatureOperand(context, tokens.values[2], &ok);
        if (!ok) return 141;
        operands[1] = parseValueOperand(context, tokens.values[3], &ok);
        if (!ok) return 142;
        operands[2] = tokens.count >= 5 ? parseValueOperand(context, tokens.values[4], &ok) : literalOperand(0.0); // twist
        if (!ok) return 143;
        operands[3] = tokens.count >= 6 ? parseValueOperand(context, tokens.values[5], &ok) : literalOperand(0.0); // slices
        if (!ok) return 144;
        operands[4] = tokens.count >= 7 ? parseValueOperand(context, tokens.values[6], &ok) : literalOperand(0.0); // centred
        if (!ok) return 145;
        operands[5] = tokens.count >= 8 ? parseValueOperand(context, tokens.values[7], &ok) : literalOperand(0.0); // convexity hint
        if (!ok) return 145;
        return context.model.addFeature(resolveObjectName(context, tokens.values[1]), FeatureKind.extrude, operands.ptr, 6) == 0 ? 146 : 0;
    }
    if (strcmp(command, "revolve".ptr) == 0 || strcmp(command, "rotate_extrude".ptr) == 0)
    {
        if (tokens.count < 4) return 147;
        Operand[3] operands;
        bool ok = false;
        operands[0] = parseFeatureOperand(context, tokens.values[2], &ok);
        if (!ok) return 148;
        operands[1] = parseValueOperand(context, tokens.values[3], &ok); // angle
        if (!ok) return 149;
        operands[2] = tokens.count >= 5 ? parseValueOperand(context, tokens.values[4], &ok) : literalOperand(0.0); // convexity hint
        if (!ok) return 149;
        return context.model.addFeature(resolveObjectName(context, tokens.values[1]), FeatureKind.revolve, operands.ptr, 3) == 0 ? 150 : 0;
    }
    if (strcmp(command, "revolve_axis".ptr) == 0)
    {
        // revolve_axis NAME PROFILE DATUM_AXIS ANGLE [CONVEXITY]
        if(tokens.count<5)return 150; Operand[4] operands; bool ok=false;
        operands[0]=parseFeatureOperand(context,tokens.values[2],&ok); if(!ok)return 151;
        operands[1]=parseFeatureOperand(context,tokens.values[3],&ok); if(!ok)return 152;
        auto axisFeature=context.model.featureById(operands[1].featureId); if(axisFeature is null||axisFeature.kind!=FeatureKind.datumAxis)return 153;
        operands[2]=parseValueOperand(context,tokens.values[4],&ok); if(!ok)return 154;
        operands[3]=tokens.count>=6?parseValueOperand(context,tokens.values[5],&ok):literalOperand(0.0); if(!ok)return 154;
        return context.model.addFeature(resolveObjectName(context,tokens.values[1]),FeatureKind.revolve,operands.ptr,4)==0?155:0;
    }
    if (strcmp(command, "sweep".ptr) == 0)
        return addBinaryFeature(context, tokens, FeatureKind.sweep, 151);
    if (strcmp(command, "loft".ptr) == 0)
        return addBinaryFeature(context, tokens, FeatureKind.loft, 155);

    // Transformations.
    if (strcmp(command, "translate".ptr) == 0)
        return addTransform3(context, tokens, FeatureKind.translate, 160);
    if (strcmp(command, "rotate".ptr) == 0)
        return addTransform3(context, tokens, FeatureKind.rotate, 164);
    if (strcmp(command, "rotate_axis".ptr) == 0)
    {
        if (tokens.count < 7) return 168;
        Operand[5] operands;
        bool ok = false;
        operands[0] = parseFeatureOperand(context, tokens.values[2], &ok);
        if (!ok || !parseValues(context, tokens, 3, &operands[1], 4)) return 169;
        return context.model.addFeature(resolveObjectName(context, tokens.values[1]), FeatureKind.rotateAxis, operands.ptr, 5) == 0 ? 170 : 0;
    }
    if (strcmp(command, "scale".ptr) == 0)
        return addTransform3(context, tokens, FeatureKind.scale, 171);
    if (strcmp(command, "resize".ptr) == 0)
    {
        if (tokens.count < 6) return 175;
        Operand[8] operands;
        bool ok = false;
        operands[0] = parseFeatureOperand(context, tokens.values[2], &ok);
        if (!ok || !parseValues(context, tokens, 3, &operands[1], 3)) return 176;
        operands[4] = tokens.count >= 7 ? parseValueOperand(context, tokens.values[6], &ok) : literalOperand(0.0); // auto X
        if (!ok) return 177;
        operands[5] = tokens.count >= 8 ? parseValueOperand(context, tokens.values[7], &ok) : literalOperand(0.0); // auto Y
        if (!ok) return 177;
        operands[6] = tokens.count >= 9 ? parseValueOperand(context, tokens.values[8], &ok) : literalOperand(0.0); // auto Z
        if (!ok) return 177;
        operands[7] = tokens.count >= 10 ? parseValueOperand(context, tokens.values[9], &ok) : literalOperand(0.0); // convexity
        if (!ok) return 177;
        return context.model.addFeature(resolveObjectName(context, tokens.values[1]), FeatureKind.resize, operands.ptr, 8) == 0 ? 178 : 0;
    }
    if (strcmp(command, "mirror".ptr) == 0)
        return addTransform3(context, tokens, FeatureKind.mirror, 179);
    if (strcmp(command, "multmatrix".ptr) == 0)
    {
        if (tokens.count < 19) return 183;
        Operand[17] operands;
        bool ok = false;
        operands[0] = parseFeatureOperand(context, tokens.values[2], &ok);
        if (!ok || !parseValues(context, tokens, 3, &operands[1], 16)) return 184;
        return context.model.addFeature(resolveObjectName(context, tokens.values[1]), FeatureKind.multMatrix, operands.ptr, 17) == 0 ? 185 : 0;
    }
    if (strcmp(command, "colour".ptr) == 0 || strcmp(command, "color".ptr) == 0)
    {
        if (tokens.count < 4) return 186;
        Operand source;
        bool ok = false;
        source = parseFeatureOperand(context, tokens.values[2], &ok);
        if (!ok) return 187;

        ScriptValue colourValue;
        bool namedColour = resolveScriptValue(context, tokens.values[3], &colourValue) && colourValue.kind == ScriptValueKind.string;
        double numericProbe = 0.0;
        if (!namedColour && !parseNumber(tokens.values[3], &numericProbe))
            namedColour = true;
        if (namedColour)
        {
            Operand[2] operands;
            operands[0] = source;
            operands[1] = tokens.count >= 5 ? parseValueOperand(context, tokens.values[4], &ok) : literalOperand(1.0);
            if (!ok) return 188;
            auto colourText = colourValue.kind == ScriptValueKind.string ? colourValue.stringValue.ptr() : tokens.values[3];
            return context.model.addFeatureWithPayload(resolveObjectName(context, tokens.values[1]), FeatureKind.colour,
                                                       operands.ptr, 2, colourText) == 0 ? 189 : 0;
        }
        if (tokens.count < 6) return 186;
        Operand[5] operands;
        operands[0] = source;
        if (!parseValues(context, tokens, 3, &operands[1], 3)) return 187;
        operands[4] = tokens.count >= 7 ? parseValueOperand(context, tokens.values[6], &ok) : literalOperand(1.0);
        if (!ok) return 188;
        return context.model.addFeature(resolveObjectName(context, tokens.values[1]), FeatureKind.colour, operands.ptr, 5) == 0 ? 189 : 0;
    }
    if (strcmp(command, "offset".ptr) == 0 || strcmp(command, "offset_delta".ptr) == 0 ||
        strcmp(command, "offset_r".ptr) == 0)
    {
        if (tokens.count < 4) return 190;
        Operand[3] operands;
        bool ok = false;
        operands[0] = parseFeatureOperand(context, tokens.values[2], &ok);
        if (!ok) return 191;
        operands[1] = parseValueOperand(context, tokens.values[3], &ok);
        if (!ok) return 192;
        operands[2] = tokens.count >= 5 ? parseValueOperand(context, tokens.values[4], &ok) : literalOperand(0.0); // delta chamfer
        if (!ok) return 192;
        auto mode = strcmp(command, "offset_r".ptr) == 0 ? "r".ptr : "delta".ptr;
        return context.model.addFeatureWithPayload(resolveObjectName(context, tokens.values[1]), FeatureKind.offset2d,
                                                   operands.ptr, 3, mode) == 0 ? 193 : 0;
    }
    if (strcmp(command, "projection".ptr) == 0)
    {
        if (tokens.count < 3) return 194;
        Operand[2] operands;
        bool ok = false;
        operands[0] = parseFeatureOperand(context, tokens.values[2], &ok);
        if (!ok) return 195;
        operands[1] = tokens.count >= 4 ? parseValueOperand(context, tokens.values[3], &ok) : literalOperand(0.0);
        if (!ok) return 196;
        return context.model.addFeature(resolveObjectName(context, tokens.values[1]), FeatureKind.projection, operands.ptr, 2) == 0 ? 197 : 0;
    }
    if (strcmp(command, "hull".ptr) == 0)
        return addBinaryFeature(context, tokens, FeatureKind.hull, 198);
    if (strcmp(command, "minkowski".ptr) == 0)
    {
        if (tokens.count < 4) return 202;
        Operand[3] operands;
        bool ok = false;
        operands[0] = parseFeatureOperand(context, tokens.values[2], &ok);
        if (!ok) return 203;
        operands[1] = parseFeatureOperand(context, tokens.values[3], &ok);
        if (!ok) return 204;
        operands[2] = tokens.count >= 5 ? parseValueOperand(context, tokens.values[4], &ok) : literalOperand(0.0); // convexity
        if (!ok) return 204;
        return context.model.addFeature(resolveObjectName(context, tokens.values[1]), FeatureKind.minkowski, operands.ptr, 3) == 0 ? 205 : 0;
    }

    // Boolean operations.
    if (strcmp(command, "union".ptr) == 0)
        return addBinaryFeature(context, tokens, FeatureKind.booleanUnion, 210);
    if (strcmp(command, "subtract".ptr) == 0 || strcmp(command, "difference".ptr) == 0)
        return addBinaryFeature(context, tokens, FeatureKind.booleanSubtract, 214);
    if (strcmp(command, "intersection".ptr) == 0 || strcmp(command, "intersect".ptr) == 0)
        return addBinaryFeature(context, tokens, FeatureKind.booleanIntersect, 218);

    // Detail and shell operations beyond OpenSCAD's baseline.
    if (strcmp(command, "fillet".ptr) == 0)
        return addUnaryFeatureWithAmount(context, tokens, FeatureKind.fillet, 222);
    if (strcmp(command, "chamfer".ptr) == 0)
        return addUnaryFeatureWithAmount(context, tokens, FeatureKind.chamfer, 226);
    if (strcmp(command, "shell".ptr) == 0)
        return addUnaryFeatureWithAmount(context, tokens, FeatureKind.shell, 230);
    if (strcmp(command, "render".ptr) == 0)
    {
        if (tokens.count < 3) return 234;
        Operand[2] operands;
        bool ok = false;
        operands[0] = parseFeatureOperand(context, tokens.values[2], &ok);
        if (!ok) return 235;
        operands[1] = tokens.count >= 4 ? parseValueOperand(context, tokens.values[3], &ok) : literalOperand(0.0); // convexity
        if (!ok) return 235;
        return context.model.addFeature(resolveObjectName(context, tokens.values[1]), FeatureKind.renderBarrier, operands.ptr, 2) == 0 ? 236 : 0;
    }

    // OpenSCAD modifier-character equivalents. SCL uses words so journals are
    // explicit rather than relying on punctuation with display-only semantics.
    if (strcmp(command, "disable".ptr) == 0)
        return addDisplayModifier(context, tokens, "disable".ptr, 240);
    if (strcmp(command, "show_only".ptr) == 0)
        return addDisplayModifier(context, tokens, "show_only".ptr, 243);
    if (strcmp(command, "highlight".ptr) == 0)
        return addDisplayModifier(context, tokens, "highlight".ptr, 246);
    if (strcmp(command, "background".ptr) == 0)
        return addDisplayModifier(context, tokens, "background".ptr, 249);

    if (strcmp(command, "assert".ptr) == 0)
    {
        if (tokens.count < 2) return 254;
        ScriptValue conditionValue;
        if (!resolveScriptValue(context, tokens.values[1], &conditionValue)) return 255;
        if (!conditionValue.truthy())
        {
            fprintf(stderr, "SCL assertion failed%s%s\n", tokens.count >= 3 ? ": ".ptr : "".ptr,
                    tokens.count >= 3 ? tokens.values[2] : "".ptr);
            return 256;
        }
        return 0;
    }

    if (strcmp(command, "recompute".ptr) == 0)
    {
        auto backend = waifuBRepBackend();
        return backend.recompute(context.model);
    }

    if (strcmp(command, "echo".ptr) == 0)
    {
        foreach (i; 1 .. tokens.count)
            fprintf(stdout, "%s%s", i == 1 ? "".ptr : " ".ptr, tokens.values[i]);
        fprintf(stdout, "\n");
        return 0;
    }

    fprintf(stderr, "Unknown SCL command: %s\n", command);
    return 400;
}

int executeLine(ScriptContext* context, char* line) nothrow @nogc
{
    if (context is null || context.model is null || line is null)
        return 10;

    // Keep an untouched copy for the semantic journal before tokenisation mutates whitespace.
    char[WC_SCL_LINE] original;
    size_t i = 0;
    while (line[i] != 0 && i + 1 < original.length)
    {
        original[i] = line[i];
        ++i;
    }
    while (i != 0 && (original[i - 1] == '\n' || original[i - 1] == '\r'))
        --i;
    original[i] = 0;

    char[WC_SCL_LINE] normalised;
    if (!normaliseRubyStyleLine(line, normalised.ptr, normalised.length))
    {
        fprintf(stderr, "SCL syntax normalisation failed (line too long or malformed).\n");
        return 401;
    }

    auto tokens = tokenise(normalised.ptr);
    return executeTokens(context, &tokens, original.ptr);
}

int executeFile(ScriptContext* context, const(char)* path) nothrow @nogc
{
    auto stream = fopen(path, "rb".ptr);
    if (stream is null)
    {
        fprintf(stderr, "Cannot open SCL script: %s\n", path);
        return 11;
    }

    char[WC_SCL_LINE] line;
    uint lineNumber = 0;
    int result = 0;
    while (fgets(line.ptr, cast(int)line.length, stream) !is null)
    {
        ++lineNumber;
        result = executeLine(context, line.ptr);
        if (result != 0)
        {
            fprintf(stderr, "SCL error %d on line %u\n", result, lineNumber);
            break;
        }
    }
    fclose(stream);
    return result;
}


int executeUseFile(ScriptContext* context, const(char)* path) nothrow @nogc
{
    auto stream = fopen(path, "rb".ptr);
    if (stream is null)
    {
        fprintf(stderr, "Cannot open SCL use file: %s\n", path);
        return 12;
    }

    char[WC_SCL_LINE] line;
    uint lineNumber = 0;
    int result = 0;
    while (fgets(line.ptr, cast(int)line.length, stream) !is null)
    {
        ++lineNumber;
        char[WC_SCL_LINE] normalised;
        if (!normaliseRubyStyleLine(line.ptr, normalised.ptr, normalised.length))
        {
            result = 401;
            break;
        }
        auto tokens = tokenise(normalised.ptr);
        if (tokens.count == 0)
            continue;
        auto command = tokens.values[0];
        if (strcmp(command, "module".ptr) != 0 &&
            strcmp(command, "function".ptr) != 0 &&
            strcmp(command, "use".ptr) != 0)
            continue;

        auto recording = context.recordCommands;
        context.recordCommands = false;
        result = executeTokens(context, &tokens, "".ptr);
        context.recordCommands = recording;
        if (result != 0)
        {
            fprintf(stderr, "SCL use error %d on line %u\n", result, lineNumber);
            break;
        }
    }
    fclose(stream);
    return result;
}





