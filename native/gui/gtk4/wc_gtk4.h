#ifndef WAIFUCAD_WC_GTK4_H
#define WAIFUCAD_WC_GTK4_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct WcGtk4WindowConfig {
    int width;
    int height;
    const char *title;
    const char *theme_id;
    const char *navigator_background;
    const char *navigator_rail_background;
    const char *gsk_renderer;
    int force_lavapipe;
} WcGtk4WindowConfig;

typedef struct WcGtk4ModelSnapshot {
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
} WcGtk4ModelSnapshot;

typedef struct WcGtk4FeatureRow {
    uint32_t id;
    const char *name;
    const char *kind_name;
    uint32_t kind;
    uint32_t exact_status;
    uint32_t dependency_depth;
    uint32_t dirty;
} WcGtk4FeatureRow;

typedef struct WcGtk4BodyRow {
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
} WcGtk4BodyRow;

typedef struct WcGtk4MassProperties {
    int valid;
    double volume;
    double surface_area;
    double centre_of_mass[3];
} WcGtk4MassProperties;

typedef struct WcGtk4CsysRow {
    uint32_t feature_id;
    const char *name;
    double origin[3];
    double x_axis[3];
    double y_axis[3];
    double z_axis[3];
} WcGtk4CsysRow;

typedef struct WcGtk4SketchGeometryRow {
    uint32_t id;
    uint32_t sketch_id;
    uint32_t kind;
    double values[6];
    int frame_valid;
    double frame_origin[3];
    double frame_x_axis[3];
    double frame_y_axis[3];
} WcGtk4SketchGeometryRow;

#define WC_GTK4_FACE_MAX_POINTS 24u

typedef struct WcGtk4PlanarFaceRow {
    uint64_t persistent_id;
    uint32_t owner_feature_id;
    uint32_t semantic_slot;
    const char *owner_name;
    uint32_t point_count;
    double points[WC_GTK4_FACE_MAX_POINTS * 3u];
} WcGtk4PlanarFaceRow;

typedef enum WcGtk4SketchSupportKind {
    WC_GTK4_SKETCH_SUPPORT_NONE = 0,
    WC_GTK4_SKETCH_SUPPORT_DATUM_PLANE = 1,
    WC_GTK4_SKETCH_SUPPORT_CSYS_PLANE = 2,
    WC_GTK4_SKETCH_SUPPORT_PLANAR_FACE = 3
} WcGtk4SketchSupportKind;

typedef struct WcGtk4SketchSupport {
    uint32_t kind;
    uint32_t feature_id;
    uint64_t face_persistent_id;
    const char *csys_plane;
} WcGtk4SketchSupport;

typedef struct WcGtk4SectionEntry {
    uint32_t abi_version;
    const char *id;
    const char *localisation_key;
    const char *icon_name;
    uint32_t capabilities;
} WcGtk4SectionEntry;

typedef struct WcGtk4RibbonTab {
    const char *id;
    const char *localisation_key;
    const char *icon_name;
} WcGtk4RibbonTab;

typedef struct WcGtk4RibbonCommand {
    const char *id;
    const char *localisation_key;
    const char *icon_name;
    const char *tab_id;
    const char *group_id;
    uint32_t flags;
} WcGtk4RibbonCommand;

typedef struct WcGtk4RibbonSnapshot {
    const char *section_id;
    const WcGtk4RibbonTab *tabs;
    size_t tab_count;
    const WcGtk4RibbonCommand *commands;
    size_t command_count;
} WcGtk4RibbonSnapshot;

#define WC_FEATURE_DIALOGUE_ABI_V1 1u
#define WC_FEATURE_DIALOGUE_NO_SOURCE UINT32_MAX

typedef enum WcFeatureDialogueFieldKind {
    WC_FEATURE_DIALOGUE_FIELD_NAME = 1,
    WC_FEATURE_DIALOGUE_FIELD_VALUE = 2,
    WC_FEATURE_DIALOGUE_FIELD_FEATURE = 3,
    WC_FEATURE_DIALOGUE_FIELD_TEXT = 4,
    WC_FEATURE_DIALOGUE_FIELD_BOOLEAN = 5,
    WC_FEATURE_DIALOGUE_FIELD_FILE = 6,
    WC_FEATURE_DIALOGUE_FIELD_CHOICE = 7,
    WC_FEATURE_DIALOGUE_FIELD_RAW = 8
} WcFeatureDialogueFieldKind;

typedef enum WcFeatureDialogueSelectionKind {
    WC_FEATURE_DIALOGUE_SELECTION_NONE = 0,
    WC_FEATURE_DIALOGUE_SELECTION_ANY_FEATURE = 1,
    WC_FEATURE_DIALOGUE_SELECTION_PROFILE = 2,
    WC_FEATURE_DIALOGUE_SELECTION_BODY = 3,
    WC_FEATURE_DIALOGUE_SELECTION_PATH = 4
} WcFeatureDialogueSelectionKind;

typedef enum WcFeatureDialogueFieldSource {
    WC_FEATURE_DIALOGUE_SOURCE_NONE = 0,
    WC_FEATURE_DIALOGUE_SOURCE_FEATURE_NAME = 1,
    WC_FEATURE_DIALOGUE_SOURCE_OPERAND = 2,
    WC_FEATURE_DIALOGUE_SOURCE_PAYLOAD = 3,
    WC_FEATURE_DIALOGUE_SOURCE_PAYLOAD2 = 4
} WcFeatureDialogueFieldSource;

#define WC_FEATURE_DIALOGUE_FIELD_REQUIRED (1u << 0)
#define WC_FEATURE_DIALOGUE_FIELD_READ_ONLY (1u << 1)

#define WC_FEATURE_DIALOGUE_EDITABLE (1u << 0)
#define WC_FEATURE_DIALOGUE_SKETCH_EDITOR (1u << 1)
#define WC_FEATURE_DIALOGUE_OPERATION (1u << 2)

typedef struct WcFeatureDialogueFieldDescriptorV1 {
    const char *id;
    const char *label;
    uint32_t kind;
    const char *default_value;
    const char *choices;
    uint32_t source;
    uint32_t source_index;
    uint32_t flags;
    uint32_t selection_kind;
} WcFeatureDialogueFieldDescriptorV1;

typedef struct WcFeatureDialogueDescriptorV1 {
    uint32_t abi_version;
    const char *id;
    const char *title;
    const char *command_name;
    const char *argument_prefix;
    const char *edit_kind;
    const char *waifu_image;
    const WcFeatureDialogueFieldDescriptorV1 *fields;
    size_t field_count;
    uint32_t flags;
} WcFeatureDialogueDescriptorV1;

typedef int (*WcGtk4SubmitCommandFn)(void *user_data, char *command);
typedef int (*WcGtk4ChooseSectionFn)(void *user_data, const char *section_id);
typedef const char *(*WcGtk4ActiveSectionFn)(void *user_data);
typedef void (*WcGtk4SnapshotFn)(void *user_data, WcGtk4ModelSnapshot *snapshot);
typedef size_t (*WcGtk4FeatureRowsFn)(void *user_data, WcGtk4FeatureRow *rows, size_t capacity);
typedef size_t (*WcGtk4BodyRowsFn)(void *user_data, WcGtk4BodyRow *rows, size_t capacity);
typedef int (*WcGtk4MassPropertiesFn)(void *user_data, uint32_t feature_id, WcGtk4MassProperties *result);
typedef size_t (*WcGtk4CsysRowsFn)(void *user_data, WcGtk4CsysRow *rows, size_t capacity);
typedef const WcGtk4SectionEntry *(*WcGtk4SectionEntriesFn)(void *user_data, size_t *count);
typedef const WcGtk4RibbonSnapshot *(*WcGtk4ActiveRibbonFn)(void *user_data);
typedef const char *(*WcGtk4RibbonTemplateFn)(void *user_data, const char *command_id);
typedef const WcFeatureDialogueDescriptorV1 *(*WcGtk4FeatureDialogueFn)(void *user_data, const char *command_id);
typedef const WcFeatureDialogueDescriptorV1 *(*WcGtk4FeatureDialogueForFeatureFn)(void *user_data, uint32_t feature_id);
typedef int (*WcGtk4FeatureDialogueValueFn)(void *user_data, uint32_t feature_id,
                                             const WcFeatureDialogueDescriptorV1 *descriptor,
                                             size_t field_index, char *output, size_t capacity);
typedef int (*WcGtk4FeatureDialogueAcceptSelectionFn)(void *user_data,
                                                       const WcFeatureDialogueDescriptorV1 *descriptor,
                                                       size_t field_index, uint32_t feature_id);
typedef int (*WcGtk4BeginNewSketchFn)(void *user_data, const WcGtk4SketchSupport *support, uint32_t *sketch_id, const char **sketch_name);
typedef int (*WcGtk4EditSketchFn)(void *user_data, uint32_t sketch_id, const char **sketch_name);
typedef int (*WcGtk4FinishSketchFn)(void *user_data, uint32_t sketch_id);
typedef size_t (*WcGtk4SketchGeometryRowsFn)(void *user_data, uint32_t sketch_id, WcGtk4SketchGeometryRow *rows, size_t capacity);
typedef size_t (*WcGtk4PlanarFaceRowsFn)(void *user_data, WcGtk4PlanarFaceRow *rows, size_t capacity);
typedef int (*WcGtk4SketchAddLineFn)(void *user_data, uint32_t sketch_id, double x1, double y1, double x2, double y2,
                                       uint32_t first_snap_feature, uint32_t first_snap_point,
                                       uint32_t second_snap_feature, uint32_t second_snap_point);
typedef int (*WcGtk4SketchAddCircleFn)(void *user_data, uint32_t sketch_id, double cx, double cy, double radius);
typedef int (*WcGtk4SketchAddRectangleFn)(void *user_data, uint32_t sketch_id, double x, double y, double width, double height);
typedef int (*WcGtk4FeatureActionFn)(void *user_data, uint32_t feature_id, int action);
typedef int (*WcGtk4FeatureReorderFn)(void *user_data, uint32_t feature_id, uint32_t target_feature_id, int after_target);

typedef struct WcGtk4Callbacks {
    WcGtk4SubmitCommandFn submit_command;
    WcGtk4ChooseSectionFn choose_section;
    WcGtk4ActiveSectionFn active_section;
    WcGtk4SnapshotFn model_snapshot;
    WcGtk4FeatureRowsFn feature_rows;
    WcGtk4BodyRowsFn body_rows;
    WcGtk4MassPropertiesFn mass_properties;
    WcGtk4CsysRowsFn csys_rows;
    WcGtk4SectionEntriesFn section_entries;
    WcGtk4ActiveRibbonFn active_ribbon;
    WcGtk4RibbonTemplateFn ribbon_template;
    WcGtk4FeatureDialogueFn feature_dialogue;
    WcGtk4FeatureDialogueForFeatureFn feature_dialogue_for_feature;
    WcGtk4FeatureDialogueValueFn feature_dialogue_value;
    WcGtk4FeatureDialogueAcceptSelectionFn feature_dialogue_accept_selection;
    WcGtk4BeginNewSketchFn begin_new_sketch;
    WcGtk4EditSketchFn edit_sketch;
    WcGtk4FinishSketchFn finish_sketch;
    WcGtk4SketchGeometryRowsFn sketch_geometry_rows;
    WcGtk4PlanarFaceRowsFn planar_face_rows;
    WcGtk4SketchAddLineFn sketch_add_line;
    WcGtk4SketchAddCircleFn sketch_add_circle;
    WcGtk4SketchAddRectangleFn sketch_add_rectangle;
    WcGtk4FeatureActionFn feature_action;
    WcGtk4FeatureReorderFn feature_reorder;
} WcGtk4Callbacks;

int wc_gtk4_native_available(void);
int wc_gtk4_run(const WcGtk4WindowConfig *config,
                const WcGtk4Callbacks *callbacks,
                void *user_data);

#ifdef __cplusplus
}
#endif

#endif

