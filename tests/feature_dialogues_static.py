from pathlib import Path
import re

root = Path(__file__).resolve().parents[1]
dialogues = (root / 'src/waifucad/gui/feature_dialogues.d').read_text()
frontend = (root / 'src/waifucad/gui/frontends/gtk4/frontend.d').read_text()
native = (root / 'native/gui/gtk4/wc_gtk4.c').read_text()
header = (root / 'native/gui/gtk4/wc_gtk4.h').read_text()
shared_header = (root / 'native/gui/shared/wc_feature_dialogue.h').read_text()
cocoa_header = (root / 'native/gui/cocoa/wc_cocoa.h').read_text()
cocoa_frontend = (root / 'src/waifucad/gui/frontends/cocoa/frontend.d').read_text()
cocoa_native = (root / 'native/gui/cocoa/wc_cocoa.m').read_text()
model = (root / 'src/waifucad/kernel/model.d').read_text()
interpreter = (root / 'src/waifucad/scl/interpreter.d').read_text()
pmi = (root / 'src/waifucad/sections/pmi/section.d').read_text()
profiles = (root / 'src/waifucad/kernel/profiles.d').read_text()
build = (root / 'build.sh').read_text()
waifu_manifest = (root / 'waifus/manifest.json').read_text()

# Ribbon use is direct or data-dialogue driven; it no longer copies a template
# into the visible command entry and asks the user to press Enter.
ribbon_fn = re.search(r'static void ribbon_command_clicked_cb\(.*?\n\}', native, re.S)
assert ribbon_fn
body = ribbon_fn.group(0)
assert 'show_feature_dialogue' in body
assert 'submit_command' in body
assert 'set_command_text' not in body
assert 'edit parameters, then press Enter' not in native

# Toolkit-neutral descriptor ABI and C/D callback bridge.
for token in [
    'FeatureDialogueDescriptorV1', 'FeatureDialogueFieldDescriptorV1',
    'FeatureDialogueSelectionKind', 'featureDialogueForCommand', 'featureDialogueForFeature',
    'featureDialogueAcceptsSelection', 'FeatureScript', 'waifus/nightcore.png'
]:
    assert token in dialogues
for token in ['WcFeatureDialogueDescriptorV1', 'WcFeatureDialogueFieldDescriptorV1',
              'WcFeatureDialogueSelectionKind', 'selection_kind']:
    assert token in shared_header
for token in ['WcGtk4FeatureDialogueFn', 'WcGtk4FeatureDialogueForFeatureFn',
              'WcGtk4FeatureDialogueValueFn', 'WcGtk4FeatureDialogueAcceptSelectionFn']:
    assert token in header
assert '#include "../shared/wc_feature_dialogue.h"' in header
assert '#include "../shared/wc_feature_dialogue.h"' in cocoa_header
for token in [
    'gtk4FeatureDialogue', 'gtk4FeatureDialogueForFeature',
    'gtk4FeatureDialogueValue', 'gtk4FeatureDialogueAcceptSelection'
]:
    assert token in frontend
for token in [
    'feature_dialogue_apply_cb', 'feature_dialogue_make_editor',
    'WC_FEATURE_DIALOGUE_SKETCH_EDITOR', 'Edit Sketch Geometry',
    'feature_dialogue_for_feature', 'feature_dialogue_select_cb',
    'feature_dialogue_accept_pick', 'hit_test_sketch', 'Select…'
]:
    assert token in native

for token in ['WcCocoaFeatureDialogueFn', 'WcCocoaFeatureDialogueForFeatureFn',
              'WcCocoaFeatureDialogueValueFn', 'WcCocoaFeatureDialogueAcceptSelectionFn']:
    assert token in cocoa_header
for token in ['cocoaFeatureDialogue', 'cocoaFeatureDialogueForFeature',
              'cocoaFeatureDialogueValue', 'cocoaFeatureDialogueAcceptSelection']:
    assert token in cocoa_frontend
for token in ['featureDialogueApply:', 'showFeatureDialogue:', 'featureDialogueSelect:',
              'acceptFeaturePick:', 'WcHitTestSketch', 'Select…', 'Edit Sketch Geometry']:
    assert token in cocoa_native

# Every built-in dialogue has a distinct waifu assignment rather than sharing
# the fallback image. The fallback remains available for future templates.
waifu_assignments = re.findall(
    r'private __gshared const FeatureDialogueDescriptorV1\s+\w+\s*=\s*\n\s*dialogue\(.*?"(waifus/[^"]+\.png)"\.ptr\);',
    dialogues, re.S)
assert len(waifu_assignments) == 34, len(waifu_assignments)
assert len(set(waifu_assignments)) == len(waifu_assignments)
for waifu in waifu_assignments:
    assert Path(waifu).name in waifu_manifest, f'waifu missing from manifest: {waifu}'
assert 'const(char)* waifuImage = "waifus/nightcore.png".ptr' in dialogues
assert 'descriptor->waifu_image' in native and 'gtk_picture_new_for_filename' in native

# Feature-reference fields declare semantic pick roles. Profile picks use the
# real profile resolver, which explicitly accepts a Sketch container.
for token in ['FeatureDialogueSelectionKind.profile', 'FeatureDialogueSelectionKind.solidBody',
              'FeatureDialogueSelectionKind.path', 'FeatureDialogueSelectionKind.anyFeature']:
    assert token in dialogues
assert 'return resolveProfile(model, featureId, &profile);' in dialogues
assert 'if(feature.kind==FeatureKind.sketch)' in profiles
assert 'regionChildren==1&&chainChildren==0' in profiles
assert 'resolveSketchMixedLoop' in profiles and 'resolveSketchLineLoop' in profiles
assert 'feature_dialogue_accept_selection' in native
assert 'graphics area or Model Navigator' in native

# Editing is one semantic journal transaction preserving EntityId/name rather
# than delete/recreate. Dependency order/depth is validated before commit.
assert '"feature_edit".ptr' in interpreter
assert 'redefineFeature' in model
assert 'auto replacement = *current;' in model
assert 'sourceIndex >= index' in model
assert 'proposedDepths' in model
assert 'markDependantsDirty(featureId, OperandKind.feature)' in model

# Double activation asks for a feature dialogue first and only falls back to
# read-only properties for unsupported/derived history entries.
activation = re.search(r'static void model_row_activated_cb\(.*?\n\}', native, re.S)
assert activation
assert 'feature_dialogue_for_feature' in activation.group(0)
assert 'show_feature_dialogue' in activation.group(0)
assert 'show_feature_properties' in activation.group(0)

# Commands which are not truly implemented must remain disabled rather than
# opening a broken pseudo-dialogue.
for command in ['pmi.annotation_plane', 'pmi.balloon', 'pmi.validate']:
    line = next(line for line in pmi.splitlines() if f'"{command}".ptr' in line)
    assert 'RibbonCommandFlags.planned' in line

assert 'src/waifucad/gui/feature_dialogues.d' in build

# Sketch-as-profile must work during preview recompute as well as in the exact
# kernel. This prevents a valid Sketch extrusion from being inserted and then
# failing recompute before WaifuBRep gets a chance to build it.
preview = (root / 'src/waifucad/kernel/builtin_preview.d').read_text()
assert 'resolveProfile' in preview
assert 'semanticProfileBounds(model, feature.operands[0].featureId' in preview
assert 'profile.frame.zAxis.x * distance' in preview
assert 'case FeatureKind.sketch:' in preview

# Every filesystem-oriented GUI operation offers a native chooser. Run Script
# and Run Journal are immediate chooser workflows; Record Journal is a
# save/stop toggle. File fields in import/export dialogues have Browse… too.
gui_app = (root / 'src/apps/waifucad_gui.d').read_text()
command_console = (root / 'src/waifucad/gui/command_console.d').read_text()
modelling_section = (root / 'src/waifucad/sections/modelling/section.d').read_text()
for token in ['GtkFileChooserNative', 'WC_PATH_CHOOSER_RUN_SCRIPT',
              'WC_PATH_CHOOSER_START_JOURNAL', 'WC_PATH_CHOOSER_RUN_JOURNAL',
              'journal_start', 'journal_stop()', 'journal_run', 'Browse…']:
    assert token in native
assert 'modelling.run_journal' in modelling_section
assert 'context.journal = &journal;' in gui_app
assert '"journal_start".ptr' in interpreter
assert '"journal_stop".ptr' in interpreter
assert '"journal_run".ptr' in interpreter
assert 'Feature dialogue failed:' in native
assert 'SCL command failed (%d): %s' in command_console
assert 'Model recompute failed after command (%d): %s' in command_console
print('Feature-dialogue static contract passed.')

