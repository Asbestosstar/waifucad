# Multicore Scheduling

WaifuCAD parallelises recompute-heavy work (tessellation, sketch solving,
batch feature evaluation) through a small persistent worker pool implemented
in `native/threads/wc_threads_posix.c` and bridged into BetterC via
`src/waifucad/core/jobs.d`.

## Persistent pool

The pool is persistent: `static wc_parallel_pool wc_pool` keeps a fixed set
of worker threads alive for the process lifetime instead of spawning threads
per job. This avoids oversubscription — the number of workers never exceeds
the host's online logical processors (`wc_parallel_pool_worker_count`), and
nested parallel dispatch is serialised (`wc_parallel_depth != 0u` runs inline)
rather than spawning more workers.

## Work stealing and cancellation

Idle workers steal jobs from siblings. Cooperative cancellation checkpoints
exist in the sketch constraint solver (`model.recomputeCancelled()`) and in
BRep tessellation (`tessellateBRepSolidCancelable`), so interactive recomputes
can abandon stale work early. Shutdown is explicit via
`wc_parallel_pool_shutdown`.

## Optional dependency

POSIX threads are probed at build time. Hosts without them build with
`WC_THREAD_IMPL=single`, which runs the same job graph serially; no source
changes are required. See `config/concurrency.json` for the machine-readable
scheduling contract.
