module waifucad.core.log;

import core.stdc.stdio : fprintf, stderr;

extern(C) void wcLogInfo(const(char)* message) nothrow @nogc
{
    if (message !is null)
        fprintf(stderr, "[WaifuCAD] %s\n", message);
}

extern(C) void wcLogError(const(char)* message) nothrow @nogc
{
    if (message !is null)
        fprintf(stderr, "[WaifuCAD:error] %s\n", message);
}



