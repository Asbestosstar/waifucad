# Cocoa native bridge

`wc_cocoa.h` defines the C ABI between the BetterC D host and the native
macOS front-end. `wc_cocoa.m` is the functional AppKit/Metal bridge (v1):
native window, Sections ribbon row plus a horizontally scrolling contextual
command row (project SVG icons from `assets/icons/` above humanised
captions, matching the GTK4 compact-ribbon conventions), shared-path
command console, model navigator rail and a Metal clear-pass viewport with
an isometric bounds-wireframe overlay. Every widget action routes through
the semantic SCL/journal command path — never direct model mutation.

`wc_cocoa_stub.c` is the headless fallback used on non-macOS build hosts so
the macOS GUI target always links (cross/CI layouts); it reports the bridge
as unavailable and returns 78.

`build.sh` compiles `wc_cocoa.m` with `-fobjc-arc` and links
`-framework Cocoa -framework Metal -framework QuartzCore` when the build
host is macOS, and falls back to the stub otherwise. Do not add GTK4 probes
or dependencies to the macOS GUI path.

Still TODO for full GTK4 parity (tracked in AGENTS.MD): data-driven feature
dialogues, sketch creation/snapping interaction, Model Navigator
reordering/properties, `assets/locales/` label lookup, and the dedicated
Metal WaifuBRep renderer replacing the bounds-wireframe overlay.
