module waifucad.gui.ribbon_actions;

import core.stdc.string : strcmp;

/*
 * Toolkit-neutral fallback command templates.
 *
 * Native ribbon front-ends now execute simple actions directly or render
 * FeatureDialogueDescriptorV1 data.  These templates remain useful for simple
 * non-dialogue actions and compatibility, but ribbon clicks no longer require
 * the user to edit the visible command line.  Every mutation still reaches the
 * kernel through semantic SCL/transaction journalling.
 */
const(char)* ribbonCommandTemplate(const(char)* commandId) nothrow @nogc
{
    if (commandId is null) return "".ptr;

    if (strcmp(commandId, "modelling.sketch".ptr) == 0) return "sketch(:new_sketch, :XY)".ptr;
    if (strcmp(commandId, "modelling.extrude".ptr) == 0) return "extrude(:new_extrude, :profile, 10.mm)".ptr;
    if (strcmp(commandId, "modelling.revolve".ptr) == 0) return "revolve(:new_revolve, :profile, 360.deg)".ptr;
    if (strcmp(commandId, "modelling.sweep".ptr) == 0) return "sweep(:new_sweep, :profile, :path)".ptr;
    if (strcmp(commandId, "modelling.loft".ptr) == 0) return "loft(:new_loft, :profile_a, :profile_b)".ptr;
    if (strcmp(commandId, "modelling.union".ptr) == 0) return "union(:new_union, :body_a, :body_b)".ptr;
    if (strcmp(commandId, "modelling.subtract".ptr) == 0) return "subtract(:new_subtract, :target, :tool)".ptr;
    if (strcmp(commandId, "modelling.intersect".ptr) == 0) return "intersect(:new_intersection, :body_a, :body_b)".ptr;
    if (strcmp(commandId, "modelling.fillet".ptr) == 0) return "fillet(:new_fillet, :body, 2.mm)".ptr;
    if (strcmp(commandId, "modelling.chamfer".ptr) == 0) return "chamfer(:new_chamfer, :body, 2.mm)".ptr;
    if (strcmp(commandId, "modelling.shell".ptr) == 0) return "shell(:new_shell, :body, 2.mm)".ptr;

    if (strcmp(commandId, "modelling.free_line".ptr) == 0) return "line(:new_line, 0, 0, 0, 50.mm, 0, 0)".ptr;
    if (strcmp(commandId, "modelling.free_arc".ptr) == 0) return "arc(:new_arc, 0, 0, 0, 25.mm, 0.deg, 90.deg)".ptr;
    if (strcmp(commandId, "modelling.free_circle".ptr) == 0) return "curve_circle(:new_circle, 0, 0, 0, 25.mm)".ptr;
    if (strcmp(commandId, "modelling.free_spline".ptr) == 0) return "spline_bbox(:new_spline, 0, 0, 0, 50.mm, 30.mm, 10.mm)".ptr;

    if (strcmp(commandId, "modelling.datum_plane".ptr) == 0) return "datum_plane(:new_plane, 0, 0, 0, 0, 0, 1, 1, 0, 0)".ptr;
    if (strcmp(commandId, "modelling.datum_axis".ptr) == 0) return "datum_axis(:new_axis, 0, 0, 0, 0, 0, 1)".ptr;
    if (strcmp(commandId, "modelling.datum_csys".ptr) == 0) return "datum_csys(:new_csys, 0, 0, 0, 1, 0, 0, 0, 1, 0)".ptr;

    if (strcmp(commandId, "modelling.measure".ptr) == 0) return "get_feature_bounds(:feature_name)".ptr;
    if (strcmp(commandId, "modelling.mass_properties".ptr) == 0) return "get_feature_volume(:feature_name)".ptr;
    if (strcmp(commandId, "modelling.import_openscad".ptr) == 0) return "scad_import(:imported_body, \"model.scad\", :auto)".ptr;
    if (strcmp(commandId, "modelling.export_openscad".ptr) == 0) return "scad_export(\"model.scad\", :body_name)".ptr;
    if (strcmp(commandId, "modelling.import_dumb_body".ptr) == 0) return "import(:imported_body, \"model.off\", 0, 0, 0, 100.mm, 100.mm, 100.mm)".ptr;
    if (strcmp(commandId, "modelling.journal_record".ptr) == 0) return "journal_start(\"model.wjournal\")".ptr;
    if (strcmp(commandId, "modelling.run_journal".ptr) == 0) return "journal_run(\"model.wjournal\")".ptr;
    if (strcmp(commandId, "modelling.run_script".ptr) == 0) return "include(\"script.wcs\")".ptr;

    if (strcmp(commandId, "pmi.quick_dimension".ptr) == 0) return "pmi_add(:linear_dimension, :new_dimension, \"DIM\", :feature, 0, 0)".ptr;
    if (strcmp(commandId, "pmi.note".ptr) == 0) return "pmi_add(:note, :new_note, \"NOTE\", none, 0, 0)".ptr;
    if (strcmp(commandId, "pmi.annotation_plane".ptr) == 0) return "# Annotation-plane editing is planned; PMI remains separate from modelling history.".ptr;
    if (strcmp(commandId, "pmi.show_hide".ptr) == 0) return "pmi_visible(:annotation_name, true)".ptr;
    if (strcmp(commandId, "pmi.linear_dimension".ptr) == 0) return "pmi_add(:linear_dimension, :new_linear_dim, \"0 mm\", :feature, 0, 0)".ptr;
    if (strcmp(commandId, "pmi.angular_dimension".ptr) == 0) return "pmi_add(:angular_dimension, :new_angular_dim, \"0 deg\", :feature, 0, 0)".ptr;
    if (strcmp(commandId, "pmi.radial_dimension".ptr) == 0) return "pmi_add(:radial_dimension, :new_radius_dim, \"R0\", :feature, 0, 0)".ptr;
    if (strcmp(commandId, "pmi.diameter_dimension".ptr) == 0) return "pmi_add(:diameter_dimension, :new_diameter_dim, \"DIA 0\", :feature, 0, 0)".ptr;
    if (strcmp(commandId, "pmi.datum_feature".ptr) == 0) return "pmi_add(:datum_feature, :new_datum, \"A\", :feature, 0, 0)".ptr;
    if (strcmp(commandId, "pmi.feature_control_frame".ptr) == 0) return "pmi_add(:feature_control_frame, :new_fcf, \"FCF\", :feature, 0, 0)".ptr;
    if (strcmp(commandId, "pmi.surface_texture".ptr) == 0) return "pmi_add(:surface_texture, :new_surface_texture, \"SURFACE\", :feature, 0, 0)".ptr;
    if (strcmp(commandId, "pmi.weld_symbol".ptr) == 0) return "pmi_add(:weld_symbol, :new_weld, \"WELD\", :feature, 0, 0)".ptr;
    if (strcmp(commandId, "pmi.general_note".ptr) == 0) return "pmi_add(:note, :new_general_note, \"GENERAL NOTE\", none, 0, 0)".ptr;
    if (strcmp(commandId, "pmi.balloon".ptr) == 0) return "pmi_add(:balloon, :new_balloon, \"1\", :feature, 0, 0)".ptr;
    if (strcmp(commandId, "pmi.validate".ptr) == 0) return "get_pmi_count()".ptr;
    if (strcmp(commandId, "pmi.import".ptr) == 0) return "# STEP AP242 PMI import is planned after persistent topology association.".ptr;
    if (strcmp(commandId, "pmi.export".ptr) == 0) return "# STEP AP242 PMI export is planned after persistent topology association.".ptr;

    return "".ptr;
}

