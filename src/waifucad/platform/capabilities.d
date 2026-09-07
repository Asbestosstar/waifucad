module waifucad.platform.capabilities;

enum GuiFamily : ubyte
{
    none, gtk1, gtk2, gtk3, gtk4, qt2, qt3, qt4, qt5, qt6, motif, xlib, cocoa
}

enum GraphicsFamily : ubyte
{
    none, vulkan, metal, opengl
}

struct RuntimeCapabilities
{
    bool hasDisplay;
    bool hasGtk1;
    bool hasGtk2;
    bool hasGtk3;
    bool hasGtk4;
    bool hasQt2;
    bool hasQt3;
    bool hasQt4;
    bool hasQt5;
    bool hasQt6;
    bool hasMotif;
    bool hasXlib;
    bool hasCocoa;

    bool hasDedicatedGpu;
    bool hasVulkanLoader;
    bool hasVulkanHardwareDevice;
    bool hasMetal;
    bool hasOpenGl;
    bool vulkanIsSoftwareOnly;
}



