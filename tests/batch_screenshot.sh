#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT"
./build.sh batch
mkdir -p build/tests/shots
OUT=build/tests/shots
rm -f "$OUT"/*.png

# Flat renderer via CLI flags, with rotation and size overrides.
./bin/waifucad-batch --script examples/scripts/brep_box.wcs \
    --screenshot "$OUT/box_flat.png" --rotate -45,35.26438968,0 --size 640x480 \
    > /dev/null
python3 tests/png_validate.py "$OUT/box_flat.png"

# Ray renderer via CLI; deterministic Halton AO must be byte-reproducible.
./bin/waifucad-batch --script examples/scripts/brep_box.wcs \
    --render ray --screenshot "$OUT/box_ray_a.png" --size 320x240 > /dev/null
./bin/waifucad-batch --script examples/scripts/brep_box.wcs \
    --render ray --screenshot "$OUT/box_ray_b.png" --size 320x240 > /dev/null
python3 tests/png_validate.py "$OUT/box_ray_a.png" "$OUT/box_ray_b.png" \
    --identical "$OUT/box_ray_a.png" "$OUT/box_ray_b.png"

# Two shots in one run; modifier scoping: --render ray after the first shot
# applies only to the second.
./bin/waifucad-batch --script examples/scripts/brep_box.wcs \
    --screenshot "$OUT/multi_flat.png" --size 160x120 \
    --render ray --screenshot "$OUT/multi_ray.png" --size 160x120 > /dev/null
python3 tests/png_validate.py "$OUT/multi_flat.png" "$OUT/multi_ray.png"
if cmp -s "$OUT/multi_flat.png" "$OUT/multi_ray.png"; then
    echo 'flat and ray screenshots are identical; render-mode scoping broken' >&2
    exit 1
fi

# In-script screenshot command (flat default and explicit ray mode).
cat > build/tests/shots_script.wcs <<'EOS'
model(:shot_check)
box(:block, 40, 25, 15)
recompute()
screenshot("build/tests/shots/scl_flat.png")
screenshot("build/tests/shots/scl_ray.png", -30, 25, 0, 320, 240, 1, :ray)
EOS
./bin/waifucad-batch --script build/tests/shots_script.wcs > /dev/null
python3 tests/png_validate.py "$OUT/scl_flat.png" "$OUT/scl_ray.png"

# Rotation must actually move geometry on screen: a tall box rendered from
# yaw 0 vs yaw 90 differs.
cat > build/tests/shots_rotate.wcs <<'EOS'
model(:rotate_check)
box(:tower, 10, 10, 80)
recompute()
EOS
./bin/waifucad-batch --script build/tests/shots_rotate.wcs \
    --screenshot "$OUT/rot0.png" --rotate 0,30,0 --size 200x200 \
    > /dev/null
./bin/waifucad-batch --script build/tests/shots_rotate.wcs \
    --screenshot "$OUT/rot45.png" --rotate 45,30,0 --size 200x200 \
    > /dev/null
if cmp -s "$OUT/rot0.png" "$OUT/rot45.png"; then
    echo '--rotate had no visible effect' >&2
    exit 1
fi

# Camera convention: positive pitch looks at the model from above. A tall
# tower centred on a wide plate must be visible in the centre of the frame in
# BOTH renderers (a below-model camera hides it behind the plate).
cat > build/tests/shots_above.wcs <<'EOS'
model(:above_check)
box(:plate, 140, 140, 10)
box(:tower_body, 20, 20, 80)
recompute()
EOS
./bin/waifucad-batch --script build/tests/shots_above.wcs \
    --screenshot "$OUT/above_flat.png" --rotate -45,60,0 --size 200x200 --no-axes \
    > /dev/null
./bin/waifucad-batch --script build/tests/shots_above.wcs \
    --render ray --screenshot "$OUT/above_ray.png" --rotate -45,60,0 --size 200x200 \
    > /dev/null
# Centre pixel must be plate-or-tower, never the dark background 0x20242C.
python3 - "$OUT/above_flat.png" "$OUT/above_ray.png" <<'PYEOF'
import sys
sys.path.insert(0, 'tests')
from png_validate import parse_png
for path in sys.argv[1:3]:
    w, h, rgb, _ = parse_png(path)
    bg = (0x20, 0x24, 0x2C)
    centre_count = 0
    for y in range(h // 2 - 10, h // 2 + 10):
        for x in range(w // 2 - 10, w // 2 + 10):
            off = (y * w + x) * 3
            if (rgb[off], rgb[off + 1], rgb[off + 2]) != bg:
                centre_count += 1
    if centre_count < 200:
        raise SystemExit(f'{path}: centre region is background; camera is not above the model')
    print(f'{path}: centre region occupied ({centre_count}/400 non-background pixels)')
PYEOF

# Bad arguments must fail, not silently produce files.
if ./bin/waifucad-batch --script examples/scripts/brep_box.wcs \
    --screenshot "$OUT/bad.png" --size 8x8 > /dev/null 2>&1; then
    echo 'out-of-range --size did not fail' >&2
    exit 1
fi
if ./bin/waifucad-batch --script examples/scripts/brep_box.wcs \
    --screenshot "$OUT/bad2.png" --render fancy > /dev/null 2>&1; then
    echo 'unknown --render mode did not fail' >&2
    exit 1
fi

printf 'Batch screenshot test passed.\n'
