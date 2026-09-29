/* Graphics back-end registry.
 *
 * This is the single ordered list of known graphics back-ends. The selector
 * (waifucad.graphics.selector) walks this table in order and picks the first
 * back-end the runtime capabilities support, so the preference policy lives
 * in exactly one place.
 *
 * The policy prefers real hardware over API fashion: software Vulkan does not
 * automatically beat a dedicated GPU that only exposes OpenGL. That is why
 * Vulkan appears twice — hardware first, software (lavapipe) as a fallback.
 *
 * Adding a new graphics back-end is a three-step change:
 *   1. add the family to GraphicsFamily and capability flags in
 *      waifucad.platform.capabilities;
 *   2. add one row here with its availability predicate (position encodes
 *      preference);
 *   3. teach the native viewport bridges to consume the new renderer hint.
 */
module waifucad.graphics.registry;

import waifucad.platform.capabilities : RuntimeCapabilities, GraphicsFamily;

alias GraphicsSupportFn = bool function(const(RuntimeCapabilities)*) nothrow @nogc;

struct GraphicsBackendInfo
{
    GraphicsFamily family;
    const(char)* id;
    const(char)* displayName;
    GraphicsSupportFn supported;
}

private bool hasMetal(const RuntimeCapabilities* caps) nothrow @nogc { return caps.hasMetal; }
private bool hasVulkanHardware(const RuntimeCapabilities* caps) nothrow @nogc
{
    return caps.hasVulkanLoader && caps.hasVulkanHardwareDevice;
}
private bool hasDedicatedOpenGl(const RuntimeCapabilities* caps) nothrow @nogc
{
    return caps.hasDedicatedGpu && caps.hasOpenGl;
}
private bool hasVulkanSoftware(const RuntimeCapabilities* caps) nothrow @nogc
{
    return caps.hasVulkanLoader && caps.vulkanIsSoftwareOnly;
}
private bool hasOpenGl(const RuntimeCapabilities* caps) nothrow @nogc { return caps.hasOpenGl; }

__gshared const GraphicsBackendInfo[5] graphicsBackendRegistry = [
    GraphicsBackendInfo(GraphicsFamily.metal,  "metal".ptr,           "Metal".ptr,            &hasMetal),
    GraphicsBackendInfo(GraphicsFamily.vulkan, "vulkan".ptr,          "Vulkan".ptr,           &hasVulkanHardware),
    GraphicsBackendInfo(GraphicsFamily.opengl, "opengl".ptr,          "OpenGL".ptr,           &hasDedicatedOpenGl),
    GraphicsBackendInfo(GraphicsFamily.vulkan, "vulkan-software".ptr, "Vulkan (lavapipe)".ptr, &hasVulkanSoftware),
    GraphicsBackendInfo(GraphicsFamily.opengl, "opengl".ptr,          "OpenGL".ptr,           &hasOpenGl),
];

const(GraphicsBackendInfo)* graphicsBackendInfoFor(GraphicsFamily family) nothrow @nogc
{
    foreach (ref entry; graphicsBackendRegistry)
        if (entry.family == family)
            return &entry;
    return null;
}
