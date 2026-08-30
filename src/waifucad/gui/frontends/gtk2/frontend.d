module waifucad.gui.frontends.gtk2.frontend;

import waifucad.gui.api : GuiFrontendV1, WC_GUI_FRONTEND_ABI_V1;

// Descriptor stub.  Native bridge implementation is intentionally target-specific.
GuiFrontendV1 gtk2Descriptor() nothrow @nogc
{
    GuiFrontendV1 result;
    result.abiVersion = WC_GUI_FRONTEND_ABI_V1;
    result.id = "gtk2".ptr;
    result.displayName = "GTK2".ptr;
    return result;
}



