module waifucad.scl.tokenise;

import core.stdc.ctype : isspace;

struct Tokens
{
    char*[64] values;
    bool[64] quoted;
    size_t count;
}

/*
 * Allocation-free SCL tokeniser. Quoted strings are kept as one token and the
 * surrounding quote marks are removed in place. Backslash escapes are copied
 * in place so file names and text payloads remain useful to scripting code.
 */
Tokens tokenise(char* line) nothrow @nogc
{
    Tokens result;
    if (line is null)
        return result;

    char* cursor = line;
    while (*cursor != 0 && result.count < result.values.length)
    {
        while (*cursor != 0 && isspace(cast(ubyte)*cursor))
        {
            *cursor = 0;
            ++cursor;
        }
        if (*cursor == 0 || *cursor == '#')
            break;

        if (*cursor == '"' || *cursor == '\'')
        {
            auto quote = *cursor;
            ++cursor;
            auto destination = cursor;
            result.values[result.count] = destination;
            result.quoted[result.count] = true;
            ++result.count;
            while (*cursor != 0 && *cursor != quote)
            {
                if (*cursor == '\\' && cursor[1] != 0)
                    ++cursor;
                *destination++ = *cursor++;
            }
            /* Step over the closing quote before NUL-terminating: with no
               escapes destination sits on the quote itself, and writing the
               terminator first would hide it and end the line early. */
            if (*cursor == quote)
                ++cursor;
            *destination = 0;
            continue;
        }

        result.values[result.count++] = cursor;
        while (*cursor != 0 && !isspace(cast(ubyte)*cursor))
            ++cursor;
    }
    return result;
}



