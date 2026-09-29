module waifucad.gui.frontends.qt4.frontend;

import waifucad.gui.api : GuiFrontendV1, guiFrontendDescriptor;

/* Descriptor stub. The native bridge implementation is intentionally
 * target-specific. When this front-end is implemented, it should bind the
 * shared toolkit-neutral core (waifucad.gui.frontends.common.frontend) exactly
 * like the Cocoa and GTK4 front-ends, so behavioural fixes propagate. */
GuiFrontendV1 qt4Descriptor() nothrow @nogc
{
    return guiFrontendDescriptor("qt4".ptr, "QT4".ptr);
}
