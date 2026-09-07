WaifuCAD Cocoa v7 — navigator planar-face highlight parity

Fixes the macOS runtime issue where selecting an Extrude planar-face child row
in Model Navigator highlighted the row but not the corresponding face in the
viewport.

Cause:
  Cocoa stored the selected face persistent ID correctly, but its drawing path
  only highlighted hovered faces or every face belonging to a selected whole
  body. GTK4 already had the missing third condition: highlight the exact face
  when the selected sketch-support kind is PLANAR_FACE and the persistent ID
  matches.

v7 mirrors that rule in Cocoa, so selecting Face N (planar) in Model Navigator
highlights exactly that B-rep face. Whole-body selection and hover highlighting
remain unchanged.

Install:
  ./INSTALL.command /Users/macbook/git/waifucad

Runtime marker:
  WaifuCAD Cocoa parity build: 2026-09-07-v7
