#define _POSIX_C_SOURCE 200809L
#include "wc_gpu_probe.h"

#include <dirent.h>
#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>
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

static void copy_text(char *destination, size_t capacity, const char *source);

static void join_path(char *out, size_t capacity, const char *base, const char *leaf)
{    if (out == NULL || capacity == 0)
        return;
    out[0] = '\0';
    if (base == NULL || leaf == NULL)
        return;
    (void)snprintf(out, capacity, "%s/%s", base, leaf);
}

/* Collect Vulkan ICD manifests (*.json) from a directory into a
 * colon-separated list. With lavapipe_only != 0 only software (lvp /
 * lavapipe) manifests are collected. Returns the number collected. */
static int collect_icd_manifests(const char *icd_dir, char *out, size_t capacity, int lavapipe_only)
{
    DIR *dir;
    struct dirent *entry;
    int count = 0;
    size_t used;
    if (out == NULL || capacity == 0)
        return 0;
    out[0] = '\0';
    if (icd_dir == NULL)
        return 0;
    dir = opendir(icd_dir);
    if (dir == NULL)
        return 0;
    used = 0;
    while ((entry = readdir(dir)) != NULL) {
        const char *name = entry->d_name;
        size_t name_len = strlen(name);
        int written;
        if (name_len < 6 || strcmp(name + name_len - 5, ".json") != 0)
            continue;
        if (lavapipe_only && !contains_case_insensitive(name, "lvp") &&
            !contains_case_insensitive(name, "lavapipe"))
            continue;
        if (used + 1 + strlen(icd_dir) + 1 + name_len + 1 > capacity)
            break;
        written = snprintf(out + used, capacity - used, "%s%s/%s",
                           count != 0 ? ":" : "", icd_dir, name);
        if (written < 0)
            break;
        used += (size_t)written;
        ++count;
    }
    closedir(dir);
    return count;
}

/* Locate a Vulkan loader shared library inside a Mesa prefix. */
static int find_opt_loader(const char *root, char *out, size_t capacity)
{
    static const char *const candidates[] = {
        "lib/libvulkan.so.1",
        "lib64/libvulkan.so.1",
        "lib/x86_64-linux-gnu/libvulkan.so.1",
        "usr/lib/libvulkan.so.1",
        "usr/lib64/libvulkan.so.1",
        "usr/lib/x86_64-linux-gnu/libvulkan.so.1"
    };
    size_t i;
    if (out == NULL || capacity == 0)
        return 0;
    out[0] = '\0';
    for (i = 0; i < sizeof(candidates) / sizeof(candidates[0]); ++i) {
        join_path(out, capacity, root, candidates[i]);
        if (path_exists(out))
            return 1;
    }
    out[0] = '\0';
    return 0;
}

static const char *opt_scan_root(void)
{
    const char *override_root = getenv("WC_OPT_MESA_ROOT");
    if (override_root != NULL && override_root[0] != '\0')
        return override_root;
    return "/opt";
}

int wc_gpu_opt_mesa_vulkan(char *root_out, size_t root_capacity,
                           char *icd_out, size_t icd_capacity,
                           int lavapipe_only)
{
    DIR *opt_dir;
    struct dirent *entry;
    const char *scan_root = opt_scan_root();
    int best_rank = -1;
    char best_name[WC_GPU_NAME_CAPACITY];
    char best_root[WC_GPU_NAME_CAPACITY];
    char best_icd[WC_GPU_SUMMARY_CAPACITY];

    if (root_out != NULL && root_capacity != 0)
        root_out[0] = '\0';
    if (icd_out != NULL && icd_capacity != 0)
        icd_out[0] = '\0';
    best_name[0] = '\0';
    best_root[0] = '\0';
    best_icd[0] = '\0';

    opt_dir = opendir(scan_root);
    if (opt_dir == NULL)
        return 0;
    while ((entry = readdir(opt_dir)) != NULL) {
        char root[WC_GPU_NAME_CAPACITY];
        char icd_dir[WC_GPU_SUMMARY_CAPACITY];
        char icds[WC_GPU_SUMMARY_CAPACITY];
        char loader[WC_GPU_SUMMARY_CAPACITY];
        int icd_count;
        int has_loader;
        int rank;
        if (!contains_case_insensitive(entry->d_name, "mesa"))
            continue;
        join_path(root, sizeof(root), scan_root, entry->d_name);
        join_path(icd_dir, sizeof(icd_dir), root, "share/vulkan/icd.d");
        icd_count = collect_icd_manifests(icd_dir, icds, sizeof(icds), lavapipe_only);
        has_loader = find_opt_loader(root, loader, sizeof(loader));
        if (icd_count == 0 && !has_loader)
            continue;
        /* Prefer manifests plus loader, then manifests alone, then loader
         * alone; ties go to the lexicographically later (newer) version. */
        rank = (icd_count != 0 ? 2 : 0) + (has_loader ? 1 : 0);
        if (rank > best_rank ||
            (rank == best_rank && strcmp(entry->d_name, best_name) > 0)) {
            best_rank = rank;
            copy_text(best_name, sizeof(best_name), entry->d_name);
            copy_text(best_root, sizeof(best_root), root);
            copy_text(best_icd, sizeof(best_icd), icd_count != 0 ? icds : NULL);
        }
    }
    closedir(opt_dir);

    if (best_rank < 0)
        return 0;
    if (root_out != NULL && root_capacity != 0)
        copy_text(root_out, root_capacity, best_root);
    if (icd_out != NULL && icd_capacity != 0)
        copy_text(icd_out, icd_capacity, best_icd[0] != '\0' ? best_icd : NULL);
    return 1;
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

/* Create a Vulkan instance and enumerate its physical devices. Returns the
 * instance (NULL on failure); *inout_count carries the device capacity in and
 * the enumerated count out (0 when enumeration fails). */
static VkInstance probe_create_and_enumerate(VkCreateInstanceWc create_instance,
                                             VkEnumeratePhysicalDevicesWc enumerate_devices,
                                             VkPhysicalDevice *devices,
                                             uint32_t *inout_count)
{
    VkApplicationInfoWc application_info;
    VkInstanceCreateInfoWc create_info;
    VkInstance instance = NULL;

    memset(&application_info, 0, sizeof(application_info));
    application_info.sType = VK_STRUCTURE_TYPE_APPLICATION_INFO_WC;
    application_info.pApplicationName = "WaifuCAD probe";
    application_info.pEngineName = "WaifuCAD";

    memset(&create_info, 0, sizeof(create_info));
    create_info.sType = VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO_WC;
    create_info.pApplicationInfo = &application_info;

    if (create_instance(&create_info, NULL, &instance) != VK_SUCCESS_WC || instance == NULL)
        return NULL;
    if (enumerate_devices(instance, inout_count, devices) != VK_SUCCESS_WC)
        *inout_count = 0;
    return instance;
}

static void append_opt_mesa_note(WcGpuProbe *probe)
{
    size_t len;
    if (probe == NULL || !probe->has_opt_mesa)
        return;
    len = strlen(probe->summary);
    if (len >= sizeof(probe->summary))
        return;
    if (probe->opt_mesa_has_vulkan)
        (void)snprintf(probe->summary + len, sizeof(probe->summary) - len,
                       "; /opt Mesa=%s (Vulkan%s)", probe->opt_mesa_root,
                       probe->opt_mesa_used ? ", configured" : "");
    else
        (void)snprintf(probe->summary + len, sizeof(probe->summary) - len,
                       "; /opt Mesa present (no Vulkan drivers)");
}

void wc_gpu_probe(WcGpuProbe *out_probe)
{
    void *loader;
    VkCreateInstanceWc create_instance;
    VkEnumeratePhysicalDevicesWc enumerate_devices;
    VkGetPhysicalDevicePropertiesWc get_properties;
    VkDestroyInstanceWc destroy_instance;
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

    /* Some systems keep newer Mesa builds outside the system paths under
     * /opt (one directory per version). Scan them for Vulkan support so a
     * system without usable Vulkan can still fall back to such a build. */
    {
        DIR *opt_dir = opendir(opt_scan_root());
        if (opt_dir != NULL) {
            struct dirent *entry;
            while ((entry = readdir(opt_dir)) != NULL) {
                if (contains_case_insensitive(entry->d_name, "mesa")) {
                    out_probe->has_opt_mesa = 1;
                    break;
                }
            }
            closedir(opt_dir);
        }
    }
    if (wc_gpu_opt_mesa_vulkan(out_probe->opt_mesa_root, sizeof(out_probe->opt_mesa_root),
                               out_probe->opt_mesa_icd, sizeof(out_probe->opt_mesa_icd), 0)) {
        out_probe->has_opt_mesa = 1;
        out_probe->opt_mesa_has_vulkan = 1;
        out_probe->has_mesa = 1;
        if (contains_case_insensitive(out_probe->opt_mesa_icd, "lvp") ||
            contains_case_insensitive(out_probe->opt_mesa_icd, "lavapipe"))
            out_probe->has_lavapipe = 1;
    }

    loader = dlopen("libvulkan.so.1", RTLD_NOW | RTLD_LOCAL);
    if (loader == NULL && out_probe->opt_mesa_has_vulkan) {
        /* No system Vulkan loader; try the loader shipped by the /opt Mesa. */
        char opt_loader[WC_GPU_SUMMARY_CAPACITY];
        if (find_opt_loader(out_probe->opt_mesa_root, opt_loader, sizeof(opt_loader))) {
            loader = dlopen(opt_loader, RTLD_NOW | RTLD_LOCAL);
            if (loader != NULL) {
                out_probe->opt_mesa_used = 1;
                if (out_probe->opt_mesa_icd[0] != '\0' && getenv("VK_ICD_FILENAMES") == NULL)
                    (void)setenv("VK_ICD_FILENAMES", out_probe->opt_mesa_icd, 1);
            }
        }
    }
    if (loader == NULL) {
        (void)snprintf(out_probe->summary, sizeof(out_probe->summary),
                       "Vulkan loader unavailable; NVIDIA=%s Mesa=%s lavapipe=%s",
                       out_probe->has_nvidia ? "yes" : "no",
                       out_probe->has_mesa ? "yes" : "no",
                       out_probe->has_lavapipe ? "yes" : "no");
        append_opt_mesa_note(out_probe);
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
        append_opt_mesa_note(out_probe);
        dlclose(loader);
        return;
    }

    device_count = 32;
    instance = probe_create_and_enumerate(create_instance, enumerate_devices, devices, &device_count);
    if (instance == NULL) {
        (void)snprintf(out_probe->summary, sizeof(out_probe->summary),
                       "Vulkan loader present but instance creation failed");
        append_opt_mesa_note(out_probe);
        dlclose(loader);
        return;
    }

    if (device_count == 0 && out_probe->opt_mesa_icd[0] != '\0' && getenv("VK_ICD_FILENAMES") == NULL) {
        /* The system paths exposed no Vulkan devices; retry instance creation
         * against the ICD manifests shipped by the /opt Mesa build. */
        destroy_instance(instance, NULL);
        (void)setenv("VK_ICD_FILENAMES", out_probe->opt_mesa_icd, 1);
        device_count = 32;
        instance = probe_create_and_enumerate(create_instance, enumerate_devices, devices, &device_count);
        if (instance == NULL) {
            (void)snprintf(out_probe->summary, sizeof(out_probe->summary),
                           "Vulkan loader present but instance creation failed against both system and /opt Mesa drivers");
            append_opt_mesa_note(out_probe);
            dlclose(loader);
            return;
        }
        out_probe->opt_mesa_used = 1;
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
    append_opt_mesa_note(out_probe);

    destroy_instance(instance, NULL);
    dlclose(loader);
}
