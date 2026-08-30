module waifucad.scl.ruby_syntax;

import core.stdc.string : strcmp, strlen;
import waifucad.scl.tokenise : Tokens, tokenise;

enum WC_SCL_LINE = 4096;

private bool appendCharacter(char* output, size_t capacity, size_t* used, char value) nothrow @nogc
{
    if (output is null || used is null || *used + 1 >= capacity)
        return false;
    output[*used] = value;
    *used = *used + 1;
    output[*used] = 0;
    return true;
}

private bool appendText(char* output, size_t capacity, size_t* used, const(char)* text) nothrow @nogc
{
    if (text is null)
        return false;
    for (size_t i = 0; text[i] != 0; ++i)
        if (!appendCharacter(output, capacity, used, text[i]))
            return false;
    return true;
}

private bool appendSpan(char* output, size_t capacity, size_t* used,
                        const(char)* text, size_t length) nothrow @nogc
{
    if (text is null)
        return false;
    foreach (i; 0 .. length)
        if (!appendCharacter(output, capacity, used, text[i]))
            return false;
    return true;
}

private bool appendSeparator(char* output, size_t capacity, size_t* used) nothrow @nogc
{
    if (*used == 0 || output[*used - 1] == ' ')
        return true;
    return appendCharacter(output, capacity, used, ' ');
}

private bool appendQuoted(char* output, size_t capacity, size_t* used, const(char)* text) nothrow @nogc
{
    if (!appendCharacter(output, capacity, used, '"'))
        return false;
    for (size_t i = 0; text[i] != 0; ++i)
    {
        if (text[i] == '"' || text[i] == '\\')
            if (!appendCharacter(output, capacity, used, '\\'))
                return false;
        if (!appendCharacter(output, capacity, used, text[i]))
            return false;
    }
    return appendCharacter(output, capacity, used, '"');
}

private bool isNumericPrefix(const(char)* token, size_t length) nothrow @nogc
{
    if (token is null || length == 0)
        return false;
    size_t i = 0;
    if (token[i] == '+' || token[i] == '-')
        ++i;
    bool hasDigit = false;
    while (i < length && token[i] >= '0' && token[i] <= '9')
    {
        hasDigit = true;
        ++i;
    }
    if (i < length && token[i] == '.')
    {
        ++i;
        while (i < length && token[i] >= '0' && token[i] <= '9')
        {
            hasDigit = true;
            ++i;
        }
    }
    if (!hasDigit)
        return false;
    if (i < length && (token[i] == 'e' || token[i] == 'E'))
    {
        ++i;
        if (i < length && (token[i] == '+' || token[i] == '-'))
            ++i;
        bool exponentDigit = false;
        while (i < length && token[i] >= '0' && token[i] <= '9')
        {
            exponentDigit = true;
            ++i;
        }
        if (!exponentDigit)
            return false;
    }
    return i == length;
}

private bool numericUnitSuffix(const(char)* token, const(char)** unit, size_t* numericLength) nothrow @nogc
{
    if (token is null || unit is null || numericLength is null)
        return false;
    auto length = strlen(token);
    size_t suffixLength = 0;
    const(char)* suffix = null;
    if (length > 3 && token[length - 3] == '.' && token[length - 2] == 'm' && token[length - 1] == 'm')
    {
        suffix = "mm".ptr;
        suffixLength = 3;
    }
    else if (length > 4 && token[length - 4] == '.' && token[length - 3] == 'd' &&
             token[length - 2] == 'e' && token[length - 1] == 'g')
    {
        suffix = "deg".ptr;
        suffixLength = 4;
    }
    else
        return false;

    auto prefixLength = length - suffixLength;
    if (!isNumericPrefix(token, prefixLength))
        return false;

    *unit = suffix;
    *numericLength = prefixLength;
    return true;
}

private bool isGetterName(const(char)* command) nothrow @nogc
{
    return command !is null && strlen(command) >= 4 && command[0] == 'g' &&
           command[1] == 'e' && command[2] == 't' && command[3] == '_';
}

private const(char)* commandAlias(const(char)* command) nothrow @nogc
{
    if (strcmp(command, "puts".ptr) == 0) return "echo".ptr;
    if (strcmp(command, "load".ptr) == 0) return "include".ptr;
    if (strcmp(command, "require".ptr) == 0) return "use".ptr;
    if (strcmp(command, "def".ptr) == 0) return "function".ptr;
    if (strcmp(command, "end".ptr) == 0) return "end_sketch".ptr;
    return command;
}

private bool emitToken(Tokens* tokens, size_t index, char* output, size_t capacity,
                       size_t* used, bool stripNumericUnit = true) nothrow @nogc
{
    if (tokens is null || index >= tokens.count)
        return false;
    if (!appendSeparator(output, capacity, used))
        return false;

    auto token = tokens.values[index];
    if (tokens.quoted[index])
        return appendQuoted(output, capacity, used, token);

    if (strcmp(token, "nil".ptr) == 0)
        return appendText(output, capacity, used, "undef".ptr);

    if (token[0] == ':' && token[1] != 0)
        ++token;

    const(char)* unit = null;
    size_t numericLength = 0;
    if (stripNumericUnit && numericUnitSuffix(token, &unit, &numericLength))
        return appendSpan(output, capacity, used, token, numericLength);

    return appendText(output, capacity, used, token);
}

private bool lexRubyPunctuation(const(char)* input, char* output, size_t capacity) nothrow @nogc
{
    if (input is null || output is null || capacity == 0)
        return false;
    size_t used = 0;
    output[0] = 0;
    char quote = 0;
    for (size_t i = 0; input[i] != 0; ++i)
    {
        char value = input[i];
        if (quote != 0)
        {
            if (!appendCharacter(output, capacity, &used, value))
                return false;
            if (value == '\\' && input[i + 1] != 0)
            {
                ++i;
                if (!appendCharacter(output, capacity, &used, input[i]))
                    return false;
            }
            else if (value == quote)
                quote = 0;
            continue;
        }

        if (value == '"' || value == '\'')
        {
            quote = value;
            if (!appendCharacter(output, capacity, &used, value))
                return false;
            continue;
        }
        if (value == '#')
            break;
        if (value == '(' || value == ')' || value == ',')
            value = ' ';
        else if (value == '=')
        {
            char previous = i == 0 ? '\0' : input[i - 1];
            char next = input[i + 1];
            if (previous != '=' && previous != '!' && previous != '<' && previous != '>' && next != '=')
            {
                if (!appendCharacter(output, capacity, &used, ' ') ||
                    !appendCharacter(output, capacity, &used, '=') ||
                    !appendCharacter(output, capacity, &used, ' '))
                    return false;
                continue;
            }
        }
        if (!appendCharacter(output, capacity, &used, value))
            return false;
    }
    return true;
}

private bool splitInclusiveRange(const(char)* token, const(char)** right, size_t* leftLength) nothrow @nogc
{
    if (token is null || right is null || leftLength is null)
        return false;
    for (size_t i = 1; token[i] != 0 && token[i + 1] != 0; ++i)
    {
        if (token[i] == '.' && token[i + 1] == '.' && token[i - 1] != '.' && token[i + 2] != '.')
        {
            *leftLength = i;
            *right = token + i + 2;
            return i != 0 && **right != 0;
        }
    }
    return false;
}

/*
 * Convert Ruby-style SCL surface syntax to the original deterministic command
 * form.  This is syntax sugar only: execution still routes through the normal
 * SCL transaction/journal interpreter and never writes kernel memory directly.
 * The historical whitespace command form is retained for .scl migration and
 * journal compatibility; shipped .wcs source uses the Ruby-like surface.
 */
bool normaliseRubyStyleLine(const(char)* input, char* output, size_t capacity) nothrow @nogc
{
    if (input is null || output is null || capacity == 0)
        return false;

    char[WC_SCL_LINE] scratch;
    if (!lexRubyPunctuation(input, scratch.ptr, scratch.length))
        return false;
    auto tokens = tokenise(scratch.ptr);
    if (tokens.count == 0)
    {
        output[0] = 0;
        return true;
    }

    size_t used = 0;
    output[0] = 0;
    auto command = commandAlias(tokens.values[0]);

    // Ruby-style getter return assignment: kind = get_feature_kind(:body).
    // Internally getters keep the deterministic SCL `COMMAND OUT ...` ABI.
    if (tokens.count >= 3 && strcmp(tokens.values[1], "=".ptr) == 0 && isGetterName(tokens.values[2]))
    {
        if (!appendText(output, capacity, &used, tokens.values[2]) ||
            !emitToken(&tokens, 0, output, capacity, &used))
            return false;
        foreach (i; 3 .. tokens.count)
            if (!emitToken(&tokens, i, output, capacity, &used))
                return false;
        return true;
    }

    // Ruby-style variable assignment: width = 80
    if (tokens.count >= 3 && strcmp(tokens.values[1], "=".ptr) == 0 &&
        strcmp(command, "param".ptr) != 0 && strcmp(command, "set".ptr) != 0 &&
        strcmp(command, "var".ptr) != 0 && strcmp(command, "let_value".ptr) != 0)
    {
        if (!appendText(output, capacity, &used, "var".ptr) ||
            !emitToken(&tokens, 0, output, capacity, &used))
            return false;
        foreach (i; 2 .. tokens.count)
            if (!emitToken(&tokens, i, output, capacity, &used))
                return false;
        return true;
    }

    // Ruby-style inclusive range loop: for i in 0..10 do COMMAND end
    if (strcmp(command, "for".ptr) == 0 && tokens.count >= 6 &&
        strcmp(tokens.values[2], "in".ptr) == 0)
    {
        const(char)* rangeRight = null;
        size_t rangeLeftLength = 0;
        if (splitInclusiveRange(tokens.values[3], &rangeRight, &rangeLeftLength))
        {
            if (!appendText(output, capacity, &used, "for".ptr) ||
                !emitToken(&tokens, 1, output, capacity, &used) ||
                !appendSeparator(output, capacity, &used) ||
                !appendSpan(output, capacity, &used, tokens.values[3], rangeLeftLength) ||
                !appendSeparator(output, capacity, &used) ||
                !appendText(output, capacity, &used, "1".ptr) ||
                !appendSeparator(output, capacity, &used) ||
                !appendText(output, capacity, &used, rangeRight))
                return false;
            size_t firstCommand = 4;
            if (firstCommand < tokens.count && strcmp(tokens.values[firstCommand], "do".ptr) == 0)
                ++firstCommand;
            size_t commandEnd = tokens.count;
            if (commandEnd > firstCommand && strcmp(tokens.values[commandEnd - 1], "end".ptr) == 0)
                --commandEnd;
            foreach (i; firstCommand .. commandEnd)
                if (!emitToken(&tokens, i, output, capacity, &used))
                    return false;
            return true;
        }
    }

    if (!appendText(output, capacity, &used, command))
        return false;

    // param(:width, 80.mm) and param width = 80.mm
    if (strcmp(command, "param".ptr) == 0 && tokens.count >= 3)
    {
        if (!emitToken(&tokens, 1, output, capacity, &used))
            return false;
        size_t valueIndex = 2;
        if (strcmp(tokens.values[valueIndex], "=".ptr) == 0)
        {
            ++valueIndex;
            if (valueIndex >= tokens.count)
                return false;
        }
        const(char)* unit = null;
        size_t numericLength = 0;
        bool hasSuffix = !tokens.quoted[valueIndex] &&
                         numericUnitSuffix(tokens.values[valueIndex], &unit, &numericLength);
        if (!emitToken(&tokens, valueIndex, output, capacity, &used))
            return false;
        if (hasSuffix)
        {
            if (!appendSeparator(output, capacity, &used) || !appendText(output, capacity, &used, unit))
                return false;
            ++valueIndex;
        }
        else
            ++valueIndex;
        foreach (i; valueIndex .. tokens.count)
            if (!emitToken(&tokens, i, output, capacity, &used, false))
                return false;
        return true;
    }

    // set(:width, 96) / set width = 96, plus var/let_value assignment spelling.
    if ((strcmp(command, "set".ptr) == 0 || strcmp(command, "var".ptr) == 0 ||
         strcmp(command, "let_value".ptr) == 0) && tokens.count >= 3)
    {
        if (!emitToken(&tokens, 1, output, capacity, &used))
            return false;
        size_t valueIndex = 2;
        if (strcmp(tokens.values[valueIndex], "=".ptr) == 0)
            ++valueIndex;
        foreach (i; valueIndex .. tokens.count)
            if (!emitToken(&tokens, i, output, capacity, &used))
                return false;
        return true;
    }

    // One-line Ruby flow form: if condition then COMMAND end
    if (strcmp(command, "if".ptr) == 0 && tokens.count >= 3)
    {
        if (!emitToken(&tokens, 1, output, capacity, &used))
            return false;
        size_t firstCommand = 2;
        if (strcmp(tokens.values[firstCommand], "then".ptr) == 0)
            ++firstCommand;
        size_t commandEnd = tokens.count;
        if (commandEnd > firstCommand && strcmp(tokens.values[commandEnd - 1], "end".ptr) == 0)
            --commandEnd;
        foreach (i; firstCommand .. commandEnd)
            if (!emitToken(&tokens, i, output, capacity, &used))
                return false;
        return true;
    }

    foreach (i; 1 .. tokens.count)
        if (!emitToken(&tokens, i, output, capacity, &used))
            return false;
    return true;
}


