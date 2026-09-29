module waifucad.gui.selector;

import waifucad.platform.capabilities : RuntimeCapabilities, GuiFamily;
import waifucad.platform.target : OsFamily;
import waifucad.gui.registry : guiFrontendRegistry;

/* The preference order is data-driven: waifucad.gui.registry holds the single
 * generic modern-to-legacy table, and this selector simply walks it. A
 * target-specific policy may narrow the choice before runtime probing.
 * Solaris policy permits GTK4 first, with older toolkit fallbacks retained
 * for machines that do not provide it. */
GuiFamily chooseGui(const RuntimeCapabilities* caps) nothrow @nogc
{
    if (caps is null || !caps.hasDisplay) return GuiFamily.none;
    foreach (ref entry; guiFrontendRegistry)
        if (entry.supported !is null && entry.supported(caps))
            return entry.family;
    return GuiFamily.none;
}

/* Target-specific narrowing. macOS uses its native Cocoa/AppKit front-end by
 * default; GTK4 there is an optional fallback and never a requirement, so it
 * only wins when no Cocoa bridge is present. Other OS families keep the
 * generic modern-to-legacy order from the registry. */
GuiFamily chooseGuiForTarget(OsFamily os, const RuntimeCapabilities* caps) nothrow @nogc
{
    if (os == OsFamily.macos && caps !is null && caps.hasDisplay && caps.hasCocoa)
        return GuiFamily.cocoa;
    return chooseGui(caps);
}
