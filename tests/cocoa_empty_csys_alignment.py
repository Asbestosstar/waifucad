#!/usr/bin/env python3
from pathlib import Path

root = Path(__file__).resolve().parents[1]
text = (root / 'native/gui/cocoa/wc_cocoa.m').read_text()
start = text.index('- (void)drawGridWithHeight:')
end = text.index('- (void)drawBodyBoundsWithTransform:', start)
block = text[start:end]
assert 'WcMakeEmptyCsysTransform(width, viewHeight)' in block
assert 'originY = height - sy' in block
assert 'double originY = height * 0.5 - g_state.pan_y;' in block
assert 'double originY = height * 0.5 + g_state.pan_y;' not in block
print('Cocoa empty-document CSYS/grid alignment regression passed.')
