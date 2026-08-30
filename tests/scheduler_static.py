#!/usr/bin/env python3
from pathlib import Path
import json
root = Path(__file__).resolve().parents[1]
posix = (root / 'native/threads/wc_threads_posix.c').read_text()
header = (root / 'native/threads/wc_threads.h').read_text()
doc = (root / 'docs/MULTICORE.md').read_text()
config = json.loads((root / 'config/concurrency.json').read_text())
assert 'static wc_parallel_pool wc_pool' in posix
assert '_Thread_local uint32_t wc_parallel_depth' in posix
assert 'wc_parallel_depth != 0u' in posix
assert 'wc_parallel_pool_shutdown' in posix and 'wc_parallel_pool_shutdown' in header
assert 'wc_parallel_pool_worker_count' in posix and 'wc_parallel_pool_worker_count' in header
assert config['workerPool'] == 'persistent-posix-helpers'
assert config['nestedParallelism'] == 'serialise-nested-dispatch'
assert config['workStealing'] is True and config['cancellation'] is True
assert 'sketch-constraint-solver' in config['cooperativeCheckpoints']
assert 'waifubrep-tessellation' in config['cooperativeCheckpoints']
assert 'persistent' in doc.lower() and 'oversubscription' in doc.lower()
solver = (root / 'src/waifucad/kernel/sketch_solver.d').read_text()
tess = (root / 'src/waifucad/mesh/tessellate_brep.d').read_text()
assert 'model.recomputeCancelled()' in solver
assert 'tessellateBRepSolidCancelable' in tess and 'WC_TESSELLATION_CANCELLED' in tess
print('persistent scheduler/work-stealing/cancellation static checks passed')

