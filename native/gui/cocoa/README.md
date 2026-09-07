# Cocoa native bridge

`wc_cocoa.h` defines the C ABI between the BetterC D host and the native
macOS front-end; it is a layout-compatible mirror of the GTK4 bridge ABI,
so the D host passes the same toolkit-neutral ribbon/section descriptors
and semantic row data to both front-ends. `wc_cocoa.m` is the functional
AppKit/Metal bridge (v2, GTK4 layout/feature parity): ribbon with
persistent Sections/Mods tabs + contextual tab row + horizontally
scrolling icon command groups (project SVGs from `assets/icons/`,
humanised captions, compact-mode rules), Nightcore art top-right,
Model/Assembly/AI navigator rail with collapsible navigator pane (feature
rows with exact/preview/failed badges, CSYS-plane and planar-face child
rows, right-click Edit-Properties/Fit/Delete, drag-and-drop dependency-safe
reordering), graphics area running the GTK4 draw pipeline (grid,
translucent body bounds, sketches on their real support frames, planar-face
hover/selection highlight, CSYS frames with positive-quadrant planes, axis
triad) over a Metal clear pass, with middle-drag orbit, cursor-centred
wheel zoom, WASD pan, Home reset, body/face hit-test selection and Fit
menus, plus the centred command-console overlay and status bar. Every
widget action routes through the semantic SCL/journal command path — never
direct model mutation.

`wc_cocoa_stub.c` is the headless fallback used on non-macOS build hosts so
the macOS GUI target always links (cross/CI layouts); it reports the bridge
as unavailable and returns 78.

`build.sh` compiles `wc_cocoa.m` with `-fobjc-arc` and links
`-framework Cocoa -framework Metal -framework QuartzCore` when the build
host is macOS, and falls back to the stub otherwise. Do not add GTK4 probes
or dependencies to the macOS GUI path.

Still TODO for full GTK4 parity (tracked in AGENTS.MD): data-driven feature
dialogues (ribbon commands submit their semantic SCL template and report
the result instead), interactive sketch mode with snapping,
`assets/locales/` label lookup, and the dedicated Metal WaifuBRep renderer
replacing the GTK4-equivalent bounds-wireframe display.
