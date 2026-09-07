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

# --- v1 bridge: icons, compact scrolling ribbon, Metal viewport ----------------
bridge = (root / 'native/gui/cocoa/wc_cocoa.m').read_text()
assert 'int wc_cocoa_native_available(void)' in bridge and 'return 1;' in bridge
assert 'int wc_cocoa_run(const WcCocoaWindowConfig *config' in bridge
for token in ['assets/icons/%s.svg', 'NSImageAbove', 'NSImageLeft',
              'hasHorizontalScroller = YES', 'WcHumanise',
              'MTLCreateSystemDefaultDevice', 'CAMetalLayer',
              'g_callbacks.submit_command', 'g_callbacks.run_ribbon_command',
              'initWithContentsOfFile', 'scrollToPoint', 'reflectScrolledClipView']:
    assert token in bridge, f'cocoa bridge is missing {token}'

# Icon names must cross the C ABI in both directions (header <-> D extern structs).
assert 'const char *icon;' in native_header and 'const char *tab_icon;' in native_header
assert 'const(char)* icon;' in frontend and 'const(char)* tabIcon;' in frontend
assert 'rows[written].icon = ribbon.commands[i].iconName;' in frontend
assert 'rows[written].icon = entries[i].iconName;' in frontend
assert 'ribbon.tabs[t].iconName' in frontend

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
