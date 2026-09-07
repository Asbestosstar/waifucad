# Cocoa / AppKit front-end

Status: functional native macOS front-end with the current GTK4 GUI workflow
contract.

Cocoa is the default macOS GUI. macOS must never require GTK4; the Cocoa D
host passes the same toolkit-neutral ribbon descriptors, feature-dialogue
descriptors, semantic model rows and sketch callbacks through the C ABI in
`native/gui/cocoa/wc_cocoa.h`. The Objective-C implementation lives in
`native/gui/cocoa/wc_cocoa.m`.

Feature creation/editing is descriptor-driven rather than Cocoa-specific.
Profile/body/path selections are validated by the shared D descriptor layer,
and all accepted mutations use semantic SCL/journal transactions. Sketch
creation/editing likewise shares the GTK4 callbacks for support creation,
line/circle/rectangle entities and coincident snapping. No AppKit callback
writes kernel/model memory directly.

Remaining Cocoa-specific work is presentation/backend work rather than a
separate modelling implementation: locale label lookup and the dedicated Metal
WaifuBRep renderer.


Generic body bounds are not part of the default CAD display. Set `WC_SHOW_BODY_BOUNDS=1` only when the bootstrap bounds overlay is useful for renderer diagnostics; selected-body bounds remain a selection aid.
