# GUI architecture

WaifuCAD keeps **GUI front-end** and **3D graphics back-end** selection separate. A front-end owns native widgets/windowing; a graphics back-end owns viewport rendering. This permits combinations such as GTK4 + Vulkan on a current Linux workstation and, later, Motif/Xlib + OpenGL on historical UNIX targets.

## Shared front-end core

All GUI front-ends share a single toolkit-neutral implementation; there is no per-toolkit copy of the windowing/bridging logic:

- **D side** — `src/waifucad/gui/frontends/common/frontend.d` owns the neutral `WcGui*` ABI structs, the callback table, and every model → snapshot / ribbon / sketch / feature-dialogue bridge. A concrete front-end module (for example `frontends/cocoa/frontend.d` or `frontends/gtk4/frontend.d`) is a thin wrapper: it declares its native `wc_<id>_native_available` / `wc_<id>_run` symbols, instantiates the shared `guiFrontendAvailable!` / `runGuiFrontend!` templates, and re-exports its historical prefixed names as aliases.
- **Native side** — `native/gui/shared/wc_gui_abi.h` is the single C ABI. The toolkit headers (`native/gui/cocoa/wc_cocoa.h`, `native/gui/gtk4/wc_gtk4.h`) are compatibility shims that typedef the prefixed names onto the neutral types.
- **Selection** — `src/waifucad/gui/registry.d` holds the single ordered front-end preference table; `selector.d` walks it. Graphics mirrors this with `src/waifucad/graphics/registry.d` and its selector.

A behavioural change is therefore made once, in the shared core or the shared ABI, and every front-end picks it up.

### Adding a new GUI front-end

1. Add the family to `GuiFamily` plus a capability flag in `src/waifucad/platform/capabilities.d`.
2. Add one row to `guiFrontendRegistry` in `src/waifucad/gui/registry.d` (position encodes preference).
3. Create `src/waifucad/gui/frontends/<id>/frontend.d` as a thin wrapper over the shared core, copying the Cocoa/GTK4 pattern.
4. Create `native/gui/<id>/` with a bridge that consumes `native/gui/shared/wc_gui_abi.h` and exports `wc_<id>_native_available` / `wc_<id>_run`.
5. List the new D module in `build.sh` next to the shared core.

### Adding a new graphics back-end

1. Add the family to `GraphicsFamily` plus capability flags in `capabilities.d`.
2. Add one row to `graphicsBackendRegistry` in `src/waifucad/graphics/registry.d` with its availability predicate.
3. Teach the native viewport bridges to consume the new renderer hint (the neutral `WcGuiWindowConfig.renderer_hint` / `force_software_vulkan` fields already carry the selection across the ABI).

### Vulkan discovery and /opt Mesa

The GPU probe (`native/graphics/wc_gpu_probe.c`) checks the system Vulkan
loader and ICD paths first, then scans the `/opt` directory for versioned
Mesa trees (any `/opt/*mesa*` entry) with Vulkan support — ICD manifests
under `share/vulkan/icd.d` and/or a `libvulkan.so.1` loader. When several
versions qualify, the one with manifests plus a loader wins, ties going to
the lexicographically later (newer) version. If the system has no loader, or
the loader exposes no devices, the probe configures the loader with the /opt
Mesa's ICD manifests (`VK_ICD_FILENAMES`, only when unset) and retries. The
result is reported in the probe summary and the `has_opt_mesa` /
`opt_mesa_has_vulkan` / `opt_mesa_used` fields. The GTK4 `--lavapipe` path
uses the same scan (`wc_gpu_opt_mesa_vulkan` with the lavapipe filter) when
no system lavapipe ICD exists. Tests can point the scan elsewhere with
`WC_OPT_MESA_ROOT`.

The baseline layout remains usable at **1024×768** and uses the `nightcore_2008` visual tokens without copying proprietary CAD artwork or controls.

## GTK4 status

GTK4 is the first native front-end whose earlier bounds-window revision was built and runtime-verified by the user on RHEL Linux x86-64. The expanded ribbon/navigation revision documented here still requires a fresh user-host build/run check. Running the executable with **no arguments** opens the native GTK4 application:

```sh
./bin/waifucad-gui
```

Optional bring-up switches remain available:

```sh
./bin/waifucad-gui --renderer auto
./bin/waifucad-gui --renderer vulkan
./bin/waifucad-gui --renderer gl
./bin/waifucad-gui --lavapipe
./bin/waifucad-gui --console
./bin/waifucad-gui --bootstrap-info
```

`--bootstrap-info` is intentionally non-interactive so automated smoke tests can inspect GUI-host state without entering the GTK event loop. `--console` keeps the historical terminal command prototype.

## Contextual ribbon

There is no separate application toolbar above the ribbon. **Sections** and **Mods** are persistent ribbon tabs in every Section, including registered application contexts whose contextual command ribbon is still planned. The Sections tab also contains a Mods group so extension management remains reachable while browsing Sections. **Scripts** is a group in each implemented Section's Home ribbon. Choosing a Section changes the contextual tabs without replacing the document or viewport.

Modelling and PMI own toolkit-neutral ribbon descriptors under their Section directories. GTK4 now consumes those descriptors directly and renders:

- a real contextual tab strip;
- adaptive command groups that use normal icons when space permits, compact icons when constrained, and rows of at most four buttons before falling back to horizontal scrolling;
- SVG-icon command buttons loaded by descriptor `iconName`;
- planned commands as visibly disabled controls rather than fake working features.

Project-owned bootstrap icons live under `assets/icons/`. Future Qt/Motif/Xlib front-ends should consume the same descriptors and icon names rather than invent independent command sets.

Ribbon command buttons do not write kernel memory directly. Simple actions run immediately; parameterised operations open data-driven feature dialogues whose Create/Apply action emits semantic Ruby-like SCL through the normal command/recompute/journal path. Filesystem actions expose native GTK file choosers: import/export dialogue file fields have **Browse…**, **Run Script…** and **Run Journal…** open files directly, and **Record Journal** chooses a destination before recording starts. The visible command line remains an optional expert interface rather than a required ribbon step.

The Nightcore theme image is loaded from `waifus/nightcore.png` and is displayed at the **top-right of the ribbon**, leaving the left navigator and viewport available for CAD work.

## Menu bar

Both native front-ends render an NX-style menu bar above the ribbon with **File / Edit / View / Insert / Tools / Help** menus. Every entry routes through the same semantic SCL/journal paths as the equivalent ribbon command — File manages journals, scripts, screenshots and confirmed part reinitialisation; Edit edits, deletes and dependency-safe reorders the selected history feature; View fits the model and toggles the compact ribbon; Insert starts sketches and direct primitives; Tools reports exact mass properties. Undo/Redo run the SCL `undo()`/`redo()` commands against the bounded undo/redo transaction log (disabled when nothing can be undone or redone). The GTK4 front-end uses `GtkMenuButton` dropdown popovers; the Cocoa front-end installs a real `NSMenu`. Keyboard shortcuts: **F** fits all, **/** focuses the ribbon command finder.

### Compact layout

The baseline layout is deliberately NX-dense: the ribbon scroller is 68 px tall, navigator rail buttons are 36 px, and the status bar carries a live pointer readout alongside the feature/exact/preview/failed counts. Ribbon density still auto-shrinks when the window narrows, but an explicit **View ▸ Toggle Compact Ribbon** choice now wins over auto-density until it is toggled back.

## Left navigator rail

GTK4 provides an NX-inspired left application rail without copying proprietary resources. It switches between:

- **Model Navigator** — live model name, feature/exact/preview/failed counts, and compact feature-history rows. Sketch child entities such as individual lines/circles/rectangles are deliberately omitted from this history view; the sketch itself is the history feature;
- **Assembly Navigator** — visible application context placeholder backed by the existing planned Assembly Section/load-policy contract;
- **AI Agent** — read-only model-summary panel using the current model snapshot while external provider connection remains future work.

The Model Navigator content pane has no forced minimum width and may be collapsed completely with the main paned divider. The application rail is a separate fixed-width sibling, so Model/Assembly/AI buttons remain visible even when the content pane is collapsed. Its default width is deliberately compact for 1024×768; the part name stays in a fixed header while the history list gets horizontal/vertical scrollbars when long labels require more room. Navigator and rail background colours come from the active theme tokens.

The Model Navigator also supports semantic history editing through its row context menu and drag-and-drop. Right-click a real feature for **Properties**, **Fit to Feature**, **Delete**, and **Edit Sketch** where applicable. Dragging a feature before/after another history row emits `feature_move_before` / `feature_move_after`; the model validates the complete proposed order before moving anything, so dependency-blocked drops are rejected atomically. Deletion remains `feature_delete` and is rejected while another feature still references the selected feature. The old bottom Up/Down/Delete button strip is intentionally gone.

Double-activating a supported feature row reopens its feature dialogue; a Sketch row provides the Sketch dialogue and access to the geometry editor. The Assembly and AI entries are deliberately honest about unfinished data models. They are navigation/UI foundations, not claims that full assembly management or an external AI provider has already landed.


Every newly initialised part contains an `absolute_csys` construction feature at **0,0,0** with canonical X/Y axes. It is pinned at the history root and cannot be deleted or reordered below another feature; its XY/YZ/XZ planes are available as sketch supports in Model Navigator.

## Sketch editing

The Modelling **Sketch** command now enters an explicit support-selection workflow. A new sketch must be attached to a datum plane, an XY/YZ/XZ plane derived from any datum CSYS, or a planar exact B-rep face. Supports can be selected from Model Navigator; planar faces can also be selected directly in the graphics area. CSYS/face supports create associative datum planes through SCL before the sketch is created. Double-clicking/activating an existing sketch in Model Navigator reopens the same sketch for editing.

While sketch mode is active the contextual ribbon changes to a compact Sketch ribbon with **Line**, **Circle**, **Rectangle** and **Finish Sketch** controls. Geometry is drawn directly in the graphics area:

- Line: click start, then end.
- Circle: click centre, then a radius point.
- Rectangle: click one corner, then the opposite corner.
- Escape cancels the in-progress entity.
- Mouse motion shows a live preview before the second click.
- Mouse wheel zooms the sketch **towards the cursor position** and middle-button drag pans the sketch view.
- Existing line endpoints are snap candidates. A nearby endpoint highlights and committed line endpoints create a semantic coincident constraint.
- When multiple endpoints occupy the snap tolerance, hovering for one second shows an ellipsis; clicking then opens a chooser dialogue instead of silently guessing.

Committed entities are not temporary GTK shapes. The frontend emits `sketch_line`, `sketch_circle_at` or `sketch_rect_at` through `CommandConsoleState.submit`, so model storage, recompute and semantic journalling use the same path as scripts. `Finish Sketch` emits `end_sketch` and returns to the normal 3D navigation mode.

This remains an early interactive 2D sketch editor. Endpoint snapping and support selection are present; constraint glyphs, selection/manipulation of arbitrary sketch entities, dimensional input overlays and richer sketch tools remain future work.

## Viewport navigation

Current GTK4 controls are:

- **Mouse wheel:** zoom in/out around the current mouse cursor rather than the viewport centre.
- **Middle mouse button + drag:** orbit/change view angle in 3D; pan the orthographic view while editing a sketch.
- **W / A / S / D:** pan in screen space.
- **Shift + W/A/S/D:** faster pan.
- **Home:** reset view orientation, zoom and pan.
- **Enter:** focus the command line when the viewport owns focus.
- **Escape:** return focus to the viewport.
- **Right-click viewport:** Fit whole model, Fit Selected, or inspect Properties for the current selection.

Keyboard navigation is suppressed whenever an editable text widget such as the command line owns focus. Clicking the viewport returns navigation focus to it.

Normal graphics-area clicking performs P1 body picking against each body's display bounds. Selecting a body highlights its complete bounds plus all currently exposed planar-face children; face-level selection remains available during the explicit Sketch-support workflow. All resolvable datum CSYS features are drawn in the graphics area with labelled X/Y/Z axes; the default `absolute_csys` therefore appears at **0,0,0** immediately in every part. This is separate from the fixed view-orientation triad.

The current P1 viewport still renders display bounds/planar-face overlays through GTK4 `GtkDrawingArea`/Cairo rather than the final tessellated WaifuBRep renderer. The camera and picking controls therefore operate on that bootstrap representation. This is **not** a claim that the dedicated Vulkan WaifuBRep renderer is complete.

## Command console

`src/waifucad/gui/command_console.d` owns the toolkit-neutral command-console state. Native GUI submission calls `CommandConsoleState.submit`, which normalises Ruby-style SCL, performs the semantic operation, and requests the normal WaifuBRep recompute. GTK does not own a second parser.

Examples:

```text
box(:body, 80.mm, 50.mm, 10.mm)
sketch(:profile, :XY)
extrude(:new_body, :profile, 10.mm)
```

## NVIDIA, Mesa and lavapipe bring-up

The native graphics probe is independent from GTK and reports:

- Vulkan loader presence;
- enumerated Vulkan devices;
- hardware vs CPU/software Vulkan devices;
- NVIDIA detection;
- Mesa detection;
- lavapipe/llvmpipe detection.

The GTK status bar displays that result so software Vulkan is not mistaken for a hardware renderer. `--lavapipe` can force a standard Mesa lavapipe ICD path for development where present.

GTK's own GSK compositor may use Vulkan, OpenGL or Cairo, but the dedicated WaifuCAD Vulkan 3D renderer remains a separate P1 task. Renderer/compositor bring-up must not be reported as equivalent to exact WaifuBRep viewport rendering.

## Linux build

The batch target remains independent of GTK. The GUI build uses `pkg-config gtk4`; if GTK4 development metadata is unavailable, a native stub is compiled so batch development still works.

Typical RHEL build:

```sh
sudo dnf install gtk4-devel
./build.sh clean
./build.sh gui
./bin/waifucad-gui
```

## Future front-ends

Qt6, GTK3, Motif and Xlib remain future front-end work. OpenGL legacy rendering and additional GPU-specific back-ends are also intentionally deferred until the GTK4 interaction shell and dedicated modern renderer are mature.



## Feature dialogues

See `docs/FEATURE_DIALOGUES.md` for direct ribbon invocation, editable history and the descriptor ABI.


### Bootstrap body-bounds diagnostics

The native GTK4 and Cocoa front-ends keep the old body-bounds renderer only as a diagnostic overlay. It is disabled by default so approximate display bounds are not mistaken for CAD geometry. Set `WC_SHOW_BODY_BOUNDS=1` to enable it temporarily. Selected-body bounds remain available for selection feedback.


Sketch support is part of the Sketch feature itself. GUI-created CSYS/face sketches do not create `sketch_support*` datum-plane history entries; the sketch directly carries the CSYS-plane or persistent planar-face association.