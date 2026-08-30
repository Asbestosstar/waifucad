module waifucad.scl.runtime_ops;

import core.stdc.math : fabs, sin, cos, tan, asin, acos, atan, atan2, floor, round, ceil, log, log10, pow, sqrt, exp, fmod;
import core.stdc.string : strcmp;
import waifucad.journal.script_runtime : ScriptValue, ScriptValueKind;

private enum WC_PI = 3.14159265358979323846264338327950288;
private double degreesToRadians(double value) nothrow @nogc { return value * WC_PI / 180.0; }
private double radiansToDegrees(double value) nothrow @nogc { return value * 180.0 / WC_PI; }

bool applyBinaryOperator(const(char)* operation, ScriptValue left, ScriptValue right,
                         ScriptValue* output) nothrow @nogc
{
    if (operation is null || output is null)
        return false;
    double a = 0.0;
    double b = 0.0;
    if (!left.asNumber(&a) || !right.asNumber(&b))
        return false;

    if (strcmp(operation, "+".ptr) == 0) *output = ScriptValue.fromNumber(a + b);
    else if (strcmp(operation, "-".ptr) == 0) *output = ScriptValue.fromNumber(a - b);
    else if (strcmp(operation, "*".ptr) == 0) *output = ScriptValue.fromNumber(a * b);
    else if (strcmp(operation, "/".ptr) == 0) { if (b == 0.0) return false; *output = ScriptValue.fromNumber(a / b); }
    else if (strcmp(operation, "%".ptr) == 0) { if (b == 0.0) return false; *output = ScriptValue.fromNumber(fmod(a, b)); }
    else if (strcmp(operation, "^".ptr) == 0) *output = ScriptValue.fromNumber(pow(a, b));
    else if (strcmp(operation, "<".ptr) == 0) *output = ScriptValue.fromBoolean(a < b);
    else if (strcmp(operation, "<=".ptr) == 0) *output = ScriptValue.fromBoolean(a <= b);
    else if (strcmp(operation, "==".ptr) == 0) *output = ScriptValue.fromBoolean(a == b);
    else if (strcmp(operation, "!=".ptr) == 0) *output = ScriptValue.fromBoolean(a != b);
    else if (strcmp(operation, ">=".ptr) == 0) *output = ScriptValue.fromBoolean(a >= b);
    else if (strcmp(operation, ">".ptr) == 0) *output = ScriptValue.fromBoolean(a > b);
    else if (strcmp(operation, "&&".ptr) == 0) *output = ScriptValue.fromBoolean(left.truthy() && right.truthy());
    else if (strcmp(operation, "||".ptr) == 0) *output = ScriptValue.fromBoolean(left.truthy() || right.truthy());
    else return false;
    return true;
}

bool applyUnaryOperator(const(char)* operation, ScriptValue input, ScriptValue* output) nothrow @nogc
{
    if (operation is null || output is null)
        return false;
    double value = 0.0;
    if (strcmp(operation, "!".ptr) == 0)
    {
        *output = ScriptValue.fromBoolean(!input.truthy());
        return true;
    }
    if (!input.asNumber(&value))
        return false;
    if (strcmp(operation, "+".ptr) == 0) *output = ScriptValue.fromNumber(value);
    else if (strcmp(operation, "-".ptr) == 0) *output = ScriptValue.fromNumber(-value);
    else return false;
    return true;
}

bool applyMathFunction(const(char)* name, const(ScriptValue)* arguments, uint count,
                       ScriptValue* output) nothrow @nogc
{
    if (name is null || output is null)
        return false;
    double a = 0.0;
    double b = 0.0;
    if (count >= 1 && !arguments[0].asNumber(&a))
        return false;
    if (count >= 2 && !arguments[1].asNumber(&b))
        return false;

    if (strcmp(name, "abs".ptr) == 0 && count == 1) *output = ScriptValue.fromNumber(fabs(a));
    else if (strcmp(name, "sign".ptr) == 0 && count == 1) *output = ScriptValue.fromNumber(a < 0.0 ? -1.0 : (a > 0.0 ? 1.0 : 0.0));
    else if (strcmp(name, "sin".ptr) == 0 && count == 1) *output = ScriptValue.fromNumber(sin(degreesToRadians(a)));
    else if (strcmp(name, "cos".ptr) == 0 && count == 1) *output = ScriptValue.fromNumber(cos(degreesToRadians(a)));
    else if (strcmp(name, "tan".ptr) == 0 && count == 1) *output = ScriptValue.fromNumber(tan(degreesToRadians(a)));
    else if (strcmp(name, "asin".ptr) == 0 && count == 1) *output = ScriptValue.fromNumber(radiansToDegrees(asin(a)));
    else if (strcmp(name, "acos".ptr) == 0 && count == 1) *output = ScriptValue.fromNumber(radiansToDegrees(acos(a)));
    else if (strcmp(name, "atan".ptr) == 0 && count == 1) *output = ScriptValue.fromNumber(radiansToDegrees(atan(a)));
    else if (strcmp(name, "atan2".ptr) == 0 && count == 2) *output = ScriptValue.fromNumber(radiansToDegrees(atan2(a, b)));
    else if (strcmp(name, "floor".ptr) == 0 && count == 1) *output = ScriptValue.fromNumber(floor(a));
    else if (strcmp(name, "round".ptr) == 0 && count == 1) *output = ScriptValue.fromNumber(round(a));
    else if (strcmp(name, "ceil".ptr) == 0 && count == 1) *output = ScriptValue.fromNumber(ceil(a));
    else if (strcmp(name, "ln".ptr) == 0 && count == 1) *output = ScriptValue.fromNumber(log(a));
    else if (strcmp(name, "log".ptr) == 0 && count == 1) *output = ScriptValue.fromNumber(log10(a));
    else if (strcmp(name, "pow".ptr) == 0 && count == 2) *output = ScriptValue.fromNumber(pow(a, b));
    else if (strcmp(name, "sqrt".ptr) == 0 && count == 1) *output = ScriptValue.fromNumber(sqrt(a));
    else if (strcmp(name, "exp".ptr) == 0 && count == 1) *output = ScriptValue.fromNumber(exp(a));
    else if (strcmp(name, "min".ptr) == 0 && count == 2) *output = ScriptValue.fromNumber(a < b ? a : b);
    else if (strcmp(name, "max".ptr) == 0 && count == 2) *output = ScriptValue.fromNumber(a > b ? a : b);
    else return false;
    return true;
}

bool typeTest(const(char)* name, const ScriptValue* value) nothrow @nogc
{
    if (name is null || value is null)
        return false;
    if (strcmp(name, "is_undef".ptr) == 0) return value.kind == ScriptValueKind.undef;
    if (strcmp(name, "is_bool".ptr) == 0) return value.kind == ScriptValueKind.boolean;
    if (strcmp(name, "is_num".ptr) == 0) return value.kind == ScriptValueKind.number;
    if (strcmp(name, "is_string".ptr) == 0) return value.kind == ScriptValueKind.string;
    if (strcmp(name, "is_list".ptr) == 0) return value.kind == ScriptValueKind.list;
    if (strcmp(name, "is_function".ptr) == 0) return false; // Function objects arrive with the later module/function bytecode layer.
    return false;
}



