#ifndef WAIFUCAD_WC_GPU_PROBE_H
#define WAIFUCAD_WC_GPU_PROBE_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

enum {
    WC_GPU_NAME_CAPACITY = 256,
    WC_GPU_SUMMARY_CAPACITY = 512
};

typedef struct WcGpuProbe {
    int has_vulkan_loader;
    int has_vulkan_device;
    int has_vulkan_hardware_device;
    int vulkan_software_only;
    int has_nvidia;
    int has_mesa;
    int has_lavapipe;
    uint32_t vulkan_device_count;
    uint32_t selected_vendor_id;
    uint32_t selected_device_type;
    char selected_device[WC_GPU_NAME_CAPACITY];
    char summary[WC_GPU_SUMMARY_CAPACITY];
} WcGpuProbe;

void wc_gpu_probe(WcGpuProbe *out_probe);

#ifdef __cplusplus
}
#endif

#endif
