#!/usr/bin/env python3
from pathlib import Path

root = Path(__file__).resolve().parents[1]
text = (root / 'native/gui/cocoa/wc_cocoa.m').read_text()
start = text.index('- (void)featureDialogueSelect:')
end = text.index('- (BOOL)acceptFeaturePick:', start)
block = text[start:end]
for token in ['self.programmaticSelection = YES;', '[self.table deselectAll:nil];', 'self.programmaticSelection = NO;']:
    assert token in block, f'missing picker re-arm guard: {token}'
assert block.index('[self.table deselectAll:nil];') < block.index('[self.featureDialogPanel orderOut:nil];')
print('Cocoa feature-dialogue navigator picker re-arm regression passed.')
