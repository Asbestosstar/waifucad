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
