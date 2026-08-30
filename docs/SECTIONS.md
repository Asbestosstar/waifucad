# Sections architecture

A **Section** is WaifuCAD's equivalent of an NX application context.  It is not
just a toolbar category.  A Section owns application-specific code and a
contextual ribbon definition while sharing the current document, viewport,
selection services, journalling, Mods and Scripts infrastructure.

## Ribbon behaviour

The global ribbon chrome always exposes **Sections**, **Mods** and **Scripts**.
The Sections tab contains the application launcher.  Selecting an entry changes
the active `SectionContext` and replaces the contextual ribbon tabs with the
ribbon owned by the new Section.  The document and viewport stay open.

`config/sections.json` defines the default and high-level behaviour.  Toolkit
front-ends must render the descriptors from `src/waifucad/sections/ribbon.d`;
they must not maintain a second, toolkit-specific list of Section commands.

## Modelling

`src/waifucad/sections/modelling/` is the default Section and owns the ribbon
for the modelling work implemented so far.  Sketch creation is a command/mode
inside Modelling, not a separate top-level Section.  The preferred modelling
workflow remains sketch/profile -> extrude/revolve/sweep/loft, with free curves
and dumb bodies available as valid alternatives.

## PMI

`src/waifucad/sections/pmi/` is the Product and Manufacturing Information
Section.  Its bootstrap ribbon has Home, Dimensions, GD&T, Notes and Exchange
tabs.  The section also owns BetterC-safe fixed-capacity PMI annotation types
and storage so future PMI functionality does not get mixed into the modelling
feature graph.

Basic PMI create/edit mutations now have semantic SCL commands (`pmi_add`, `pmi_text`, `pmi_visible`, `pmi_delete`) so journals can replay PMI work without putting annotations into the modelling feature graph.

PMI annotations are intended to associate to persistent model/topology IDs once
the topological-naming work is mature.  The current store therefore carries an
association record but must not pretend that unstable subentity indices are a
finished persistent-naming solution.

## Future Sections

Assembly, Drawing, Manufacturing, AI and Journalling remain registered launcher
entries.  Each should migrate to its own source directory and contextual ribbon
as implementation work begins.  The Assembly design is tracked separately in
`docs/ASSEMBLIES.md` and `config/assembly_load_options.json`.



