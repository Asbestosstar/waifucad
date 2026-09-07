#!/usr/bin/env python3
"""Regression guard: selecting a planar face row must highlight that exact face."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
bridge = (ROOT / "native/gui/cocoa/wc_cocoa.m").read_text()
gtk = (ROOT / "native/gui/gtk4/wc_gtk4.c").read_text()

cocoa_required = [
    'g_state.selected_support_kind == WC_COCOA_SKETCH_SUPPORT_PLANAR_FACE',
    'faces[i].persistent_id == g_state.selected_face_persistent_id',
    'g_state.selected_face_persistent_id = record.faceId;',
    'faceRow.faceId = faces[f].persistent_id;',
]
for token in cocoa_required:
    assert token in bridge, f"Cocoa planar-face selection path missing: {token}"

# Keep the two native front-ends on the same semantic rule.
assert 'state->selected_support_kind == WC_GTK4_SKETCH_SUPPORT_PLANAR_FACE' in gtk
assert 'faces[i].persistent_id == state->selected_face_persistent_id' in gtk

print('Cocoa planar-face navigator highlight regression passed.')
