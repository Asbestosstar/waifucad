module waifucad.sections.ribbon;


/*
 * Ribbons are data, not toolkit widgets.  GTK/Qt/Motif/Xlib front-ends render
 * the same descriptors, which keeps Section behaviour independent of GUI ABI.
 */
enum RibbonCommandFlags : uint
{
    none = 0,
    toggle = 1u << 0,
    requiresDocument = 1u << 1,
    requiresSelection = 1u << 2,
    planned = 1u << 3
}

struct RibbonTabDescriptorV1
{
    const(char)* id;
    const(char)* localisationKey;
    const(char)* iconName;
}

struct RibbonCommandDescriptorV1
{
    const(char)* id;
    const(char)* localisationKey;
    const(char)* iconName;
    const(char)* tabId;
    const(char)* groupId;
    uint flags;
}

struct SectionRibbonV1
{
    const(char)* sectionId;
    const(RibbonTabDescriptorV1)* tabs;
    size_t tabCount;
    const(RibbonCommandDescriptorV1)* commands;
    size_t commandCount;
}



