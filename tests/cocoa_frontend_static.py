#!/usr/bin/env python3
"""Static contract for the native macOS Cocoa front-end policy.

macOS must default to its native Cocoa/AppKit front-end; GTK4 is an optional
fallback there and must never be a macOS build requirement. LoongArch must
stay declared LA64-only.
"""
import json
from pathlib import Path

root = Path(__file__).resolve().parents[1]

# --- macOS GUI policy manifests -------------------------------------------
targets = json.loads((root / 'config/targets.json').read_text())
macos_targets = [t for t in targets['targets'] if t['os'] == 'macos' and t['status'] != 'historical']
assert macos_targets, 'no non-historical macOS targets declared'
for target in macos_targets:
    assert target['guiPolicy'][0] == 'cocoa', f"{target['id']} must prefer the native cocoa front-end first"
    assert 'metal' in target['graphicsPolicy'], f"{target['id']} must keep Metal as native graphics"

gui_config = json.loads((root / 'config/gui.json').read_text())
assert gui_config['osFrontendPreference']['macos'][0] == 'cocoa'

# --- selector/capabilities --------------------------------------------------
capabilities = (root / 'src/waifucad/platform/capabilities.d').read_text()
assert 'cocoa' in capabilities and 'hasCocoa' in capabilities

selector = (root / 'src/waifucad/gui/selector.d').read_text()
assert 'chooseGuiForTarget' in selector and 'GuiFamily.cocoa' in selector
assert 'OsFamily.macos' in selector

# --- front-end scaffold and native shim -------------------------------------
frontend = (root / 'src/waifucad/gui/frontends/cocoa/frontend.d').read_text()
for token in ['cocoaDescriptor', 'cocoaNativeAvailable', 'runCocoaNative',
              'wc_cocoa_native_available', 'wc_cocoa_run', 'GuiFrontendV1',
              '"cocoa".ptr', 'Cocoa / AppKit']:
    assert token in frontend, f'cocoa frontend scaffold is missing {token}'

native_header = (root / 'native/gui/cocoa/wc_cocoa.h').read_text()
native_stub = (root / 'native/gui/cocoa/wc_cocoa_stub.c').read_text()
assert 'WcCocoaWindowConfig' in native_header and 'WcCocoaCallbacks' in native_header
assert 'return 78;' in native_stub and 'wc_cocoa_native_available' in native_stub

# --- native bridge: GTK4 workflow parity over AppKit/Metal ----------------------
bridge = (root / 'native/gui/cocoa/wc_cocoa.m').read_text()
assert 'int wc_cocoa_native_available(void)' in bridge and 'return 1;' in bridge
assert 'int wc_cocoa_run(const WcCocoaWindowConfig *config' in bridge
assert 'WC_COCOA_PARITY_BUILD "2026-09-07-v7"' in bridge
assert 'WaifuCAD Cocoa renderer: exact planar faces' in bridge
for token in ['assets/icons/%s.svg', 'WcRibbonButton',
              'hasHorizontalScroller = YES', 'WcHumanise',
              'MTLCreateSystemDefaultDevice', 'CAMetalLayer',
              'g_callbacks.submit_command', 'g_callbacks.ribbon_template',
              'g_callbacks.feature_action', 'g_callbacks.feature_reorder',
              'initWithContentsOfFile', 'scrollToPoint', 'reflectScrolledClipView',
              'WcResolveProjectPath', 'WC_ASSET_ROOT']:
    assert token in bridge, f'cocoa bridge is missing {token}'

# GTK4 layout/feature parity anchors: rail, navigator pages, graphics pipeline,
# centred command overlay, orbit/zoom/pan/hover/fit interactions, journal verbs.
for token in ['Model Navigator', 'Assembly Navigator', 'AI Agent',
              'nav_model', 'nav_assembly', 'nav_ai',
              'WcProjectPoint', 'WcMakeViewTransform', 'WcHitTestBody', 'WcHitTestPlanarFace',
              'drawBodyBoundsWithTransform', 'drawAllSketches3DWithTransform',
              'drawPlanarBodyFacesWithTransform', 'drawPlanarFaceSelectionWithTransform', 'drawAbsoluteCsys', 'drawAxisTriad',
              'otherMouseDown', 'scrollWheel', 'mouseMoved', 'rightMouseDown', 'keyDown',
              'global.sections', 'global.mods', 'Sections',
              'journal_start', 'journal_run', 'journal_stop()',
              'NSTableViewDropOn', 'menuForEvent', 'WC_COCOA_FEATURE_KIND_SKETCH',
              'Nightcore theme image', 'Command complete — press Esc for viewport navigation',
              'transform = WcMakeEmptyCsysTransform', 'sizeForIconButton',
              'dispatch_async(dispatch_get_main_queue()']:
    assert token in bridge, f'cocoa bridge is missing parity anchor {token}'



# Shared feature-dialogue/sketch parity: Cocoa must consume the same neutral
# descriptor ABI and semantic callbacks rather than falling back to SCL text.
shared_dialogue = (root / 'native/gui/shared/wc_feature_dialogue.h').read_text()
assert '#include "../shared/wc_feature_dialogue.h"' in native_header
for token in ['WcFeatureDialogueDescriptorV1', 'WcFeatureDialogueFieldDescriptorV1',
              'WC_FEATURE_DIALOGUE_SELECTION_PROFILE', 'WC_FEATURE_DIALOGUE_SKETCH_EDITOR']:
    assert token in shared_dialogue, f'shared feature-dialogue ABI is missing {token}'
for token in ['WcCocoaFeatureDialogueFn', 'WcCocoaFeatureDialogueForFeatureFn',
              'WcCocoaFeatureDialogueValueFn', 'WcCocoaFeatureDialogueAcceptSelectionFn',
              'WcCocoaBeginNewSketchFn', 'WcCocoaEditSketchFn', 'WcCocoaFinishSketchFn',
              'WcCocoaSketchAddLineFn', 'WcCocoaSketchAddCircleFn', 'WcCocoaSketchAddRectangleFn']:
    assert token in native_header, f'Cocoa ABI is missing {token}'
for token in ['cocoaFeatureDialogue', 'cocoaFeatureDialogueForFeature',
              'cocoaFeatureDialogueValue', 'cocoaFeatureDialogueAcceptSelection',
              'cocoaBeginNewSketch', 'cocoaEditSketch', 'cocoaFinishSketch',
              'cocoaSketchAddLine', 'cocoaSketchAddCircle', 'cocoaSketchAddRectangle']:
    assert token in frontend, f'Cocoa D bridge is missing {token}'
for token in ['showFeatureDialogue:', 'featureDialogueApply:', 'acceptFeaturePick:',
              'WcHitTestSketch', 'WcHitTestCsysPlane', 'beginNewSketch', 'beginEditSketch:',
              'finishSketch', 'commitSketchX:', 'WcUpdateSnapCandidates', 'showSnapChoiceMenuForView:',
              'sketchLineTool:', 'sketchCircleTool:', 'sketchRectangleTool:', 'cmd_finish_sketch',
              'layoutNavigatorTable', 'featureName', 'csysPlane = WcString(planes[pi])']:
    assert token in bridge, f'Cocoa bridge is missing workflow parity anchor {token}'
for forbidden in ['GTK4-only', 'Interactive sketch editing is GTK4-only',
                  'Feature dialogues and sketch interaction remain GTK4-only']:
    assert forbidden not in bridge, f'Cocoa bridge still contains obsolete fallback: {forbidden}'

# Cocoa picker must re-arm an already-selected navigator row, and an empty document
# must use the same y-down transform for the grid and CSYS when cursor-centred zoom changes pan.
assert '[self.table deselectAll:nil];' in bridge
assert 'WcMakeEmptyCsysTransform(width, viewHeight)' in bridge


# Ribbon commands must not use the stock rounded AppKit pill: it does not
# reproduce GTK4's vertical SVG+caption command layout.
assert '@interface WcRibbonButton : NSButton' in bridge
assert 'WcRibbonButton *button = [[WcRibbonButton alloc] initWithFrame:NSZeroRect]' in bridge
assert 'button.iconExtent = iconSize' in bridge
assert 'drawInRect:NSMakeRect(iconX, iconY, iconExtent, iconExtent)' in bridge
assert 'button.imagePosition = NSImageAbove' not in bridge
# Project SVGs are deterministically rasterised before any native NSImage fallback.
loader = bridge.split('static NSImage *WcLoadIcon', 1)[1].split('static NSString *WcHumanise', 1)[0]
assert loader.find('WcRenderSvgIcon(path, size)') < loader.find('initWithContentsOfFile:path')
# Generic bootstrap body bounds are a diagnostic overlay, off by default.
assert 'g_showDiagnosticBodyBounds' in bridge and 'WC_SHOW_BODY_BOUNDS' in bridge
draw = bridge.split('- (void)drawRect:(NSRect)dirtyRect', 1)[1].split('/* Input — GTK4 gesture parity', 1)[0]
assert 'if (g_showDiagnosticBodyBounds)' in draw
assert '[self drawBodyBoundsWithTransform:&transform height:height];' in draw
assert '[self drawPlanarBodyFacesWithTransform:&transform height:height];' in draw
assert draw.find('[self drawPlanarBodyFacesWithTransform:&transform height:height];') < draw.find('[self drawPlanarFaceSelectionWithTransform:&transform height:height];')
# The fixed AppKit ribbon must keep all seven Sections visible: compact two-row
# geometry, first row visually on top, and no 70 px natural-height overflow.
assert 'const CGFloat sectionHeight = 44.0;' in bridge
assert 'rowTotal - 1u - rowIndex' in bridge
assert 'iconSize:18.0' in bridge
# Built-in Section descriptors must reference real project-owned SVG names.
modelling_section = (root / 'src/waifucad/sections/modelling/section.d').read_text()
pmi_section = (root / 'src/waifucad/sections/pmi/section.d').read_text()
section_registry = (root / 'src/waifucad/sections/registry.d').read_text()
for icon_name in ['tab_home', 'nav_assembly', 'tab_pmi', 'tab_notes', 'tab_tools', 'nav_ai', 'cmd_record']:
    assert (root / 'assets/icons' / f'{icon_name}.svg').exists(), f'missing Section SVG {icon_name}'
assert 'result.iconName = "tab_home".ptr;' in modelling_section
assert 'result.iconName = "tab_pmi".ptr;' in pmi_section
for icon_name in ['nav_assembly', 'tab_notes', 'tab_tools', 'nav_ai', 'cmd_record']:
    assert f'"{icon_name}".ptr' in section_registry
# ARC-managed Objective-C objects must not live in the memset-cleared C state struct.
state_block = bridge.split('typedef struct WcCocoaState', 1)[1].split('} WcCocoaState;', 1)[0]
assert 'NSTimer *' not in state_block
assert 'static NSTimer *g_snapTimer = nil;' in bridge

# AI patch context must include Objective-C sources; otherwise future coding
# agents see the Cocoa header/tests but not the implementation being fixed.
make_todos = (root / 'make_todos.sh').read_text()
assert '*.m|*.mm' in make_todos, 'make_todos.sh must include Objective-C .m/.mm sources'

# Icon names cross the C ABI through the layout-compatible descriptor mirrors.
assert 'const char *icon_name;' in native_header
assert 'WcCocoaRibbonSnapshot' in native_header and 'WcCocoaSectionEntry' in native_header
assert 'cast(const(WcCocoaRibbonSnapshot)*)ribbon' in frontend
assert 'cast(const(WcCocoaSectionEntry)*)entries' in frontend
# Semantic SCL feature actions/reorders mirror the GTK4 trampolines.
for token in ['feature_delete', 'feature_move_up', 'feature_move_down',
              'feature_move_after', 'feature_move_before']:
    assert f'"{token}".ptr' in frontend, f'cocoa frontend is missing {token}'

# --- GUI host selection -------------------------------------------------------
app = (root / 'src/apps/waifucad_gui.d').read_text()
assert 'version (WaifuCadGuiCocoa)' in app
assert 'runCocoaNative' in app and 'runGtk4Native' in app  # gtk4 token is a GTK4-static-contract requirement
assert 'guiNativeAvailable' in app and 'runGuiNative' in app

# --- build system ---------------------------------------------------------------
build = (root / 'build.sh').read_text()
assert 'detect_target_os' in build and 'build_native_cocoa' in build
assert '-d-version=WaifuCadGuiCocoa' in build and '-fversion=WaifuCadGuiCocoa' in build
assert 'wc_cocoa_stub.c' in build and 'wc_cocoa.m' in build
macos_branch = build.split('if [ "$gui_target_os" = macos ]; then', 1)[1].split('build_native_gtk4', 1)[0]
assert 'pkg-config' not in macos_branch, 'macOS GUI branch must not probe GTK4 via pkg-config'
for forbidden in ['wc_gtk4', 'frontends/gtk4', 'GTK4_LINK_FLAGS']:
    assert forbidden not in macos_branch, f'macOS GUI branch must not compile or link GTK4 ({forbidden})'
# Framework link flags must be spelled per compiler kind (LDC wraps with -L=).
cocoa_native = build.split('build_native_cocoa() {', 1)[1].split('\n}\n', 1)[0]
assert '-L=-framework -L=Cocoa -L=-framework -L=Metal -L=-framework -L=QuartzCore' in cocoa_native
assert '"-framework Cocoa -framework Metal -framework QuartzCore"' in cocoa_native
assert 'cocoa_dl_flag_ldc' in macos_branch and 'cocoa_dl_flag_gdc' in macos_branch

# --- LoongArch stays LA64-only ----------------------------------------------------
architectures = json.loads((root / 'config/architectures.json').read_text())
loong = [a for a in architectures['architectures'] if a['id'] == 'loongarch64']
assert loong and loong[0]['bits'] == 64 and loong[0]['family'] == 'LoongArch'
assert any(t['id'] == 'linux-loongarch64' and t['arch'] == 'loongarch64' for t in targets['targets'])
target_d = (root / 'src/waifucad/platform/target.d').read_text()
assert 'loongarch64' in target_d
assert 'static assert(architectureAddressBits(CpuArchitecture.loongarch64) == 64);' in target_d

print('Cocoa macOS front-end and LoongArch static contract passed.')


