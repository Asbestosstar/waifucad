module waifucad.sections.pmi.section;

import waifucad.sections.api : SectionDescriptorV1, SectionCapability, WC_SECTION_ABI_V1;
import waifucad.sections.ribbon : RibbonTabDescriptorV1, RibbonCommandDescriptorV1, SectionRibbonV1, RibbonCommandFlags;

private __gshared const RibbonTabDescriptorV1[5] pmiTabs = [
    RibbonTabDescriptorV1("pmi.home".ptr, "ribbon.pmi.home".ptr, "tab_pmi".ptr),
    RibbonTabDescriptorV1("pmi.dimensions".ptr, "ribbon.pmi.dimensions".ptr, "tab_dimensions".ptr),
    RibbonTabDescriptorV1("pmi.gdt".ptr, "ribbon.pmi.gdt".ptr, "tab_gdt".ptr),
    RibbonTabDescriptorV1("pmi.notes".ptr, "ribbon.pmi.notes".ptr, "tab_notes".ptr),
    RibbonTabDescriptorV1("pmi.exchange".ptr, "ribbon.pmi.exchange".ptr, "tab_exchange".ptr)
];

private __gshared const RibbonCommandDescriptorV1[17] pmiCommands = [
    RibbonCommandDescriptorV1("pmi.quick_dimension".ptr, "command.pmi.quick_dimension".ptr, "cmd_pmi_quick_dimension".ptr, "pmi.home".ptr, "group.pmi_create".ptr, cast(uint)RibbonCommandFlags.requiresSelection),
    RibbonCommandDescriptorV1("pmi.note".ptr, "command.pmi.note".ptr, "cmd_pmi_note".ptr, "pmi.home".ptr, "group.pmi_create".ptr, cast(uint)RibbonCommandFlags.requiresDocument),
    RibbonCommandDescriptorV1("pmi.annotation_plane".ptr, "command.pmi.annotation_plane".ptr, "cmd_pmi_plane".ptr, "pmi.home".ptr, "group.pmi_orientation".ptr, cast(uint)(RibbonCommandFlags.requiresDocument | RibbonCommandFlags.planned)),
    RibbonCommandDescriptorV1("pmi.show_hide".ptr, "command.pmi.show_hide".ptr, "cmd_pmi_show".ptr, "pmi.home".ptr, "group.pmi_display".ptr, cast(uint)RibbonCommandFlags.toggle),
    RibbonCommandDescriptorV1("pmi.linear_dimension".ptr, "command.pmi.linear_dimension".ptr, "cmd_pmi_linear".ptr, "pmi.dimensions".ptr, "group.dimension".ptr, cast(uint)RibbonCommandFlags.requiresSelection),
    RibbonCommandDescriptorV1("pmi.angular_dimension".ptr, "command.pmi.angular_dimension".ptr, "cmd_pmi_angular".ptr, "pmi.dimensions".ptr, "group.dimension".ptr, cast(uint)RibbonCommandFlags.requiresSelection),
    RibbonCommandDescriptorV1("pmi.radial_dimension".ptr, "command.pmi.radial_dimension".ptr, "cmd_pmi_radial".ptr, "pmi.dimensions".ptr, "group.dimension".ptr, cast(uint)RibbonCommandFlags.requiresSelection),
    RibbonCommandDescriptorV1("pmi.diameter_dimension".ptr, "command.pmi.diameter_dimension".ptr, "cmd_pmi_diameter".ptr, "pmi.dimensions".ptr, "group.dimension".ptr, cast(uint)RibbonCommandFlags.requiresSelection),
    RibbonCommandDescriptorV1("pmi.datum_feature".ptr, "command.pmi.datum_feature".ptr, "cmd_pmi_datum".ptr, "pmi.gdt".ptr, "group.gdt".ptr, cast(uint)RibbonCommandFlags.requiresSelection),
    RibbonCommandDescriptorV1("pmi.feature_control_frame".ptr, "command.pmi.feature_control_frame".ptr, "cmd_pmi_fcf".ptr, "pmi.gdt".ptr, "group.gdt".ptr, cast(uint)RibbonCommandFlags.requiresSelection),
    RibbonCommandDescriptorV1("pmi.surface_texture".ptr, "command.pmi.surface_texture".ptr, "cmd_pmi_surface".ptr, "pmi.gdt".ptr, "group.manufacturing_symbols".ptr, cast(uint)RibbonCommandFlags.requiresSelection),
    RibbonCommandDescriptorV1("pmi.weld_symbol".ptr, "command.pmi.weld_symbol".ptr, "cmd_pmi_weld".ptr, "pmi.gdt".ptr, "group.manufacturing_symbols".ptr, cast(uint)RibbonCommandFlags.requiresSelection),
    RibbonCommandDescriptorV1("pmi.general_note".ptr, "command.pmi.general_note".ptr, "cmd_pmi_general_note".ptr, "pmi.notes".ptr, "group.notes".ptr, cast(uint)RibbonCommandFlags.requiresDocument),
    RibbonCommandDescriptorV1("pmi.balloon".ptr, "command.pmi.balloon".ptr, "cmd_pmi_balloon".ptr, "pmi.notes".ptr, "group.notes".ptr, cast(uint)(RibbonCommandFlags.requiresSelection | RibbonCommandFlags.planned)),
    RibbonCommandDescriptorV1("pmi.validate".ptr, "command.pmi.validate".ptr, "cmd_pmi_validate".ptr, "pmi.exchange".ptr, "group.pmi_check".ptr, cast(uint)(RibbonCommandFlags.requiresDocument | RibbonCommandFlags.planned)),
    RibbonCommandDescriptorV1("pmi.import".ptr, "command.pmi.import".ptr, "cmd_pmi_import".ptr, "pmi.exchange".ptr, "group.pmi_exchange".ptr, cast(uint)(RibbonCommandFlags.requiresDocument | RibbonCommandFlags.planned)),
    RibbonCommandDescriptorV1("pmi.export".ptr, "command.pmi.export".ptr, "cmd_pmi_export".ptr, "pmi.exchange".ptr, "group.pmi_exchange".ptr, cast(uint)(RibbonCommandFlags.requiresDocument | RibbonCommandFlags.planned))
];

private __gshared const SectionRibbonV1 pmiRibbon = SectionRibbonV1(
    "pmi".ptr,
    pmiTabs.ptr,
    pmiTabs.length,
    pmiCommands.ptr,
    pmiCommands.length
);

SectionDescriptorV1 pmiSectionDescriptor() nothrow @nogc
{
    SectionDescriptorV1 result;
    result.abiVersion = WC_SECTION_ABI_V1;
    result.id = "pmi".ptr;
    result.localisationKey = "section.pmi".ptr;
    result.iconName = "tab_pmi".ptr;
    result.capabilities = cast(uint)(SectionCapability.documentRead | SectionCapability.documentWrite | SectionCapability.viewport | SectionCapability.annotation);
    return result;
}

const(SectionRibbonV1)* pmiSectionRibbon() nothrow @nogc
{
    return &pmiRibbon;
}





