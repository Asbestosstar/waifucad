module waifucad.sections.modelling.section;

import waifucad.sections.api : SectionDescriptorV1, SectionCapability, WC_SECTION_ABI_V1;
import waifucad.sections.ribbon : RibbonTabDescriptorV1, RibbonCommandDescriptorV1, SectionRibbonV1, RibbonCommandFlags;

/* The Modelling Section is WaifuCAD's default application context. */
private __gshared const RibbonTabDescriptorV1[5] modellingTabs = [
    RibbonTabDescriptorV1("modelling.home".ptr, "ribbon.modelling.home".ptr, "tab_home".ptr),
    RibbonTabDescriptorV1("modelling.curve".ptr, "ribbon.modelling.curve".ptr, "tab_curve".ptr),
    RibbonTabDescriptorV1("modelling.surface".ptr, "ribbon.modelling.surface".ptr, "tab_surface".ptr),
    RibbonTabDescriptorV1("modelling.analysis".ptr, "ribbon.modelling.analysis".ptr, "tab_analysis".ptr),
    RibbonTabDescriptorV1("modelling.tools".ptr, "ribbon.modelling.tools".ptr, "tab_tools".ptr)
];

private __gshared const RibbonCommandDescriptorV1[26] modellingCommands = [
    RibbonCommandDescriptorV1("modelling.sketch".ptr, "command.sketch".ptr, "cmd_sketch".ptr, "modelling.home".ptr, "group.create".ptr, cast(uint)RibbonCommandFlags.requiresDocument),
    RibbonCommandDescriptorV1("modelling.extrude".ptr, "command.extrude".ptr, "cmd_extrude".ptr, "modelling.home".ptr, "group.create".ptr, cast(uint)RibbonCommandFlags.requiresDocument),
    RibbonCommandDescriptorV1("modelling.revolve".ptr, "command.revolve".ptr, "cmd_revolve".ptr, "modelling.home".ptr, "group.create".ptr, cast(uint)RibbonCommandFlags.requiresDocument),
    RibbonCommandDescriptorV1("modelling.sweep".ptr, "command.sweep".ptr, "cmd_sweep".ptr, "modelling.home".ptr, "group.create".ptr, cast(uint)RibbonCommandFlags.requiresDocument),
    RibbonCommandDescriptorV1("modelling.loft".ptr, "command.loft".ptr, "cmd_loft".ptr, "modelling.home".ptr, "group.create".ptr, cast(uint)RibbonCommandFlags.requiresDocument),
    RibbonCommandDescriptorV1("modelling.union".ptr, "command.union".ptr, "cmd_union".ptr, "modelling.home".ptr, "group.combine".ptr, cast(uint)RibbonCommandFlags.requiresSelection),
    RibbonCommandDescriptorV1("modelling.subtract".ptr, "command.subtract".ptr, "cmd_subtract".ptr, "modelling.home".ptr, "group.combine".ptr, cast(uint)RibbonCommandFlags.requiresSelection),
    RibbonCommandDescriptorV1("modelling.intersect".ptr, "command.intersect".ptr, "cmd_intersect".ptr, "modelling.home".ptr, "group.combine".ptr, cast(uint)RibbonCommandFlags.requiresSelection),
    RibbonCommandDescriptorV1("modelling.fillet".ptr, "command.fillet".ptr, "cmd_fillet".ptr, "modelling.home".ptr, "group.detail".ptr, cast(uint)RibbonCommandFlags.requiresSelection),
    RibbonCommandDescriptorV1("modelling.chamfer".ptr, "command.chamfer".ptr, "cmd_chamfer".ptr, "modelling.home".ptr, "group.detail".ptr, cast(uint)RibbonCommandFlags.requiresSelection),
    RibbonCommandDescriptorV1("modelling.shell".ptr, "command.shell".ptr, "cmd_shell".ptr, "modelling.home".ptr, "group.detail".ptr, cast(uint)RibbonCommandFlags.requiresSelection),
    RibbonCommandDescriptorV1("modelling.free_line".ptr, "command.free_line".ptr, "cmd_line".ptr, "modelling.curve".ptr, "group.rough_curves".ptr, cast(uint)RibbonCommandFlags.requiresDocument),
    RibbonCommandDescriptorV1("modelling.free_arc".ptr, "command.free_arc".ptr, "cmd_arc".ptr, "modelling.curve".ptr, "group.rough_curves".ptr, cast(uint)RibbonCommandFlags.requiresDocument),
    RibbonCommandDescriptorV1("modelling.free_circle".ptr, "command.free_circle".ptr, "cmd_circle".ptr, "modelling.curve".ptr, "group.rough_curves".ptr, cast(uint)RibbonCommandFlags.requiresDocument),
    RibbonCommandDescriptorV1("modelling.free_spline".ptr, "command.free_spline".ptr, "cmd_spline".ptr, "modelling.curve".ptr, "group.rough_curves".ptr, cast(uint)RibbonCommandFlags.requiresDocument),
    RibbonCommandDescriptorV1("modelling.datum_plane".ptr, "command.datum_plane".ptr, "cmd_datum_plane".ptr, "modelling.surface".ptr, "group.datum".ptr, cast(uint)RibbonCommandFlags.requiresDocument),
    RibbonCommandDescriptorV1("modelling.datum_axis".ptr, "command.datum_axis".ptr, "cmd_datum_axis".ptr, "modelling.surface".ptr, "group.datum".ptr, cast(uint)RibbonCommandFlags.requiresDocument),
    RibbonCommandDescriptorV1("modelling.datum_csys".ptr, "command.datum_csys".ptr, "cmd_datum_csys".ptr, "modelling.surface".ptr, "group.datum".ptr, cast(uint)RibbonCommandFlags.requiresDocument),
    RibbonCommandDescriptorV1("modelling.measure".ptr, "command.measure".ptr, "cmd_measure".ptr, "modelling.analysis".ptr, "group.inspect".ptr, cast(uint)RibbonCommandFlags.requiresDocument),
    RibbonCommandDescriptorV1("modelling.mass_properties".ptr, "command.mass_properties".ptr, "cmd_mass".ptr, "modelling.analysis".ptr, "group.inspect".ptr, cast(uint)RibbonCommandFlags.requiresSelection),
    RibbonCommandDescriptorV1("modelling.import_openscad".ptr, "interchange.openscad.import".ptr, "cmd_import_scad".ptr, "modelling.tools".ptr, "group.interchange".ptr, cast(uint)RibbonCommandFlags.requiresDocument),
    RibbonCommandDescriptorV1("modelling.export_openscad".ptr, "interchange.openscad.export".ptr, "cmd_export_scad".ptr, "modelling.tools".ptr, "group.interchange".ptr, cast(uint)RibbonCommandFlags.requiresDocument),
    RibbonCommandDescriptorV1("modelling.import_dumb_body".ptr, "command.import_dumb_body".ptr, "cmd_import_body".ptr, "modelling.tools".ptr, "group.interchange".ptr, cast(uint)RibbonCommandFlags.requiresDocument),
    RibbonCommandDescriptorV1("modelling.journal_record".ptr, "journal.record".ptr, "cmd_record".ptr, "modelling.tools".ptr, "group.automation".ptr, cast(uint)RibbonCommandFlags.toggle),
    RibbonCommandDescriptorV1("modelling.run_journal".ptr, "journal.run".ptr, "cmd_script".ptr, "modelling.tools".ptr, "group.automation".ptr, 0),
    RibbonCommandDescriptorV1("modelling.run_script".ptr, "command.run_script".ptr, "cmd_script".ptr, "modelling.tools".ptr, "group.automation".ptr, 0)
];

private __gshared const SectionRibbonV1 modellingRibbon = SectionRibbonV1(
    "modelling".ptr,
    modellingTabs.ptr,
    modellingTabs.length,
    modellingCommands.ptr,
    modellingCommands.length
);

SectionDescriptorV1 modellingSectionDescriptor() nothrow @nogc
{
    SectionDescriptorV1 result;
    result.abiVersion = WC_SECTION_ABI_V1;
    result.id = "modelling".ptr;
    result.localisationKey = "section.modelling".ptr;
    result.iconName = "section_modelling".ptr;
    result.capabilities = cast(uint)(SectionCapability.modelling | SectionCapability.documentRead | SectionCapability.documentWrite | SectionCapability.viewport);
    return result;
}

const(SectionRibbonV1)* modellingSectionRibbon() nothrow @nogc
{
    return &modellingRibbon;
}




