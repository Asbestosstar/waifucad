module waifucad.graphics.api;

import waifucad.platform.capabilities : GraphicsFamily;

enum WC_GRAPHICS_BACKEND_ABI_V1 = 1u;

extern(C) alias GraphicsInitialiseFn = int function(void*) nothrow @nogc;
extern(C) alias GraphicsBeginFrameFn = void function(float, float, float, float) nothrow @nogc;
extern(C) alias GraphicsEndFrameFn = void function() nothrow @nogc;
extern(C) alias GraphicsShutDownFn = void function() nothrow @nogc;

struct GraphicsBackendV1
{
    uint abiVersion;
    const(char)* id;
    GraphicsFamily family;
    GraphicsInitialiseFn initialise;
    GraphicsBeginFrameFn beginFrame;
    GraphicsEndFrameFn endFrame;
    GraphicsShutDownFn shutDown;
}



