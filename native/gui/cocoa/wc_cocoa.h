#ifndef WC_COCOA_H
#define WC_COCOA_H

/*
 * WaifuCAD Cocoa/AppKit native front-end C ABI.
 *
 * Layout-compatible mirror of the GTK4 bridge ABI (wc_gtk4.h) for the
 * callbacks the Cocoa host implements, so both front-ends consume the same
 * toolkit-neutral ribbon/section descriptors and the same semantic row data.
 * BetterC kernel code never imports toolkit headers; all widget actions
 * route through the shared semantic SCL/journal command path
 * (submit_command / feature_action / feature_reorder), never through direct
 * model mutation — matching the GTK4 contract.
 *
 * Not yet part of this ABI (tracked in AGENTS.MD as Cocoa parity work):
 * data-driven feature dialogues, interactive sketch mode (begin/edit/finish
 * and sketch_add_* drawing callbacks).
 */

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define WC_COCOA_UI_ID_CAPACITY 160
#define WC_COCOA_FEATURE_ROW_CAPACITY 1024
#define WC_COCOA_FACE_ROW_CAPACITY 512u
#define WC_COCOA_BODY_ROW_CAPACITY 512u
#define WC_COCOA_CSYS_ROW_CAPACITY 128u
#define WC_COCOA_FACE_MAX_POINTS 24u

/* FeatureKind numeric values shared with the D kernel (mirrors GTK4). */
#define WC_COCOA_FEATURE_KIND_SKETCH 1u
#define WC_COCOA_FEATURE_KIND_SKETCH_LINE 2u
#define WC_COCOA_FEATURE_KIND_SKETCH_ARC 3u
#define WC_COCOA_FEATURE_KIND_SKETCH_CIRCLE 4u
#define WC_COCOA_FEATURE_KIND_SKETCH_RECTANGLE 5u
#define WC_COCOA_FEATURE_KIND_DATUM_PLANE 8u
#define WC_COCOA_FEATURE_KIND_DATUM_CSYS 10u

/* RibbonCommandFlags.planned */
#define WC_COCOA_RIBBON_FLAG_PLANNED (1u << 3)

typedef struct WcCocoaWindowConfig
{
    int width;
    int height;
    const char *title;
    const char *theme_id;
    const char *navigator_background;
    const char *navigator_rail_background;
    /* Renderer hint for the Metal drawing surface: "auto" or "metal".
       GTK-specific GSK names are accepted and ignored by the Cocoa bridge. */
    const char *renderer_hint;
    int force_software_vulkan;
} WcCocoaWindowConfig;

typedef struct WcCocoaModelSnapshot
{
    const char *model_name;
    double min_x, min_y, min_z;
    double max_x, max_y, max_z;
    uint32_t feature_count;
    uint32_t exact_count;
    uint32_t preview_count;
    uint32_t failed_count;
    int bounds_valid;
} WcCocoaModelSnapshot;

typedef struct WcCocoaFeatureRow
{
    uint32_t id;
    const char *name;
    const char *kind_name;
    uint32_t kind;
    uint32_t exact_status;
    uint32_t dependency_depth;
    uint32_t dirty;
} WcCocoaFeatureRow;

typedef struct WcCocoaBodyRow
{
    uint32_t feature_id;
    const char *name;
    uint32_t kind;
    uint32_t exact_status;
    double min_x, min_y, min_z;
    double max_x, max_y, max_z;
} WcCocoaBodyRow;

typedef struct WcCocoaMassProperties
{
    int valid;
    double volume;
    double surface_area;
    double centre_of_mass[3];
} WcCocoaMassProperties;

typedef struct WcCocoaCsysRow
{
    uint32_t feature_id;
    const char *name;
    double origin[3];
    double x_axis[3];
    double y_axis[3];
    double z_axis[3];
} WcCocoaCsysRow;

typedef struct WcCocoaSketchGeometryRow
{
    uint32_t id;
    uint32_t sketch_id;
    uint32_t kind;
    double values[6];
    int frame_valid;
    double frame_origin[3];
    double frame_x_axis[3];
    double frame_y_axis[3];
} WcCocoaSketchGeometryRow;

typedef struct WcCocoaPlanarFaceRow
{
    uint64_t persistent_id;
    uint32_t owner_feature_id;
    uint32_t semantic_slot;
    const char *owner_name;
    uint32_t point_count;
    double points[WC_COCOA_FACE_MAX_POINTS * 3u];
} WcCocoaPlanarFaceRow;

/* Mirrors SectionDescriptorV1; returned as a borrowed pointer array. */
typedef struct WcCocoaSectionEntry
{
    uint32_t abi_version;
    const char *id;
    const char *localisation_key;
    const char *icon_name;
    uint32_t capabilities;
} WcCocoaSectionEntry;

/* Mirrors RibbonTabDescriptorV1 / RibbonCommandDescriptorV1 /
   SectionRibbonV1 so the D host can pass its descriptors straight through. */
typedef struct WcCocoaRibbonTab
{
    const char *id;
    const char *localisation_key;
    const char *icon_name;
} WcCocoaRibbonTab;

typedef struct WcCocoaRibbonCommand
{
    const char *id;
    const char *localisation_key;
    const char *icon_name;
    const char *tab_id;
    const char *group_id;
    uint32_t flags;
} WcCocoaRibbonCommand;

typedef struct WcCocoaRibbonSnapshot
{
    const char *section_id;
    const WcCocoaRibbonTab *tabs;
    size_t tab_count;
    const WcCocoaRibbonCommand *commands;
    size_t command_count;
} WcCocoaRibbonSnapshot;

typedef int (*WcCocoaSubmitCommandFn)(void *user_data, char *command_line);
typedef int (*WcCocoaChooseSectionFn)(void *user_data, const char *section_id);
typedef const char *(*WcCocoaActiveSectionFn)(void *user_data);
typedef void (*WcCocoaSnapshotFn)(void *user_data, WcCocoaModelSnapshot *snapshot);
typedef size_t (*WcCocoaFeatureRowsFn)(void *user_data, WcCocoaFeatureRow *rows, size_t capacity);
typedef size_t (*WcCocoaBodyRowsFn)(void *user_data, WcCocoaBodyRow *rows, size_t capacity);
typedef int (*WcCocoaMassPropertiesFn)(void *user_data, uint32_t feature_id, WcCocoaMassProperties *result);
typedef size_t (*WcCocoaCsysRowsFn)(void *user_data, WcCocoaCsysRow *rows, size_t capacity);
typedef const WcCocoaSectionEntry *(*WcCocoaSectionEntriesFn)(void *user_data, size_t *count);
typedef const WcCocoaRibbonSnapshot *(*WcCocoaActiveRibbonFn)(void *user_data);
typedef const char *(*WcCocoaRibbonTemplateFn)(void *user_data, const char *command_id);
typedef size_t (*WcCocoaSketchGeometryRowsFn)(void *user_data, uint32_t sketch_id, WcCocoaSketchGeometryRow *rows, size_t capacity);
typedef size_t (*WcCocoaPlanarFaceRowsFn)(void *user_data, WcCocoaPlanarFaceRow *rows, size_t capacity);
/* action: 0 = delete, < 0 = move up, > 0 = move down (semantic SCL). */
typedef int (*WcCocoaFeatureActionFn)(void *user_data, uint32_t feature_id, int action);
typedef int (*WcCocoaFeatureReorderFn)(void *user_data, uint32_t feature_id, uint32_t target_feature_id, int after_target);

typedef struct WcCocoaCallbacks
{
    WcCocoaSubmitCommandFn submit_command;
    WcCocoaChooseSectionFn choose_section;
    WcCocoaActiveSectionFn active_section;
    WcCocoaSnapshotFn model_snapshot;
    WcCocoaFeatureRowsFn feature_rows;
    WcCocoaBodyRowsFn body_rows;
    WcCocoaMassPropertiesFn mass_properties;
    WcCocoaCsysRowsFn csys_rows;
    WcCocoaSectionEntriesFn section_entries;
    WcCocoaActiveRibbonFn active_ribbon;
    WcCocoaRibbonTemplateFn ribbon_template;
    WcCocoaSketchGeometryRowsFn sketch_geometry_rows;
    WcCocoaPlanarFaceRowsFn planar_face_rows;
    WcCocoaFeatureActionFn feature_action;
    WcCocoaFeatureReorderFn feature_reorder;
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
