# WaifuCAD NX-style menu bar and compact layout patch

This patch completes the desktop chrome of both native front-ends without touching the kernel, journal or Section ABI.

Implemented:
- **GTK4** (`native/gui/gtk4/wc_gtk4.c`): a six-dropdown menu bar (File/Edit/View/Insert/Tools/Help) above the ribbon, built from `GtkMenuButton` + `GtkPopover`; compact CSS block (menubar, dropdown, status); ribbon scroller 94 -> 68 px; navigator rail buttons 42 -> 36 px; auto-density can no longer override a manual compact choice; `F` fits all and `/` focuses the ribbon command finder; status bar gained a live pointer readout updated from `viewport_motion_cb`.
- **Cocoa** (`native/gui/cocoa/wc_cocoa.m`): a `WcAppDelegate` category installing a real `NSMenu` (`installMainMenu`) with the identical action mapping, dispatched through `menuBarAction:`.
- Menu semantics: every mutation still reaches the kernel through the existing `submit_command` / feature-action / feature-dialogue paths — no GUI-click journalling was introduced. File > New Part confirms before `model(:new_part)`; Undo/Redo render as disabled planned controls because the SCL transaction stack does not exist yet.

Verification performed in this environment:
- All edits anchor-matched and written incrementally; GTK4 call signatures verified against the existing file (`open_path_chooser`, `show_feature_dialogue`, `run_feature_action`, `WC_PATH_CHOOSER_*`).
- The sandbox lacks GTK4/AppKit headers, so no native compile was run here; `./build.sh` on a host remains the definitive check.

# WaifuCAD /opt Mesa Vulkan discovery patch


This patch teaches GPU discovery to look for versioned Mesa installations
under /opt so machines whose system stack lacks Vulkan can fall back to an
/opt Mesa build with Vulkan support.

Implemented:
- `wc_gpu_opt_mesa_vulkan()` in `native/graphics/wc_gpu_probe.c`: scans the
  /opt scan root (default `/opt`, overridable with `WC_OPT_MESA_ROOT` for
  tests) for `*mesa*` trees, and picks one with Vulkan support — ICD
  manifests under `share/vulkan/icd.d` and/or a `libvulkan.so.1` loader.
  Preference: manifests + loader > manifests > loader, ties to the newer
  (lexicographically later) version directory. A lavapipe-only filter mode is
  available for software-Vulkan lookups.
- `wc_gpu_probe()` now scans /opt: when the system has no Vulkan loader it
  dlopens the /opt Mesa loader directly; when the loader exposes no devices
  it configures `VK_ICD_FILENAMES` with the /opt Mesa ICD manifests (only if
  unset) and retries instance creation. Findings are exposed via
  `has_opt_mesa` / `opt_mesa_has_vulkan` / `opt_mesa_used`,
  `opt_mesa_root` / `opt_mesa_icd`, and appended to the probe summary.
- The GTK4 `--lavapipe` path falls back to the /opt Mesa lavapipe ICD when
  no system lavapipe manifest exists.
- `tests/gpu_probe.sh` gains a functional fake-/opt test (versioned trees,
  no-Vulkan rejection); `tests/gpu_probe.c` gains /opt field consistency
  assertions.

Verification performed in this environment:
- `tests/gpu_probe.sh` passes, including the fake-/opt version-selection and
  no-Vulkan-rejection cases (run against the system llvmpipe stack).
- Probe compiles clean with `-std=c11 -Wall -Wextra`.
- All other Python/shell static tests unaffected.

# WaifuCAD GUI/graphics abstraction patch

This patch removes the Cocoa/GTK4 duplication and makes GUI front-ends and
graphics back-ends pluggable, so a change made once propagates to every
front-end and future ports can be added without copying code.

Implemented:
- `src/waifucad/gui/frontends/common/frontend.d` is now the single toolkit-neutral
  front-end core: neutral `WcGui*` ABI structs, the callback table, and all
  model/ribbon/sketch/feature-dialogue bridging previously duplicated between
  the Cocoa and GTK4 front-ends (the two files were byte-identical modulo
  prefixes).
- `frontends/cocoa/frontend.d` and `frontends/gtk4/frontend.d` are thin
  wrappers: native bridge symbols, shared-template instantiation, and
  historical prefixed aliases for compatibility.
- `native/gui/shared/wc_gui_abi.h` is the single native ABI; `wc_cocoa.h` and
  `wc_gtk4.h` are compatibility shims typedef'ing the prefixed names.
- `waifucad.gui.registry` / `waifucad.graphics.registry` hold the single
  ordered selection tables; the selectors now walk the tables instead of
  hard-coded if-chains. Adding a front-end/back-end = enum + capability flag +
  one registry row + thin binding (documented in docs/GUI.md).
- Descriptor stubs (GTK1-3, Qt2-6, Motif, Xlib) share `guiFrontendDescriptor`.
- New regression contract: `tests/gui_shared_abi_static.py`.

Verification performed in this environment:
- D compile (`-betterC -wi -I=src`, DMD 2.109.1, no codegen): batch, GTK4 GUI
  and Cocoa GUI targets all compile clean, zero warnings.
- C ABI: both stubs and a cross-header consistency check compile and pass with
  `-std=c11 -Wall -Wextra`.
- All Python static tests pass, including the new `tests/gui_shared_abi_static.py`.
- `tests/cocoa_gui_target.sh`, `cocoa_native_syntax.sh`, `gtk4_native_syntax.sh`,
  `native_temp_files.sh`, `gpu_probe.sh`: pass.
- `make_todos.sh`: pass; PROJECT_TREE.txt and todos.txt regenerated.

Notes:
- A full DMD betterC *link* fails identically before and after this patch:
  DMD emits a druntime `_memsetDouble` helper in betterC codegen; the supported
  LDC/GDC paths are unaffected.
- `tests/ai_protocol_static.py`, `tests/getters_static.py`,
  `tests/scheduler_static.py` and `tests/portability_layout.sh` fail on the
  unmodified baseline too: they reference files absent from this tree
  (docs/ARCHITECTURE.md, docs/AI_MODEL_INSPECTION.md, docs/MULTICORE.md,
  build/arch/loongarch64-linux.sh).

# WaifuCAD Cocoa / GTK4 parity patch

This patch brings the Cocoa/AppKit front-end onto the same shared feature-dialogue and interactive-sketch contracts already used by GTK4, while keeping macOS independent of GTK4.

Implemented:
- Cocoa ribbon commands consume toolkit-neutral `FeatureDialogueDescriptorV1` data.
- `native/gui/shared/wc_feature_dialogue.h` is the shared native neutral dialogue contract for GTK4 and Cocoa.
- Native AppKit create/edit feature panels, semantic profile/body/path picks, native file fields, and identity-preserving `feature_edit` submission through SCL.
- Model Navigator fixes: semantic feature names are distinct from decorated labels, CSYS child-plane identity is preserved, row layout/reload is explicitly sized for AppKit, and double activation reopens editable dialogues/sketches.
- Cocoa interactive sketch mode: datum/CSYS/planar-face support selection, line/circle/rectangle tools, live preview, snapping, one-second ambiguity choice, semantic coincident constraints, edit/finish, and sketch ribbon controls.
- Project/bundle/executable-relative SVG/Nightcore asset lookup so launching outside the source-tree working directory does not drop ribbon icons.
- `make_todos.sh` includes `.m` and `.mm`; `tests/objective_c_context_static.py` verifies generated AI context contains the full Cocoa Objective-C bridge.

Verification performed in the supplied Linux environment:
- Cocoa/static feature-dialogue tests: pass.
- D parser-hazard and semantic compatibility tests: pass.
- Cocoa macOS target-selection regression: pass.
- Cocoa C stub syntax: pass; native Objective-C syntax step is skipped on non-macOS hosts by design.
- `make_todos.sh`: pass; generated `todos.txt` contains the `wc_cocoa.m` body.
- Additional Objective-C delimiter and @interface/@implementation structural check: pass.
- Patch applies cleanly with `git apply --check`.

Not claimed as verified here:
- Native AppKit/Metal compile/run, because this host has no macOS SDK.
- D compile, because neither LDC nor GDC is installed here.
- The future dedicated Metal WaifuBRep renderer. The current Cocoa viewport deliberately remains at the same bootstrap body-bounds rendering level as current GTK4.

`PROJECT_TREE.txt` is intentionally not included as a replacement: the supplied AI context omitted binary waifu/theme assets, so regenerating it in this reconstructed tree would incorrectly remove those entries. After applying this patch to the complete project tree, run `./make_todos.sh` there to regenerate both `PROJECT_TREE.txt` and `todos.txt` correctly.
