# GUI front-end port data: cocoa

Native macOS front-end (AppKit + Metal). No package manager dependency: the
bridge builds against the macOS SDK frameworks (`Cocoa`, `Metal`,
`QuartzCore`) with the platform clang. Minimum deployment target should
match the supported macOS releases recorded in `ports/os/macos/`.

`config/targets.json` lists `cocoa` first in the macOS GUI policy; GTK4 on
macOS is an optional fallback (for example via a user-installed toolkit) and
must never be a build requirement for macOS targets.
