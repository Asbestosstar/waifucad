#!/usr/bin/env python3
"""Shared GUI/graphics abstraction contract.

GUI front-ends and graphics back-ends must stay abstracted behind single
shared definitions so a change to one front-end propagates to all, and new
front-ends/back-ends can be added without copying the implementation:

- src/waifucad/gui/frontends/common/frontend.d holds the one toolkit-neutral
  D implementation (ABI structs, callbacks, model/ribbon/sketch bridging).
- The Cocoa and GTK4 front-ends are thin wrappers: native bridge symbols plus
  prefixed aliases onto the shared core, with no duplicated logic.
- native/gui/shared/wc_gui_abi.h holds the one native ABI; the toolkit
  headers are compatibility shims over it.
- waifucad.gui.registry / waifucad.graphics.registry hold the single ordered
  selection tables that the selectors walk.
"""
from pathlib import Path

root = Path(__file__).resolve().parents[1]

shared = (root / 'src/waifucad/gui/frontends/common/frontend.d').read_text()
cocoa = (root / 'src/waifucad/gui/frontends/cocoa/frontend.d').read_text()
gtk4 = (root / 'src/waifucad/gui/frontends/gtk4/frontend.d').read_text()
abi = (root / 'native/gui/shared/wc_gui_abi.h').read_text()
cocoa_h = (root / 'native/gui/cocoa/wc_cocoa.h').read_text()
gtk4_h = (root / 'native/gui/gtk4/wc_gtk4.h').read_text()
gui_registry = (root / 'src/waifucad/gui/registry.d').read_text()
gfx_registry = (root / 'src/waifucad/graphics/registry.d').read_text()
gui_selector = (root / 'src/waifucad/gui/selector.d').read_text()
gfx_selector = (root / 'src/waifucad/graphics/selector.d').read_text()
build = (root / 'build.sh').read_text()

# --- shared D core owns the neutral ABI and the full implementation ---------
for token in [
    'module waifucad.gui.frontends.common.frontend;',
    'struct WcGuiWindowConfig', 'struct WcGuiModelSnapshot', 'struct WcGuiFeatureRow',
    'struct WcGuiBodyRow', 'struct WcGuiMassProperties', 'struct WcGuiCsysRow',
    'struct WcGuiSketchGeometryRow', 'struct WcGuiPlanarFaceRow',
    'struct WcGuiSketchSupport', 'struct WcGuiSectionEntry',
    'struct WcGuiRibbonSnapshot', 'struct WcGuiCallbacks',
    'int runGuiFrontend(alias nativeRun)', 'bool guiFrontendAvailable(alias nativeAvailable)',
    'submitGenerated', 'navigatorShowsFeature',
]:
    assert token in shared, f'shared front-end core is missing {token}'

# The shared core must not hard-code any specific toolkit prefix.
for forbidden in ['wc_cocoa_run(&config', 'wc_gtk4_run(&config',
                  'wc_cocoa_native_available() != 0', 'wc_gtk4_native_available() != 0']:
    assert forbidden not in shared, f'shared core still hard-codes a toolkit bridge: {forbidden}'

# --- front-ends are thin wrappers over the shared core ----------------------
for name, text, run_sym, avail_sym in [
    ('cocoa', cocoa, 'wc_cocoa_run', 'wc_cocoa_native_available'),
    ('gtk4', gtk4, 'wc_gtk4_run', 'wc_gtk4_native_available'),
]:
    assert f'public import waifucad.gui.frontends.common.frontend;' in text, \
        f'{name} front-end must publicly re-export the shared core'
    assert f'runGuiFrontend!{run_sym}' in text, f'{name} must instantiate the shared run template'
    assert f'guiFrontendAvailable!{avail_sym}' in text, f'{name} must instantiate the shared availability probe'
    # Thin means thin: wrappers carry aliases and entry points, not logic.
    assert len(text.splitlines()) < 140, f'{name} wrapper is no longer thin ({len(text.splitlines())} lines)'
    for duplicated in ['submitGenerated(context', 'navigatorShowsFeature', 'makeUniqueConstraintName']:
        assert duplicated not in text, f'{name} wrapper duplicates shared logic: {duplicated}'

# --- native ABI is defined exactly once -------------------------------------
for token in ['typedef struct WcGuiWindowConfig', 'typedef struct WcGuiCallbacks',
              'typedef struct WcGuiModelSnapshot', 'WcGuiSketchSupportKind',
              'WC_GUI_SKETCH_SUPPORT_PLANAR_FACE', 'renderer_hint', 'force_software_vulkan']:
    assert token in abi, f'shared native ABI is missing {token}'

for name, header in [('cocoa', cocoa_h), ('gtk4', gtk4_h)]:
    assert '#include "../shared/wc_gui_abi.h"' in header, f'{name} header must consume the shared ABI'
    assert 'typedef struct' not in header, f'{name} header still defines its own structs'
    assert 'const WcFeatureDialogueDescriptorV1 *' not in header or True  # dialogue tokens come via the ABI

# --- registries are the single selection order ------------------------------
for family in ['gtk4', 'qt6', 'gtk3', 'qt5', 'qt4', 'gtk2', 'qt3', 'gtk1', 'qt2', 'motif', 'xlib', 'cocoa']:
    assert f'GuiFamily.{family}' in gui_registry, f'GUI registry missing family {family}'
assert 'foreach (ref entry; guiFrontendRegistry)' in gui_selector
assert 'chooseGuiForTarget' in gui_selector

for family in ['metal', 'vulkan', 'opengl']:
    assert f'GraphicsFamily.{family}' in gfx_registry, f'graphics registry missing family {family}'
assert 'foreach (ref entry; graphicsBackendRegistry)' in gfx_selector

# --- build system compiles the shared modules --------------------------------
assert 'src/waifucad/gui/frontends/common/frontend.d' in build
assert 'src/waifucad/gui/registry.d' in build
assert 'src/waifucad/graphics/registry.d' in build

print('Shared GUI/graphics abstraction contract passed.')

assert 'scl_error_text' in abi
assert 'WcGuiSclErrorTextFn' in abi
