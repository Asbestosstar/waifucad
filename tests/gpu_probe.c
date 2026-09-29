#include "../native/graphics/wc_gpu_probe.h"
#include <stdio.h>
#include <string.h>

int main(void)
{
    WcGpuProbe probe;
    wc_gpu_probe(&probe);
    if (probe.summary[0] == '\0') {
        fprintf(stderr, "GPU probe summary was empty\n");
        return 1;
    }
    if (probe.vulkan_software_only && probe.has_vulkan_hardware_device) {
        fprintf(stderr, "GPU probe reported software-only and hardware Vulkan simultaneously\n");
        return 2;
    }
    if (probe.has_lavapipe && !probe.has_mesa) {
        fprintf(stderr, "lavapipe must imply Mesa stack availability\n");
        return 3;
    }
    /* /opt Mesa scan consistency: Vulkan support requires a found tree, and a
     * configured tree implies Vulkan support; a Vulkan-capable tree always
     * reports its root path. */
    if (probe.opt_mesa_has_vulkan && !probe.has_opt_mesa) {
        fprintf(stderr, "opt Mesa Vulkan support without an opt Mesa tree\n");
        return 4;
    }
    if (probe.opt_mesa_used && !probe.opt_mesa_has_vulkan) {
        fprintf(stderr, "opt Mesa configured without opt Mesa Vulkan support\n");
        return 5;
    }
    if (probe.opt_mesa_has_vulkan && probe.opt_mesa_root[0] == '\0') {
        fprintf(stderr, "opt Mesa Vulkan support without a root path\n");
        return 6;
    }
    if (probe.opt_mesa_has_vulkan && !probe.has_mesa) {
        fprintf(stderr, "opt Mesa Vulkan support must imply Mesa stack availability\n");
        return 7;
    }
    printf("%s\n", probe.summary);
    return 0;
}
