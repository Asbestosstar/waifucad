#ifndef WAIFUCAD_MOD_API_H
#define WAIFUCAD_MOD_API_H
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define WC_MOD_ABI_V1 1u
#define WC_SECTION_ABI_V1 1u

typedef struct WcSectionDescriptorV1 {
    uint32_t abi_version;
    const char *id;
    const char *localisation_key;
    const char *icon_name;
    uint32_t capabilities;
} WcSectionDescriptorV1;

typedef struct WcModHostV1 {
    uint32_t abi_version;
    int (*register_section)(const WcSectionDescriptorV1 *section);
    int (*register_scl_command)(const char *command_name, void *callback);
} WcModHostV1;

typedef struct WcModDescriptorV1 {
    uint32_t abi_version;
    const char *id;
    const char *name;
    const char *version_text;
    int (*load)(const WcModHostV1 *host);
    void (*unload)(void);
} WcModDescriptorV1;

typedef WcModDescriptorV1 *(*waifucad_mod_entry_v1_fn)(void);

#ifdef __cplusplus
}
#endif
#endif



