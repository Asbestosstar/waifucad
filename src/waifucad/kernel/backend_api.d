module waifucad.kernel.backend_api;

import waifucad.kernel.model : Model;

enum WC_GEOMETRY_ABI_V1 = 1u;

extern(C) alias GeometryRecomputeFn = int function(Model*) nothrow @nogc;

// Geometry back-ends may be D BetterC, C or C++ behind an extern(C) bridge.
struct GeometryBackendV1
{
    uint abiVersion;
    const(char)* name;
    GeometryRecomputeFn recompute;
}



