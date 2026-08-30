module waifucad.sections.api;

enum WC_SECTION_ABI_V1 = 1u;

enum SectionCapability : uint
{
    modelling = 1u << 0,
    documentRead = 1u << 1,
    documentWrite = 1u << 2,
    viewport = 1u << 3,
    batch = 1u << 4,
    annotation = 1u << 5,
    assembly = 1u << 6
}

/*
 * Keep V1 deliberately small for Mods.  Built-in contextual ribbon data is
 * queried separately, so third-party ABI compatibility is not tied to GUI
 * toolkit details or ribbon-layout revisions.
 */
struct SectionDescriptorV1
{
    uint abiVersion;
    const(char)* id;
    const(char)* localisationKey;
    const(char)* iconName;
    uint capabilities;
}



