module waifucad.gui.selector;

import waifucad.platform.capabilities : RuntimeCapabilities, GuiFamily;
import waifucad.platform.target : OsFamily;

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

/* Target-specific narrowing. macOS uses its native Cocoa/AppKit front-end by
 * default; GTK4 there is an optional fallback and never a requirement, so it
 * only wins when no Cocoa bridge is present. Other OS families keep the
 * generic modern-to-legacy order. */
GuiFamily chooseGuiForTarget(OsFamily os, const RuntimeCapabilities* caps) nothrow @nogc
{
    if (os == OsFamily.macos && caps !is null && caps.hasDisplay && caps.hasCocoa)
        return GuiFamily.cocoa;
    return chooseGui(caps);
}



