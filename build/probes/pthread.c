#define _POSIX_C_SOURCE 200809L
#include <pthread.h>
static void* worker(void* p) { return p; }
int main(void) {
    pthread_t t;
    if (pthread_create(&t, (pthread_attr_t*)0, worker, (void*)0) != 0) return 1;
    return pthread_join(t, (void**)0);
}
