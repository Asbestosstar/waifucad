#include "wc_threads.h"

#include <pthread.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

#define TEST_JOBS 4096u
#define MAX_SEEN_THREADS 64u

typedef struct thread_set {
    pthread_mutex_t lock;
    pthread_t seen[MAX_SEEN_THREADS];
    uint32_t seen_count;
} thread_set;

typedef struct test_context {
    uint32_t hits[TEST_JOBS];
    thread_set threads;
    pthread_t caller;
    uint32_t nested_hits;
} test_context;

static void note_thread(thread_set *set)
{
    pthread_t self = pthread_self();
    uint32_t i;
    pthread_mutex_lock(&set->lock);
    for (i = 0u; i < set->seen_count; ++i) {
        if (pthread_equal(set->seen[i], self)) {
            pthread_mutex_unlock(&set->lock);
            return;
        }
    }
    if (set->seen_count < MAX_SEEN_THREADS)
        set->seen[set->seen_count++] = self;
    pthread_mutex_unlock(&set->lock);
}

static void nested_job(void *opaque, size_t index)
{
    test_context *context = (test_context *)opaque;
    (void)index;
    context->nested_hits += 1u;
}

static void test_job(void *opaque, size_t index)
{
    test_context *context = (test_context *)opaque;
    volatile uint32_t spin = 0u;
    uint32_t i;
    for (i = 0u; i < 5000u; ++i)
        spin = spin * 33u + i;
    (void)spin;
    context->hits[index] += 1u;
    note_thread(&context->threads);

    /* Exercise the nested scheduling policy once. It must complete serially
       instead of deadlocking or recursively creating more pool workers. */
    if (index == 0u)
        (void)wc_parallel_for(3u, 4u, nested_job, context);
}


typedef struct cancel_context {
    wc_cancel_token token;
    uint32_t completed;
    pthread_mutex_t lock;
} cancel_context;

static void cancel_job(void *opaque, size_t index)
{
    cancel_context *context=(cancel_context *)opaque;
    pthread_mutex_lock(&context->lock);
    ++context->completed;
    pthread_mutex_unlock(&context->lock);
    if (index == 7u) wc_cancel(&context->token);
}

static int has_reused_helper(const thread_set *first, const thread_set *second, pthread_t caller)
{
    uint32_t i;
    uint32_t j;
    for (i = 0u; i < first->seen_count; ++i) {
        if (pthread_equal(first->seen[i], caller))
            continue;
        for (j = 0u; j < second->seen_count; ++j) {
            if (pthread_equal(second->seen[j], caller))
                continue;
            if (pthread_equal(first->seen[i], second->seen[j]))
                return 1;
        }
    }
    return 0;
}

static int run_dispatch(test_context *context, uint32_t workers)
{
    uint32_t i;
    memset(context->hits, 0, sizeof(context->hits));
    context->nested_hits = 0u;
    context->threads.seen_count = 0u;
    if (wc_parallel_for(TEST_JOBS, workers, test_job, context) != 0)
        return 1;
    for (i = 0u; i < TEST_JOBS; ++i) {
        if (context->hits[i] != 1u) {
            fprintf(stderr, "job %u ran %u times\n", i, context->hits[i]);
            return 2;
        }
    }
    if (context->nested_hits != 3u) {
        fprintf(stderr, "nested dispatch ran %u jobs instead of 3\n", context->nested_hits);
        return 3;
    }
    return 0;
}

int main(void)
{
    test_context first;
    test_context second;
    uint32_t hardware = wc_hardware_thread_count();
    uint32_t workers = hardware > 1u ? 4u : 1u;
    memset(&first, 0, sizeof(first));
    memset(&second, 0, sizeof(second));
    first.caller = pthread_self();
    second.caller = first.caller;
    if (pthread_mutex_init(&first.threads.lock, NULL) != 0 ||
        pthread_mutex_init(&second.threads.lock, NULL) != 0)
        return 2;

    if (run_dispatch(&first, workers) != 0)
        return 3;
    if (workers > 1u && wc_parallel_pool_worker_count() < workers - 1u) {
        fprintf(stderr, "persistent pool did not retain requested helper workers\n");
        return 4;
    }
    if (run_dispatch(&second, workers) != 0)
        return 5;

    if (hardware > 1u && (first.threads.seen_count < 2u || second.threads.seen_count < 2u)) {
        fprintf(stderr, "parallel scheduler did not show multiple participating threads\n");
        return 6;
    }
    if (hardware > 1u && !has_reused_helper(&first.threads, &second.threads, first.caller)) {
        fprintf(stderr, "no persistent helper thread was reused across dispatches\n");
        return 7;
    }

    {
        cancel_context cancelled;
        int cancel_result;
        memset(&cancelled,0,sizeof(cancelled));
        wc_cancel_token_init(&cancelled.token);
        if (pthread_mutex_init(&cancelled.lock,NULL) != 0) return 8;
        cancel_result=wc_parallel_for_cancelable(TEST_JOBS,workers,cancel_job,&cancelled,&cancelled.token);
        if (cancel_result != WC_PARALLEL_CANCELLED || !wc_is_cancelled(&cancelled.token) || cancelled.completed >= TEST_JOBS) {
            fprintf(stderr,"cancel dispatch result=%d completed=%u\n",cancel_result,cancelled.completed);
            return 9;
        }
        pthread_mutex_destroy(&cancelled.lock);
    }

    printf("hardware_threads=%u first_threads=%u second_threads=%u persistent_helpers=%u jobs=%u work_stealing=enabled cancellation=passed\n",
           hardware, first.threads.seen_count, second.threads.seen_count,
           wc_parallel_pool_worker_count(), TEST_JOBS);

    if (wc_parallel_pool_shutdown() != 0 || wc_parallel_pool_worker_count() != 0u)
        return 10;
    pthread_mutex_destroy(&first.threads.lock);
    pthread_mutex_destroy(&second.threads.lock);
    return 0;
}

