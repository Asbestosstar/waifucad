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



