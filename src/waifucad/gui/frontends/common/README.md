# Shared toolkit-neutral front-end core

`frontend.d` in this directory is the single D implementation shared by every
GUI front-end (Cocoa/AppKit, GTK4 and future ports): the neutral `WcGui*` ABI
structs, the callback table, and all model/ribbon/sketch/feature-dialogue
bridging. A concrete front-end module under `src/waifucad/gui/frontends/<id>/`
is a thin wrapper that declares its native `wc_<id>_native_available` /
`wc_<id>_run` bridge symbols and instantiates the shared
`guiFrontendAvailable!` / `runGuiFrontend!` templates.

The native counterpart is `native/gui/shared/wc_gui_abi.h`. Make behavioural
and ABI changes here, once — never in a per-toolkit copy. See `docs/GUI.md`
for the front-end/back-end extension recipe.
