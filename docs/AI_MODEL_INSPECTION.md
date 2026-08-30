# AI model inspection getters

WaifuCAD exposes model information to AI providers through **read-only SCL/WCS getters** rather than raw kernel pointers. The same getter implementation is available from Ruby-like `.wcs`, the compatibility `.scl` command form, the batch command line and the GUI command-console path.

Getters write their result into a named `ScriptRuntime` variable. They do not modify the document and are deliberately excluded from semantic journal recording. Ruby-like `.wcs` supports natural return assignment such as `kind = get_feature_kind(:body)`; the deterministic internal/legacy `.scl` ABI keeps the output variable first as `get_feature_kind kind body`. Direct `.wcs` calls with an explicit output argument also remain accepted for compatibility.

Ruby-like `.wcs`:

```text
count = get_feature_count()
name = get_feature_name(0)
kind = get_feature_kind(:body)
bounds = get_feature_bounds(:body)
status = get_feature_geometry_status(:body)
echo_value(:bounds)
```

Legacy `.scl` compatibility form:

```text
get_feature_count count
get_feature_name name 0
get_feature_kind kind body
get_feature_bounds bounds body
get_feature_geometry_status status body
echo_value bounds
```

Enumeration indices are zero-based and may be numeric literals or numeric script variables, so AI loops can enumerate a model without knowing names in advance. Parameter/feature/PMI and topology enumeration indices are inspection cursors, not persistent document identity. Exact primitive-derived topology now exposes separate 64-bit persistent IDs; raw face/edge/vertex arena indices must still never be cached as stable references.

## Model discovery

- `get_model_name OUT`
- `get_parameter_count OUT`
- `get_feature_count OUT`
- `get_model_worker_count OUT`
- `get_model_requested_worker_count OUT` (`0` means automatic)
- `get_model_hardware_thread_count OUT`
- `get_model_persistent_worker_count OUT`
- `get_model_exact_solid_count OUT`
- `get_model_mesh_count OUT`
- `get_model_brep_counts OUT` -> `[vertices, edges, coedges, loops, faces, shells, solids]`
- `get_model_mesh_totals OUT` -> `[meshes, vertices, triangles]`

## Parameters

- `get_parameter_name OUT INDEX`
- `get_parameter_exists OUT NAME`
- `get_parameter_id OUT NAME`
- `get_parameter_value OUT NAME`
- `get_parameter_unit OUT NAME` -> `unitless`, `mm` or `deg`
- `get_parameter_dependant_count OUT NAME`
- `get_parameter_dependant_name OUT NAME INDEX`

An AI can therefore enumerate every parameter without knowing its names in advance, then discover which features consume it.

## Feature graph

- `get_feature_name OUT INDEX`
- `get_feature_exists OUT NAME`
- `get_feature_id OUT NAME`
- `get_feature_index OUT NAME`
- `get_feature_kind OUT NAME`
- `get_feature_role OUT NAME`
- `get_feature_dirty OUT NAME`
- `get_feature_recommended OUT NAME`
- `get_feature_dependency_depth OUT NAME`
- `get_feature_operand_count OUT NAME`
- `get_feature_dependant_count OUT NAME`
- `get_feature_dependant_name OUT NAME INDEX`
- `get_feature_payload OUT NAME`
- `get_feature_payload2 OUT NAME`
- `get_feature_mesh_id OUT NAME`

Operand inspection:

- `get_feature_operand_kind OUT NAME INDEX` -> `literal`, `parameter`, or `feature`
- `get_feature_operand_name OUT NAME INDEX`
- `get_feature_operand_value OUT NAME INDEX`
- `get_feature_operand_entity_id OUT NAME INDEX`

For a literal, `get_feature_operand_name` returns an empty string. `get_feature_operand_value` returns the literal value, the current parameter value, or a referenced feature ID according to the operand kind.

## Geometry state and measurements

- `get_feature_geometry_status OUT NAME` -> `none`, `exact`, `preview_only`, or `failed`
- `get_feature_preview_error OUT NAME`
- `get_feature_exact_error OUT NAME`
- `get_feature_exact_solid_id OUT NAME`
- `get_feature_preview_bounds_valid OUT NAME`
- `get_feature_preview_bounds OUT NAME`
- `get_feature_exact_bounds_valid OUT NAME`
- `get_feature_exact_bounds OUT NAME`
- `get_feature_bounds_source OUT NAME` -> `exact`, `preview`, or `none`
- `get_feature_bounds OUT NAME`
- `get_feature_exact_primitive_kind OUT NAME`
- `get_feature_exact_topology_counts OUT NAME` -> `[vertices, edges, faces]`
- `get_feature_volume OUT NAME`
- `get_feature_surface_area OUT NAME`
- `get_feature_centre_of_mass OUT NAME` -> `[x, y, z]`

`get_feature_bounds` prefers an exact WaifuBRep solid bound when one exists; otherwise it returns preview bounds and `get_feature_bounds_source` makes that distinction explicit. Exact mass-property getters fail rather than substituting a preview box when exact properties are unavailable.

## Dumb-mesh bodies

- `get_feature_mesh_vertex_count OUT NAME`
- `get_feature_mesh_triangle_count OUT NAME`
- `get_feature_mesh_source OUT NAME`
- `get_feature_mesh_format OUT NAME`
- `get_feature_mesh_closed_hint OUT NAME`
- `get_feature_mesh_convexity OUT NAME`

These describe tessellated dumb bodies only and never promote a mesh to exact WaifuBRep geometry.

## PMI

- `get_pmi_count OUT`
- `get_pmi_name OUT INDEX`
- `get_pmi_exists OUT NAME`
- `get_pmi_id OUT NAME`
- `get_pmi_kind OUT NAME`
- `get_pmi_text OUT NAME`
- `get_pmi_visible OUT NAME`
- `get_pmi_associative OUT NAME`
- `get_pmi_feature_id OUT NAME`
- `get_pmi_feature_name OUT NAME`
- `get_pmi_subentity_kind OUT NAME`
- `get_pmi_subentity_index OUT NAME`

The final two fields expose the current temporary PMI association data for diagnostics only. They are not persistent topology names and must not be cached as stable references.

## Recommended AI discovery sequence

1. Query model, parameter, feature and PMI counts.
2. Enumerate names by zero-based index.
3. Query feature kinds, roles, operands, dependants and geometry status.
4. Use exact measurements only where `get_feature_geometry_status` reports `exact`; inspect `get_feature_bounds_source` when using bounds.
5. Request dumb-mesh metadata only for mesh-backed features.
6. Use semantic names/entity IDs for feature-level reasoning and wait for persistent topology naming before creating long-lived face/edge associations.

## Persistent exact-topology getters

Exact analytic bodies now carry a separate 64-bit persistent topology identity; raw `BRepId`/array positions are still rebuild-local implementation details. Persistent IDs are returned as fixed hexadecimal strings so they are never rounded through the numeric script value type. The v1 ID combines the owning feature EntityId, topology kind and a semantic slot. It survives ordinary dimensional recompute and arena relocation inside a document session. Cross-save stability waits for deterministic document serialisation, and boolean/split-generated topology still needs explicit lineage propagation.

- `get_feature_persistent_body_id` returns the persistent body identity for an exact feature.
- `get_feature_face_persistent_id`, `get_feature_edge_persistent_id` and `get_feature_vertex_persistent_id` enumerate exact subentities and return their persistent IDs. The enumeration index is only a cursor used to discover the IDs; the returned ID is the stable reference.
- `get_topology_exists`, `get_topology_kind`, `get_topology_owner_feature_id`, `get_topology_owner_feature_name` and `get_topology_semantic_slot` resolve/dissect a persistent identity.
- `get_topology_vertex_point` and `get_topology_vertex_tolerance` expose exact vertex data.
- `get_topology_edge_start_vertex_id`, `get_topology_edge_end_vertex_id`, `get_topology_edge_curve_kind`, `get_topology_edge_radius` and `get_topology_edge_parameter_range` expose exact edge data while preserving persistent endpoint references.
- `get_topology_face_surface_kind`, `get_topology_face_origin`, `get_topology_face_axis`, `get_topology_face_radius` and `get_topology_face_secondary_radius` expose analytic face data.

Ruby-like WCS example:

```text
body_id = get_feature_persistent_body_id(:base)
face_id = get_feature_face_persistent_id(:base, 0)
face_kind = get_topology_kind(face_id)
surface = get_topology_face_surface_kind(face_id)
```

Legacy SCL compatibility form:

```text
get_feature_persistent_body_id body_id base
get_feature_face_persistent_id face_id base 0
get_topology_kind face_kind face_id
get_topology_face_surface_kind surface face_id
```

Do not persist enumeration indices. PMI's older `subentityKind/subentityIndex` fields remain compatibility diagnostics until PMI storage is migrated to these persistent IDs.


## Expressions, constraints, datums and recompute state

Expression parameters are inspectable without evaluating arbitrary provider code:

- `get_parameter_is_expression OUT NAME`
- `get_parameter_expression OUT NAME`
- `get_parameter_expression_error OUT NAME`

Sketch constraint discovery:

- `get_sketch_constraint_count OUT`
- `get_sketch_constraint_name OUT INDEX`
- `get_sketch_constraint_exists OUT NAME`
- `get_sketch_constraint_kind OUT NAME`
- `get_sketch_constraint_status OUT NAME`
- `get_sketch_constraint_value OUT NAME`
- `get_sketch_constraint_enabled OUT NAME`
- `get_sketch_constraint_sketch_name OUT NAME`
- `get_sketch_constraint_first_feature_name OUT NAME`
- `get_sketch_constraint_second_feature_name OUT NAME`
- `get_sketch_constraint_points OUT NAME`
- `get_sketch_constraint_residual OUT NAME`
- `get_sketch_constraint_rank_contribution OUT NAME`
- `get_sketch_constraint_rank_redundant OUT NAME`

Sketch solve diagnostics:

- `get_sketch_initial_dof OUT SKETCH`
- `get_sketch_dof OUT SKETCH`
- `get_sketch_constraint_equation_count OUT SKETCH`
- `get_sketch_satisfied_constraint_count OUT SKETCH`
- `get_sketch_redundant_constraint_count OUT SKETCH`
- `get_sketch_conflicting_constraint_count OUT SKETCH`
- `get_sketch_invalid_constraint_count OUT SKETCH`
- `get_sketch_unsatisfied_constraint_count OUT SKETCH`
- `get_sketch_solve_iterations OUT SKETCH`
- `get_sketch_max_residual OUT SKETCH`
- `get_sketch_solve_converged OUT SKETCH`
- `get_sketch_fully_constrained OUT SKETCH`
- `get_sketch_total_equation_count OUT SKETCH`
- `get_sketch_jacobian_rank OUT SKETCH`
- `get_sketch_rank_deficiency OUT SKETCH`
- `get_sketch_nonlinear_iterations OUT SKETCH`
- `get_sketch_under_constrained OUT SKETCH`
- `get_sketch_over_constrained OUT SKETCH`
- `get_sketch_rank_analysis_truncated OUT SKETCH`

Resolved datum construction geometry:

- `get_datum_frame_origin OUT NAME`
- `get_datum_frame_x_axis OUT NAME`
- `get_datum_frame_y_axis OUT NAME`
- `get_datum_frame_z_axis OUT NAME`
- `get_datum_axis_origin OUT NAME`
- `get_datum_axis_direction OUT NAME`

Kernel/scheduler state:

- `get_model_nurbs_curve_count OUT`
- `get_model_nurbs_surface_count OUT`
- `get_topology_lineage_count OUT`
- `get_model_recompute_cancelled OUT`

Persistent topology lineage can be enumerated after split/merge/boolean operations:

- `get_topology_lineage_result OUT INDEX`
- `get_topology_lineage_parent_a OUT INDEX`
- `get_topology_lineage_parent_b OUT INDEX`
- `get_topology_lineage_kind OUT INDEX`

Lineage IDs are the same 64-bit hexadecimal persistent topology references used by the other topology getters. A zero parent is reported as `none`.

Topological complexity getters:

- `get_feature_exact_shell_count OUT NAME`
- `get_feature_exact_genus OUT NAME`
- `get_topology_face_loop_count OUT PERSISTENT_ID`

These distinguish multi-shell cavities, genus-one revolved bodies/tori and faces with inner trimming loops without exposing rebuild-local loop indices.

### Jacobian/rank sketch diagnostics

The P1 sketch solver performs a bounded finite-difference Jacobian analysis after the deterministic projection pass. It can also run a damped nonlinear correction for coupled line/circle/arc constraints. The analysis is fixed-capacity and BetterC-safe: up to 64 mutable literal variables and 128 scalar constraint equations are analysed in one sketch. Larger sketches remain valid, but `get_sketch_rank_analysis_truncated` becomes true and the rank result must not be treated as complete.

`get_sketch_jacobian_rank` and `get_sketch_rank_deficiency` are local solved-state diagnostics, not persistent topology identities. `get_sketch_constraint_rank_redundant` means the constraint adds no independent local Jacobian row at that state; it supplements the solver's semantic duplicate/conflict checks rather than replacing them.

