#define _POSIX_C_SOURCE 200809L
#include <dlfcn.h>
int main(void) {
    void* h = dlopen("libwaifucad_probe_nonexistent.so", RTLD_LAZY);
    if (h == (void*)0) return 0;
    return dlsym(h, "waifucad_probe") != (void*)0;
}
