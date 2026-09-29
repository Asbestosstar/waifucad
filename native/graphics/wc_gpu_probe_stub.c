/*
 * GPU probe stub for hosts without dynamic loading (no dlopen/dlsym).
 *
 * The real probe (wc_gpu_probe.c) dlopens the Vulkan loader at runtime; on
 * minimal or statically-linked systems that is impossible, so this stub
 * reports "no probe support" instead of failing the build. Selected by
 * WC_GPU_PROBE_IMPL=stub or automatically by ./build.sh when the host cannot
 * link dlopen.
 */

#include <stdio.h>
#include <string.h>

#include "wc_gpu_probe.h"

void wc_gpu_probe(WcGpuProbe *out_probe)
{
    if (out_probe == NULL)
        return;
    memset(out_probe, 0, sizeof(*out_probe));
    snprintf(out_probe->summary, sizeof(out_probe->summary),
             "GPU probe unavailable (host has no dynamic loading support)");
}

int wc_gpu_opt_mesa_vulkan(char *root_out, size_t root_capacity,
                           char *icd_out, size_t icd_capacity,
                           int lavapipe_only)
{
    (void)lavapipe_only;
    if (root_out != NULL && root_capacity > 0)
        root_out[0] = '\0';
    if (icd_out != NULL && icd_capacity > 0)
        icd_out[0] = '\0';
    return 0;
}
