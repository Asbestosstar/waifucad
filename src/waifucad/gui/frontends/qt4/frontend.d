module waifucad.gui.frontends.qt4.frontend;

import waifucad.gui.api : GuiFrontendV1, WC_GUI_FRONTEND_ABI_V1;

// Descriptor stub.  Native bridge implementation is intentionally target-specific.
GuiFrontendV1 qt4Descriptor() nothrow @nogc
{
    GuiFrontendV1 result;
    result.abiVersion = WC_GUI_FRONTEND_ABI_V1;
    result.id = "qt4".ptr;
    result.displayName = "QT4".ptr;
    return result;
}



