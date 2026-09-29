module waifucad.gui.frontends.qt6.frontend;

import waifucad.gui.api : GuiFrontendV1, guiFrontendDescriptor;

/* Descriptor stub. The native bridge implementation is intentionally
 * target-specific. When this front-end is implemented, it should bind the
 * shared toolkit-neutral core (waifucad.gui.frontends.common.frontend) exactly
 * like the Cocoa and GTK4 front-ends, so behavioural fixes propagate. */
GuiFrontendV1 qt6Descriptor() nothrow @nogc
{
    return guiFrontendDescriptor("qt6".ptr, "QT6".ptr);
}
