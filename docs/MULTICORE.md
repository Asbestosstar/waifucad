# Multicore execution

WaifuCAD's BetterC kernel does not depend on `core.thread` or the D garbage collector. Multicore execution crosses the C ABI in `src/waifucad/core/jobs.d`; the initial POSIX implementation lives in `native/threads/wc_threads_posix.c`.

## Dependency-safe dispatch

Feature recompute still proceeds by dependency depth. Jobs in one depth are independent by construction; a later/dependent feature is never eligible for the queue until its source depth has completed. Work stealing therefore changes only which worker executes an already-independent job, not CAD dependency semantics.

## Persistent pool and work stealing

The POSIX bridge lazily creates a process-wide helper pool and reuses those pthreads across dispatches. The calling thread participates as another worker. Each participant has a bounded queue seeded for the current dispatch; an idle participant first consumes its own queue and may then steal work from a peer queue while holding the scheduler mutex.

A nested `wc_parallel_for` or `wc_parallel_for_cancelable` invoked from inside an active callback executes serially. This prevents a worker from blocking on its own pool and bounds process-wide oversubscription.

Diagnostics/teardown remain available through `wc_parallel_pool_worker_count` and `wc_parallel_pool_shutdown`; native pthread handles are never exposed to BetterC model code.

## Cancellation

`wc_cancel_token` and `wc_parallel_for_cancelable` provide cooperative cancellation. Once cancelled, already-running callbacks are permitted to finish but the dispatcher stops starting new jobs. `Model.recomputeCancellation` is reset at recompute start, used by the multicore preview pass, and checked between serial exact feature builds.

This means an interactive host can request cancellation without corrupting dependency order or interrupting a topology mutation halfway through. The sketch-constraint solver now checks cancellation between projection passes and individual constraints. WaifuBRep tessellation has a cancellable entry point and checks the token during boundary sampling, ear clipping and analytic-surface meshing. Other long future geometry algorithms must adopt the same safe-checkpoint pattern rather than being interrupted while mutating topology.

## Command-line control

```sh
./bin/waifucad-batch --script examples/scripts/multicore_features.wcs --threads 0 --dump-model
./bin/waifucad-batch --script examples/scripts/multicore_features.wcs --threads 8 --dump-model
```

`--threads 0` selects the detected host count; 1 through 64 override it.

## Porting

The ABI includes hardware-count, normal/cancellable parallel-for, cancellation-token and pool diagnostic operations. POSIX uses pthreads; the wasm64 research bootstrap still uses `wc_threads_single.c`. Historical/research targets are not considered verified merely because the ABI has an implementation path.

The POSIX cancellation token currently uses compiler atomic built-ins available on the GCC/Clang toolchains used by the active POSIX path. A historical compiler port may provide a different native implementation while preserving the C ABI.

## Remaining scheduler work

- extend cooperative cancellation checkpoints to future long boolean/NURBS/healing operations;
- native GUI event wiring to request cancellation;
- profiling/queue-size tuning for very large feature graphs; and
- only after deterministic per-worker geometry arenas exist, parallel exact B-rep construction/merge. The shared exact arena remains serial today by design.

