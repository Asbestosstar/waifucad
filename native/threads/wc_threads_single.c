#include "wc_threads.h"

void wc_cancel_token_init(wc_cancel_token *token)
{
    if (token != NULL) token->cancelled = 0u;
}

void wc_cancel(wc_cancel_token *token)
{
    if (token != NULL) token->cancelled = 1u;
}

int wc_is_cancelled(const wc_cancel_token *token)
{
    return token != NULL && token->cancelled != 0u;
}

uint32_t wc_hardware_thread_count(void) { return 1u; }
uint32_t wc_parallel_pool_worker_count(void) { return 0u; }
int wc_parallel_pool_shutdown(void) { return 0; }

int wc_parallel_for_cancelable(size_t count, uint32_t requested_workers,
                               wc_parallel_job_fn job, void *context,
                               wc_cancel_token *cancel_token)
{
    size_t i;
    (void)requested_workers;
    if (job == NULL) return 0;
    for (i = 0u; i < count; ++i) {
        if (wc_is_cancelled(cancel_token)) return WC_PARALLEL_CANCELLED;
        job(context, i);
    }
    return 0;
}

int wc_parallel_for(size_t count, uint32_t requested_workers,
                    wc_parallel_job_fn job, void *context)
{
    return wc_parallel_for_cancelable(count, requested_workers, job, context, NULL);
}

