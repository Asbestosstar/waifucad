#define _POSIX_C_SOURCE 200809L
#include "wc_gpu_probe.h"

#include <dlfcn.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>

/*
 * Header-free Vulkan loader probe.  This deliberately uses only the stable
 * Vulkan 1.0 entry points needed to enumerate physical devices.  WaifuCAD's
 * renderer remains behind its own C ABI; having a loader is not treated as
 * proof that a usable hardware device exists.
 */
typedef void *VkInstance;
typedef void *VkPhysicalDevice;
typedef int32_t VkResult;
typedef uint32_t VkFlags;

enum {
    VK_SUCCESS_WC = 0,
    VK_STRUCTURE_TYPE_APPLICATION_INFO_WC = 0,
    VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO_WC = 1,
    VK_PHYSICAL_DEVICE_TYPE_DISCRETE_GPU_WC = 2,
    VK_PHYSICAL_DEVICE_TYPE_CPU_WC = 4,
    VK_MAX_PHYSICAL_DEVICE_NAME_SIZE_WC = 256
};

typedef struct VkApplicationInfoWc {
    uint32_t sType;
    const void *pNext;
    const char *pApplicationName;
    uint32_t applicationVersion;
    const char *pEngineName;
    uint32_t engineVersion;
    uint32_t apiVersion;
} VkApplicationInfoWc;

typedef struct VkInstanceCreateInfoWc {
    uint32_t sType;
    const void *pNext;
    VkFlags flags;
    const VkApplicationInfoWc *pApplicationInfo;
    uint32_t enabledLayerCount;
    const char *const *ppEnabledLayerNames;
    uint32_t enabledExtensionCount;
    const char *const *ppEnabledExtensionNames;
} VkInstanceCreateInfoWc;

/* The Vulkan 1.0 prefix is stable.  The tail is intentionally oversized so
 * vkGetPhysicalDeviceProperties can write the implementation-defined limits
 * and sparse-property portion without this probe depending on Vulkan headers.
 */
typedef struct VkPhysicalDevicePropertiesWc {
    uint32_t apiVersion;
    uint32_t driverVersion;
    uint32_t vendorID;
    uint32_t deviceID;
    uint32_t deviceType;
    char deviceName[VK_MAX_PHYSICAL_DEVICE_NAME_SIZE_WC];
    unsigned char pipelineCacheUUID[16];
    unsigned char opaqueTail[4096];
} VkPhysicalDevicePropertiesWc;

typedef VkResult (*VkCreateInstanceWc)(const VkInstanceCreateInfoWc *, const void *, VkInstance *);
typedef VkResult (*VkEnumeratePhysicalDevicesWc)(VkInstance, uint32_t *, VkPhysicalDevice *);
typedef void (*VkGetPhysicalDevicePropertiesWc)(VkPhysicalDevice, VkPhysicalDevicePropertiesWc *);
typedef void (*VkDestroyInstanceWc)(VkInstance, const void *);

static int contains_case_insensitive(const char *text, const char *needle)
{
    size_t text_len;
    size_t needle_len;
    size_t i;
    size_t j;
    if (text == NULL || needle == NULL)
        return 0;
    text_len = strlen(text);
    needle_len = strlen(needle);
    if (needle_len == 0 || needle_len > text_len)
        return 0;
    for (i = 0; i + needle_len <= text_len; ++i) {
        for (j = 0; j < needle_len; ++j) {
            unsigned char a = (unsigned char)text[i + j];
            unsigned char b = (unsigned char)needle[j];
            if (a >= 'A' && a <= 'Z') a = (unsigned char)(a - 'A' + 'a');
            if (b >= 'A' && b <= 'Z') b = (unsigned char)(b - 'A' + 'a');
            if (a != b)
                break;
        }
        if (j == needle_len)
            return 1;
    }
    return 0;
}

static int path_exists(const char *path)
{
    return path != NULL && access(path, F_OK) == 0;
}

static void copy_text(char *destination, size_t capacity, const char *source)
{
    if (destination == NULL || capacity == 0)
        return;
    destination[0] = '\0';
    if (source == NULL)
        return;
    (void)snprintf(destination, capacity, "%s", source);
}

void wc_gpu_probe(WcGpuProbe *out_probe)
{
    void *loader;
    VkCreateInstanceWc create_instance;
    VkEnumeratePhysicalDevicesWc enumerate_devices;
    VkGetPhysicalDevicePropertiesWc get_properties;
    VkDestroyInstanceWc destroy_instance;
    VkApplicationInfoWc application_info;
    VkInstanceCreateInfoWc create_info;
    VkInstance instance = NULL;
    VkPhysicalDevice devices[32];
    uint32_t device_count = 32;
    uint32_t i;
    int any_hardware = 0;
    int any_software = 0;
    int best_score = -1;

    if (out_probe == NULL)
        return;
    memset(out_probe, 0, sizeof(*out_probe));

    out_probe->has_nvidia = path_exists("/proc/driver/nvidia/version");
    out_probe->has_mesa = path_exists("/usr/lib64/dri") || path_exists("/usr/lib/dri") ||
                          path_exists("/usr/share/vulkan/icd.d/radeon_icd.x86_64.json") ||
                          path_exists("/usr/share/vulkan/icd.d/intel_icd.x86_64.json") ||
                          path_exists("/usr/share/vulkan/icd.d/lvp_icd.x86_64.json");
    out_probe->has_lavapipe = path_exists("/usr/share/vulkan/icd.d/lvp_icd.x86_64.json") ||
                              path_exists("/usr/share/vulkan/icd.d/lvp_icd.i686.json");

    loader = dlopen("libvulkan.so.1", RTLD_NOW | RTLD_LOCAL);
    if (loader == NULL) {
        (void)snprintf(out_probe->summary, sizeof(out_probe->summary),
                       "Vulkan loader unavailable; NVIDIA=%s Mesa=%s lavapipe=%s",
                       out_probe->has_nvidia ? "yes" : "no",
                       out_probe->has_mesa ? "yes" : "no",
                       out_probe->has_lavapipe ? "yes" : "no");
        return;
    }
    out_probe->has_vulkan_loader = 1;

    create_instance = (VkCreateInstanceWc)dlsym(loader, "vkCreateInstance");
    enumerate_devices = (VkEnumeratePhysicalDevicesWc)dlsym(loader, "vkEnumeratePhysicalDevices");
    get_properties = (VkGetPhysicalDevicePropertiesWc)dlsym(loader, "vkGetPhysicalDeviceProperties");
    destroy_instance = (VkDestroyInstanceWc)dlsym(loader, "vkDestroyInstance");
    if (create_instance == NULL || enumerate_devices == NULL || get_properties == NULL || destroy_instance == NULL) {
        (void)snprintf(out_probe->summary, sizeof(out_probe->summary),
                       "Vulkan loader present but required Vulkan 1.0 entry points are unavailable");
        dlclose(loader);
        return;
    }

    memset(&application_info, 0, sizeof(application_info));
    application_info.sType = VK_STRUCTURE_TYPE_APPLICATION_INFO_WC;
    application_info.pApplicationName = "WaifuCAD probe";
    application_info.pEngineName = "WaifuCAD";

    memset(&create_info, 0, sizeof(create_info));
    create_info.sType = VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO_WC;
    create_info.pApplicationInfo = &application_info;

    if (create_instance(&create_info, NULL, &instance) != VK_SUCCESS_WC || instance == NULL) {
        (void)snprintf(out_probe->summary, sizeof(out_probe->summary),
                       "Vulkan loader present but instance creation failed");
        dlclose(loader);
        return;
    }

    if (enumerate_devices(instance, &device_count, devices) != VK_SUCCESS_WC) {
        device_count = 0;
    }
    if (device_count > 32)
        device_count = 32;
    out_probe->vulkan_device_count = device_count;
    out_probe->has_vulkan_device = device_count != 0;

    for (i = 0; i < device_count; ++i) {
        VkPhysicalDevicePropertiesWc properties;
        int is_software;
        int score;
        memset(&properties, 0, sizeof(properties));
        get_properties(devices[i], &properties);
        properties.deviceName[VK_MAX_PHYSICAL_DEVICE_NAME_SIZE_WC - 1] = '\0';

        if (properties.vendorID == 0x10deU || contains_case_insensitive(properties.deviceName, "nvidia"))
            out_probe->has_nvidia = 1;
        if (contains_case_insensitive(properties.deviceName, "mesa"))
            out_probe->has_mesa = 1;
        if (contains_case_insensitive(properties.deviceName, "lavapipe") ||
            contains_case_insensitive(properties.deviceName, "llvmpipe")) {
            out_probe->has_lavapipe = 1;
            out_probe->has_mesa = 1;
        }

        is_software = properties.deviceType == VK_PHYSICAL_DEVICE_TYPE_CPU_WC ||
                      contains_case_insensitive(properties.deviceName, "lavapipe") ||
                      contains_case_insensitive(properties.deviceName, "llvmpipe") ||
                      contains_case_insensitive(properties.deviceName, "software");
        if (is_software)
            any_software = 1;
        else
            any_hardware = 1;

        score = is_software ? 10 : 100;
        if (properties.deviceType == VK_PHYSICAL_DEVICE_TYPE_DISCRETE_GPU_WC)
            score += 50;
        if (properties.vendorID == 0x10deU)
            score += 10;
        if (score > best_score) {
            best_score = score;
            out_probe->selected_vendor_id = properties.vendorID;
            out_probe->selected_device_type = properties.deviceType;
            copy_text(out_probe->selected_device, sizeof(out_probe->selected_device), properties.deviceName);
        }
    }

    out_probe->has_vulkan_hardware_device = any_hardware;
    out_probe->vulkan_software_only = device_count != 0 && !any_hardware && any_software;
    if (device_count == 0) {
        (void)snprintf(out_probe->summary, sizeof(out_probe->summary),
                       "Vulkan loader present; no Vulkan physical devices found; NVIDIA=%s Mesa=%s lavapipe=%s",
                       out_probe->has_nvidia ? "yes" : "no",
                       out_probe->has_mesa ? "yes" : "no",
                       out_probe->has_lavapipe ? "yes" : "no");
    } else {
        (void)snprintf(out_probe->summary, sizeof(out_probe->summary),
                       "%sVulkan devices=%u selected='%s' hardware=%s software-only=%s NVIDIA=%s Mesa=%s lavapipe=%s",
                       out_probe->vulkan_software_only ? "SOFTWARE VULKAN WARNING: " : "",
                       device_count,
                       out_probe->selected_device[0] ? out_probe->selected_device : "unknown",
                       out_probe->has_vulkan_hardware_device ? "yes" : "no",
                       out_probe->vulkan_software_only ? "yes" : "no",
                       out_probe->has_nvidia ? "yes" : "no",
                       out_probe->has_mesa ? "yes" : "no",
                       out_probe->has_lavapipe ? "yes" : "no");
    }

    destroy_instance(instance, NULL);
    dlclose(loader);
}
