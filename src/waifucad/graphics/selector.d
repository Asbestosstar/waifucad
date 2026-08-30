module waifucad.graphics.selector;

import waifucad.platform.capabilities : RuntimeCapabilities, GraphicsFamily;

// Prefer real hardware over API fashion.  Software Vulkan does not automatically
// beat a dedicated GPU that only exposes OpenGL.
GraphicsFamily chooseGraphics(const RuntimeCapabilities* caps) nothrow @nogc
{
    if (caps is null)
        return GraphicsFamily.none;

    if (caps.hasMetal)
        return GraphicsFamily.metal;

    if (caps.hasVulkanLoader && caps.hasVulkanHardwareDevice)
        return GraphicsFamily.vulkan;

    if (caps.hasDedicatedGpu && caps.hasOpenGl)
        return GraphicsFamily.opengl;

    if (caps.hasVulkanLoader && caps.vulkanIsSoftwareOnly)
        return GraphicsFamily.vulkan;

    if (caps.hasOpenGl)
        return GraphicsFamily.opengl;

    return GraphicsFamily.none;
}



