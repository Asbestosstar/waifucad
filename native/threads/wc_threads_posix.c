#include "wc_threads.h"

#include <pthread.h>
#include <unistd.h>

#define WC_THREAD_LIMIT 64u
#define WC_HELPER_LIMIT (WC_THREAD_LIMIT - 1u)

typedef struct wc_worker_context {
    uint32_t index;
    uint64_t seen_generation;
} wc_worker_context;

typedef struct wc_worker_queue {
    size_t next;
    size_t end;
} wc_worker_queue;

typedef struct wc_parallel_pool {
    pthread_mutex_t lock;
    pthread_cond_t work_available;
    pthread_cond_t work_done;
    pthread_cond_t dispatch_idle;
    pthread_t threads[WC_HELPER_LIMIT];
    wc_worker_context workers[WC_HELPER_LIMIT];
    wc_worker_queue queues[WC_THREAD_LIMIT];
    uint32_t thread_count;
    uint32_t helper_limit;
    uint32_t participant_count;
    uint32_t helpers_remaining;
    uint64_t generation;
    int dispatch_active;
    int stopping;
    size_t count;
    wc_parallel_job_fn job;
    void *context;
    wc_cancel_token *cancel_token;
} wc_parallel_pool;

static wc_parallel_pool wc_pool = {
    PTHREAD_MUTEX_INITIALIZER,
    PTHREAD_COND_INITIALIZER,
    PTHREAD_COND_INITIALIZER,
    PTHREAD_COND_INITIALIZER,
    {0}, {{0}}, {{0}},
    0u, 0u, 0u, 0u, 0u, 0, 0, 0u, NULL, NULL, NULL
};

/* Nested parallel-for invocations run serially. This prevents a callback from
   waiting on the process-wide dispatch that is already executing it and keeps
   geometry kernels from silently oversubscribing the host. */
static _Thread_local uint32_t wc_parallel_depth = 0u;

void wc_cancel_token_init(wc_cancel_token *token)
{
    if (token != NULL)
        __atomic_store_n(&token->cancelled, 0u, __ATOMIC_RELEASE);
}

void wc_cancel(wc_cancel_token *token)
{
    if (token != NULL)
        __atomic_store_n(&token->cancelled, 1u, __ATOMIC_RELEASE);
}

int wc_is_cancelled(const wc_cancel_token *token)
{
    return token != NULL && __atomic_load_n(&token->cancelled, __ATOMIC_ACQUIRE) != 0u;
}

static size_t wc_take_job(uint32_t queue_index)
{
    size_t index = (size_t)-1;
    uint32_t victim;
    pthread_mutex_lock(&wc_pool.lock);

    if (wc_is_cancelled(wc_pool.cancel_token)) {
        pthread_mutex_unlock(&wc_pool.lock);
        return index;
    }

    if (queue_index < wc_pool.participant_count) {
        wc_worker_queue *own = &wc_pool.queues[queue_index];
        if (own->next < own->end)
            index = own->next++;
    }

    /* If the local queue is empty, steal one job from the tail of the largest
       non-empty peer queue.  All queue mutation is under the pool mutex, so no
       atomics or heap-owned deque nodes are required. */
    if (index == (size_t)-1) {
        size_t best_count = 0u;
        uint32_t best = WC_THREAD_LIMIT;
        for (victim = 0u; victim < wc_pool.participant_count; ++victim) {
            wc_worker_queue *queue;
            size_t available;
            if (victim == queue_index)
                continue;
            queue = &wc_pool.queues[victim];
            available = queue->end > queue->next ? queue->end - queue->next : 0u;
            if (available > best_count) {
                best_count = available;
                best = victim;
            }
        }
        if (best != WC_THREAD_LIMIT && best_count != 0u) {
            wc_worker_queue *queue = &wc_pool.queues[best];
            --queue->end;
            index = queue->end;
        }
    }

    pthread_mutex_unlock(&wc_pool.lock);
    return index;
}

static void wc_run_current_dispatch(uint32_t queue_index)
{
    for (;;) {
        size_t index = wc_take_job(queue_index);
        if (index == (size_t)-1)
            break;
        if (wc_is_cancelled(wc_pool.cancel_token))
            break;
        wc_pool.job(wc_pool.context, index);
    }
}

static void *wc_worker_main(void *opaque)
{
    wc_worker_context *worker = (wc_worker_context *)opaque;

    pthread_mutex_lock(&wc_pool.lock);
    for (;;) {
        for (;;) {
            if (wc_pool.stopping) {
                pthread_mutex_unlock(&wc_pool.lock);
                return NULL;
            }
            if (worker->seen_generation != wc_pool.generation) {
                worker->seen_generation = wc_pool.generation;
                if (wc_pool.dispatch_active && worker->index < wc_pool.helper_limit)
                    break;
            }
            pthread_cond_wait(&wc_pool.work_available, &wc_pool.lock);
        }

        pthread_mutex_unlock(&wc_pool.lock);
        ++wc_parallel_depth;
        wc_run_current_dispatch(worker->index);
        --wc_parallel_depth;
        pthread_mutex_lock(&wc_pool.lock);

        if (wc_pool.helpers_remaining != 0u)
            --wc_pool.helpers_remaining;
        if (wc_pool.helpers_remaining == 0u)
            pthread_cond_signal(&wc_pool.work_done);
    }
}

static uint32_t wc_ensure_helpers_locked(uint32_t requested_helpers)
{
    while (wc_pool.thread_count < requested_helpers && wc_pool.thread_count < WC_HELPER_LIMIT) {
        uint32_t index = wc_pool.thread_count;
        wc_pool.workers[index].index = index;
        wc_pool.workers[index].seen_generation = wc_pool.generation;
        if (pthread_create(&wc_pool.threads[index], NULL, wc_worker_main, &wc_pool.workers[index]) != 0)
            break;
        ++wc_pool.thread_count;
    }
    return wc_pool.thread_count < requested_helpers ? wc_pool.thread_count : requested_helpers;
}

uint32_t wc_hardware_thread_count(void)
{
    long value = sysconf(_SC_NPROCESSORS_ONLN);
    if (value < 1)
        return 1u;
    if (value > (long)WC_THREAD_LIMIT)
        return WC_THREAD_LIMIT;
    return (uint32_t)value;
}

uint32_t wc_parallel_pool_worker_count(void)
{
    uint32_t result;
    pthread_mutex_lock(&wc_pool.lock);
    result = wc_pool.thread_count;
    pthread_mutex_unlock(&wc_pool.lock);
    return result;
}

static int wc_parallel_for_impl(size_t count,
                                uint32_t requested_workers,
                                wc_parallel_job_fn job,
                                void *context,
                                wc_cancel_token *cancel_token)
{
    uint32_t wanted;
    uint32_t helpers;
    uint32_t participants;
    uint32_t q;
    size_t base;
    size_t remainder;
    size_t cursor;

    if (job == NULL || count == 0u)
        return 0;
    if (wc_is_cancelled(cancel_token))
        return WC_PARALLEL_CANCELLED;

    wanted = requested_workers == 0u ? wc_hardware_thread_count() : requested_workers;
    if (wanted < 1u)
        wanted = 1u;
    if (wanted > WC_THREAD_LIMIT)
        wanted = WC_THREAD_LIMIT;
    if ((size_t)wanted > count)
        wanted = (uint32_t)count;

    if (wanted <= 1u || wc_parallel_depth != 0u) {
        size_t i;
        ++wc_parallel_depth;
        for (i = 0u; i < count; ++i) {
            if (wc_is_cancelled(cancel_token)) {
                --wc_parallel_depth;
                return WC_PARALLEL_CANCELLED;
            }
            job(context, i);
        }
        --wc_parallel_depth;
        return 0;
    }

    pthread_mutex_lock(&wc_pool.lock);
    while (wc_pool.dispatch_active && !wc_pool.stopping)
        pthread_cond_wait(&wc_pool.dispatch_idle, &wc_pool.lock);
    if (wc_pool.stopping) {
        pthread_mutex_unlock(&wc_pool.lock);
        return 2;
    }

    helpers = wc_ensure_helpers_locked(wanted - 1u);
    participants = helpers + 1u;
    wc_pool.count = count;
    wc_pool.job = job;
    wc_pool.context = context;
    wc_pool.cancel_token = cancel_token;
    wc_pool.helper_limit = helpers;
    wc_pool.participant_count = participants;
    wc_pool.helpers_remaining = helpers;

    /* Seed one bounded local queue per participant. Work stealing handles
       uneven callback cost without changing deterministic dependency levels. */
    base = count / participants;
    remainder = count % participants;
    cursor = 0u;
    for (q = 0u; q < participants; ++q) {
        size_t length = base + (q < remainder ? 1u : 0u);
        wc_pool.queues[q].next = cursor;
        wc_pool.queues[q].end = cursor + length;
        cursor += length;
    }
    for (; q < WC_THREAD_LIMIT; ++q) {
        wc_pool.queues[q].next = 0u;
        wc_pool.queues[q].end = 0u;
    }

    wc_pool.dispatch_active = 1;
    ++wc_pool.generation;
    pthread_cond_broadcast(&wc_pool.work_available);
    pthread_mutex_unlock(&wc_pool.lock);

    ++wc_parallel_depth;
    wc_run_current_dispatch(helpers); /* caller owns the final queue */
    --wc_parallel_depth;

    pthread_mutex_lock(&wc_pool.lock);
    while (wc_pool.helpers_remaining != 0u)
        pthread_cond_wait(&wc_pool.work_done, &wc_pool.lock);
    wc_pool.dispatch_active = 0;
    wc_pool.helper_limit = 0u;
    wc_pool.participant_count = 0u;
    wc_pool.job = NULL;
    wc_pool.context = NULL;
    wc_pool.cancel_token = NULL;
    pthread_cond_broadcast(&wc_pool.dispatch_idle);
    pthread_mutex_unlock(&wc_pool.lock);
    return wc_is_cancelled(cancel_token) ? WC_PARALLEL_CANCELLED : 0;
}

int wc_parallel_for(size_t count,
                    uint32_t requested_workers,
                    wc_parallel_job_fn job,
                    void *context)
{
    return wc_parallel_for_impl(count, requested_workers, job, context, NULL);
}

int wc_parallel_for_cancelable(size_t count,
                               uint32_t requested_workers,
                               wc_parallel_job_fn job,
                               void *context,
                               wc_cancel_token *cancel_token)
{
    return wc_parallel_for_impl(count, requested_workers, job, context, cancel_token);
}

int wc_parallel_pool_shutdown(void)
{
    pthread_t threads[WC_HELPER_LIMIT];
    uint32_t count;
    uint32_t i;

    if (wc_parallel_depth != 0u)
        return 3;

    pthread_mutex_lock(&wc_pool.lock);
    while (wc_pool.dispatch_active)
        pthread_cond_wait(&wc_pool.dispatch_idle, &wc_pool.lock);
    wc_pool.stopping = 1;
    ++wc_pool.generation;
    count = wc_pool.thread_count;
    for (i = 0u; i < count; ++i)
        threads[i] = wc_pool.threads[i];
    pthread_cond_broadcast(&wc_pool.work_available);
    pthread_mutex_unlock(&wc_pool.lock);

    for (i = 0u; i < count; ++i)
        pthread_join(threads[i], NULL);

    pthread_mutex_lock(&wc_pool.lock);
    wc_pool.thread_count = 0u;
    wc_pool.helper_limit = 0u;
    wc_pool.participant_count = 0u;
    wc_pool.helpers_remaining = 0u;
    wc_pool.stopping = 0;
    wc_pool.count = 0u;
    wc_pool.job = NULL;
    wc_pool.context = NULL;
    wc_pool.cancel_token = NULL;
    pthread_mutex_unlock(&wc_pool.lock);
    return 0;
}

