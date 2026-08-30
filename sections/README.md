# Sections

Sections are WaifuCAD application contexts, analogous to NX Applications.

Built-in Section code belongs under `src/waifucad/sections/<section>/`.  The
permanent **Sections** ribbon tab launches them, and activation swaps the
contextual ribbon while preserving the open document and viewport.

Current application contexts:

- **Modelling** — default; contextual ribbon implemented.
- **PMI** — Product and Manufacturing Information; bootstrap ribbon and PMI
  storage implemented.
- **Assembly** — launcher entry exists; architecture/load policies are planned.
- Drawing, Manufacturing, AI and Journalling — registered placeholders.

Optional out-of-tree first-party Section packages may be staged in this folder
before they are moved into `src/waifucad/sections`.



