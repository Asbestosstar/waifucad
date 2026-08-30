#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT"
python3 tests/d_parser_hazards.py
python3 tests/d_semantic_compat.py
python3 tests/wcs_extension_policy.py
python3 tests/getters_static.py
python3 tests/brep_naming_static.py
python3 tests/ai_protocol_static.py
python3 tests/p1_modelling_kernel_static.py
python3 tests/scheduler_static.py
python3 tests/sketch_solver_static.py
python3 tests/sketch_jacobian_static.py
python3 tests/expression_p1_static.py
python3 tests/brep_classification_static.py
python3 tests/mixed_profile_static.py
python3 tests/gtk4_frontend_static.py
python3 tests/feature_dialogues_static.py
./make_todos.sh >/dev/null
python3 tests/make_todos_waifu_index.py
./tests/gpu_probe.sh

./tests/portability_layout.sh
./tests/openscad_parity.sh
python3 ./tests/openscad_interchange_static.py
python3 ./tests/sections_static.py
python3 ./tests/pmi_scl_static.py
./tests/openscad_cli_probe.sh
./tests/build_link_flags.sh
./tests/gui_build_link_flags.sh
./tests/native_temp_files.sh
if command -v python3 >/dev/null 2>&1; then
    python3 ./tests/validate_target_manifests.py
fi
./tests/brep_box.sh
./tests/brep_cylinder.sh
./tests/brep_analytic.sh
./tests/brep_p1_advanced.sh
./tests/sketch_solver_p1.sh
./tests/expression_p1.sh
sh ./tests/brep_naming.sh
./tests/scl_ruby_syntax.sh

./tests/native_threads.sh
./tests/gtk4_native_syntax.sh
./build.sh batch
./build.sh gui

# Feature-dialogue edits are semantic SCL transactions that preserve feature identity.
./bin/waifucad-batch --script tests/feature_dialogue_edit.wcs > build/obj/feature-dialogue-edit.txt
id_before=$(sed -n '1p' build/obj/feature-dialogue-edit.txt)
id_after=$(sed -n '2p' build/obj/feature-dialogue-edit.txt)
[ "$id_before" = "$id_after" ]
grep -Fqx '[-20,-10,0,20,10,25]' build/obj/feature-dialogue-edit.txt
grep -Fqx '20000' build/obj/feature-dialogue-edit.txt

# Model Navigator history actions and viewport-created positioned sketch geometry
# use the same semantic SCL path as scripts/journal replay.
./bin/waifucad-batch --script tests/model_history_edit.wcs --dump-model > build/obj/model-history-edit.txt
grep -q 'second.*kind=2' build/obj/model-history-edit.txt
grep -q 'third.*kind=2' build/obj/model-history-edit.txt
grep -q 'first.*kind=2' build/obj/model-history-edit.txt
grep -q 'placed_rect.*kind=5' build/obj/model-history-edit.txt
if grep -q 'delete_me.*kind=' build/obj/model-history-edit.txt; then
    echo 'feature_delete did not remove the selected independent feature' >&2
    exit 1
fi
second_line=$(grep -n 'second.*kind=2' build/obj/model-history-edit.txt | head -1 | cut -d: -f1)
third_line=$(grep -n 'third.*kind=2' build/obj/model-history-edit.txt | head -1 | cut -d: -f1)
first_line=$(grep -n 'first.*kind=2' build/obj/model-history-edit.txt | head -1 | cut -d: -f1)
if [ "$third_line" -ge "$second_line" ] || [ "$second_line" -ge "$first_line" ]; then
    echo 'feature_move_up/feature_move_before did not reorder independent sketch entities' >&2
    exit 1
fi
./bin/waifucad-gui --bootstrap-info --section modelling --command 'box(:gui_cli_box, 12.mm, 8.mm, 4.mm)' > build/obj/gui-command-console.txt
grep -q 'Command line overlay: Command:' build/obj/gui-command-console.txt
grep -q 'Command syntax: Ruby-like .wcs SCL' build/obj/gui-command-console.txt
rm -f journals/smoke.wjournal build/obj/smoke-replay.txt

./bin/waifucad-batch \
    --script examples/scripts/multicore_features.wcs \
    --journal-out journals/smoke.wjournal \
    --threads 4 \
    --dump-model --dump-brep

test -s journals/smoke.wjournal
grep -Fqx 'set(:width, 96)' journals/smoke.wjournal
grep -Fqx 'union(:combined, :base, :boss)' journals/smoke.wjournal
grep -Fqx 'extrude(:raised, :softened, 5.mm)' journals/smoke.wjournal

./bin/waifucad-batch \
    --journal-in journals/smoke.wjournal \
    --threads 2 \
    --dump-model --dump-brep > build/obj/smoke-replay.txt

grep -q 'raised' build/obj/smoke-replay.txt
grep -q 'boss.*brep=exact' build/obj/smoke-replay.txt
grep -q 'combined.*brep=preview-only' build/obj/smoke-replay.txt
grep -q 'dirty=0' build/obj/smoke-replay.txt

./bin/waifucad-batch --script examples/scripts/pmi_journal.wcs --threads 2

# Read-only AI/model getters work from Ruby-like WCS and legacy SCL.
rm -f build/obj/model-getters.wjournal
./bin/waifucad-batch --script examples/scripts/model_getters.wcs --threads 2 --journal-out build/obj/model-getters.wjournal > build/obj/model-getters-wcs.txt
grep -Fqx 'getter_demo' build/obj/model-getters-wcs.txt
if grep -q '^get_' build/obj/model-getters.wjournal; then
    echo 'Read-only getters incorrectly entered the semantic journal' >&2
    exit 1
fi
grep -Fqx 'box' build/obj/model-getters-wcs.txt
grep -Fqx 'exact' build/obj/model-getters-wcs.txt
grep -Fqx '[0,0,0,40,25,10]' build/obj/model-getters-wcs.txt
grep -Fqx '10000' build/obj/model-getters-wcs.txt
grep -Eq '^0x[0-9a-f]{16}$' build/obj/model-getters-wcs.txt
grep -Fqx 'plane' build/obj/model-getters-wcs.txt
./bin/waifucad-batch --script examples/scripts/legacy/model_getters.scl --threads 2 > build/obj/model-getters-scl.txt
grep -Fqx 'getter_demo_legacy' build/obj/model-getters-scl.txt
grep -Fqx 'box' build/obj/model-getters-scl.txt
grep -Fqx 'exact' build/obj/model-getters-scl.txt

# Historical command-form scripts use .scl, not .wcs.
./bin/waifucad-batch --script examples/scripts/legacy/brep_box.scl --threads 2 --dump-model > build/obj/legacy-scl.txt
grep -q 'body.*brep=exact' build/obj/legacy-scl.txt

./bin/waifucad-batch --script examples/scripts/ruby_style.wcs --threads 2 --dump-model > build/obj/ruby-style.txt
grep -q 'base_body.*brep=exact' build/obj/ruby-style.txt
./bin/waifucad-batch --command 'box(:cli_box, 12.mm, 8.mm, 4.mm)' --dump-model > build/obj/ruby-cli.txt
grep -q 'cli_box.*brep=exact' build/obj/ruby-cli.txt
printf 'box(:repl_box, 9.mm, 7.mm, 3.mm)\nquit\n' | ./bin/waifucad-batch --repl --dump-model > build/obj/ruby-repl.txt
grep -q 'repl_box.*brep=exact' build/obj/ruby-repl.txt

./bin/waifucad-batch --script examples/scripts/nx_style_workflow.wcs --threads 4 --dump-model > build/obj/nx-style.txt
grep -q 'rough_axis.*role=' build/obj/nx-style.txt
grep -q 'supplier_motor.*preferred=0' build/obj/nx-style.txt
grep -q 'base_body.*brep=exact' build/obj/nx-style.txt

# P1 expression/datums/constraints and exact-geometry demonstration.
./bin/waifucad-batch --script examples/scripts/p1_parametric_kernel.wcs --threads 4 --dump-model --dump-brep > build/obj/p1-parametric-kernel.txt
grep -q 'plate.*brep=exact' build/obj/p1-parametric-kernel.txt
grep -q 'arc_prism.*brep=exact' build/obj/p1-parametric-kernel.txt
grep -q 'ring.*brep=exact' build/obj/p1-parametric-kernel.txt
grep -q 'swept_pin.*brep=exact' build/obj/p1-parametric-kernel.txt
grep -q 'lofted_body.*brep=exact' build/obj/p1-parametric-kernel.txt
grep -q 'hollow_box.*brep=exact' build/obj/p1-parametric-kernel.txt
grep -q 'box_intersection.*brep=exact' build/obj/p1-parametric-kernel.txt
grep -q 'analytic_torus.*brep=exact' build/obj/p1-parametric-kernel.txt
grep -Fqx 'width / 2' build/obj/p1-parametric-kernel.txt
grep -Fqx '[0,0,1]' build/obj/p1-parametric-kernel.txt
grep -Fqx 'satisfied' build/obj/p1-parametric-kernel.txt
./bin/waifucad-batch --script examples/scripts/legacy/p1_parametric_kernel.scl --threads 2 --dump-model > build/obj/p1-parametric-kernel-legacy.txt
grep -q 'analytic_torus.*brep=exact' build/obj/p1-parametric-kernel-legacy.txt

./bin/waifucad-batch --script examples/scripts/openscad_parity.wcs --threads 4 --dump-model > build/obj/openscad-parity.txt
grep -q 'marker_1' build/obj/openscad-parity.txt
grep -q 'drilled.*brep=preview-only' build/obj/openscad-parity.txt
grep -q 'ball.*brep=exact' build/obj/openscad-parity.txt
grep -q 'ball_diameter.*brep=exact' build/obj/openscad-parity.txt
grep -q 'taper_diameter.*brep=exact' build/obj/openscad-parity.txt
grep -q 'library_child' build/obj/openscad-parity.txt
if grep -q 'use_side_effect_must_not_exist' build/obj/openscad-parity.txt; then
    echo "OpenSCAD use incorrectly executed a top-level modelling side effect" >&2
    exit 1
fi


# OpenSCAD dumb-body export -> dependency-free internal import round trip.
rm -f build/obj/box-dumb.scad build/obj/scad-roundtrip.txt build/obj/scad-external.txt
./bin/waifucad-batch \
    --script examples/scripts/brep_box.wcs \
    --export-openscad build/obj/box-dumb.scad \
    --export-feature body \
    --export-scad-precision 12 \
    --export-scad-convexity 10

grep -q 'WaifuCAD dumb-body OpenSCAD export' build/obj/box-dumb.scad
grep -q 'polyhedron(points=' build/obj/box-dumb.scad
grep -q '^// wc-vertex ' build/obj/box-dumb.scad

./bin/waifucad-batch \
    --import-openscad build/obj/box-dumb.scad \
    --import-name roundtrip_box \
    --scad-engine internal \
    --scad-require-closed \
    --dump-model > build/obj/scad-roundtrip.txt

grep -q 'Dumb meshes: 1' build/obj/scad-roundtrip.txt
grep -q 'roundtrip_box.*dumb_mesh=1' build/obj/scad-roundtrip.txt

# SCL polyhedron payloads are also flattened as real polyhedron meshes.
./bin/waifucad-batch \
    --script examples/scripts/openscad_parity.wcs \
    --export-openscad build/obj/tetra-dumb.scad \
    --export-feature tetra

grep -q '// wc-vertex 0.000000000 0.000000000 0.000000000' build/obj/tetra-dumb.scad
grep -q '\[0,2,1\]' build/obj/tetra-dumb.scad

# When OpenSCAD is installed, exercise arbitrary .scad evaluation too.
if command -v openscad >/dev/null 2>&1; then
    ./bin/waifucad-batch \
        --import-openscad examples/openscad/external_import_demo.scad \
        --import-name external_scad \
        --scad-engine external \
        --scad-backend auto \
        --scad-no-check-parameters \
        --scad-no-check-ranges \
        --dump-model > build/obj/scad-external.txt
    grep -q 'external_scad.*dumb_mesh=1' build/obj/scad-external.txt
fi

echo "WaifuCAD smoke test passed."




