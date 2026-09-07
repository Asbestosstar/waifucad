#!/usr/bin/env python3
"""Body bounds are a debug overlay, not the default CAD display."""
from pathlib import Path
root = Path(__file__).resolve().parents[1]
cocoa = (root / "native/gui/cocoa/wc_cocoa.m").read_text()
gtk = (root / "native/gui/gtk4/wc_gtk4.c").read_text()
assert 'WC_SHOW_BODY_BOUNDS' in cocoa
assert 'if (g_showDiagnosticBodyBounds)' in cocoa
assert 'WC_SHOW_BODY_BOUNDS' in gtk
assert 'if (state->show_body_bounds)' in gtk
print('Default body-bounds display contract passed.')

# Exact planar bodies must remain visible even when diagnostic bounds are off.
assert 'drawPlanarBodyFacesWithTransform' in cocoa
assert '[self drawPlanarBodyFacesWithTransform:&transform height:height];' in cocoa
assert 'draw_planar_body_faces' in gtk
assert 'draw_planar_body_faces(cr, width, height, state);' in gtk
