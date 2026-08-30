# Feature dialogues

WaifuCAD ribbon commands use a toolkit-neutral **feature-dialogue descriptor**
instead of forcing a ribbon click through the visible command console.

## Behaviour

- Simple interactive actions execute immediately (for example Sketch support
  selection and read-only inspection).
- Parameterised modelling and PMI commands open a native feature dialogue.
- Pressing **Create** or **Apply** emits one Ruby-like SCL command through the
  same `CommandConsoleState.submit` transaction path used by scripts and
  journalling.  GTK never mutates `Model` storage directly.
- Double-activating an editable Model Navigator history row reopens the same
  descriptor with values read from that feature.
- Sketch history rows open the Sketch feature dialogue; **Edit Sketch Geometry**
  enters the existing interactive sketch editor.
- Every built-in feature dialogue supplies its own project-owned waifu image assignment.
  The descriptor still has a fallback image for future third-party templates, but built-ins
  do not all reuse one character.

The command console remains available as an explicit expert interface, but it is
not a required intermediate step for ribbon use.

## Descriptor ABI

`src/waifucad/gui/feature_dialogues.d` defines
`FeatureDialogueDescriptorV1` and `FeatureDialogueFieldDescriptorV1`.
Descriptors contain data only:

- stable dialogue/command id;
- title;
- semantic SCL command name;
- optional fixed argument prefix;
- semantic edit kind;
- waifu image path;
- ordered fields;
- field type, default, choices and edit-value source.

Front-ends render this data.  They do not own command semantics.

Field kinds cover names, scalar/expression values, feature references, text,
booleans, file paths, choices and explicit raw SCL values. Feature-reference
fields also carry a semantic selection role: **profile**, **body**, **path** or
**any feature**. Edit-value sources map a field to the feature name, an operand
slot, `payload` or `payload2`.


## Picking feature references

A feature-reference row has a **Select…** button when its descriptor declares a
selection role. Pressing it temporarily returns focus to the CAD window. The
user may then choose a compatible item from Model Navigator or click compatible
visible geometry in the graphics area. The dialogue reappears with the selected
feature name filled into the field. Escape cancels the pick and restores the
dialogue.

Selection is semantic rather than name-based:

- **Profile** calls the same `resolveProfile` path used by modelling. A Sketch
  container is therefore directly acceptable when it contains exactly one
  resolvable region or one closed line/arc loop; users do not have to select the
  internal rectangle/circle child.
- **Body** accepts body-producing modelling history.
- **Path** accepts curve/path feature kinds; Model Navigator selection remains
  available even when a rough curve is not yet drawn by the bootstrap viewport.
- **Any feature** is used for associations such as PMI.

The GTK4 bootstrap can hit-test visible sketch geometry and returns the owning
Sketch for a profile pick. Visible bodies use the existing body hit test. A pick
that does not satisfy the field role is rejected without changing the field.

## Files and automation

File-valued fields render an editable path plus **Browse…** and use a native GTK file chooser. OpenSCAD import/export and dumb-body import therefore do not require manually typing a filesystem path. Export fields use a Save chooser; imports use Open.

Automation ribbon commands are direct file workflows rather than command-line templates:

- **Run Script…** chooses a local `.wcs`/`.scl` file and executes it through `include(...)`.
- **Record Journal** chooses a `.wjournal` destination and starts semantic recording; pressing Record Journal again stops the active recording.
- **Run Journal…** chooses a `.wjournal`/`.wcs` file and replays it through `journal_run(...)`.

The GUI owns a real `Journal` instance, but start/stop/replay still cross the SCL interpreter boundary so the UI does not manipulate document geometry or journal internals directly. Failed dialogue/file actions are reported in the status area and on stderr with the generated semantic command and numeric status.

## Sketch profiles and preview recompute

A Sketch being accepted by `resolveProfile` must also be accepted by preview recompute. The built-in preview therefore resolves semantic profile geometry directly for Sketch containers instead of assuming that the Sketch history node already has cached region bounds. Extrude preview translates that resolved region along the Sketch frame's actual Z axis, including non-XY support planes. This keeps preview and exact WaifuBRep semantics aligned.

## In-place edit transaction

Feature dialogue edits emit:

```text
feature_edit(:existing_feature, :extrude, :profile, 25.mm, 0, 0, 0, 0)
```

`feature_edit` validates the complete new definition and calls
`Model.redefineFeature`.  The feature keeps its existing `EntityId` and name.
All feature references must still point to an earlier history entry.  Dependency
depths are calculated before commit; a rejected edit leaves the model unchanged.
The edited feature and downstream dependants are then dirtied for normal
recompute.

This is deliberately preferable to delete/recreate, which would invalidate
downstream feature identity.

## Scriptable templates and Mods

The descriptor is intentionally independent of GTK and contains no widget
pointers.  A future Mod/script template loader can therefore translate a
versioned declarative template into this same ABI rather than adding a second
GUI command system.

A user template should ultimately describe:

1. the semantic SCL command it emits;
2. the field order and field types;
3. defaults/choices;
4. which fields map back to feature operands for editing;
5. a waifu image (or the standard WaifuCAD fallback);
6. the feature kind used by `feature_edit`, when the template is editable.

Template loading must remain non-mutating.  Only pressing Create/Apply may emit
the resulting semantic SCL transaction.

## FeatureScript import boundary

FeatureScript is not executed inside WaifuCAD and must never receive direct
kernel pointers.  A future FeatureScript importer should parse supported
feature-definition **metadata** (parameter names, types, defaults, enum choices
and constraints), translate it to `FeatureDialogueDescriptorV1`, and separately
translate the feature body to supported WaifuCAD SCL/Mod operations.

Unsupported FeatureScript language/runtime behaviour must be reported rather
than silently approximated.  The dialogue descriptor is the UI target of that
adapter; it is not a claim that arbitrary FeatureScript execution is currently
implemented.
