/* GUI front-end registry.
 *
 * This is the single ordered list of known GUI front-ends. The selector
 * (waifucad.gui.selector) walks this table in order and picks the first
 * front-end the runtime capabilities support, so the modern-to-legacy
 * preference order lives in exactly one place.
 *
 * Adding a new front-end family is a three-step change:
 *   1. add the family to GuiFamily and a capability flag in
 *      waifucad.platform.capabilities;
 *   2. add one row here with its availability predicate;
 *   3. bind the shared front-end core
 *      (waifucad.gui.frontends.common.frontend) in a new module under
 *      src/waifucad/gui/frontends/<id>/, exactly like the Cocoa and GTK4
 *      thin wrappers.
 */
module waifucad.gui.registry;

import waifucad.platform.capabilities : RuntimeCapabilities, GuiFamily;

alias GuiSupportFn = bool function(const(RuntimeCapabilities)*) nothrow @nogc;

struct GuiFrontendInfo
{
    GuiFamily family;
    const(char)* id;
    const(char)* displayName;
    GuiSupportFn supported;
}

private bool hasCocoa(const RuntimeCapabilities* caps) nothrow @nogc { return caps.hasCocoa; }
private bool hasGtk4(const RuntimeCapabilities* caps) nothrow @nogc { return caps.hasGtk4; }
private bool hasQt6(const RuntimeCapabilities* caps) nothrow @nogc { return caps.hasQt6; }
private bool hasGtk3(const RuntimeCapabilities* caps) nothrow @nogc { return caps.hasGtk3; }
private bool hasQt5(const RuntimeCapabilities* caps) nothrow @nogc { return caps.hasQt5; }
private bool hasQt4(const RuntimeCapabilities* caps) nothrow @nogc { return caps.hasQt4; }
private bool hasGtk2(const RuntimeCapabilities* caps) nothrow @nogc { return caps.hasGtk2; }
private bool hasQt3(const RuntimeCapabilities* caps) nothrow @nogc { return caps.hasQt3; }
private bool hasGtk1(const RuntimeCapabilities* caps) nothrow @nogc { return caps.hasGtk1; }
private bool hasQt2(const RuntimeCapabilities* caps) nothrow @nogc { return caps.hasQt2; }
private bool hasMotif(const RuntimeCapabilities* caps) nothrow @nogc { return caps.hasMotif; }
private bool hasXlib(const RuntimeCapabilities* caps) nothrow @nogc { return caps.hasXlib; }

/* Generic modern-to-legacy preference order. A target-specific policy may
 * narrow this before runtime probing (see chooseGuiForTarget); macOS keeps
 * its native Cocoa front-end first through that narrowing, so Cocoa sits at
 * the end of the generic order and only wins elsewhere when nothing else is
 * present. */
__gshared const GuiFrontendInfo[12] guiFrontendRegistry = [
    GuiFrontendInfo(GuiFamily.gtk4,  "gtk4".ptr,  "GTK4".ptr,           &hasGtk4),
    GuiFrontendInfo(GuiFamily.qt6,   "qt6".ptr,   "QT6".ptr,            &hasQt6),
    GuiFrontendInfo(GuiFamily.gtk3,  "gtk3".ptr,  "GTK3".ptr,           &hasGtk3),
    GuiFrontendInfo(GuiFamily.qt5,   "qt5".ptr,   "QT5".ptr,            &hasQt5),
    GuiFrontendInfo(GuiFamily.qt4,   "qt4".ptr,   "QT4".ptr,            &hasQt4),
    GuiFrontendInfo(GuiFamily.gtk2,  "gtk2".ptr,  "GTK2".ptr,           &hasGtk2),
    GuiFrontendInfo(GuiFamily.qt3,   "qt3".ptr,   "QT3".ptr,            &hasQt3),
    GuiFrontendInfo(GuiFamily.gtk1,  "gtk1".ptr,  "GTK1".ptr,           &hasGtk1),
    GuiFrontendInfo(GuiFamily.qt2,   "qt2".ptr,   "QT2".ptr,            &hasQt2),
    GuiFrontendInfo(GuiFamily.motif, "motif".ptr, "Motif".ptr,          &hasMotif),
    GuiFrontendInfo(GuiFamily.xlib,  "xlib".ptr,  "Xlib / X Basic".ptr, &hasXlib),
    GuiFrontendInfo(GuiFamily.cocoa, "cocoa".ptr, "Cocoa / AppKit".ptr, &hasCocoa),
];

const(GuiFrontendInfo)* guiFrontendInfoFor(GuiFamily family) nothrow @nogc
{
    foreach (ref entry; guiFrontendRegistry)
        if (entry.family == family)
            return &entry;
    return null;
}
