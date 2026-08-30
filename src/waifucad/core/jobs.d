module waifucad.core.jobs;

extern(C) alias ParallelJobFn = void function(void*, size_t) nothrow @nogc;

struct CancellationToken
{
    uint cancelled;
}

enum WC_PARALLEL_CANCELLED = 4;

extern(C) uint wc_hardware_thread_count() nothrow @nogc;
extern(C) int wc_parallel_for(size_t, uint, ParallelJobFn, void*) nothrow @nogc;
extern(C) int wc_parallel_for_cancelable(size_t, uint, ParallelJobFn, void*, CancellationToken*) nothrow @nogc;
extern(C) void wc_cancel_token_init(CancellationToken*) nothrow @nogc;
extern(C) void wc_cancel(CancellationToken*) nothrow @nogc;
extern(C) int wc_is_cancelled(const(CancellationToken)*) nothrow @nogc;
extern(C) uint wc_parallel_pool_worker_count() nothrow @nogc;
extern(C) int wc_parallel_pool_shutdown() nothrow @nogc;

uint hardwareThreadCount() nothrow @nogc
{
    auto count = wc_hardware_thread_count();
    return count == 0 ? 1u : count;
}

int parallelFor(size_t count, uint requestedWorkers, ParallelJobFn job, void* context) nothrow @nogc
{
    if (count == 0 || job is null) return 0;
    return wc_parallel_for(count, requestedWorkers, job, context);
}

int parallelForCancelable(size_t count, uint requestedWorkers, ParallelJobFn job,
                          void* context, CancellationToken* token) nothrow @nogc
{
    if (count == 0 || job is null) return 0;
    return wc_parallel_for_cancelable(count, requestedWorkers, job, context, token);
}

void initialiseCancellation(CancellationToken* token) nothrow @nogc
{
    if (token !is null) wc_cancel_token_init(token);
}

void cancel(CancellationToken* token) nothrow @nogc
{
    if (token !is null) wc_cancel(token);
}

bool isCancelled(const(CancellationToken)* token) nothrow @nogc
{
    return token !is null && wc_is_cancelled(token) != 0;
}

uint persistentWorkerCount() nothrow @nogc { return wc_parallel_pool_worker_count(); }
int shutdownPersistentWorkers() nothrow @nogc { return wc_parallel_pool_shutdown(); }

