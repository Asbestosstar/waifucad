module waifucad.gui.api;

enum WC_GUI_FRONTEND_ABI_V1 = 1u;

struct GuiWindowConfig
{
    int width;
    int height;
    const(char)* title;
    const(char)* themeId;
}

extern(C) alias GuiCreateWindowFn = int function(const GuiWindowConfig*) nothrow @nogc;
extern(C) alias GuiRunEventLoopFn = int function() nothrow @nogc;
extern(C) alias GuiDestroyWindowFn = void function() nothrow @nogc;

struct GuiFrontendV1
{
    uint abiVersion;
    const(char)* id;
    const(char)* displayName;
    GuiCreateWindowFn createWindow;
    GuiRunEventLoopFn runEventLoop;
    GuiDestroyWindowFn destroyWindow;
}

/* Single construction point for front-end descriptors. Stub front-ends (whose
 * native bridge is target-specific and not yet landed) call this with only an
 * id and display name; full front-ends attach their native entry points on top.
 * Centralising the ABI version here means a future ABI bump touches one file. */
GuiFrontendV1 guiFrontendDescriptor(const(char)* id, const(char)* displayName) nothrow @nogc
{
    GuiFrontendV1 result;
    result.abiVersion = WC_GUI_FRONTEND_ABI_V1;
    result.id = id;
    result.displayName = displayName;
    return result;
}



