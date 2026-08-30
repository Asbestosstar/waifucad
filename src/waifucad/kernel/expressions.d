module waifucad.kernel.expressions;

import core.stdc.ctype : isalpha, isalnum, isspace;
import core.stdc.stdlib : strtod;
import core.stdc.math : fabs, sqrt, sin, cos, tan, atan2;
import core.stdc.string : strcmp;
import waifucad.kernel.types : Unit;

enum int WC_EXPRESSION_OK = 0;
enum int WC_EXPRESSION_SYNTAX = 1;
enum int WC_EXPRESSION_UNKNOWN_NAME = 2;
enum int WC_EXPRESSION_UNIT_MISMATCH = 3;
enum int WC_EXPRESSION_DIVIDE_BY_ZERO = 4;
enum int WC_EXPRESSION_CYCLE = 5;
enum int WC_EXPRESSION_DEPTH = 6;
enum int WC_EXPRESSION_DOMAIN = 7;

alias ExpressionLookup = bool function(void* context, const(char)* name,
                                       double* value, Unit* unit) nothrow @nogc;

struct ExpressionValue
{
    double value;
    Unit unit;
    int error;
}

private bool sameUnit(Unit a, Unit b) nothrow @nogc { return a == b; }

private struct Parser
{
    const(char)* cursor;
    ExpressionLookup lookup;
    void* context;
    uint depth;

    void skipSpace() nothrow @nogc
    {
        while (*cursor != 0 && isspace(cast(ubyte)*cursor)) ++cursor;
    }

    ExpressionValue fail(int code) nothrow @nogc
    {
        ExpressionValue result;
        result.error = code;
        return result;
    }

    ExpressionValue parseFunction(const(char)* name) nothrow @nogc
    {
        if (*cursor != '(') return fail(WC_EXPRESSION_SYNTAX);
        ++cursor;
        auto first = parseAdditive();
        if (first.error != 0) return first;
        skipSpace();

        ExpressionValue second;
        ExpressionValue third;
        bool hasSecond = false;
        bool hasThird = false;
        if (*cursor == ',')
        {
            ++cursor;
            second = parseAdditive();
            if (second.error != 0) return second;
            hasSecond = true;
            skipSpace();
            if (*cursor == ',')
            {
                ++cursor;
                third = parseAdditive();
                if (third.error != 0) return third;
                hasThird = true;
                skipSpace();
            }
        }
        if (*cursor != ')') return fail(WC_EXPRESSION_SYNTAX);
        ++cursor;

        ExpressionValue result;
        if (strcmp(name, "abs".ptr) == 0 && !hasSecond)
        {
            result = first; result.value = fabs(result.value); return result;
        }
        if (strcmp(name, "sqrt".ptr) == 0 && !hasSecond)
        {
            if (first.unit != Unit.unitless || first.value < 0.0) return fail(WC_EXPRESSION_DOMAIN);
            result.value = sqrt(first.value); result.unit = Unit.unitless; return result;
        }
        if ((strcmp(name, "sin".ptr) == 0 || strcmp(name, "cos".ptr) == 0 || strcmp(name, "tan".ptr) == 0) && !hasSecond)
        {
            if (first.unit != Unit.unitless && first.unit != Unit.degree) return fail(WC_EXPRESSION_UNIT_MISMATCH);
            auto radians = first.value * 3.14159265358979323846264338327950288 / 180.0;
            if (strcmp(name, "sin".ptr) == 0) result.value = sin(radians);
            else if (strcmp(name, "cos".ptr) == 0) result.value = cos(radians);
            else result.value = tan(radians);
            result.unit = Unit.unitless; return result;
        }
        if (strcmp(name, "atan2".ptr) == 0 && hasSecond && !hasThird)
        {
            if (!sameUnit(first.unit, second.unit)) return fail(WC_EXPRESSION_UNIT_MISMATCH);
            result.value = atan2(first.value, second.value) * 180.0 / 3.14159265358979323846264338327950288;
            result.unit = Unit.degree; return result;
        }
        if ((strcmp(name, "min".ptr) == 0 || strcmp(name, "max".ptr) == 0) && hasSecond && !hasThird)
        {
            if (!sameUnit(first.unit, second.unit)) return fail(WC_EXPRESSION_UNIT_MISMATCH);
            result.unit = first.unit;
            result.value = strcmp(name, "min".ptr) == 0 ? (first.value < second.value ? first.value : second.value) :
                                                           (first.value > second.value ? first.value : second.value);
            return result;
        }
        if (strcmp(name, "clamp".ptr) == 0 && hasSecond && hasThird)
        {
            if (!sameUnit(first.unit, second.unit) || !sameUnit(first.unit, third.unit)) return fail(WC_EXPRESSION_UNIT_MISMATCH);
            result = first;
            if (result.value < second.value) result.value = second.value;
            if (result.value > third.value) result.value = third.value;
            return result;
        }
        return fail(WC_EXPRESSION_SYNTAX);
    }

    ExpressionValue parsePrimary() nothrow @nogc
    {
        skipSpace();
        if (++depth > 64u)
        {
            --depth;
            return fail(WC_EXPRESSION_DEPTH);
        }

        if (*cursor == '(')
        {
            ++cursor;
            auto result = parseAdditive();
            skipSpace();
            if (result.error == 0 && *cursor == ')') ++cursor;
            else if (result.error == 0) result.error = WC_EXPRESSION_SYNTAX;
            --depth;
            return result;
        }

        if (*cursor == '+' || *cursor == '-')
        {
            auto negative = *cursor == '-';
            ++cursor;
            auto result = parsePrimary();
            if (negative && result.error == 0) result.value = -result.value;
            --depth;
            return result;
        }

        const(char)* end = null;
        auto number = strtod(cursor, &end);
        if (end !is cursor)
        {
            cursor = end;
            Unit unit = Unit.unitless;
            if (cursor[0] == 'm' && cursor[1] == 'm')
            {
                unit = Unit.millimetre;
                cursor += 2;
            }
            else if (cursor[0] == 'd' && cursor[1] == 'e' && cursor[2] == 'g')
            {
                unit = Unit.degree;
                cursor += 3;
            }
            ExpressionValue result;
            result.value = number;
            result.unit = unit;
            --depth;
            return result;
        }

        if (isalpha(cast(ubyte)*cursor) || *cursor == '_' || *cursor == '$')
        {
            char[64] name;
            size_t used = 0;
            while (*cursor != 0 && (isalnum(cast(ubyte)*cursor) || *cursor == '_' || *cursor == '$'))
            {
                if (used + 1 >= name.length)
                {
                    --depth;
                    return fail(WC_EXPRESSION_SYNTAX);
                }
                name[used++] = *cursor++;
            }
            name[used] = 0;
            ExpressionValue result;
            skipSpace();
            if (*cursor == '(')
            {
                result = parseFunction(name.ptr);
                --depth;
                return result;
            }
            if (strcmp(name.ptr, "PI".ptr) == 0 || strcmp(name.ptr, "TAU".ptr) == 0 || strcmp(name.ptr, "E".ptr) == 0)
            {
                if (strcmp(name.ptr, "PI".ptr) == 0) result.value = 3.14159265358979323846264338327950288;
                else if (strcmp(name.ptr, "TAU".ptr) == 0) result.value = 6.28318530717958647692528676655900576;
                else result.value = 2.71828182845904523536028747135266250;
                result.unit = Unit.unitless;
                --depth;
                return result;
            }
            if (lookup is null || !lookup(context, name.ptr, &result.value, &result.unit))
                result.error = WC_EXPRESSION_UNKNOWN_NAME;
            --depth;
            return result;
        }

        --depth;
        return fail(WC_EXPRESSION_SYNTAX);
    }

    ExpressionValue parseMultiplicative() nothrow @nogc
    {
        auto left = parsePrimary();
        while (left.error == 0)
        {
            skipSpace();
            auto op = *cursor;
            if (op != '*' && op != '/') break;
            ++cursor;
            auto right = parsePrimary();
            if (right.error != 0) return right;
            if (op == '*')
            {
                if (left.unit != Unit.unitless && right.unit != Unit.unitless)
                    return fail(WC_EXPRESSION_UNIT_MISMATCH);
                left.value *= right.value;
                if (left.unit == Unit.unitless) left.unit = right.unit;
            }
            else
            {
                if (right.value == 0.0) return fail(WC_EXPRESSION_DIVIDE_BY_ZERO);
                left.value /= right.value;
                if (right.unit == Unit.unitless) { }
                else if (sameUnit(left.unit, right.unit)) left.unit = Unit.unitless;
                else return fail(WC_EXPRESSION_UNIT_MISMATCH);
            }
        }
        return left;
    }

    ExpressionValue parseAdditive() nothrow @nogc
    {
        auto left = parseMultiplicative();
        while (left.error == 0)
        {
            skipSpace();
            auto op = *cursor;
            if (op != '+' && op != '-') break;
            ++cursor;
            auto right = parseMultiplicative();
            if (right.error != 0) return right;
            if (!sameUnit(left.unit, right.unit))
            {
                if (left.unit == Unit.unitless && left.value == 0.0) left.unit = right.unit;
                else if (right.unit == Unit.unitless && right.value == 0.0) { }
                else return fail(WC_EXPRESSION_UNIT_MISMATCH);
            }
            left.value = op == '+' ? left.value + right.value : left.value - right.value;
        }
        return left;
    }
}

ExpressionValue evaluateExpression(const(char)* expression,
                                   ExpressionLookup lookup,
                                   void* context,
                                   Unit expectedUnit) nothrow @nogc
{
    ExpressionValue result;
    if (expression is null || *expression == 0)
    {
        result.error = WC_EXPRESSION_SYNTAX;
        return result;
    }
    Parser parser;
    parser.cursor = expression;
    parser.lookup = lookup;
    parser.context = context;
    result = parser.parseAdditive();
    parser.skipSpace();
    if (result.error == 0 && *parser.cursor != 0)
        result.error = WC_EXPRESSION_SYNTAX;
    if (result.error == 0 && expectedUnit != Unit.unitless)
    {
        /* Bare numeric constants inherit the declared parameter unit. */
        if (result.unit == Unit.unitless) result.unit = expectedUnit;
        else if (result.unit != expectedUnit) result.error = WC_EXPRESSION_UNIT_MISMATCH;
    }
    else if (result.error == 0 && expectedUnit == Unit.unitless && result.unit != Unit.unitless)
        result.error = WC_EXPRESSION_UNIT_MISMATCH;
    return result;
}

