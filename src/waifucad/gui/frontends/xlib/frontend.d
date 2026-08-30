module waifucad.gui.frontends.xlib.frontend;

import waifucad.gui.api : GuiFrontendV1, WC_GUI_FRONTEND_ABI_V1;

// Descriptor stub.  Native bridge implementation is intentionally target-specific.
GuiFrontendV1 xlibDescriptor() nothrow @nogc
{
    GuiFrontendV1 result;
    result.abiVersion = WC_GUI_FRONTEND_ABI_V1;
    result.id = "xlib".ptr;
    result.displayName = "Xlib / X Basic".ptr;
    return result;
}



