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
    printf("%s\n", probe.summary);
    return 0;
}
