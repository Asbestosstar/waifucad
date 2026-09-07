# Cocoa / AppKit front-end

Status: functional v1 bridge (native/gui/cocoa/wc_cocoa.m); default native front-end for macOS targets.

Cocoa is the native macOS GUI: AppKit window/ribbon hosting with a
Metal-backed drawing surface. macOS must never require GTK4; per
`config/targets.json` the macOS GUI policy is `cocoa, qt6, gtk4` in that
order, and `build.sh` selects this front-end (and only this front-end's
native shim) whenever the target OS is macOS.

The native bridge lives in `native/gui/cocoa/wc_cocoa.m` (Objective-C,
`-framework Cocoa -framework Metal -framework QuartzCore`) behind the
`wc_cocoa.h` C ABI; this module owns the D-side trampolines (section
entries, contextual ribbon commands with icon names, body rows, SCL
submission). Toolkit headers and Objective-C details stay inside
`native/gui/cocoa/` so BetterC kernel code never imports them. All widget
actions route through the shared semantic SCL/journal command path,
matching the GTK4 contract; no direct model mutation from AppKit callbacks.
Feature dialogues and sketch interaction remain GTK4-only for now; Cocoa
ribbon buttons submit their semantic SCL templates and report results in
the status line.
