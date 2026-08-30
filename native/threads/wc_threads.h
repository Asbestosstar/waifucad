#ifndef WAIFUCAD_WC_THREADS_H
#define WAIFUCAD_WC_THREADS_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef void (*wc_parallel_job_fn)(void *context, size_t index);

typedef struct wc_cancel_token {
    uint32_t cancelled;
} wc_cancel_token;

enum { WC_PARALLEL_CANCELLED = 4 };

uint32_t wc_hardware_thread_count(void);

int wc_parallel_for(size_t count,
                    uint32_t requested_workers,
                    wc_parallel_job_fn job,
                    void *context);

/* Same dependency-safe dispatch contract, but callbacks stop being scheduled
 * once the token is cancelled. Already-running callbacks are allowed to finish. */
int wc_parallel_for_cancelable(size_t count,
                               uint32_t requested_workers,
                               wc_parallel_job_fn job,
                               void *context,
                               wc_cancel_token *cancel_token);

void wc_cancel_token_init(wc_cancel_token *token);
void wc_cancel(wc_cancel_token *token);
int wc_is_cancelled(const wc_cancel_token *token);

uint32_t wc_parallel_pool_worker_count(void);
int wc_parallel_pool_shutdown(void);

#ifdef __cplusplus
}
#endif

#endif

