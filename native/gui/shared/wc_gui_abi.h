#ifndef WAIFUCAD_WC_GUI_ABI_H
#define WAIFUCAD_WC_GUI_ABI_H

/* Toolkit-neutral GUI front-end ABI.
 *
 * This is the single native contract shared by every GUI front-end bridge
 * (Cocoa/AppKit, GTK4, and any future Qt/Motif/Xlib or new toolkit port).
 * Toolkit bridges include this header — directly or through a thin prefixed
 * compatibility shim such as native/gui/cocoa/wc_cocoa.h — so an ABI change
 * is made once here and propagates to every front-end.
 *
 * The D side mirrors these layouts in
 * src/waifucad/gui/frontends/common/frontend.d; both must stay in sync. */

#include <stddef.h>
#include <stdint.h>
#include "wc_feature_dialogue.h"

#ifdef __cplusplus
extern "C" {
#endif

#define WC_GUI_UI_ID_CAPACITY 160
#define WC_GUI_FEATURE_ROW_CAPACITY 1024
#define WC_GUI_FACE_ROW_CAPACITY 512u
#define WC_GUI_BODY_ROW_CAPACITY 512u
#define WC_GUI_CSYS_ROW_CAPACITY 128u
#define WC_GUI_FACE_MAX_POINTS 24u

/* FeatureKind numeric values shared with the D kernel. */
#define WC_GUI_FEATURE_KIND_SKETCH 1u
#define WC_GUI_FEATURE_KIND_SKETCH_LINE 2u
#define WC_GUI_FEATURE_KIND_SKETCH_ARC 3u
#define WC_GUI_FEATURE_KIND_SKETCH_CIRCLE 4u
#define WC_GUI_FEATURE_KIND_SKETCH_RECTANGLE 5u
#define WC_GUI_FEATURE_KIND_DATUM_PLANE 8u
#define WC_GUI_FEATURE_KIND_DATUM_CSYS 10u

/* RibbonCommandFlags.planned */
#define WC_GUI_RIBBON_FLAG_PLANNED (1u << 3)

/* renderer_hint is a toolkit/backend-specific renderer selection string
 * (for example a GTK GSK renderer name); force_software_vulkan requests the
 * software Vulkan path (lavapipe) where the stack supports it. Front-ends
 * without a selectable renderer may ignore both. */
typedef struct WcGuiWindowConfig {
    int width;
    int height;
    const char *title;
    const char *theme_id;
    const char *navigator_background;
    const char *navigator_rail_background;
    const char *renderer_hint;
    int force_software_vulkan;
} WcGuiWindowConfig;

typedef struct WcGuiModelSnapshot {
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
} WcGuiModelSnapshot;

typedef struct WcGuiFeatureRow {
    uint32_t id;
    const char *name;
    const char *kind_name;
    uint32_t kind;
    uint32_t exact_status;
    uint32_t dependency_depth;
    uint32_t dirty;
} WcGuiFeatureRow;

typedef struct WcGuiBodyRow {
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
} WcGuiBodyRow;

typedef struct WcGuiMassProperties {
    int valid;
    double volume;
    double surface_area;
    double centre_of_mass[3];
} WcGuiMassProperties;

typedef struct WcGuiCsysRow {
    uint32_t feature_id;
    const char *name;
    double origin[3];
    double x_axis[3];
    double y_axis[3];
    double z_axis[3];
} WcGuiCsysRow;

typedef struct WcGuiSketchGeometryRow {
    uint32_t id;
    uint32_t sketch_id;
    uint32_t kind;
    double values[6];
    int frame_valid;
    double frame_origin[3];
    double frame_x_axis[3];
    double frame_y_axis[3];
} WcGuiSketchGeometryRow;

typedef struct WcGuiPlanarFaceRow {
    uint64_t persistent_id;
    uint32_t owner_feature_id;
    uint32_t semantic_slot;
    const char *owner_name;
    uint32_t point_count;
    double points[WC_GUI_FACE_MAX_POINTS * 3u];
} WcGuiPlanarFaceRow;

typedef enum WcGuiSketchSupportKind {
    WC_GUI_SKETCH_SUPPORT_NONE = 0,
    WC_GUI_SKETCH_SUPPORT_DATUM_PLANE = 1,
    WC_GUI_SKETCH_SUPPORT_CSYS_PLANE = 2,
    WC_GUI_SKETCH_SUPPORT_PLANAR_FACE = 3
} WcGuiSketchSupportKind;

typedef struct WcGuiSketchSupport {
    uint32_t kind;
    uint32_t feature_id;
    uint64_t face_persistent_id;
    const char *csys_plane;
} WcGuiSketchSupport;

/* These layouts intentionally mirror the toolkit-neutral Section/ribbon ABI. */
typedef struct WcGuiSectionEntry {
    uint32_t abi_version;
    const char *id;
    const char *localisation_key;
    const char *icon_name;
    uint32_t capabilities;
} WcGuiSectionEntry;

typedef struct WcGuiRibbonTab {
    const char *id;
    const char *localisation_key;
    const char *icon_name;
} WcGuiRibbonTab;

typedef struct WcGuiRibbonCommand {
    const char *id;
    const char *localisation_key;
    const char *icon_name;
    const char *tab_id;
    const char *group_id;
    uint32_t flags;
} WcGuiRibbonCommand;

typedef struct WcGuiRibbonSnapshot {
    const char *section_id;
    const WcGuiRibbonTab *tabs;
    size_t tab_count;
    const WcGuiRibbonCommand *commands;
    size_t command_count;
} WcGuiRibbonSnapshot;

typedef int (*WcGuiSubmitCommandFn)(void *user_data, char *command);
typedef int (*WcGuiChooseSectionFn)(void *user_data, const char *section_id);
typedef const char *(*WcGuiActiveSectionFn)(void *user_data);
typedef void (*WcGuiSnapshotFn)(void *user_data, WcGuiModelSnapshot *snapshot);
typedef size_t (*WcGuiFeatureRowsFn)(void *user_data, WcGuiFeatureRow *rows, size_t capacity);
typedef size_t (*WcGuiBodyRowsFn)(void *user_data, WcGuiBodyRow *rows, size_t capacity);
typedef int (*WcGuiMassPropertiesFn)(void *user_data, uint32_t feature_id, WcGuiMassProperties *result);
typedef size_t (*WcGuiCsysRowsFn)(void *user_data, WcGuiCsysRow *rows, size_t capacity);
typedef const WcGuiSectionEntry *(*WcGuiSectionEntriesFn)(void *user_data, size_t *count);
typedef const WcGuiRibbonSnapshot *(*WcGuiActiveRibbonFn)(void *user_data);
typedef const char *(*WcGuiRibbonTemplateFn)(void *user_data, const char *command_id);
typedef const WcFeatureDialogueDescriptorV1 *(*WcGuiFeatureDialogueFn)(void *user_data, const char *command_id);
typedef const WcFeatureDialogueDescriptorV1 *(*WcGuiFeatureDialogueForFeatureFn)(void *user_data, uint32_t feature_id);
typedef int (*WcGuiFeatureDialogueValueFn)(void *user_data, uint32_t feature_id,
                                             const WcFeatureDialogueDescriptorV1 *descriptor,
                                             size_t field_index, char *output, size_t capacity);
typedef int (*WcGuiFeatureDialogueAcceptSelectionFn)(void *user_data,
                                                       const WcFeatureDialogueDescriptorV1 *descriptor,
                                                       size_t field_index, uint32_t feature_id);
typedef int (*WcGuiBeginNewSketchFn)(void *user_data, const WcGuiSketchSupport *support, uint32_t *sketch_id, const char **sketch_name);
typedef int (*WcGuiEditSketchFn)(void *user_data, uint32_t sketch_id, const char **sketch_name);
typedef int (*WcGuiFinishSketchFn)(void *user_data, uint32_t sketch_id);
typedef size_t (*WcGuiSketchGeometryRowsFn)(void *user_data, uint32_t sketch_id, WcGuiSketchGeometryRow *rows, size_t capacity);
typedef size_t (*WcGuiPlanarFaceRowsFn)(void *user_data, WcGuiPlanarFaceRow *rows, size_t capacity);
typedef int (*WcGuiSketchAddLineFn)(void *user_data, uint32_t sketch_id, double x1, double y1, double x2, double y2,
                                       uint32_t first_snap_feature, uint32_t first_snap_point,
                                       uint32_t second_snap_feature, uint32_t second_snap_point);
typedef int (*WcGuiSketchAddCircleFn)(void *user_data, uint32_t sketch_id, double cx, double cy, double radius);
typedef int (*WcGuiSketchAddRectangleFn)(void *user_data, uint32_t sketch_id, double x, double y, double width, double height);
typedef int (*WcGuiFeatureActionFn)(void *user_data, uint32_t feature_id, int action);
typedef int (*WcGuiFeatureReorderFn)(void *user_data, uint32_t feature_id, uint32_t target_feature_id, int after_target);
/* Ribbon command search. `matches` is a caller-owned buffer of at most
 * `capacity` WcGuiRibbonCommand slots; returns the number written. The D
 * side owns matching so every toolkit shares one ranking implementation.
 * Appended at the end of the struct for front-end/toolkit compatibility. */
typedef size_t (*WcGuiRibbonSearchFn)(void *user_data, const char *query,
                                      WcGuiRibbonCommand *matches, size_t capacity);

typedef const char *(*WcGuiSclErrorTextFn)(void *user_data, int code);
typedef struct WcGuiCallbacks {
    WcGuiSubmitCommandFn submit_command;
    WcGuiChooseSectionFn choose_section;
    WcGuiActiveSectionFn active_section;
    WcGuiSnapshotFn model_snapshot;
    WcGuiFeatureRowsFn feature_rows;
    WcGuiBodyRowsFn body_rows;
    WcGuiMassPropertiesFn mass_properties;
    WcGuiCsysRowsFn csys_rows;
    WcGuiSectionEntriesFn section_entries;
    WcGuiActiveRibbonFn active_ribbon;
    WcGuiRibbonTemplateFn ribbon_template;
    WcGuiFeatureDialogueFn feature_dialogue;
    WcGuiFeatureDialogueForFeatureFn feature_dialogue_for_feature;
    WcGuiFeatureDialogueValueFn feature_dialogue_value;
    WcGuiFeatureDialogueAcceptSelectionFn feature_dialogue_accept_selection;
    WcGuiBeginNewSketchFn begin_new_sketch;
    WcGuiEditSketchFn edit_sketch;
    WcGuiFinishSketchFn finish_sketch;
    WcGuiSketchGeometryRowsFn sketch_geometry_rows;
    WcGuiPlanarFaceRowsFn planar_face_rows;
    WcGuiSketchAddLineFn sketch_add_line;
    WcGuiSketchAddCircleFn sketch_add_circle;
    WcGuiSketchAddRectangleFn sketch_add_rectangle;
    WcGuiFeatureActionFn feature_action;
    WcGuiFeatureReorderFn feature_reorder;
    WcGuiRibbonSearchFn ribbon_search;
    WcGuiSclErrorTextFn scl_error_text;
} WcGuiCallbacks;

/* Every front-end native bridge exports this pair of entry points under its
 * own prefix, e.g. wc_cocoa_native_available / wc_cocoa_run:
 *
 *   int wc_<id>_native_available(void);
 *   int wc_<id>_run(const WcGuiWindowConfig *config,
 *                   const WcGuiCallbacks *callbacks,
 *                   void *user_data);
 */

#ifdef __cplusplus
}
#endif

#endif
