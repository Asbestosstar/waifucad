#ifndef WC_COCOA_H
#define WC_COCOA_H

#include <stddef.h>
#include <stdint.h>
#include "../shared/wc_feature_dialogue.h"

#ifdef __cplusplus
extern "C" {
#endif

#define WC_COCOA_UI_ID_CAPACITY 160
#define WC_COCOA_FEATURE_ROW_CAPACITY 1024
#define WC_COCOA_FACE_ROW_CAPACITY 512u
#define WC_COCOA_BODY_ROW_CAPACITY 512u
#define WC_COCOA_CSYS_ROW_CAPACITY 128u

/* FeatureKind numeric values shared with the D kernel. */
#define WC_COCOA_FEATURE_KIND_SKETCH 1u
#define WC_COCOA_FEATURE_KIND_SKETCH_LINE 2u
#define WC_COCOA_FEATURE_KIND_SKETCH_ARC 3u
#define WC_COCOA_FEATURE_KIND_SKETCH_CIRCLE 4u
#define WC_COCOA_FEATURE_KIND_SKETCH_RECTANGLE 5u
#define WC_COCOA_FEATURE_KIND_DATUM_PLANE 8u
#define WC_COCOA_FEATURE_KIND_DATUM_CSYS 10u

/* RibbonCommandFlags.planned */
#define WC_COCOA_RIBBON_FLAG_PLANNED (1u << 3)

typedef struct WcCocoaWindowConfig {
    int width;
    int height;
    const char *title;
    const char *theme_id;
    const char *navigator_background;
    const char *navigator_rail_background;
    const char *renderer_hint;
    int force_software_vulkan;
} WcCocoaWindowConfig;

typedef struct WcCocoaModelSnapshot {
    const char *model_name;
    double min_x;
    double min_y;
    double min_z;
    double max_x;
    double max_y;
    double max_z;
    uint32_t feature_count;
    uint32_t exact_count;
    uint32_t preview_count;
    uint32_t failed_count;
    int bounds_valid;
} WcCocoaModelSnapshot;

typedef struct WcCocoaFeatureRow {
    uint32_t id;
    const char *name;
    const char *kind_name;
    uint32_t kind;
    uint32_t exact_status;
    uint32_t dependency_depth;
    uint32_t dirty;
} WcCocoaFeatureRow;

typedef struct WcCocoaBodyRow {
    uint32_t feature_id;
    const char *name;
    uint32_t kind;
    uint32_t exact_status;
    double min_x;
    double min_y;
    double min_z;
    double max_x;
    double max_y;
    double max_z;
} WcCocoaBodyRow;

typedef struct WcCocoaMassProperties {
    int valid;
    double volume;
    double surface_area;
    double centre_of_mass[3];
} WcCocoaMassProperties;

typedef struct WcCocoaCsysRow {
    uint32_t feature_id;
    const char *name;
    double origin[3];
    double x_axis[3];
    double y_axis[3];
    double z_axis[3];
} WcCocoaCsysRow;

typedef struct WcCocoaSketchGeometryRow {
    uint32_t id;
    uint32_t sketch_id;
    uint32_t kind;
    double values[6];
    int frame_valid;
    double frame_origin[3];
    double frame_x_axis[3];
    double frame_y_axis[3];
} WcCocoaSketchGeometryRow;

#define WC_COCOA_FACE_MAX_POINTS 24u

typedef struct WcCocoaPlanarFaceRow {
    uint64_t persistent_id;
    uint32_t owner_feature_id;
    uint32_t semantic_slot;
    const char *owner_name;
    uint32_t point_count;
    double points[WC_COCOA_FACE_MAX_POINTS * 3u];
} WcCocoaPlanarFaceRow;

typedef enum WcCocoaSketchSupportKind {
    WC_COCOA_SKETCH_SUPPORT_NONE = 0,
    WC_COCOA_SKETCH_SUPPORT_DATUM_PLANE = 1,
    WC_COCOA_SKETCH_SUPPORT_CSYS_PLANE = 2,
    WC_COCOA_SKETCH_SUPPORT_PLANAR_FACE = 3
} WcCocoaSketchSupportKind;

typedef struct WcCocoaSketchSupport {
    uint32_t kind;
    uint32_t feature_id;
    uint64_t face_persistent_id;
    const char *csys_plane;
} WcCocoaSketchSupport;

typedef struct WcCocoaSectionEntry {
    uint32_t abi_version;
    const char *id;
    const char *localisation_key;
    const char *icon_name;
    uint32_t capabilities;
} WcCocoaSectionEntry;

typedef struct WcCocoaRibbonTab {
    const char *id;
    const char *localisation_key;
    const char *icon_name;
} WcCocoaRibbonTab;

typedef struct WcCocoaRibbonCommand {
    const char *id;
    const char *localisation_key;
    const char *icon_name;
    const char *tab_id;
    const char *group_id;
    uint32_t flags;
} WcCocoaRibbonCommand;

typedef struct WcCocoaRibbonSnapshot {
    const char *section_id;
    const WcCocoaRibbonTab *tabs;
    size_t tab_count;
    const WcCocoaRibbonCommand *commands;
    size_t command_count;
} WcCocoaRibbonSnapshot;

typedef int (*WcCocoaSubmitCommandFn)(void *user_data, char *command);
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
typedef const WcFeatureDialogueDescriptorV1 *(*WcCocoaFeatureDialogueFn)(void *user_data, const char *command_id);
typedef const WcFeatureDialogueDescriptorV1 *(*WcCocoaFeatureDialogueForFeatureFn)(void *user_data, uint32_t feature_id);
typedef int (*WcCocoaFeatureDialogueValueFn)(void *user_data, uint32_t feature_id,
                                             const WcFeatureDialogueDescriptorV1 *descriptor,
                                             size_t field_index, char *output, size_t capacity);
typedef int (*WcCocoaFeatureDialogueAcceptSelectionFn)(void *user_data,
                                                       const WcFeatureDialogueDescriptorV1 *descriptor,
                                                       size_t field_index, uint32_t feature_id);
typedef int (*WcCocoaBeginNewSketchFn)(void *user_data, const WcCocoaSketchSupport *support, uint32_t *sketch_id, const char **sketch_name);
typedef int (*WcCocoaEditSketchFn)(void *user_data, uint32_t sketch_id, const char **sketch_name);
typedef int (*WcCocoaFinishSketchFn)(void *user_data, uint32_t sketch_id);
typedef size_t (*WcCocoaSketchGeometryRowsFn)(void *user_data, uint32_t sketch_id, WcCocoaSketchGeometryRow *rows, size_t capacity);
typedef size_t (*WcCocoaPlanarFaceRowsFn)(void *user_data, WcCocoaPlanarFaceRow *rows, size_t capacity);
typedef int (*WcCocoaSketchAddLineFn)(void *user_data, uint32_t sketch_id, double x1, double y1, double x2, double y2,
                                       uint32_t first_snap_feature, uint32_t first_snap_point,
                                       uint32_t second_snap_feature, uint32_t second_snap_point);
typedef int (*WcCocoaSketchAddCircleFn)(void *user_data, uint32_t sketch_id, double cx, double cy, double radius);
typedef int (*WcCocoaSketchAddRectangleFn)(void *user_data, uint32_t sketch_id, double x, double y, double width, double height);
typedef int (*WcCocoaFeatureActionFn)(void *user_data, uint32_t feature_id, int action);
typedef int (*WcCocoaFeatureReorderFn)(void *user_data, uint32_t feature_id, uint32_t target_feature_id, int after_target);

typedef struct WcCocoaCallbacks {
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
    WcCocoaFeatureDialogueFn feature_dialogue;
    WcCocoaFeatureDialogueForFeatureFn feature_dialogue_for_feature;
    WcCocoaFeatureDialogueValueFn feature_dialogue_value;
    WcCocoaFeatureDialogueAcceptSelectionFn feature_dialogue_accept_selection;
    WcCocoaBeginNewSketchFn begin_new_sketch;
    WcCocoaEditSketchFn edit_sketch;
    WcCocoaFinishSketchFn finish_sketch;
    WcCocoaSketchGeometryRowsFn sketch_geometry_rows;
    WcCocoaPlanarFaceRowsFn planar_face_rows;
    WcCocoaSketchAddLineFn sketch_add_line;
    WcCocoaSketchAddCircleFn sketch_add_circle;
    WcCocoaSketchAddRectangleFn sketch_add_rectangle;
    WcCocoaFeatureActionFn feature_action;
    WcCocoaFeatureReorderFn feature_reorder;
} WcCocoaCallbacks;

int wc_cocoa_native_available(void);
int wc_cocoa_run(const WcCocoaWindowConfig *config,
                const WcCocoaCallbacks *callbacks,
                void *user_data);

#ifdef __cplusplus
}
#endif

#endif
