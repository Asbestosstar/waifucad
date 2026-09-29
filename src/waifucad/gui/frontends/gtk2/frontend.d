module waifucad.gui.frontends.gtk2.frontend;

import waifucad.gui.api : GuiFrontendV1, guiFrontendDescriptor;

/* Descriptor stub. The native bridge implementation is intentionally
 * target-specific. When this front-end is implemented, it should bind the
 * shared toolkit-neutral core (waifucad.gui.frontends.common.frontend) exactly
 * like the Cocoa and GTK4 front-ends, so behavioural fixes propagate. */
GuiFrontendV1 gtk2Descriptor() nothrow @nogc
{
    return guiFrontendDescriptor("gtk2".ptr, "GTK2".ptr);
}
