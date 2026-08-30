module waifucad.gui.frontends.gtk3.frontend;

import waifucad.gui.api : GuiFrontendV1, WC_GUI_FRONTEND_ABI_V1;

// Descriptor stub.  Native bridge implementation is intentionally target-specific.
GuiFrontendV1 gtk3Descriptor() nothrow @nogc
{
    GuiFrontendV1 result;
    result.abiVersion = WC_GUI_FRONTEND_ABI_V1;
    result.id = "gtk3".ptr;
    result.displayName = "GTK3".ptr;
    return result;
}



