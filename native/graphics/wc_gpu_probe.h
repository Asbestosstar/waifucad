#ifndef WAIFUCAD_WC_GPU_PROBE_H
#define WAIFUCAD_WC_GPU_PROBE_H

#include <stddef.h>
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
    int has_opt_mesa;         /* a Mesa tree exists under the /opt scan root */
    int opt_mesa_has_vulkan;  /* that tree provides Vulkan (loader and/or ICDs) */
    int opt_mesa_used;        /* the probe configured/used the /opt Mesa for Vulkan */
    uint32_t vulkan_device_count;
    uint32_t selected_vendor_id;
    uint32_t selected_device_type;
    char selected_device[WC_GPU_NAME_CAPACITY];
    char opt_mesa_root[WC_GPU_NAME_CAPACITY];   /* e.g. /opt/mesa-24.1 */
    char opt_mesa_icd[WC_GPU_SUMMARY_CAPACITY]; /* colon-separated ICD manifests */
    char summary[WC_GPU_SUMMARY_CAPACITY];
} WcGpuProbe;

void wc_gpu_probe(WcGpuProbe *out_probe);

/* Scan for Mesa installations under the /opt scan root ("/opt" by default;
 * overridable with WC_OPT_MESA_ROOT, mainly for tests) and pick one with
 * Vulkan support — ICD manifests under share/vulkan/icd.d and/or a
 * libvulkan.so.1 loader. Returns 1 when a Vulkan-capable /opt Mesa was found.
 * root_out receives the chosen Mesa root; icd_out receives a colon-separated
 * list of ICD manifest paths (empty when only a loader was found). With
 * lavapipe_only != 0 only software (lvp/lavapipe) ICDs are listed and the
 * result counts as Vulkan-capable only when such an ICD or loader exists. */
int wc_gpu_opt_mesa_vulkan(char *root_out, size_t root_capacity,
                           char *icd_out, size_t icd_capacity,
                           int lavapipe_only);

#ifdef __cplusplus
}
#endif

#endif
