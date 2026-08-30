module waifucad.gui.selector;

import waifucad.platform.capabilities : RuntimeCapabilities, GuiFamily;

// This is the generic modern-to-legacy order. A target-specific policy may
// narrow it before runtime probing. Solaris policy permits GTK4 first, with
// older toolkit fallbacks retained for machines that do not provide it.
GuiFamily chooseGui(const RuntimeCapabilities* caps) nothrow @nogc
{
    if (caps is null || !caps.hasDisplay) return GuiFamily.none;
    if (caps.hasGtk4) return GuiFamily.gtk4;
    if (caps.hasQt6) return GuiFamily.qt6;
    if (caps.hasGtk3) return GuiFamily.gtk3;
    if (caps.hasQt5) return GuiFamily.qt5;
    if (caps.hasQt4) return GuiFamily.qt4;
    if (caps.hasGtk2) return GuiFamily.gtk2;
    if (caps.hasQt3) return GuiFamily.qt3;
    if (caps.hasGtk1) return GuiFamily.gtk1;
    if (caps.hasQt2) return GuiFamily.qt2;
    if (caps.hasMotif) return GuiFamily.motif;
    if (caps.hasXlib) return GuiFamily.xlib;
    return GuiFamily.none;
}



