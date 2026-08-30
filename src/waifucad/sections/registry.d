module waifucad.sections.registry;

import core.stdc.string : strcmp;
import waifucad.sections.api : SectionDescriptorV1, SectionCapability, WC_SECTION_ABI_V1;
import waifucad.sections.ribbon : SectionRibbonV1;
import waifucad.sections.modelling.section : modellingSectionDescriptor, modellingSectionRibbon;
import waifucad.sections.pmi.section : pmiSectionDescriptor, pmiSectionRibbon;

private SectionDescriptorV1[7] builtins;
private bool initialised;

private SectionDescriptorV1 makeSection(const(char)* id, const(char)* key, const(char)* icon, uint caps) nothrow @nogc
{
    SectionDescriptorV1 result;
    result.abiVersion = WC_SECTION_ABI_V1;
    result.id = id;
    result.localisationKey = key;
    result.iconName = icon;
    result.capabilities = caps;
    return result;
}

private void initialiseBuiltins() nothrow @nogc
{
    if (initialised) return;
    auto edit = cast(uint)(SectionCapability.modelling | SectionCapability.documentRead | SectionCapability.documentWrite | SectionCapability.viewport);
    builtins[0] = modellingSectionDescriptor();
    builtins[1] = makeSection("assembly".ptr, "section.assembly".ptr, "section_assembly".ptr,
        cast(uint)(SectionCapability.documentRead | SectionCapability.documentWrite | SectionCapability.viewport | SectionCapability.assembly));
    builtins[2] = pmiSectionDescriptor();
    builtins[3] = makeSection("drawing".ptr, "section.drawing".ptr, "section_drawing".ptr, edit);
    builtins[4] = makeSection("manufacturing".ptr, "section.manufacturing".ptr, "section_manufacturing".ptr, edit);
    builtins[5] = makeSection("ai".ptr, "section.ai".ptr, "section_ai".ptr, edit);
    builtins[6] = makeSection("journalling".ptr, "section.journalling".ptr, "section_journalling".ptr, cast(uint)SectionCapability.documentRead);
    initialised = true;
}

SectionDescriptorV1* builtInSections(size_t* count) nothrow @nogc
{
    initialiseBuiltins();
    if (count !is null)
        *count = builtins.length;
    return builtins.ptr;
}

SectionDescriptorV1* findBuiltInSection(const(char)* id) nothrow @nogc
{
    if (id is null) return null;
    initialiseBuiltins();
    foreach (i; 0 .. builtins.length)
        if (strcmp(builtins[i].id, id) == 0)
            return &builtins[i];
    return null;
}

const(SectionRibbonV1)* ribbonForSection(const(char)* id) nothrow @nogc
{
    if (id is null) return null;
    if (strcmp(id, "modelling".ptr) == 0) return modellingSectionRibbon();
    if (strcmp(id, "pmi".ptr) == 0) return pmiSectionRibbon();
    // Other Sections remain registered application contexts but do not yet
    // own contextual ribbon descriptors in this bootstrap.
    return null;
}



