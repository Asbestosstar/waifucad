module waifucad.graphics.selector;

import waifucad.platform.capabilities : RuntimeCapabilities, GraphicsFamily;
import waifucad.graphics.registry : graphicsBackendRegistry;

/* The preference order is data-driven: waifucad.graphics.registry holds the
 * single ordered back-end table, and this selector simply walks it. The
 * policy prefers real hardware over API fashion; software Vulkan does not
 * automatically beat a dedicated GPU that only exposes OpenGL. */
GraphicsFamily chooseGraphics(const RuntimeCapabilities* caps) nothrow @nogc
{
    if (caps is null)
        return GraphicsFamily.none;

    foreach (ref entry; graphicsBackendRegistry)
        if (entry.supported !is null && entry.supported(caps))
            return entry.family;

    return GraphicsFamily.none;
}
