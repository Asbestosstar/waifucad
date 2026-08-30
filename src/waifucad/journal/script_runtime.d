module waifucad.journal.script_runtime;

import waifucad.core.fixed_string : FixedString64, FixedString256;

enum ScriptValueKind : ubyte
{
    undef,
    boolean,
    number,
    string,
    list
}

enum WC_SCRIPT_MAX_LIST_VALUES = 64;
enum WC_SCRIPT_MAX_VARIABLES = 128;
enum WC_SCRIPT_MAX_CALLABLES = 32;
enum WC_SCRIPT_MAX_CALL_DEPTH = 16;

struct ScriptValue
{
    ScriptValueKind kind;
    bool booleanValue;
    double numberValue;
    FixedString256 stringValue;
    double[WC_SCRIPT_MAX_LIST_VALUES] listValues;
    uint listCount;

    void clear() nothrow @nogc
    {
        kind = ScriptValueKind.undef;
        booleanValue = false;
        numberValue = 0.0;
        stringValue.clear();
        listCount = 0;
    }

    static ScriptValue fromNumber(double value) nothrow @nogc
    {
        ScriptValue result;
        result.clear();
        result.kind = ScriptValueKind.number;
        result.numberValue = value;
        return result;
    }

    static ScriptValue fromBoolean(bool value) nothrow @nogc
    {
        ScriptValue result;
        result.clear();
        result.kind = ScriptValueKind.boolean;
        result.booleanValue = value;
        result.numberValue = value ? 1.0 : 0.0;
        return result;
    }

    static ScriptValue fromString(const(char)* value) nothrow @nogc
    {
        ScriptValue result;
        result.clear();
        result.kind = ScriptValueKind.string;
        result.stringValue.set(value);
        return result;
    }

    bool asNumber(double* value) const nothrow @nogc
    {
        if (value is null)
            return false;
        if (kind == ScriptValueKind.number)
        {
            *value = numberValue;
            return true;
        }
        if (kind == ScriptValueKind.boolean)
        {
            *value = booleanValue ? 1.0 : 0.0;
            return true;
        }
        return false;
    }

    bool truthy() const nothrow @nogc
    {
        final switch (kind)
        {
            case ScriptValueKind.undef: return false;
            case ScriptValueKind.boolean: return booleanValue;
            case ScriptValueKind.number: return numberValue != 0.0;
            case ScriptValueKind.string: return stringValue.length != 0;
            case ScriptValueKind.list: return listCount != 0;
        }
    }
}


enum ScriptCallableKind : ubyte
{
    moduleBlock,
    functionBlock
}

struct ScriptCallable
{
    FixedString64 name;
    FixedString256 scriptBody;
    ScriptCallableKind kind;
    ubyte argumentCount;
}
struct ScriptVariable
{
    FixedString64 name;
    ScriptValue value;
}

struct ScriptRuntime
{
    ScriptVariable[WC_SCRIPT_MAX_VARIABLES] variables;
    ScriptCallable[WC_SCRIPT_MAX_CALLABLES] callables;
    FixedString64[WC_SCRIPT_MAX_CALL_DEPTH] callStack;
    size_t variableCount;
    size_t callableCount;
    uint callDepth;
    ulong randomState;

    void initialise() nothrow @nogc
    {
        variableCount = 0;
        callableCount = 0;
        callDepth = 0;
        randomState = 0x5741494655434144UL; // "WAIFUCAD"-derived deterministic bootstrap seed.
        setNumber("$fa".ptr, 12.0);
        setNumber("$fs".ptr, 2.0);
        setNumber("$fn".ptr, 0.0);
        setNumber("$t".ptr, 0.0);
        setNumber("$vpd".ptr, 500.0);
        setNumber("$vpf".ptr, 22.5);
        setNumber("$children".ptr, 0.0);
        setBoolean("$preview".ptr, true);
        double[3] zeros = [0.0, 0.0, 0.0];
        setList("$vpr".ptr, zeros.ptr, 3);
        setList("$vpt".ptr, zeros.ptr, 3);
    }

    ScriptVariable* find(const(char)* name) nothrow @nogc
    {
        if (name is null)
            return null;
        foreach (i; 0 .. variableCount)
            if (variables[i].name.equals(name))
                return &variables[i];
        return null;
    }

    const(ScriptVariable)* findConst(const(char)* name) const nothrow @nogc
    {
        if (name is null)
            return null;
        foreach (i; 0 .. variableCount)
            if (variables[i].name.equals(name))
                return &variables[i];
        return null;
    }

    ScriptVariable* ensure(const(char)* name) nothrow @nogc
    {
        auto existing = find(name);
        if (existing !is null)
            return existing;
        if (name is null || variableCount >= variables.length)
            return null;
        auto slot = &variables[variableCount++];
        slot.name.set(name);
        slot.value.clear();
        return slot;
    }

    bool set(const(char)* name, ScriptValue value) nothrow @nogc
    {
        auto slot = ensure(name);
        if (slot is null)
            return false;
        slot.value = value;
        return true;
    }

    bool setNumber(const(char)* name, double value) nothrow @nogc
    {
        return set(name, ScriptValue.fromNumber(value));
    }

    bool setBoolean(const(char)* name, bool value) nothrow @nogc
    {
        return set(name, ScriptValue.fromBoolean(value));
    }

    bool setString(const(char)* name, const(char)* value) nothrow @nogc
    {
        return set(name, ScriptValue.fromString(value));
    }

    bool setList(const(char)* name, const(double)* values, uint count) nothrow @nogc
    {
        if (values is null || count > WC_SCRIPT_MAX_LIST_VALUES)
            return false;
        ScriptValue result;
        result.clear();
        result.kind = ScriptValueKind.list;
        result.listCount = count;
        foreach (i; 0 .. count)
            result.listValues[i] = values[i];
        return set(name, result);
    }

    ScriptCallable* findCallable(const(char)* name) nothrow @nogc
    {
        if (name is null)
            return null;
        foreach (i; 0 .. callableCount)
            if (callables[i].name.equals(name))
                return &callables[i];
        return null;
    }

    bool defineCallable(const(char)* name, ScriptCallableKind kind, ubyte argumentCount,
                        const(char)* scriptBody) nothrow @nogc
    {
        if (name is null || scriptBody is null)
            return false;
        auto existing = findCallable(name);
        ScriptCallable* slot = existing;
        if (slot is null)
        {
            if (callableCount >= callables.length)
                return false;
            slot = &callables[callableCount++];
            slot.name.set(name);
        }
        slot.kind = kind;
        slot.argumentCount = argumentCount;
        slot.scriptBody.set(scriptBody);
        return true;
    }


    bool pushCall(const(char)* name) nothrow @nogc
    {
        if (name is null || callDepth >= WC_SCRIPT_MAX_CALL_DEPTH)
            return false;
        callStack[callDepth++].set(name);
        return true;
    }

    void popCall() nothrow @nogc
    {
        if (callDepth == 0)
            return;
        --callDepth;
        callStack[callDepth].clear();
    }

    const(char)* parentCall(uint index) const nothrow @nogc
    {
        if (callDepth <= index + 1)
            return null;
        return callStack[callDepth - index - 2].ptr();
    }

    ulong nextRandom() nothrow @nogc
    {
        // xorshift64*; deterministic unless a script explicitly supplies a seed.
        auto x = randomState;
        x ^= x >> 12;
        x ^= x << 25;
        x ^= x >> 27;
        randomState = x;
        return x * 2685821657736338717UL;
    }
}



