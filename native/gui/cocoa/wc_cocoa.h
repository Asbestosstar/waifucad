#ifndef WC_COCOA_H
#define WC_COCOA_H

/*
 * WaifuCAD Cocoa/AppKit native front-end C ABI.
 *
 * The bridge is Objective-C (wc_cocoa.m): an AppKit window with the Sections
 * ribbon, contextual command buttons, a shared-path command console, a model
 * navigator list and a Metal-backed viewport. BetterC kernel code never
 * imports toolkit headers; it only sees this C ABI, exactly like the GTK4
 * bridge. wc_cocoa_stub.c provides the headless fallback used on non-macOS
 * build hosts so the macOS GUI target always links.
 *
 * All command submission from native widgets must route through the shared
 * semantic SCL/journal command path (submit_command / run_ribbon_command),
 * never through direct model mutation, matching the GTK4 contract.
 */

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct WcCocoaWindowConfig
{
    int32_t width;
    int32_t height;
    const char *title;
    const char *theme_id;
    const char *navigator_background;
    const char *navigator_rail_background;
    /* Renderer hint for the Metal drawing surface: "auto" or "metal".
       GTK-specific GSK names are accepted and ignored by the Cocoa bridge. */
    const char *renderer_hint;
    int32_t force_software_vulkan;
} WcCocoaWindowConfig;

typedef struct WcCocoaSectionEntry
{
    const char *id;
    const char *icon;   /* assets/icons/<icon>.svg; may be NULL or missing on disk */
    int32_t active;
} WcCocoaSectionEntry;

typedef struct WcCocoaRibbonCommand
{
    const char *id;
    const char *label;     /* localisation key, used for tooltips */
    const char *tab_id;
    const char *icon;      /* assets/icons/<icon>.svg; may be NULL or missing on disk */
    const char *tab_icon;  /* icon of the owning ribbon tab; may be NULL */
    int32_t planned;       /* non-zero renders the button disabled */
} WcCocoaRibbonCommand;

typedef struct WcCocoaBodyRow
{
    uint32_t feature_id;
    const char *name;
    int32_t exact;      /* non-zero when the body carries exact WaifuBRep geometry */
    double bounds[6];   /* minX, minY, minZ, maxX, maxY, maxZ */
} WcCocoaBodyRow;

/* Submit one Ruby-like .wcs SCL line through the shared command path.
   Returns 0 on success, non-zero SCL error otherwise. */
typedef int (*WcCocoaSubmitCommandFn)(void *user_data, char *command_line);

/* Fill up to capacity section launcher entries; returns the total count. */
typedef size_t (*WcCocoaSectionEntriesFn)(void *user_data, WcCocoaSectionEntry *out, size_t capacity);

/* Activate a Section by id. Returns 0 on success. */
typedef int (*WcCocoaChooseSectionFn)(void *user_data, const char *section_id);

/* Fill up to capacity contextual ribbon commands of the active Section;
   returns the total count, ordered by ribbon tab. */
typedef size_t (*WcCocoaRibbonCommandsFn)(void *user_data, WcCocoaRibbonCommand *out, size_t capacity);

/* Execute one ribbon command through the shared semantic SCL path.
   Returns 0 on success, non-zero SCL error otherwise. */
typedef int (*WcCocoaRunRibbonCommandFn)(void *user_data, const char *command_id);

/* Fill up to capacity displayable body rows; returns the total count. */
typedef size_t (*WcCocoaBodyRowsFn)(void *user_data, WcCocoaBodyRow *out, size_t capacity);

typedef struct WcCocoaCallbacks
{
    WcCocoaSubmitCommandFn submit_command;
    WcCocoaSectionEntriesFn section_entries;
    WcCocoaChooseSectionFn choose_section;
    WcCocoaRibbonCommandsFn ribbon_commands;
    WcCocoaRunRibbonCommandFn run_ribbon_command;
    WcCocoaBodyRowsFn body_rows;
} WcCocoaCallbacks;

/* Non-zero when a functional AppKit/Metal bridge is linked in. */
int wc_cocoa_native_available(void);

/* Run the native event loop. Returns 0 on clean exit; 78 (EX_CONFIG-style
   unavailable) when only the scaffold stub is linked. */
int wc_cocoa_run(const WcCocoaWindowConfig *config,
                 const WcCocoaCallbacks *callbacks,
                 void *user_data);

#ifdef __cplusplus
}
#endif

#endif /* WC_COCOA_H */
