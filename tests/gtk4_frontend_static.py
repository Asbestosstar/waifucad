from pathlib import Path
import re

root = Path(__file__).resolve().parents[1]
app = (root / 'src/apps/waifucad_gui.d').read_text()
frontend = (root / 'src/waifucad/gui/frontends/gtk4/frontend.d').read_text()
actions = (root / 'src/waifucad/gui/ribbon_actions.d').read_text()
native = (root / 'native/gui/gtk4/wc_gtk4.c').read_text()
header = (root / 'native/gui/gtk4/wc_gtk4.h').read_text()
build = (root / 'build.sh').read_text()
agents = (root / 'AGENTS.MD').read_text()
modelling = (root / 'src/waifucad/sections/modelling/section.d').read_text()
pmi = (root / 'src/waifucad/sections/pmi/section.d').read_text()
theme = (root / 'src/waifucad/gui/theme.d').read_text()
sections_config = (root / 'config/sections.json').read_text()

# No-argument startup now opens the native GUI. Tests can still request text-only
# bootstrap diagnostics explicitly so smoke.sh does not hang in the event loop.
assert 'bool nativeGui = true;' in app
assert '--bootstrap-info' in app
assert '--native' in app and '--renderer' in app and '--lavapipe' in app and 'runGtk4Native' in app

# Toolkit-neutral ribbon and navigator data are supplied across the D/C ABI.
for token in [
    'gtk4FeatureRows', 'gtk4SectionEntries', 'gtk4ActiveRibbon', 'gtk4RibbonTemplate',
    'gtk4BodyRows', 'gtk4CsysRows',
    'gtk4BeginNewSketch', 'gtk4EditSketch', 'gtk4FinishSketch', 'gtk4SketchGeometryRows', 'gtk4PlanarFaceRows',
    'gtk4SketchAddLine', 'gtk4SketchAddCircle', 'gtk4SketchAddRectangle', 'gtk4FeatureAction', 'gtk4FeatureReorder'
]:
    assert token in frontend
for token in [
    'WcGtk4FeatureRow', 'WcGtk4BodyRow', 'WcGtk4CsysRow', 'WcGtk4SectionEntry', 'WcGtk4RibbonSnapshot', 'WcGtk4RibbonTemplateFn',
    'WcGtk4SketchGeometryRow', 'WcGtk4BeginNewSketchFn', 'WcGtk4EditSketchFn',
    'WcGtk4SketchAddLineFn', 'WcGtk4SketchAddCircleFn', 'WcGtk4SketchAddRectangleFn',
    'WcGtk4FeatureActionFn', 'WcGtk4FeatureReorderFn', 'WcGtk4SketchSupport', 'WcGtk4PlanarFaceRow'
]:
    assert token in header
assert 'ribbonCommandTemplate' in actions
assert 'src/waifucad/gui/ribbon_actions.d' in build

# Interactive sketch and semantic model-history editing must stay on the shared
# SCL path rather than mutating the model directly from GTK callbacks.
interpreter = (root / 'src/waifucad/scl/interpreter.d').read_text()
model = (root / 'src/waifucad/kernel/model.d').read_text()
preview = (root / 'src/waifucad/kernel/builtin_preview.d').read_text()
profiles = (root / 'src/waifucad/kernel/profiles.d').read_text()
for command in ['feature_delete', 'feature_move_up', 'feature_move_down', 'feature_move_before', 'feature_move_after', 'sketch_rect_at', 'datum_plane_from_face']:
    assert f'"{command}".ptr' in interpreter
for method in ['featureHasDependants', 'moveFeatureUp', 'moveFeatureDown', 'moveFeatureBefore', 'moveFeatureAfter', 'deleteFeature']:
    assert method in model
assert 'FeatureKind.sketchRectangle' in preview and 'feature.operandCount >= 5' in preview
assert 'FeatureKind.sketchRectangle' in profiles
assert 'submitGenerated(context' in frontend
# Stack char[N] buffers use D's .ptr property, not a callable .ptr().
assert 'constraintName.ptr, sketch.name.ptr(), name.ptr, newPoint' in frontend
assert 'navigatorShowsFeature' in frontend and 'FeatureKind.sketchLine' in frontend
assert 'absolute_csys' in model and 'features[0].dirty = false' in model
assert 'navigatorBackground' in theme and 'navigatorRailBackground' in theme
assert '"global_ribbon_tabs": ["sections", "mods"]' in sections_config
assert '"home_ribbon_groups": ["scripts"]' in sections_config

# Real GTK4 ribbon, navigator stack, and viewport controls.
for token in [
    'rebuild_ribbon', 'build_ribbon_commands', 'wc-ribbon-command',
    'Model Navigator', 'Assembly Navigator', 'AI Agent',
    'gtk_event_controller_scroll_new', 'GDK_BUTTON_MIDDLE',
    'GDK_KEY_w', 'GDK_KEY_a', 'GDK_KEY_s', 'GDK_KEY_d',
    'gtk_stack_set_visible_child_name', 'gtk_widget_grab_focus(state.drawing_area)',
    'waifus/nightcore.png', 'ribbon_waifu', 'wc_gpu_probe',
    'build_sketch_ribbon', 'begin_new_sketch', 'begin_edit_sketch', 'finish_sketch',
    'model_row_activated_cb', 'viewport_motion_cb', 'WC_SKETCH_TOOL_RECTANGLE',
    'show_feature_context_menu', 'model_context_pressed_cb', 'configure_feature_drag', 'feature_drop_cb',
    'gtk_paned_set_shrink_start_child', 'row_count == 4', 'wc-ribbon-command-compact',
    'build_navigator_rail', 'build_navigator_content', 'navigator_paned',
    'global.sections', 'global.mods', 'append_scripts_home_group',
    'hit_test_planar_face', 'hit_test_body', 'draw_selected_body_bounds', 'WC_GTK4_SKETCH_SUPPORT_PLANAR_FACE',
    'update_snap_candidates', 'g_timeout_add(1000', 'show_snap_choice_dialogue',
    'draw_snap_feedback', 'snap_candidate_count', 'pointer_valid',
    'draw_absolute_csys', 'draw_csys_plane', 'hit_test_csys_plane', 'draw_all_sketches_3d', 'draw_body_bounds',
    'WC_SNAP_CORNER', 'WC_SNAP_ORIGIN', 'WC_SNAP_X_AXIS', 'WC_SNAP_Y_AXIS',
    'viewport_context_pressed_cb', 'viewport_fit_all_cb',
    'gtk_list_box_set_activate_on_single_click', 'gtk_scrolled_window_set_propagate_natural_width'
]:
    assert token in native
assert 'draw_model_bounds(' not in native
assert 'gtk_paned_set_end_child(GTK_PANED(main_paned), overlay);' in native
assert 'gtk_stack_set_hhomogeneous(GTK_STACK(state->navigator_stack), FALSE);' in native
assert 'set_initial_navigator_width_cb' in native
assert 'g_idle_add(set_initial_navigator_width_cb, &state);' in native
assert 'transform.model_cx = 0.0;' in native and 'orientation-invariant 3D' in native
assert 'viewport_model_origin_screen' in native
assert 'model_to_screen(state, &transform, 0.0, 0.0, 0.0, origin_x, origin_y);' in native
assert 'The viewport cross is the absolute model origin' in native
assert 'make_empty_csys_transform' in native
assert 'An empty part still owns the absolute CSYS' in native
assert 'static const double quadrant[4][2] = {{0,0},{1,0},{1,1},{0,1}};' in native
assert '{{-1,-1},{1,-1},{1,1},{-1,1}}' not in native
assert 'Do not mirror' in native and 'the construction plane through the origin.' in native
assert 'frameOrigin' in frontend and 'frameXAxis' in frontend and 'frameYAxis' in frontend
assert 'GtkWidget *global_toolbar' not in native
assert 'build_sections_popover' not in native and 'build_scripts_popover' not in native and 'build_mods_popover' not in native
assert 'GTK_CHECK_VERSION(4, 12, 0)' in native and 'gtk_css_provider_load_from_string' in native
assert 'gtk_box_append(GTK_BOX(root), global_toolbar)' not in native
assert 'feature_delete_clicked_cb' not in native and 'feature_up_clicked_cb' not in native and 'feature_down_clicked_cb' not in native
assert 'make_ribbon_tab_button(state, "global.sections", "Sections")' in native
assert 'build_mods_ribbon_commands(state);' in native

# All command/tab descriptor icon names used by the implemented Modelling and PMI
# ribbons must resolve to project-owned SVG files.
icon_names = set(re.findall(r'"((?:cmd|tab)_[A-Za-z0-9_]+)"\.ptr', modelling + pmi))
icon_names.update({'nav_model', 'nav_assembly', 'nav_ai', 'waifucad', 'cmd_rectangle', 'cmd_finish_sketch', 'cmd_command', 'tab_mods'})
assert icon_names
for icon in sorted(icon_names):
    path = root / 'assets' / 'icons' / f'{icon}.svg'
    assert path.is_file(), f'missing SVG icon: {path}'
    assert '<svg' in path.read_text()[:256]

assert (root / 'waifus/nightcore.png').is_file()
assert 'pkg-config --exists gtk4' in build
assert 'wc_gtk4_stub.c' in build
assert '- [x] Compile and smoke-test with LDC on Linux x86-64.' in agents
print(f'GTK4 native frontend static contract passed ({len(icon_names)} SVG icons checked).')
