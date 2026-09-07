# Cocoa native bridge

`wc_cocoa.h` defines the C ABI between the BetterC D host and the native
macOS front-end. It mirrors the GTK4 host contracts for toolkit-neutral
ribbon/section descriptors, model/navigator rows, data-driven feature
dialogues and interactive sketch operations. `wc_cocoa.m` is the native
AppKit/Metal bridge. All modelling mutations continue through semantic
SCL/journal callbacks rather than direct model access.

The AppKit host now provides the same current GUI workflows as GTK4: project
SVG ribbon icons with bundle/project-root resolution plus an AppKit fallback
renderer for the project SVG subset (so icon display does not depend on
`NSImage` SVG support), persistent Sections/Mods tabs, contextual ribbon
groups, the Model/Assembly/AI rail and collapsible
navigator, editable feature dialogues generated from
`FeatureDialogueDescriptorV1`, semantic profile/body/path selection, native
file choosers, and sketch creation/editing on datum planes, CSYS planes and
planar faces. Sketch mode includes Line/Circle/Rectangle tools, live preview,
endpoint/corner/centre/origin/axis snapping, the one-second ambiguity chooser,
cursor-centred wheel zoom and middle-drag pan. The Model Navigator implements
AppKit's exact `NSTableViewDataSource` selectors (`numberOfRowsInTableView:` and
`tableView:objectValueForTableColumn:row:`); keep those names covered by the
static contract because a near-miss selector causes AppKit to reject the data
source at runtime. Ribbon command cells use the same fixed density-class sizes
as GTK4 rather than `sizeToFit`, keeping buttons uniform.

The graphics area still uses the same bootstrap bounds/sketch/construction
display policy as GTK4, drawn over a Metal clear pass. The dedicated Metal
WaifuBRep renderer is separate graphics-backend work and remains TODO. Locale
label lookup from `assets/locales/` also remains TODO.

`wc_cocoa_stub.c` is the headless fallback used on non-macOS build hosts.
`build.sh` compiles `wc_cocoa.m` with `-fobjc-arc` and links `-framework Cocoa
-framework Metal -framework QuartzCore` on macOS; the macOS GUI path must not
probe or require GTK4.


Generic body bounds are not part of the default CAD display. Set `WC_SHOW_BODY_BOUNDS=1` only when the bootstrap bounds overlay is useful for renderer diagnostics; selected-body bounds remain a selection aid.
