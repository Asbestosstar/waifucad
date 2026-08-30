#include "wc_gtk4.h"
#include "../../graphics/wc_gpu_probe.h"

#include <gtk/gtk.h>
#include <gdk/gdkkeysyms.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define WC_COMMAND_CAPACITY 4096
#define WC_UI_ID_CAPACITY 160
#define WC_FEATURE_ROW_CAPACITY 1024
#define WC_RIBBON_FLAG_PLANNED (1u << 3)
#define WC_FEATURE_KIND_SKETCH 1u
#define WC_FEATURE_KIND_SKETCH_LINE 2u
#define WC_FEATURE_KIND_SKETCH_ARC 3u
#define WC_FEATURE_KIND_SKETCH_CIRCLE 4u
#define WC_FEATURE_KIND_SKETCH_RECTANGLE 5u
#define WC_FEATURE_KIND_DATUM_PLANE 8u
#define WC_FEATURE_KIND_DATUM_CSYS 10u
#define WC_SNAP_MAX_CANDIDATES 16u
#define WC_FACE_ROW_CAPACITY 512u
#define WC_BODY_ROW_CAPACITY 512u
#define WC_CSYS_ROW_CAPACITY 128u

typedef enum WcSketchTool {
    WC_SKETCH_TOOL_LINE = 1,
    WC_SKETCH_TOOL_CIRCLE = 2,
    WC_SKETCH_TOOL_RECTANGLE = 3
} WcSketchTool;

#ifndef M_PI
#define M_PI 3.14159265358979323846
#endif

typedef struct WcGtk4State WcGtk4State;

typedef struct WcProjectedPoint {
    double x;
    double y;
} WcProjectedPoint;

typedef struct WcRibbonButtonData {
    WcGtk4State *state;
    char id[WC_UI_ID_CAPACITY];
} WcRibbonButtonData;

typedef struct WcSectionButtonData {
    WcGtk4State *state;
    char id[WC_UI_ID_CAPACITY];
} WcSectionButtonData;

typedef struct WcSnapCandidate {
    uint32_t feature_id;
    uint32_t point_index;
    uint32_t kind;
    double x;
    double y;
    double screen_x;
    double screen_y;
    double distance;
} WcSnapCandidate;

enum {
    WC_SNAP_ENDPOINT = 0u,
    WC_SNAP_CORNER = 1u,
    WC_SNAP_CENTRE = 2u,
    WC_SNAP_ORIGIN = 3u,
    WC_SNAP_X_AXIS = 4u,
    WC_SNAP_Y_AXIS = 5u
};

typedef struct WcSnapChoiceData {
    WcGtk4State *state;
    uint32_t candidate_index;
    GtkWidget *window;
} WcSnapChoiceData;

typedef struct WcFeatureMenuData {
    WcGtk4State *state;
    uint32_t feature_id;
} WcFeatureMenuData;

typedef struct WcFeatureDropData {
    WcGtk4State *state;
    uint32_t target_feature_id;
} WcFeatureDropData;

typedef struct WcFeatureDialogueUi {
    WcGtk4State *state;
    const WcFeatureDialogueDescriptorV1 *descriptor;
    uint32_t feature_id;
    GtkWidget *window;
    GtkWidget **editors;
} WcFeatureDialogueUi;

typedef enum WcPathChooserMode {
    WC_PATH_CHOOSER_FIELD = 0,
    WC_PATH_CHOOSER_RUN_SCRIPT = 1,
    WC_PATH_CHOOSER_START_JOURNAL = 2,
    WC_PATH_CHOOSER_RUN_JOURNAL = 3
} WcPathChooserMode;

typedef struct WcPathChooserData {
    WcGtk4State *state;
    GtkWidget *entry;
    WcPathChooserMode mode;
} WcPathChooserData;

struct WcGtk4State {
    const WcGtk4Callbacks *callbacks;
    void *user_data;
    GMainLoop *loop;
    GtkWidget *window;
    GtkWidget *drawing_area;
    GtkWidget *command_entry;
    GtkWidget *command_status;
    GtkWidget *model_status;
    GtkWidget *section_status;
    GtkWidget *renderer_status;
    GtkWidget *model_name_label;
    GtkWidget *model_list;
    GtkWidget *assembly_name_label;
    GtkWidget *ai_summary_label;
    GtkWidget *navigator_stack;
    GtkWidget *navigator_paned;
    GtkWidget *ribbon_tabs_box;
    GtkWidget *ribbon_commands_box;
    GtkWidget *ribbon_scroller;
    GtkWidget *ribbon_waifu;
    WcGpuProbe gpu;

    char active_ribbon_tab[WC_UI_ID_CAPACITY];
    double yaw;
    double pitch;
    double zoom;
    double pan_x;
    double pan_y;
    double drag_yaw;
    double drag_pitch;
    double drag_pan_x;
    double drag_pan_y;

    uint32_t selected_feature_id;
    uint32_t selected_feature_kind;
    uint32_t selected_feature_exact_status;
    uint32_t selected_feature_depth;
    uint32_t selected_body_feature_id;
    char selected_feature_name[WC_UI_ID_CAPACITY];
    uint32_t selected_support_kind;
    uint32_t selected_support_feature_id;
    uint64_t selected_face_persistent_id;
    char selected_csys_plane[4];
    int selected_row_is_feature;
    WcFeatureDialogueUi *feature_pick_ui;
    WcFeatureDialogueUi *active_feature_dialogue_ui;
    size_t feature_pick_field_index;
    int sketch_support_mode;
    uint64_t hover_face_persistent_id;
    uint32_t hover_face_owner_id;
    double pointer_x;
    double pointer_y;
    int pointer_valid;
    int sketch_mode;
    uint32_t active_sketch_id;
    char active_sketch_name[WC_UI_ID_CAPACITY];
    WcSketchTool sketch_tool;
    int sketch_has_anchor;
    double sketch_anchor_x;
    double sketch_anchor_y;
    double sketch_cursor_x;
    double sketch_cursor_y;
    int sketch_cursor_valid;
    uint32_t sketch_anchor_snap_feature;
    uint32_t sketch_anchor_snap_point;
    WcSnapCandidate snap_candidates[WC_SNAP_MAX_CANDIDATES];
    size_t snap_candidate_count;
    int snap_choice_locked;
    WcSnapCandidate snap_choice;
    guint snap_timer_id;
    int snap_ambiguity_ready;
    double snap_pointer_x;
    double snap_pointer_y;
    int window_width_hint;
    int ribbon_density;
    int journal_recording;
    int fit_bounds_valid;
    double fit_min_x;
    double fit_min_y;
    double fit_min_z;
    double fit_max_x;
    double fit_max_y;
    double fit_max_z;
};

static void configure_feature_drag(WcGtk4State *state, GtkWidget *row_widget, uint32_t feature_id);
static void show_feature_context_menu(WcGtk4State *state, GtkWidget *relative_to,
                                      uint32_t feature_id, double x, double y);
static void show_feature_properties(WcGtk4State *state, uint32_t feature_id);
static void show_mass_properties(WcGtk4State *state, uint32_t feature_id);
static void show_feature_dialogue(WcGtk4State *state,
                                  const WcFeatureDialogueDescriptorV1 *descriptor,
                                  uint32_t feature_id);
static uint32_t hit_test_sketch(WcGtk4State *state, int width, int height, double x, double y);
static int feature_dialogue_accept_pick(WcGtk4State *state, uint32_t feature_id, const char *feature_name);
static void open_path_chooser(WcGtk4State *state, GtkWindow *parent, GtkWidget *entry,
                              WcPathChooserMode mode, const char *title,
                              GtkFileChooserAction action, const char *kind,
                              const char *suggested_name);
static void build_mods_ribbon_commands(WcGtk4State *state);
static void update_navigator_descendant_highlight(WcGtk4State *state);
static gboolean deferred_update_status_cb(gpointer user_data);

static void set_source_rgba(cairo_t *cr, double r, double g, double b, double a)
{
    cairo_set_source_rgba(cr, r, g, b, a);
}

static double clamp_double(double value, double minimum, double maximum)
{
    if (value < minimum) return minimum;
    if (value > maximum) return maximum;
    return value;
}

static void copy_text(char *destination, size_t capacity, const char *source)
{
    if (destination == NULL || capacity == 0)
        return;
    destination[0] = '\0';
    if (source != NULL)
        (void)snprintf(destination, capacity, "%s", source);
}

static const char *suffix_after_dot(const char *text)
{
    const char *dot;
    const char *candidate;
    if (text == NULL)
        return "";
    candidate = text;
    for (dot = text; *dot != '\0'; ++dot)
        if (*dot == '.')
            candidate = dot + 1;
    return candidate;
}

static void humanise_identifier(const char *identifier, char *output, size_t capacity)
{
    const char *source = suffix_after_dot(identifier);
    size_t write_index = 0;
    int word_start = 1;
    if (output == NULL || capacity == 0)
        return;
    output[0] = '\0';
    while (*source != '\0' && write_index + 1 < capacity) {
        char ch = *source++;
        if (ch == '_' || ch == '-') {
            output[write_index++] = ' ';
            word_start = 1;
            continue;
        }
        if (word_start && ch >= 'a' && ch <= 'z')
            ch = (char)(ch - 'a' + 'A');
        output[write_index++] = ch;
        word_start = 0;
    }
    output[write_index] = '\0';
}

static void clear_children(GtkWidget *container)
{
    GtkWidget *child;
    if (container == NULL)
        return;
    child = gtk_widget_get_first_child(container);
    while (child != NULL) {
        GtkWidget *next = gtk_widget_get_next_sibling(child);
        if (GTK_IS_LIST_BOX(container))
            gtk_list_box_remove(GTK_LIST_BOX(container), child);
        else if (GTK_IS_BOX(container))
            gtk_box_remove(GTK_BOX(container), child);
        else
            gtk_widget_unparent(child);
        child = next;
    }
}

static GtkWidget *make_label(const char *text, const char *css_class)
{
    GtkWidget *label = gtk_label_new(text != NULL ? text : "");
    gtk_label_set_xalign(GTK_LABEL(label), 0.0f);
    if (css_class != NULL)
        gtk_widget_add_css_class(label, css_class);
    return label;
}

static GtkWidget *load_svg_image(const char *icon_name, int pixel_size)
{
    char path[512];
    GtkWidget *image;
    if (icon_name == NULL || icon_name[0] == '\0')
        return gtk_image_new_from_icon_name("applications-graphics-symbolic");
    (void)snprintf(path, sizeof(path), "assets/icons/%s.svg", icon_name);
    if (g_file_test(path, G_FILE_TEST_EXISTS))
        image = gtk_image_new_from_file(path);
    else
        image = gtk_image_new_from_icon_name("applications-graphics-symbolic");
    gtk_image_set_pixel_size(GTK_IMAGE(image), pixel_size);
    return image;
}

static GtkWidget *make_icon_text_button(const char *icon_name, const char *label_text, int icon_size)
{
    GtkWidget *button = gtk_button_new();
    GtkWidget *box = gtk_box_new(GTK_ORIENTATION_VERTICAL, 3);
    GtkWidget *label = gtk_label_new(label_text != NULL ? label_text : "");
    gtk_label_set_wrap(GTK_LABEL(label), TRUE);
    gtk_label_set_justify(GTK_LABEL(label), GTK_JUSTIFY_CENTER);
    gtk_widget_set_halign(label, GTK_ALIGN_CENTER);
    gtk_box_append(GTK_BOX(box), load_svg_image(icon_name, icon_size));
    gtk_box_append(GTK_BOX(box), label);
    gtk_button_set_child(GTK_BUTTON(button), box);
    gtk_widget_add_css_class(button, "wc-ribbon-command");
    return button;
}

static void get_snapshot(WcGtk4State *state, WcGtk4ModelSnapshot *snapshot)
{
    memset(snapshot, 0, sizeof(*snapshot));
    if (state != NULL && state->callbacks != NULL && state->callbacks->model_snapshot != NULL)
        state->callbacks->model_snapshot(state->user_data, snapshot);
}

static const WcGtk4RibbonSnapshot *get_active_ribbon(WcGtk4State *state)
{
    if (state == NULL || state->callbacks == NULL || state->callbacks->active_ribbon == NULL)
        return NULL;
    return state->callbacks->active_ribbon(state->user_data);
}

static const char *exact_status_text(uint32_t status)
{
    switch (status) {
        case 1u: return "exact";
        case 2u: return "preview";
        case 3u: return "failed";
        default: return "none";
    }
}

static GtkWidget *append_model_tree_row(WcGtk4State *state, const char *text,
                                       uint32_t feature_id, uint32_t feature_kind,
                                       uint32_t exact_status, int depth,
                                       uint32_t support_kind, uint32_t support_feature_id,
                                       uint64_t face_persistent_id, const char *csys_plane,
                                       int real_feature)
{
    GtkWidget *row_box = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 5);
    GtkWidget *label = make_label(text != NULL ? text : "feature", "wc-tree-row");
    GtkWidget *row_widget = gtk_list_box_row_new();
    uint64_t *face_copy = NULL;
    gtk_widget_set_margin_start(label, depth > 0 ? depth * 12 : 2);
    gtk_label_set_single_line_mode(GTK_LABEL(label), TRUE);
    gtk_widget_set_halign(label, GTK_ALIGN_START);
    gtk_widget_set_hexpand(label, TRUE);
    gtk_box_append(GTK_BOX(row_box), label);
    if (real_feature && exact_status != 0u) {
        GtkWidget *badge = gtk_label_new(exact_status_text(exact_status));
        gtk_widget_add_css_class(badge, exact_status == 1u ? "wc-badge-exact" :
                                       exact_status == 3u ? "wc-badge-failed" : "wc-badge-preview");
        gtk_box_append(GTK_BOX(row_box), badge);
    }
    gtk_list_box_row_set_child(GTK_LIST_BOX_ROW(row_widget), row_box);
    g_object_set_data(G_OBJECT(row_widget), "wc-feature-id", GUINT_TO_POINTER(feature_id));
    g_object_set_data(G_OBJECT(row_widget), "wc-feature-kind", GUINT_TO_POINTER(feature_kind));
    g_object_set_data(G_OBJECT(row_widget), "wc-support-kind", GUINT_TO_POINTER(support_kind));
    g_object_set_data(G_OBJECT(row_widget), "wc-support-feature-id", GUINT_TO_POINTER(support_feature_id));
    g_object_set_data(G_OBJECT(row_widget), "wc-real-feature", GINT_TO_POINTER(real_feature));
    g_object_set_data(G_OBJECT(row_widget), "wc-exact-status", GUINT_TO_POINTER(exact_status));
    g_object_set_data(G_OBJECT(row_widget), "wc-depth", GUINT_TO_POINTER(depth < 0 ? 0u : (uint32_t)depth));
    if (text != NULL)
        g_object_set_data_full(G_OBJECT(row_widget), "wc-row-name", g_strdup(text), g_free);
    if (face_persistent_id != 0) {
        face_copy = g_new(uint64_t, 1);
        *face_copy = face_persistent_id;
        g_object_set_data_full(G_OBJECT(row_widget), "wc-face-id", face_copy, g_free);
    }
    if (csys_plane != NULL && csys_plane[0] != '\0')
        g_object_set_data_full(G_OBJECT(row_widget), "wc-csys-plane", g_strdup(csys_plane), g_free);
    if (real_feature)
        configure_feature_drag(state, row_widget, feature_id);
    gtk_list_box_append(GTK_LIST_BOX(state->model_list), row_widget);
    return row_widget;
}

static void refresh_model_navigator(WcGtk4State *state)
{
    WcGtk4FeatureRow rows[WC_FEATURE_ROW_CAPACITY];
    WcGtk4PlanarFaceRow faces[WC_FACE_ROW_CAPACITY];
    WcGtk4ModelSnapshot snapshot;
    size_t count = 0, face_count = 0;
    size_t i, f;
    GtkListBoxRow *selected_row = NULL;
    if (state == NULL || state->model_list == NULL)
        return;

    get_snapshot(state, &snapshot);
    gtk_label_set_text(GTK_LABEL(state->model_name_label),
                       snapshot.model_name != NULL ? snapshot.model_name : "untitled");
    gtk_widget_set_tooltip_text(state->model_name_label,
                                snapshot.model_name != NULL ? snapshot.model_name : "untitled");
    gtk_label_set_text(GTK_LABEL(state->assembly_name_label),
                       snapshot.model_name != NULL ? snapshot.model_name : "untitled");

    clear_children(state->model_list);
    if (state->callbacks != NULL && state->callbacks->feature_rows != NULL)
        count = state->callbacks->feature_rows(state->user_data, rows, WC_FEATURE_ROW_CAPACITY);
    if (count > WC_FEATURE_ROW_CAPACITY) count = WC_FEATURE_ROW_CAPACITY;
    if (state->callbacks != NULL && state->callbacks->planar_face_rows != NULL)
        face_count = state->callbacks->planar_face_rows(state->user_data, faces, WC_FACE_ROW_CAPACITY);
    if (face_count > WC_FACE_ROW_CAPACITY) face_count = WC_FACE_ROW_CAPACITY;

    if (count == 0) {
        gtk_list_box_append(GTK_LIST_BOX(state->model_list), make_label("Model History", "wc-subtle"));
        state->selected_feature_id = 0;
        return;
    }

    for (i = 0; i < count; ++i) {
        char text[256];
        GtkWidget *row_widget;
        (void)snprintf(text, sizeof(text), "%s%s%s",
                       rows[i].name != NULL ? rows[i].name : "feature",
                       rows[i].dirty ? "  •" : "",
                       rows[i].kind == WC_FEATURE_KIND_DATUM_CSYS ? "  [CSYS]" : "");
        row_widget = append_model_tree_row(state, text, rows[i].id, rows[i].kind,
                                           rows[i].exact_status, (int)rows[i].dependency_depth,
                                           rows[i].kind == WC_FEATURE_KIND_DATUM_PLANE ? WC_GTK4_SKETCH_SUPPORT_DATUM_PLANE : WC_GTK4_SKETCH_SUPPORT_NONE,
                                           rows[i].kind == WC_FEATURE_KIND_DATUM_PLANE ? rows[i].id : 0u,
                                           0, NULL, 1);
        if (rows[i].id == state->selected_feature_id && state->selected_row_is_feature)
            selected_row = GTK_LIST_BOX_ROW(row_widget);

        if (rows[i].kind == WC_FEATURE_KIND_DATUM_CSYS) {
            static const char *planes[] = { "XY", "YZ", "XZ" };
            size_t pi;
            for (pi = 0; pi < 3; ++pi) {
                char plane_text[64];
                (void)snprintf(plane_text, sizeof(plane_text), "%s Plane", planes[pi]);
                append_model_tree_row(state, plane_text, rows[i].id, rows[i].kind, 0u,
                                      (int)rows[i].dependency_depth + 1,
                                      WC_GTK4_SKETCH_SUPPORT_CSYS_PLANE, rows[i].id, 0, planes[pi], 0);
            }
        }

        for (f = 0; f < face_count; ++f) {
            if (faces[f].owner_feature_id == rows[i].id) {
                char face_text[96];
                (void)snprintf(face_text, sizeof(face_text), "Face %u  (planar)", faces[f].semantic_slot);
                append_model_tree_row(state, face_text, rows[i].id, rows[i].kind, 0u,
                                      (int)rows[i].dependency_depth + 1,
                                      WC_GTK4_SKETCH_SUPPORT_PLANAR_FACE, rows[i].id,
                                      faces[f].persistent_id, NULL, 0);
            }
        }
    }
    if (selected_row != NULL)
        gtk_list_box_select_row(GTK_LIST_BOX(state->model_list), selected_row);
    update_navigator_descendant_highlight(state);
}

static void update_navigator_descendant_highlight(WcGtk4State *state)
{
    GtkWidget *row;
    if (state == NULL || state->model_list == NULL)
        return;
    row = gtk_widget_get_first_child(state->model_list);
    while (row != NULL) {
        uint32_t owner = GPOINTER_TO_UINT(g_object_get_data(G_OBJECT(row), "wc-support-feature-id"));
        int real = GPOINTER_TO_INT(g_object_get_data(G_OBJECT(row), "wc-real-feature"));
        gtk_widget_remove_css_class(row, "wc-tree-descendant-selected");
        if (!real && state->selected_body_feature_id != 0 && owner == state->selected_body_feature_id)
            gtk_widget_add_css_class(row, "wc-tree-descendant-selected");
        row = gtk_widget_get_next_sibling(row);
    }
}

static GtkListBoxRow *model_row_for_feature(WcGtk4State *state, uint32_t feature_id)
{
    GtkWidget *row;
    if (state == NULL || state->model_list == NULL || feature_id == 0)
        return NULL;
    row = gtk_widget_get_first_child(state->model_list);
    while (row != NULL) {
        if (GPOINTER_TO_INT(g_object_get_data(G_OBJECT(row), "wc-real-feature")) &&
            GPOINTER_TO_UINT(g_object_get_data(G_OBJECT(row), "wc-feature-id")) == feature_id)
            return GTK_LIST_BOX_ROW(row);
        row = gtk_widget_get_next_sibling(row);
    }
    return NULL;
}

static int feature_name_for_id(WcGtk4State *state, uint32_t feature_id,
                               char *output, size_t capacity)
{
    WcGtk4FeatureRow rows[WC_FEATURE_ROW_CAPACITY];
    size_t count, i;
    if (output == NULL || capacity == 0)
        return 0;
    output[0] = '\0';
    if (state == NULL || feature_id == 0 || state->callbacks == NULL ||
        state->callbacks->feature_rows == NULL)
        return 0;
    count = state->callbacks->feature_rows(state->user_data, rows, WC_FEATURE_ROW_CAPACITY);
    if (count > WC_FEATURE_ROW_CAPACITY) count = WC_FEATURE_ROW_CAPACITY;
    for (i = 0; i < count; ++i) {
        if (rows[i].id == feature_id && rows[i].name != NULL) {
            copy_text(output, capacity, rows[i].name);
            return 1;
        }
    }
    return 0;
}

static void select_model_feature(WcGtk4State *state, uint32_t feature_id, int select_body)
{
    GtkListBoxRow *row;
    if (state == NULL || feature_id == 0)
        return;
    state->selected_feature_id = feature_id;
    state->selected_row_is_feature = 1;
    state->selected_body_feature_id = select_body ? feature_id : 0;
    row = model_row_for_feature(state, feature_id);
    if (row != NULL)
        gtk_list_box_select_row(GTK_LIST_BOX(state->model_list), row);
    update_navigator_descendant_highlight(state);
}

static void update_ai_summary(WcGtk4State *state)
{
    WcGtk4ModelSnapshot snapshot;
    char text[512];
    if (state == NULL || state->ai_summary_label == NULL)
        return;
    get_snapshot(state, &snapshot);
    (void)snprintf(text, sizeof(text),
                   "Read-only model context\n\nModel: %s\nFeatures: %u\nExact: %u\nPreview: %u\nFailed: %u\n\n"
                   "The provider-neutral AI ABI exists, but no external provider is connected in this GTK4 bootstrap.",
                   snapshot.model_name != NULL ? snapshot.model_name : "untitled",
                   snapshot.feature_count, snapshot.exact_count,
                   snapshot.preview_count, snapshot.failed_count);
    gtk_label_set_text(GTK_LABEL(state->ai_summary_label), text);
}

static void update_status(WcGtk4State *state)
{
    WcGtk4ModelSnapshot snapshot;
    char text[256];
    const char *section = "modelling";
    if (state == NULL)
        return;
    get_snapshot(state, &snapshot);
    if (state->callbacks != NULL && state->callbacks->active_section != NULL) {
        const char *active = state->callbacks->active_section(state->user_data);
        if (active != NULL && active[0] != '\0')
            section = active;
    }
    (void)snprintf(text, sizeof(text), "Section: %s", section);
    gtk_label_set_text(GTK_LABEL(state->section_status), text);
    (void)snprintf(text, sizeof(text), "Features %u   Exact %u   Preview %u   Failed %u",
                   snapshot.feature_count, snapshot.exact_count,
                   snapshot.preview_count, snapshot.failed_count);
    gtk_label_set_text(GTK_LABEL(state->model_status), text);
    refresh_model_navigator(state);
    update_ai_summary(state);
}

static gboolean deferred_update_status_cb(gpointer user_data)
{
    WcGtk4State *state = (WcGtk4State *)user_data;
    if (state != NULL)
        update_status(state);
    return G_SOURCE_REMOVE;
}

static WcProjectedPoint project_point(WcGtk4State *state, double x, double y, double z)
{
    double cy = cos(state->yaw);
    double sy = sin(state->yaw);
    double cp = cos(state->pitch);
    double sp = sin(state->pitch);
    double x1 = cy * x - sy * y;
    double y1 = sy * x + cy * y;
    double z1 = z;
    WcProjectedPoint result;
    (void)(cp * y1 - sp * z1); /* depth is not yet used by the Cairo bounds renderer */
    result.x = x1;
    result.y = -(sp * y1 + cp * z1);
    return result;
}

typedef struct WcViewTransform {
    double model_cx, model_cy, model_cz;
    double scale, centre_x, centre_y;
    int valid;
} WcViewTransform;

static WcViewTransform make_view_transform(WcGtk4State *state, int width, int height,
                                           const WcGtk4ModelSnapshot *snapshot)
{
    WcViewTransform transform;
    double xs[2], ys[2], zs[2];
    double dx, dy, dz, diagonal;
    memset(&transform, 0, sizeof(transform));
    if (state == NULL || snapshot == NULL || (!snapshot->bounds_valid && !state->fit_bounds_valid))
        return transform;
    if (state->fit_bounds_valid) {
        xs[0] = state->fit_min_x; xs[1] = state->fit_max_x;
        ys[0] = state->fit_min_y; ys[1] = state->fit_max_y;
        zs[0] = state->fit_min_z; zs[1] = state->fit_max_z;
    } else {
        xs[0] = snapshot->min_x; xs[1] = snapshot->max_x;
        ys[0] = snapshot->min_y; ys[1] = snapshot->max_y;
        zs[0] = snapshot->min_z; zs[1] = snapshot->max_z;
    }
    dx = xs[1] - xs[0];
    dy = ys[1] - ys[0];
    dz = zs[1] - zs[0];
    diagonal = sqrt(dx * dx + dy * dy + dz * dz);
    if (diagonal < 1e-9)
        diagonal = 100.0;

    /* Orbit is always about the absolute model origin.  The old transform
       subtracted the current model-bounds centre and re-fit the projected
       extents for every yaw/pitch update.  That made middle-drag orbit around
       the model centre and visibly changed scale while rotating.  Keep 0,0,0
       fixed at the viewport pan origin and use an orientation-invariant 3D
       diagonal for scale so rotation itself can never zoom the model. */
    transform.model_cx = 0.0;
    transform.model_cy = 0.0;
    transform.model_cz = 0.0;
    transform.scale = fmin((double)width, (double)height) * 0.60 / diagonal * state->zoom;
    transform.centre_x = width * 0.5 + state->pan_x;
    transform.centre_y = height * 0.5 + state->pan_y;
    transform.valid = 1;
    return transform;
}

static WcViewTransform make_empty_csys_transform(WcGtk4State *state, int width, int height)
{
    WcViewTransform transform;
    memset(&transform, 0, sizeof(transform));
    if (state == NULL) return transform;
    transform.model_cx = 0.0;
    transform.model_cy = 0.0;
    transform.model_cz = 0.0;
    transform.scale = fmin((double)width, (double)height) * 0.60 / 100.0 * state->zoom;
    transform.centre_x = width * 0.5 + state->pan_x;
    transform.centre_y = height * 0.5 + state->pan_y;
    transform.valid = 1;
    return transform;
}

static void model_to_screen(WcGtk4State *state, const WcViewTransform *transform,
                            double x, double y, double z, double *sx, double *sy)
{
    WcProjectedPoint p = project_point(state, x - transform->model_cx,
                                       y - transform->model_cy, z - transform->model_cz);
    *sx = transform->centre_x + p.x * transform->scale;
    *sy = transform->centre_y + p.y * transform->scale;
}

static int point_in_polygon(const double *xy, uint32_t count, double x, double y)
{
    uint32_t i, j;
    int inside = 0;
    if (xy == NULL || count < 3) return 0;
    for (i = 0, j = count - 1; i < count; j = i++) {
        double xi = xy[i * 2], yi = xy[i * 2 + 1];
        double xj = xy[j * 2], yj = xy[j * 2 + 1];
        if (((yi > y) != (yj > y)) &&
            (x < (xj - xi) * (y - yi) / ((yj - yi) == 0.0 ? 1e-12 : (yj - yi)) + xi))
            inside = !inside;
    }
    return inside;
}

static uint64_t hit_test_planar_face(WcGtk4State *state, int width, int height,
                                     double x, double y, uint32_t *owner_id)
{
    WcGtk4PlanarFaceRow faces[WC_FACE_ROW_CAPACITY];
    WcGtk4ModelSnapshot snapshot;
    WcViewTransform transform;
    size_t count = 0, i;
    uint64_t hit = 0;
    if (owner_id != NULL) *owner_id = 0;
    if (state == NULL || state->callbacks == NULL || state->callbacks->planar_face_rows == NULL)
        return 0;
    get_snapshot(state, &snapshot);
    transform = make_view_transform(state, width, height, &snapshot);
    if (!transform.valid) return 0;
    count = state->callbacks->planar_face_rows(state->user_data, faces, WC_FACE_ROW_CAPACITY);
    if (count > WC_FACE_ROW_CAPACITY) count = WC_FACE_ROW_CAPACITY;
    for (i = 0; i < count; ++i) {
        double xy[WC_GTK4_FACE_MAX_POINTS * 2u];
        uint32_t p;
        if (faces[i].point_count < 3 || faces[i].point_count > WC_GTK4_FACE_MAX_POINTS) continue;
        for (p = 0; p < faces[i].point_count; ++p)
            model_to_screen(state, &transform,
                faces[i].points[p * 3], faces[i].points[p * 3 + 1], faces[i].points[p * 3 + 2],
                &xy[p * 2], &xy[p * 2 + 1]);
        if (point_in_polygon(xy, faces[i].point_count, x, y)) {
            hit = faces[i].persistent_id;
            if (owner_id != NULL) *owner_id = faces[i].owner_feature_id;
        }
    }
    return hit;
}

static int hit_test_csys_plane(WcGtk4State *state, int width, int height, double x, double y,
                               uint32_t *feature_id, char *plane, size_t plane_capacity)
{
    WcGtk4CsysRow rows[WC_CSYS_ROW_CAPACITY];
    WcGtk4ModelSnapshot snapshot;
    WcViewTransform transform;
    size_t count = 0, i;
    double dx = 0.0, dy = 0.0, dz = 0.0, diagonal = 0.0, side_size = 20.0 * 0.62;
    static const char *names[3] = {"XY", "YZ", "XZ"};
    static const double quadrant[4][2] = {{0,0},{1,0},{1,1},{0,1}};
    if (feature_id != NULL) *feature_id = 0;
    if (plane != NULL && plane_capacity != 0) plane[0] = '\0';
    if (state == NULL || state->callbacks == NULL || state->callbacks->csys_rows == NULL)
        return 0;
    count = state->callbacks->csys_rows(state->user_data, rows, WC_CSYS_ROW_CAPACITY);
    if (count > WC_CSYS_ROW_CAPACITY) count = WC_CSYS_ROW_CAPACITY;
    if (count == 0) return 0;

    get_snapshot(state, &snapshot);
    transform = make_view_transform(state, width, height, &snapshot);
    if (snapshot.bounds_valid || state->fit_bounds_valid) {
        if (state->fit_bounds_valid) {
            dx = state->fit_max_x - state->fit_min_x;
            dy = state->fit_max_y - state->fit_min_y;
            dz = state->fit_max_z - state->fit_min_z;
        } else {
            dx = snapshot.max_x - snapshot.min_x;
            dy = snapshot.max_y - snapshot.min_y;
            dz = snapshot.max_z - snapshot.min_z;
        }
        diagonal = sqrt(dx * dx + dy * dy + dz * dz);
        side_size = (diagonal > 1e-6 ? clamp_double(diagonal * 0.18, 5.0, 100.0) : 20.0) * 0.62;
    } else {
        transform = make_empty_csys_transform(state, width, height);
        side_size = 12.0 * 0.62;
    }

    for (i = 0; i < count; ++i) {
        int pi;
        for (pi = 0; pi < 3; ++pi) {
            const double *a = pi == 0 ? rows[i].x_axis : (pi == 1 ? rows[i].y_axis : rows[i].x_axis);
            const double *b = pi == 0 ? rows[i].y_axis : rows[i].z_axis;
            double polygon[8];
            int corner;
            for (corner = 0; corner < 4; ++corner) {
                {
                    double wx = rows[i].origin[0] + a[0] * side_size * quadrant[corner][0] + b[0] * side_size * quadrant[corner][1];
                    double wy = rows[i].origin[1] + a[1] * side_size * quadrant[corner][0] + b[1] * side_size * quadrant[corner][1];
                    double wz = rows[i].origin[2] + a[2] * side_size * quadrant[corner][0] + b[2] * side_size * quadrant[corner][1];
                    model_to_screen(state, &transform, wx, wy, wz, &polygon[corner * 2], &polygon[corner * 2 + 1]);
                }
            }
            if (point_in_polygon(polygon, 4, x, y)) {
                if (feature_id != NULL) *feature_id = rows[i].feature_id;
                if (plane != NULL && plane_capacity != 0)
                    (void)snprintf(plane, plane_capacity, "%s", names[pi]);
                return 1;
            }
        }
    }
    return 0;
}

static int body_bounds_for_feature(WcGtk4State *state, uint32_t feature_id, WcGtk4BodyRow *result)
{
    WcGtk4BodyRow bodies[WC_BODY_ROW_CAPACITY];
    size_t count = 0, i;
    if (result != NULL) memset(result, 0, sizeof(*result));
    if (state == NULL || feature_id == 0 || state->callbacks == NULL || state->callbacks->body_rows == NULL)
        return 0;
    count = state->callbacks->body_rows(state->user_data, bodies, WC_BODY_ROW_CAPACITY);
    if (count > WC_BODY_ROW_CAPACITY) count = WC_BODY_ROW_CAPACITY;
    for (i = 0; i < count; ++i) {
        if (bodies[i].feature_id == feature_id) {
            if (result != NULL) *result = bodies[i];
            return 1;
        }
    }
    return 0;
}

static int projected_body_contains(WcGtk4State *state, const WcViewTransform *transform,
                                   const WcGtk4BodyRow *body, double x, double y)
{
    double xs[2], ys[2], zs[2], screen[8][2], polygon[8];
    int i, face;
    static const int faces[6][4] = {
        {0,1,3,2}, {4,6,7,5}, {0,4,5,1},
        {2,3,7,6}, {0,2,6,4}, {1,5,7,3}
    };
    if (state == NULL || transform == NULL || body == NULL || !transform->valid)
        return 0;
    xs[0] = body->min_x; xs[1] = body->max_x;
    ys[0] = body->min_y; ys[1] = body->max_y;
    zs[0] = body->min_z; zs[1] = body->max_z;
    for (i = 0; i < 8; ++i)
        model_to_screen(state, transform,
                        xs[(i & 1) != 0], ys[(i & 2) != 0], zs[(i & 4) != 0],
                        &screen[i][0], &screen[i][1]);
    for (face = 0; face < 6; ++face) {
        for (i = 0; i < 4; ++i) {
            polygon[i * 2] = screen[faces[face][i]][0];
            polygon[i * 2 + 1] = screen[faces[face][i]][1];
        }
        if (point_in_polygon(polygon, 4, x, y))
            return 1;
    }
    return 0;
}

static uint32_t hit_test_body(WcGtk4State *state, int width, int height, double x, double y)
{
    WcGtk4BodyRow bodies[WC_BODY_ROW_CAPACITY];
    WcGtk4ModelSnapshot snapshot;
    WcViewTransform transform;
    size_t count = 0, i;
    uint32_t hit = 0;
    double best_area = 0.0;
    if (state == NULL || state->callbacks == NULL || state->callbacks->body_rows == NULL)
        return 0;
    get_snapshot(state, &snapshot);
    transform = make_view_transform(state, width, height, &snapshot);
    if (!transform.valid) return 0;
    count = state->callbacks->body_rows(state->user_data, bodies, WC_BODY_ROW_CAPACITY);
    if (count > WC_BODY_ROW_CAPACITY) count = WC_BODY_ROW_CAPACITY;
    for (i = 0; i < count; ++i) {
        if (projected_body_contains(state, &transform, &bodies[i], x, y)) {
            double dx = bodies[i].max_x - bodies[i].min_x;
            double dy = bodies[i].max_y - bodies[i].min_y;
            double dz = bodies[i].max_z - bodies[i].min_z;
            double area = fabs(dx * dy) + fabs(dx * dz) + fabs(dy * dz);
            if (hit == 0 || area < best_area) {
                hit = bodies[i].feature_id;
                best_area = area;
            }
        }
    }
    return hit;
}

static void fit_all(WcGtk4State *state)
{
    if (state == NULL) return;
    state->fit_bounds_valid = 0;
    state->zoom = 1.0;
    state->pan_x = 0.0;
    state->pan_y = 0.0;
    gtk_widget_queue_draw(state->drawing_area);
}

static int fit_feature(WcGtk4State *state, uint32_t feature_id)
{
    WcGtk4BodyRow body;
    if (state == NULL || !body_bounds_for_feature(state, feature_id, &body))
        return 0;
    state->fit_bounds_valid = 1;
    state->fit_min_x = body.min_x;
    state->fit_min_y = body.min_y;
    state->fit_min_z = body.min_z;
    state->fit_max_x = body.max_x;
    state->fit_max_y = body.max_y;
    state->fit_max_z = body.max_z;
    state->zoom = 1.0;
    state->pan_x = 0.0;
    state->pan_y = 0.0;
    gtk_widget_queue_draw(state->drawing_area);
    return 1;
}

static void draw_planar_face_selection(cairo_t *cr, int width, int height, WcGtk4State *state)
{
    WcGtk4PlanarFaceRow faces[WC_FACE_ROW_CAPACITY];
    WcGtk4ModelSnapshot snapshot;
    WcViewTransform transform;
    size_t count = 0, i;
    if (state == NULL || state->callbacks == NULL || state->callbacks->planar_face_rows == NULL)
        return;
    get_snapshot(state, &snapshot);
    transform = make_view_transform(state, width, height, &snapshot);
    if (!transform.valid) return;
    count = state->callbacks->planar_face_rows(state->user_data, faces, WC_FACE_ROW_CAPACITY);
    if (count > WC_FACE_ROW_CAPACITY) count = WC_FACE_ROW_CAPACITY;
    for (i = 0; i < count; ++i) {
        uint32_t p;
        int highlight = faces[i].persistent_id == state->hover_face_persistent_id ||
                        (state->selected_body_feature_id != 0 &&
                         faces[i].owner_feature_id == state->selected_body_feature_id) ||
                        (state->selected_support_kind == WC_GTK4_SKETCH_SUPPORT_PLANAR_FACE &&
                         faces[i].persistent_id == state->selected_face_persistent_id);
        if (!highlight || faces[i].point_count < 3) continue;
        for (p = 0; p < faces[i].point_count; ++p) {
            double sx, sy;
            model_to_screen(state, &transform,
                faces[i].points[p * 3], faces[i].points[p * 3 + 1], faces[i].points[p * 3 + 2], &sx, &sy);
            if (p == 0) cairo_move_to(cr, sx, sy); else cairo_line_to(cr, sx, sy);
        }
        cairo_close_path(cr);
        set_source_rgba(cr, 0.98, 0.48, 0.82, 0.24);
        cairo_fill_preserve(cr);
        cairo_set_line_width(cr, 2.2);
        set_source_rgba(cr, 1.0, 0.72, 0.93, 0.95);
        cairo_stroke(cr);
    }
}

static void draw_selected_body_bounds(cairo_t *cr, int width, int height, WcGtk4State *state)
{
    WcGtk4BodyRow body;
    WcGtk4ModelSnapshot snapshot;
    WcViewTransform transform;
    double xs[2], ys[2], zs[2], screen[8][2];
    int i;
    static const int edges[12][2] = {
        {0,1},{0,2},{0,4},{1,3},{1,5},{2,3},
        {2,6},{3,7},{4,5},{4,6},{5,7},{6,7}
    };
    if (state == NULL || state->selected_body_feature_id == 0 ||
        !body_bounds_for_feature(state, state->selected_body_feature_id, &body))
        return;
    get_snapshot(state, &snapshot);
    transform = make_view_transform(state, width, height, &snapshot);
    if (!transform.valid) return;
    xs[0] = body.min_x; xs[1] = body.max_x;
    ys[0] = body.min_y; ys[1] = body.max_y;
    zs[0] = body.min_z; zs[1] = body.max_z;
    for (i = 0; i < 8; ++i)
        model_to_screen(state, &transform,
                        xs[(i & 1) != 0], ys[(i & 2) != 0], zs[(i & 4) != 0],
                        &screen[i][0], &screen[i][1]);
    cairo_set_line_width(cr, 3.0);
    set_source_rgba(cr, 1.0, 0.52, 0.86, 0.98);
    for (i = 0; i < 12; ++i) {
        cairo_move_to(cr, screen[edges[i][0]][0], screen[edges[i][0]][1]);
        cairo_line_to(cr, screen[edges[i][1]][0], screen[edges[i][1]][1]);
    }
    cairo_stroke(cr);
}

static void viewport_model_origin_screen(WcGtk4State *state, int width, int height,
                                         double *origin_x, double *origin_y)
{
    WcGtk4ModelSnapshot snapshot;
    WcViewTransform transform;
    if (origin_x == NULL || origin_y == NULL) return;
    *origin_x = width * 0.5 + (state != NULL ? state->pan_x : 0.0);
    *origin_y = height * 0.5 + (state != NULL ? state->pan_y : 0.0);
    if (state == NULL) return;
    get_snapshot(state, &snapshot);
    transform = make_view_transform(state, width, height, &snapshot);
    if (transform.valid)
        model_to_screen(state, &transform, 0.0, 0.0, 0.0, origin_x, origin_y);
}

static void draw_grid(cairo_t *cr, int width, int height, WcGtk4State *state)
{
    int x;
    int y;
    const int step = 32;
    double model_origin_x, model_origin_y;
    int grid_origin_x, grid_origin_y;

    /* The viewport cross is the absolute model origin, not merely the screen
       centre.  Derive it through the same transform used by the rendered CSYS
       so the cross and absolute (0,0,0) stay coincident after pan/fit/zoom and
       as the camera implementation evolves. */
    viewport_model_origin_screen(state, width, height, &model_origin_x, &model_origin_y);
    grid_origin_x = (int)floor(model_origin_x);
    grid_origin_y = (int)floor(model_origin_y);

    cairo_set_line_width(cr, 1.0);
    set_source_rgba(cr, 0.24, 0.19, 0.34, 0.30);
    for (x = grid_origin_x; x > 0; x -= step) {
        cairo_move_to(cr, x + 0.5, 0.0);
        cairo_line_to(cr, x + 0.5, height);
    }
    for (x = grid_origin_x + step; x < width; x += step) {
        cairo_move_to(cr, x + 0.5, 0.0);
        cairo_line_to(cr, x + 0.5, height);
    }
    for (y = grid_origin_y; y > 0; y -= step) {
        cairo_move_to(cr, 0.0, y + 0.5);
        cairo_line_to(cr, width, y + 0.5);
    }
    for (y = grid_origin_y + step; y < height; y += step) {
        cairo_move_to(cr, 0.0, y + 0.5);
        cairo_line_to(cr, width, y + 0.5);
    }
    cairo_stroke(cr);

    cairo_set_line_width(cr, 1.4);
    set_source_rgba(cr, 0.93, 0.28, 0.66, 0.64);
    cairo_move_to(cr, 0.0, model_origin_y);
    cairo_line_to(cr, width, model_origin_y);
    cairo_stroke(cr);
    set_source_rgba(cr, 0.45, 0.68, 1.0, 0.64);
    cairo_move_to(cr, model_origin_x, 0.0);
    cairo_line_to(cr, model_origin_x, height);
    cairo_stroke(cr);
}

static void draw_body_bounds(cairo_t *cr, int width, int height,
                             WcGtk4State *state, const WcGtk4ModelSnapshot *snapshot)
{
    WcGtk4BodyRow bodies[WC_BODY_ROW_CAPACITY];
    WcViewTransform transform;
    size_t count = 0, body_index;
    static const int faces[3][4] = {
        { 4, 5, 7, 6 },
        { 0, 2, 6, 4 },
        { 1, 5, 7, 3 }
    };
    static const int edges[12][2] = {
        {0,1},{0,2},{0,4},{1,3},{1,5},{2,3},
        {2,6},{3,7},{4,5},{4,6},{5,7},{6,7}
    };
    if (state == NULL || snapshot == NULL || state->callbacks == NULL ||
        state->callbacks->body_rows == NULL)
        return;
    transform = make_view_transform(state, width, height, snapshot);
    if (!transform.valid) return;
    count = state->callbacks->body_rows(state->user_data, bodies, WC_BODY_ROW_CAPACITY);
    if (count > WC_BODY_ROW_CAPACITY) count = WC_BODY_ROW_CAPACITY;
    for (body_index = 0; body_index < count; ++body_index) {
        double xs[2], ys[2], zs[2], screen[8][2];
        int i;
        xs[0] = bodies[body_index].min_x; xs[1] = bodies[body_index].max_x;
        ys[0] = bodies[body_index].min_y; ys[1] = bodies[body_index].max_y;
        zs[0] = bodies[body_index].min_z; zs[1] = bodies[body_index].max_z;
        for (i = 0; i < 8; ++i)
            model_to_screen(state, &transform,
                            xs[(i & 1) != 0], ys[(i & 2) != 0], zs[(i & 4) != 0],
                            &screen[i][0], &screen[i][1]);
        set_source_rgba(cr, 0.56, 0.28, 0.82, 0.12);
        cairo_move_to(cr, screen[faces[0][0]][0], screen[faces[0][0]][1]);
        for (i = 1; i < 4; ++i) cairo_line_to(cr, screen[faces[0][i]][0], screen[faces[0][i]][1]);
        cairo_close_path(cr); cairo_fill(cr);
        set_source_rgba(cr, 0.96, 0.30, 0.68, 0.10);
        cairo_move_to(cr, screen[faces[1][0]][0], screen[faces[1][0]][1]);
        for (i = 1; i < 4; ++i) cairo_line_to(cr, screen[faces[1][i]][0], screen[faces[1][i]][1]);
        cairo_close_path(cr); cairo_fill(cr);
        set_source_rgba(cr, 0.30, 0.58, 0.96, 0.08);
        cairo_move_to(cr, screen[faces[2][0]][0], screen[faces[2][0]][1]);
        for (i = 1; i < 4; ++i) cairo_line_to(cr, screen[faces[2][i]][0], screen[faces[2][i]][1]);
        cairo_close_path(cr); cairo_fill(cr);
        cairo_set_line_width(cr, 1.8);
        set_source_rgba(cr, 0.96, 0.72, 0.92, 0.88);
        for (i = 0; i < 12; ++i) {
            cairo_move_to(cr, screen[edges[i][0]][0], screen[edges[i][0]][1]);
            cairo_line_to(cr, screen[edges[i][1]][0], screen[edges[i][1]][1]);
        }
        cairo_stroke(cr);
    }
}

static void sketch_world_point(const WcGtk4SketchGeometryRow *row, double u, double v,
                               double *x, double *y, double *z)
{
    if (row == NULL || x == NULL || y == NULL || z == NULL) return;
    *x = row->frame_origin[0] + row->frame_x_axis[0] * u + row->frame_y_axis[0] * v;
    *y = row->frame_origin[1] + row->frame_x_axis[1] * u + row->frame_y_axis[1] * v;
    *z = row->frame_origin[2] + row->frame_x_axis[2] * u + row->frame_y_axis[2] * v;
}

static void sketch_world_segment(cairo_t *cr, WcGtk4State *state, const WcViewTransform *transform,
                                 const WcGtk4SketchGeometryRow *row,
                                 double u1, double v1, double u2, double v2)
{
    double x1, y1, z1, x2, y2, z2, sx1, sy1, sx2, sy2;
    sketch_world_point(row, u1, v1, &x1, &y1, &z1);
    sketch_world_point(row, u2, v2, &x2, &y2, &z2);
    model_to_screen(state, transform, x1, y1, z1, &sx1, &sy1);
    model_to_screen(state, transform, x2, y2, z2, &sx2, &sy2);
    cairo_move_to(cr, sx1, sy1);
    cairo_line_to(cr, sx2, sy2);
}

static void draw_all_sketches_3d(cairo_t *cr, int width, int height,
                                 WcGtk4State *state, const WcGtk4ModelSnapshot *snapshot)
{
    WcGtk4FeatureRow features[WC_FEATURE_ROW_CAPACITY];
    WcGtk4SketchGeometryRow geometry[WC_FEATURE_ROW_CAPACITY];
    WcViewTransform transform;
    size_t feature_count = 0, fi;
    if (state == NULL || snapshot == NULL || state->callbacks == NULL ||
        state->callbacks->feature_rows == NULL || state->callbacks->sketch_geometry_rows == NULL)
        return;
    transform = make_view_transform(state, width, height, snapshot);
    if (!transform.valid) return;
    feature_count = state->callbacks->feature_rows(state->user_data, features, WC_FEATURE_ROW_CAPACITY);
    if (feature_count > WC_FEATURE_ROW_CAPACITY) feature_count = WC_FEATURE_ROW_CAPACITY;
    cairo_set_line_width(cr, 2.0);
    set_source_rgba(cr, 0.98, 0.70, 0.91, 0.94);
    for (fi = 0; fi < feature_count; ++fi) {
        size_t count, gi;
        if (features[fi].kind != WC_FEATURE_KIND_SKETCH) continue;
        count = state->callbacks->sketch_geometry_rows(state->user_data, features[fi].id,
                                                        geometry, WC_FEATURE_ROW_CAPACITY);
        if (count > WC_FEATURE_ROW_CAPACITY) count = WC_FEATURE_ROW_CAPACITY;
        for (gi = 0; gi < count; ++gi) {
            WcGtk4SketchGeometryRow *row = &geometry[gi];
            if (!row->frame_valid) continue;
            if (row->kind == WC_FEATURE_KIND_SKETCH_LINE) {
                sketch_world_segment(cr, state, &transform, row,
                                     row->values[0], row->values[1], row->values[2], row->values[3]);
                cairo_stroke(cr);
            } else if (row->kind == WC_FEATURE_KIND_SKETCH_RECTANGLE) {
                double x = row->values[0], y = row->values[1], w = row->values[2], h = row->values[3];
                sketch_world_segment(cr, state, &transform, row, x, y, x + w, y); cairo_stroke(cr);
                sketch_world_segment(cr, state, &transform, row, x + w, y, x + w, y + h); cairo_stroke(cr);
                sketch_world_segment(cr, state, &transform, row, x + w, y + h, x, y + h); cairo_stroke(cr);
                sketch_world_segment(cr, state, &transform, row, x, y + h, x, y); cairo_stroke(cr);
            } else if (row->kind == WC_FEATURE_KIND_SKETCH_CIRCLE || row->kind == WC_FEATURE_KIND_SKETCH_ARC) {
                int segment;
                double start = 0.0, end = 2.0 * M_PI;
                double cx = row->values[0], cy = row->values[1], radius = fabs(row->values[2]);
                if (row->kind == WC_FEATURE_KIND_SKETCH_ARC) {
                    start = row->values[3] * M_PI / 180.0;
                    end = row->values[4] * M_PI / 180.0;
                    if (end < start) end += 2.0 * M_PI;
                }
                for (segment = 0; segment <= 64; ++segment) {
                    double t = start + (end - start) * ((double)segment / 64.0);
                    double wx, wy, wz, sx, sy;
                    sketch_world_point(row, cx + cos(t) * radius, cy + sin(t) * radius, &wx, &wy, &wz);
                    model_to_screen(state, &transform, wx, wy, wz, &sx, &sy);
                    if (segment == 0) cairo_move_to(cr, sx, sy); else cairo_line_to(cr, sx, sy);
                }
                cairo_stroke(cr);
            }
        }
    }
}

static double screen_segment_distance(double px, double py,
                                      double ax, double ay, double bx, double by)
{
    double dx = bx - ax;
    double dy = by - ay;
    double length2 = dx * dx + dy * dy;
    double t;
    if (length2 <= 1.0e-12)
        return hypot(px - ax, py - ay);
    t = ((px - ax) * dx + (py - ay) * dy) / length2;
    t = clamp_double(t, 0.0, 1.0);
    return hypot(px - (ax + dx * t), py - (ay + dy * t));
}

static uint32_t hit_test_sketch(WcGtk4State *state, int width, int height, double x, double y)
{
    WcGtk4FeatureRow features[WC_FEATURE_ROW_CAPACITY];
    WcGtk4SketchGeometryRow geometry[WC_FEATURE_ROW_CAPACITY];
    WcGtk4ModelSnapshot snapshot;
    WcViewTransform transform;
    size_t feature_count = 0, fi;
    uint32_t best_id = 0;
    double best_distance = 9.0;
    if (state == NULL || state->callbacks == NULL || state->callbacks->model_snapshot == NULL ||
        state->callbacks->feature_rows == NULL || state->callbacks->sketch_geometry_rows == NULL)
        return 0;
    memset(&snapshot, 0, sizeof(snapshot));
    state->callbacks->model_snapshot(state->user_data, &snapshot);
    transform = make_view_transform(state, width, height, &snapshot);
    if (!transform.valid)
        return 0;
    feature_count = state->callbacks->feature_rows(state->user_data, features, WC_FEATURE_ROW_CAPACITY);
    if (feature_count > WC_FEATURE_ROW_CAPACITY) feature_count = WC_FEATURE_ROW_CAPACITY;
    for (fi = 0; fi < feature_count; ++fi) {
        size_t count, gi;
        if (features[fi].kind != WC_FEATURE_KIND_SKETCH)
            continue;
        count = state->callbacks->sketch_geometry_rows(state->user_data, features[fi].id,
                                                        geometry, WC_FEATURE_ROW_CAPACITY);
        if (count > WC_FEATURE_ROW_CAPACITY) count = WC_FEATURE_ROW_CAPACITY;
        for (gi = 0; gi < count; ++gi) {
            WcGtk4SketchGeometryRow *row = &geometry[gi];
            double distance = 1.0e30;
            if (!row->frame_valid) continue;
            if (row->kind == WC_FEATURE_KIND_SKETCH_LINE) {
                double wx0, wy0, wz0, wx1, wy1, wz1, sx0, sy0, sx1, sy1;
                sketch_world_point(row, row->values[0], row->values[1], &wx0, &wy0, &wz0);
                sketch_world_point(row, row->values[2], row->values[3], &wx1, &wy1, &wz1);
                model_to_screen(state, &transform, wx0, wy0, wz0, &sx0, &sy0);
                model_to_screen(state, &transform, wx1, wy1, wz1, &sx1, &sy1);
                distance = screen_segment_distance(x, y, sx0, sy0, sx1, sy1);
            } else if (row->kind == WC_FEATURE_KIND_SKETCH_RECTANGLE) {
                static const int edges[4][2] = {{0,1},{1,2},{2,3},{3,0}};
                double px[4], py[4];
                double cx[4] = {row->values[0], row->values[0] + row->values[2],
                                row->values[0] + row->values[2], row->values[0]};
                double cy[4] = {row->values[1], row->values[1],
                                row->values[1] + row->values[3], row->values[1] + row->values[3]};
                int corner, edge;
                for (corner = 0; corner < 4; ++corner) {
                    double wx, wy, wz;
                    sketch_world_point(row, cx[corner], cy[corner], &wx, &wy, &wz);
                    model_to_screen(state, &transform, wx, wy, wz, &px[corner], &py[corner]);
                }
                for (edge = 0; edge < 4; ++edge) {
                    double candidate = screen_segment_distance(x, y,
                        px[edges[edge][0]], py[edges[edge][0]], px[edges[edge][1]], py[edges[edge][1]]);
                    if (candidate < distance) distance = candidate;
                }
            } else if (row->kind == WC_FEATURE_KIND_SKETCH_CIRCLE || row->kind == WC_FEATURE_KIND_SKETCH_ARC) {
                int segment;
                double start = 0.0, end = 2.0 * M_PI;
                double cx = row->values[0], cy = row->values[1], radius = fabs(row->values[2]);
                double previous_x = 0.0, previous_y = 0.0;
                if (row->kind == WC_FEATURE_KIND_SKETCH_ARC) {
                    start = row->values[3] * M_PI / 180.0;
                    end = row->values[4] * M_PI / 180.0;
                    if (end < start) end += 2.0 * M_PI;
                }
                for (segment = 0; segment <= 48; ++segment) {
                    double t = start + (end - start) * ((double)segment / 48.0);
                    double wx, wy, wz, sx, sy;
                    sketch_world_point(row, cx + cos(t) * radius, cy + sin(t) * radius, &wx, &wy, &wz);
                    model_to_screen(state, &transform, wx, wy, wz, &sx, &sy);
                    if (segment != 0) {
                        double candidate = screen_segment_distance(x, y, previous_x, previous_y, sx, sy);
                        if (candidate < distance) distance = candidate;
                    }
                    previous_x = sx; previous_y = sy;
                }
            }
            if (distance < best_distance) {
                best_distance = distance;
                best_id = features[fi].id;
            }
        }
    }
    return best_id;
}

static void draw_axis_triad(cairo_t *cr, int height, WcGtk4State *state)
{
    WcProjectedPoint origin = project_point(state, 0.0, 0.0, 0.0);
    WcProjectedPoint x_axis = project_point(state, 1.0, 0.0, 0.0);
    WcProjectedPoint y_axis = project_point(state, 0.0, 1.0, 0.0);
    WcProjectedPoint z_axis = project_point(state, 0.0, 0.0, 1.0);
    double ox = 54.0;
    double oy = height - 54.0;
    double length = 28.0;
    (void)origin;
    cairo_set_line_width(cr, 2.5);

    set_source_rgba(cr, 0.95, 0.36, 0.40, 0.95);
    cairo_move_to(cr, ox, oy); cairo_line_to(cr, ox + x_axis.x * length, oy + x_axis.y * length); cairo_stroke(cr);
    set_source_rgba(cr, 0.40, 0.88, 0.48, 0.95);
    cairo_move_to(cr, ox, oy); cairo_line_to(cr, ox + y_axis.x * length, oy + y_axis.y * length); cairo_stroke(cr);
    set_source_rgba(cr, 0.38, 0.66, 1.0, 0.95);
    cairo_move_to(cr, ox, oy); cairo_line_to(cr, ox + z_axis.x * length, oy + z_axis.y * length); cairo_stroke(cr);

    cairo_select_font_face(cr, "Sans", CAIRO_FONT_SLANT_NORMAL, CAIRO_FONT_WEIGHT_BOLD);
    cairo_set_font_size(cr, 11.0);
    set_source_rgba(cr, 0.95, 0.36, 0.40, 1.0); cairo_move_to(cr, ox + x_axis.x * length + 3, oy + x_axis.y * length); cairo_show_text(cr, "X");
    set_source_rgba(cr, 0.40, 0.88, 0.48, 1.0); cairo_move_to(cr, ox + y_axis.x * length + 3, oy + y_axis.y * length); cairo_show_text(cr, "Y");
    set_source_rgba(cr, 0.38, 0.66, 1.0, 1.0); cairo_move_to(cr, ox + z_axis.x * length + 3, oy + z_axis.y * length); cairo_show_text(cr, "Z");
}

static void draw_csys_plane(cairo_t *cr, WcGtk4State *state, const WcViewTransform *transform,
                            const WcGtk4CsysRow *row, const double *a, const double *b,
                            double side_size, double red, double green, double blue, double alpha)
{
    int corner;
    static const double quadrant[4][2] = {{0,0},{1,0},{1,1},{0,1}};
    if (cr == NULL || state == NULL || transform == NULL || row == NULL || a == NULL || b == NULL)
        return;
    for (corner = 0; corner < 4; ++corner) {
        double x = row->origin[0] + a[0] * side_size * quadrant[corner][0] + b[0] * side_size * quadrant[corner][1];
        double y = row->origin[1] + a[1] * side_size * quadrant[corner][0] + b[1] * side_size * quadrant[corner][1];
        double z = row->origin[2] + a[2] * side_size * quadrant[corner][0] + b[2] * side_size * quadrant[corner][1];
        double sx, sy;
        model_to_screen(state, transform, x, y, z, &sx, &sy);
        if (corner == 0) cairo_move_to(cr, sx, sy); else cairo_line_to(cr, sx, sy);
    }
    cairo_close_path(cr);
    set_source_rgba(cr, red, green, blue, alpha);
    cairo_fill_preserve(cr);
    cairo_set_line_width(cr, 1.0);
    set_source_rgba(cr, red, green, blue, alpha * 2.5 > 0.75 ? 0.75 : alpha * 2.5);
    cairo_stroke(cr);
}

static void draw_absolute_csys(cairo_t *cr, int width, int height,
                               WcGtk4State *state, const WcGtk4ModelSnapshot *snapshot)
{
    WcGtk4CsysRow rows[WC_CSYS_ROW_CAPACITY];
    size_t count = 0, i;
    WcViewTransform transform;
    double length = 12.0;
    double dx = 0.0, dy = 0.0, dz = 0.0, diagonal = 0.0;
    if (state == NULL || snapshot == NULL)
        return;

    if (state->callbacks != NULL && state->callbacks->csys_rows != NULL)
        count = state->callbacks->csys_rows(state->user_data, rows, WC_CSYS_ROW_CAPACITY);
    if (count > WC_CSYS_ROW_CAPACITY) count = WC_CSYS_ROW_CAPACITY;
    if (count == 0) {
        memset(&rows[0], 0, sizeof(rows[0]));
        rows[0].name = "absolute_csys";
        rows[0].x_axis[0] = 1.0;
        rows[0].y_axis[1] = 1.0;
        rows[0].z_axis[2] = 1.0;
        count = 1;
    }

    if (snapshot->bounds_valid || state->fit_bounds_valid) {
        if (state->fit_bounds_valid) {
            dx = state->fit_max_x - state->fit_min_x;
            dy = state->fit_max_y - state->fit_min_y;
            dz = state->fit_max_z - state->fit_min_z;
        } else {
            dx = snapshot->max_x - snapshot->min_x;
            dy = snapshot->max_y - snapshot->min_y;
            dz = snapshot->max_z - snapshot->min_z;
        }
        diagonal = sqrt(dx * dx + dy * dy + dz * dz);
        if (diagonal > 1e-6)
            length = clamp_double(diagonal * 0.18, 5.0, 100.0);
        transform = make_view_transform(state, width, height, snapshot);
    } else {
        /* An empty part still owns the absolute CSYS.  Give it a stable
           nominal model scale so its axes and three construction planes are
           visible and selectable before any other geometry exists. */
        transform = make_empty_csys_transform(state, width, height);
    }
    if (!transform.valid) return;

    for (i = 0; i < count; ++i) {
        double ox, oy, xx, xy, yx, yy, zx, zy;
        double x_end[3], y_end[3], z_end[3];
        double plane_side = length * 0.62;
        double plane_alpha = rows[i].feature_id == state->selected_feature_id ? 0.15 : 0.075;

        /* Each CSYS plane occupies only the positive quadrant bounded by its
           two positive axis rays: O->A, A->A+B, A+B->B, B->O.  Do not mirror
           the construction plane through the origin. */
        draw_csys_plane(cr, state, &transform, &rows[i], rows[i].x_axis, rows[i].y_axis,
                        plane_side, 0.95, 0.36, 0.68, plane_alpha);
        draw_csys_plane(cr, state, &transform, &rows[i], rows[i].y_axis, rows[i].z_axis,
                        plane_side, 0.40, 0.88, 0.60, plane_alpha);
        draw_csys_plane(cr, state, &transform, &rows[i], rows[i].x_axis, rows[i].z_axis,
                        plane_side, 0.38, 0.66, 1.00, plane_alpha);

        x_end[0] = rows[i].origin[0] + rows[i].x_axis[0] * length;
        x_end[1] = rows[i].origin[1] + rows[i].x_axis[1] * length;
        x_end[2] = rows[i].origin[2] + rows[i].x_axis[2] * length;
        y_end[0] = rows[i].origin[0] + rows[i].y_axis[0] * length;
        y_end[1] = rows[i].origin[1] + rows[i].y_axis[1] * length;
        y_end[2] = rows[i].origin[2] + rows[i].y_axis[2] * length;
        z_end[0] = rows[i].origin[0] + rows[i].z_axis[0] * length;
        z_end[1] = rows[i].origin[1] + rows[i].z_axis[1] * length;
        z_end[2] = rows[i].origin[2] + rows[i].z_axis[2] * length;
        model_to_screen(state, &transform, rows[i].origin[0], rows[i].origin[1], rows[i].origin[2], &ox, &oy);
        model_to_screen(state, &transform, x_end[0], x_end[1], x_end[2], &xx, &xy);
        model_to_screen(state, &transform, y_end[0], y_end[1], y_end[2], &yx, &yy);
        model_to_screen(state, &transform, z_end[0], z_end[1], z_end[2], &zx, &zy);

        cairo_set_line_width(cr, rows[i].feature_id == state->selected_feature_id ? 3.0 : 2.0);
        set_source_rgba(cr, 0.95, 0.36, 0.40, 0.96); cairo_move_to(cr, ox, oy); cairo_line_to(cr, xx, xy); cairo_stroke(cr);
        set_source_rgba(cr, 0.40, 0.88, 0.48, 0.96); cairo_move_to(cr, ox, oy); cairo_line_to(cr, yx, yy); cairo_stroke(cr);
        set_source_rgba(cr, 0.38, 0.66, 1.0, 0.96); cairo_move_to(cr, ox, oy); cairo_line_to(cr, zx, zy); cairo_stroke(cr);
        cairo_arc(cr, ox, oy, rows[i].feature_id == state->selected_feature_id ? 5.0 : 3.5, 0.0, M_PI * 2.0);
        set_source_rgba(cr, 0.96, 0.85, 0.95, 0.95); cairo_fill(cr);
        cairo_select_font_face(cr, "Sans", CAIRO_FONT_SLANT_NORMAL, CAIRO_FONT_WEIGHT_BOLD);
        cairo_set_font_size(cr, 9.0);
        set_source_rgba(cr, 0.95, 0.36, 0.40, 1.0); cairo_move_to(cr, xx + 3, xy); cairo_show_text(cr, "X");
        set_source_rgba(cr, 0.40, 0.88, 0.48, 1.0); cairo_move_to(cr, yx + 3, yy); cairo_show_text(cr, "Y");
        set_source_rgba(cr, 0.38, 0.66, 1.0, 1.0); cairo_move_to(cr, zx + 3, zy); cairo_show_text(cr, "Z");
        if (rows[i].name != NULL) {
            set_source_rgba(cr, 0.86, 0.78, 0.90, 0.86);
            cairo_move_to(cr, ox + 7.0, oy - 7.0);
            cairo_show_text(cr, rows[i].name);
        }
    }
}

static double sketch_pixels_per_mm(const WcGtk4State *state)
{
    double scale = 7.5 * (state != NULL ? state->zoom : 1.0);
    return clamp_double(scale, 0.2, 240.0);
}

static void sketch_to_screen(WcGtk4State *state, int width, int height, double x, double y, double *sx, double *sy)
{
    double scale = sketch_pixels_per_mm(state);
    *sx = width * 0.5 + state->pan_x + x * scale;
    *sy = height * 0.5 + state->pan_y - y * scale;
}

static void screen_to_sketch(WcGtk4State *state, int width, int height, double sx, double sy, double *x, double *y)
{
    double scale = sketch_pixels_per_mm(state);
    *x = (sx - width * 0.5 - state->pan_x) / scale;
    *y = -(sy - height * 0.5 - state->pan_y) / scale;
}

static void clear_snap_timer(WcGtk4State *state)
{
    if (state != NULL && state->snap_timer_id != 0) {
        g_source_remove(state->snap_timer_id);
        state->snap_timer_id = 0;
    }
    if (state != NULL) state->snap_ambiguity_ready = 0;
}

static gboolean snap_ambiguity_timer_cb(gpointer user_data)
{
    WcGtk4State *state = (WcGtk4State *)user_data;
    if (state == NULL) return G_SOURCE_REMOVE;
    state->snap_timer_id = 0;
    if (state->snap_candidate_count > 1) {
        state->snap_ambiguity_ready = 1;
        gtk_widget_queue_draw(state->drawing_area);
    }
    return G_SOURCE_REMOVE;
}

static void sort_snap_candidates(WcGtk4State *state)
{
    size_t i;
    for (i = 1; i < state->snap_candidate_count; ++i) {
        WcSnapCandidate key = state->snap_candidates[i];
        size_t j = i;
        while (j > 0 && state->snap_candidates[j - 1].distance > key.distance) {
            state->snap_candidates[j] = state->snap_candidates[j - 1];
            --j;
        }
        state->snap_candidates[j] = key;
    }
}

static void add_snap_candidate(WcGtk4State *state, uint32_t feature_id, uint32_t point_index,
                               uint32_t kind, double x, double y, double screen_x, double screen_y,
                               double pointer_x, double pointer_y, double radius_px)
{
    WcSnapCandidate *candidate;
    double distance;
    if (state == NULL || state->snap_candidate_count >= WC_SNAP_MAX_CANDIDATES) return;
    distance = hypot(screen_x - pointer_x, screen_y - pointer_y);
    if (distance > radius_px) return;
    candidate = &state->snap_candidates[state->snap_candidate_count++];
    candidate->feature_id = feature_id;
    candidate->point_index = point_index;
    candidate->kind = kind;
    candidate->x = x;
    candidate->y = y;
    candidate->screen_x = screen_x;
    candidate->screen_y = screen_y;
    candidate->distance = distance;
}

static void update_snap_candidates(WcGtk4State *state, int width, int height, double pointer_x, double pointer_y)
{
    WcGtk4SketchGeometryRow rows[WC_FEATURE_ROW_CAPACITY];
    size_t count = 0, i;
    const double radius_px = 15.0;
    const double axis_radius_px = 8.0;
    int same_hover;
    double origin_x, origin_y;
    double raw_x, raw_y;
    if (state == NULL || !state->sketch_mode) return;
    same_hover = hypot(pointer_x - state->snap_pointer_x, pointer_y - state->snap_pointer_y) < 3.0;
    state->snap_candidate_count = 0;
    if (state->callbacks != NULL && state->callbacks->sketch_geometry_rows != NULL)
        count = state->callbacks->sketch_geometry_rows(state->user_data, state->active_sketch_id,
                                                       rows, WC_FEATURE_ROW_CAPACITY);
    if (count > WC_FEATURE_ROW_CAPACITY) count = WC_FEATURE_ROW_CAPACITY;
    for (i = 0; i < count && state->snap_candidate_count < WC_SNAP_MAX_CANDIDATES; ++i) {
        WcGtk4SketchGeometryRow *row = &rows[i];
        if (row->kind == WC_FEATURE_KIND_SKETCH_LINE) {
            int endpoint;
            for (endpoint = 0; endpoint < 2; ++endpoint) {
                double ex = row->values[endpoint ? 2 : 0];
                double ey = row->values[endpoint ? 3 : 1];
                double px, py;
                sketch_to_screen(state, width, height, ex, ey, &px, &py);
                add_snap_candidate(state, row->id, (uint32_t)endpoint, WC_SNAP_ENDPOINT,
                                   ex, ey, px, py, pointer_x, pointer_y, radius_px);
            }
        } else if (row->kind == WC_FEATURE_KIND_SKETCH_RECTANGLE) {
            double x = row->values[0], y = row->values[1], w = row->values[2], h = row->values[3];
            double corners[4][2] = {{x,y},{x+w,y},{x+w,y+h},{x,y+h}};
            int corner;
            for (corner = 0; corner < 4; ++corner) {
                double px, py;
                sketch_to_screen(state, width, height, corners[corner][0], corners[corner][1], &px, &py);
                add_snap_candidate(state, row->id, (uint32_t)corner, WC_SNAP_CORNER,
                                   corners[corner][0], corners[corner][1], px, py,
                                   pointer_x, pointer_y, radius_px);
            }
        } else if (row->kind == WC_FEATURE_KIND_SKETCH_CIRCLE) {
            double cx = row->values[0], cy = row->values[1], r = fabs(row->values[2]);
            double points[5][2] = {{cx,cy},{cx+r,cy},{cx-r,cy},{cx,cy+r},{cx,cy-r}};
            int point;
            for (point = 0; point < 5; ++point) {
                double px, py;
                sketch_to_screen(state, width, height, points[point][0], points[point][1], &px, &py);
                add_snap_candidate(state, row->id, (uint32_t)point,
                                   point == 0 ? WC_SNAP_CENTRE : WC_SNAP_ENDPOINT,
                                   points[point][0], points[point][1], px, py,
                                   pointer_x, pointer_y, radius_px);
            }
        } else if (row->kind == WC_FEATURE_KIND_SKETCH_ARC) {
            double cx = row->values[0], cy = row->values[1], r = fabs(row->values[2]);
            double angles[2] = {row->values[3] * M_PI / 180.0, row->values[4] * M_PI / 180.0};
            int point;
            double px, py;
            sketch_to_screen(state, width, height, cx, cy, &px, &py);
            add_snap_candidate(state, row->id, 2u, WC_SNAP_CENTRE, cx, cy, px, py,
                               pointer_x, pointer_y, radius_px);
            for (point = 0; point < 2; ++point) {
                double ex = cx + cos(angles[point]) * r;
                double ey = cy + sin(angles[point]) * r;
                sketch_to_screen(state, width, height, ex, ey, &px, &py);
                add_snap_candidate(state, row->id, (uint32_t)point, WC_SNAP_ENDPOINT,
                                   ex, ey, px, py, pointer_x, pointer_y, radius_px);
            }
        }
    }

    /* The sketch support origin and axes are first-class snap references. */
    sketch_to_screen(state, width, height, 0.0, 0.0, &origin_x, &origin_y);
    add_snap_candidate(state, 0u, 0u, WC_SNAP_ORIGIN, 0.0, 0.0, origin_x, origin_y,
                       pointer_x, pointer_y, radius_px);
    screen_to_sketch(state, width, height, pointer_x, pointer_y, &raw_x, &raw_y);
    if (state->snap_candidate_count == 0 &&
        hypot(pointer_x - origin_x, pointer_y - origin_y) > radius_px * 1.25) {
        double ax, ay;
        sketch_to_screen(state, width, height, raw_x, 0.0, &ax, &ay);
        add_snap_candidate(state, 0u, 0u, WC_SNAP_X_AXIS, raw_x, 0.0, ax, ay,
                           pointer_x, pointer_y, axis_radius_px);
        sketch_to_screen(state, width, height, 0.0, raw_y, &ax, &ay);
        add_snap_candidate(state, 0u, 0u, WC_SNAP_Y_AXIS, 0.0, raw_y, ax, ay,
                           pointer_x, pointer_y, axis_radius_px);
    }

    sort_snap_candidates(state);
    if (state->snap_candidate_count > 1) {
        if (!same_hover || (state->snap_timer_id == 0 && !state->snap_ambiguity_ready)) {
            clear_snap_timer(state);
            state->snap_pointer_x = pointer_x;
            state->snap_pointer_y = pointer_y;
            state->snap_timer_id = g_timeout_add(1000, snap_ambiguity_timer_cb, state);
        }
    } else {
        clear_snap_timer(state);
        state->snap_pointer_x = pointer_x;
        state->snap_pointer_y = pointer_y;
    }
    if (state->snap_choice_locked &&
        hypot(pointer_x - state->snap_choice.screen_x, pointer_y - state->snap_choice.screen_y) > radius_px * 2.0)
        state->snap_choice_locked = 0;
}

static void draw_snap_feedback(cairo_t *cr, WcGtk4State *state)
{
    WcSnapCandidate *candidate;
    if (state == NULL || state->snap_candidate_count == 0) return;
    candidate = state->snap_choice_locked ? &state->snap_choice : &state->snap_candidates[0];
    cairo_set_line_width(cr, 2.0);
    set_source_rgba(cr, 0.42, 0.94, 1.0, 0.98);
    if (candidate->kind == WC_SNAP_X_AXIS) {
        cairo_move_to(cr, 0.0, candidate->screen_y);
        cairo_line_to(cr, gtk_widget_get_width(state->drawing_area), candidate->screen_y);
        cairo_stroke(cr);
    } else if (candidate->kind == WC_SNAP_Y_AXIS) {
        cairo_move_to(cr, candidate->screen_x, 0.0);
        cairo_line_to(cr, candidate->screen_x, gtk_widget_get_height(state->drawing_area));
        cairo_stroke(cr);
    }
    cairo_arc(cr, candidate->screen_x, candidate->screen_y, 6.0, 0.0, 2.0 * M_PI);
    cairo_stroke(cr);
    cairo_arc(cr, candidate->screen_x, candidate->screen_y, 2.2, 0.0, 2.0 * M_PI);
    cairo_fill(cr);
    if (state->snap_candidate_count > 1 && state->snap_ambiguity_ready) {
        set_source_rgba(cr, 0.96, 0.76, 0.92, 0.98);
        cairo_select_font_face(cr, "Sans", CAIRO_FONT_SLANT_NORMAL, CAIRO_FONT_WEIGHT_BOLD);
        cairo_set_font_size(cr, 13.0);
        cairo_move_to(cr, candidate->screen_x + 9.0, candidate->screen_y - 7.0);
        cairo_show_text(cr, "...");
    }
}

static void commit_sketch_point(WcGtk4State *state, double sx, double sy,
                                uint32_t snap_feature, uint32_t snap_point)
{
    int status = 0;
    char message[160];
    if (state == NULL) return;
    state->sketch_cursor_x = sx;
    state->sketch_cursor_y = sy;
    state->sketch_cursor_valid = 1;
    if (!state->sketch_has_anchor) {
        state->sketch_anchor_x = sx;
        state->sketch_anchor_y = sy;
        state->sketch_anchor_snap_feature = snap_feature;
        state->sketch_anchor_snap_point = snap_point;
        state->sketch_has_anchor = 1;
        gtk_label_set_text(GTK_LABEL(state->command_status),
            state->sketch_tool == WC_SKETCH_TOOL_LINE ? "Line: click end point" :
            state->sketch_tool == WC_SKETCH_TOOL_CIRCLE ? "Circle: click radius point" : "Rectangle: click opposite corner");
        gtk_widget_queue_draw(state->drawing_area);
        return;
    }
    if (state->callbacks != NULL) {
        if (state->sketch_tool == WC_SKETCH_TOOL_LINE && state->callbacks->sketch_add_line != NULL) {
            if (hypot(sx - state->sketch_anchor_x, sy - state->sketch_anchor_y) > 1e-6)
                status = state->callbacks->sketch_add_line(state->user_data, state->active_sketch_id,
                    state->sketch_anchor_x, state->sketch_anchor_y, sx, sy,
                    state->sketch_anchor_snap_feature, state->sketch_anchor_snap_point,
                    snap_feature, snap_point);
        } else if (state->sketch_tool == WC_SKETCH_TOOL_CIRCLE && state->callbacks->sketch_add_circle != NULL) {
            double radius = hypot(sx - state->sketch_anchor_x, sy - state->sketch_anchor_y);
            if (radius > 1e-6)
                status = state->callbacks->sketch_add_circle(state->user_data, state->active_sketch_id,
                    state->sketch_anchor_x, state->sketch_anchor_y, radius);
        } else if (state->sketch_tool == WC_SKETCH_TOOL_RECTANGLE && state->callbacks->sketch_add_rectangle != NULL) {
            double min_x = sx < state->sketch_anchor_x ? sx : state->sketch_anchor_x;
            double min_y = sy < state->sketch_anchor_y ? sy : state->sketch_anchor_y;
            double width_mm = fabs(sx - state->sketch_anchor_x);
            double height_mm = fabs(sy - state->sketch_anchor_y);
            if (width_mm > 1e-6 && height_mm > 1e-6)
                status = state->callbacks->sketch_add_rectangle(state->user_data, state->active_sketch_id,
                    min_x, min_y, width_mm, height_mm);
        }
    }
    state->sketch_has_anchor = 0;
    state->sketch_anchor_snap_feature = 0;
    state->sketch_anchor_snap_point = 0;
    state->snap_choice_locked = 0;
    if (status == 0)
        gtk_label_set_text(GTK_LABEL(state->command_status), "Sketch entity added — draw another or Finish Sketch");
    else {
        (void)snprintf(message, sizeof(message), "Sketch draw failed (SCL error %d)", status);
        gtk_label_set_text(GTK_LABEL(state->command_status), message);
    }
    update_status(state);
    gtk_widget_queue_draw(state->drawing_area);
}

static void snap_choice_clicked_cb(GtkButton *button, gpointer user_data)
{
    WcSnapChoiceData *data = (WcSnapChoiceData *)user_data;
    WcGtk4State *state;
    WcSnapCandidate candidate;
    (void)button;
    if (data == NULL || data->state == NULL) return;
    state = data->state;
    if (data->candidate_index >= state->snap_candidate_count) return;
    candidate = state->snap_candidates[data->candidate_index];
    if (data->window != NULL) gtk_window_destroy(GTK_WINDOW(data->window));
    state->snap_choice = candidate;
    state->snap_choice_locked = 1;
    clear_snap_timer(state);
    commit_sketch_point(state, candidate.x, candidate.y, candidate.feature_id, candidate.point_index);
}

static void free_snap_choice_data(gpointer data, GClosure *closure)
{
    (void)closure;
    g_free(data);
}

static void show_snap_choice_dialogue(WcGtk4State *state)
{
    GtkWidget *dialogue;
    GtkWidget *box;
    size_t i;
    if (state == NULL || state->snap_candidate_count < 2) return;
    dialogue = gtk_window_new();
    gtk_window_set_title(GTK_WINDOW(dialogue), "Choose sketch point");
    gtk_window_set_transient_for(GTK_WINDOW(dialogue), GTK_WINDOW(state->window));
    gtk_window_set_modal(GTK_WINDOW(dialogue), TRUE);
    gtk_window_set_default_size(GTK_WINDOW(dialogue), 280, -1);
    box = gtk_box_new(GTK_ORIENTATION_VERTICAL, 5);
    gtk_widget_set_margin_top(box, 10); gtk_widget_set_margin_bottom(box, 10);
    gtk_widget_set_margin_start(box, 10); gtk_widget_set_margin_end(box, 10);
    gtk_box_append(GTK_BOX(box), make_label("Multiple endpoints are within the snap tolerance:", "wc-model-name"));
    for (i = 0; i < state->snap_candidate_count; ++i) {
        char label[128];
        GtkWidget *button;
        WcSnapChoiceData *data = g_new0(WcSnapChoiceData, 1);
        switch (state->snap_candidates[i].kind) {
            case WC_SNAP_ORIGIN:
                (void)snprintf(label, sizeof(label), "Sketch origin (0, 0)");
                break;
            case WC_SNAP_X_AXIS:
                (void)snprintf(label, sizeof(label), "Sketch X axis");
                break;
            case WC_SNAP_Y_AXIS:
                (void)snprintf(label, sizeof(label), "Sketch Y axis");
                break;
            case WC_SNAP_CENTRE:
                (void)snprintf(label, sizeof(label), "Feature #%u — centre", state->snap_candidates[i].feature_id);
                break;
            case WC_SNAP_CORNER:
                (void)snprintf(label, sizeof(label), "Feature #%u — corner %u",
                               state->snap_candidates[i].feature_id, state->snap_candidates[i].point_index + 1u);
                break;
            default:
                (void)snprintf(label, sizeof(label), "Feature #%u — endpoint %u",
                               state->snap_candidates[i].feature_id, state->snap_candidates[i].point_index + 1u);
                break;
        }
        button = gtk_button_new_with_label(label);
        data->state = state;
        data->candidate_index = (uint32_t)i;
        data->window = dialogue;
        g_signal_connect_data(button, "clicked", G_CALLBACK(snap_choice_clicked_cb), data,
                              free_snap_choice_data, 0);
        gtk_box_append(GTK_BOX(box), button);
    }
    gtk_window_set_child(GTK_WINDOW(dialogue), box);
    gtk_window_present(GTK_WINDOW(dialogue));
}

static void draw_sketch_grid(cairo_t *cr, int width, int height, WcGtk4State *state)
{
    double scale = sketch_pixels_per_mm(state);
    double grid_mm = 10.0;
    double step;
    double origin_x = width * 0.5 + state->pan_x;
    double origin_y = height * 0.5 + state->pan_y;
    double x;
    double y;
    while (grid_mm * scale < 24.0) grid_mm *= 2.0;
    while (grid_mm * scale > 96.0) grid_mm *= 0.5;
    step = grid_mm * scale;
    cairo_set_line_width(cr, 1.0);
    set_source_rgba(cr, 0.24, 0.19, 0.34, 0.38);
    for (x = fmod(origin_x, step); x < width; x += step) {
        if (x < 0.0) continue;
        cairo_move_to(cr, x + 0.5, 0.0); cairo_line_to(cr, x + 0.5, height);
    }
    for (y = fmod(origin_y, step); y < height; y += step) {
        if (y < 0.0) continue;
        cairo_move_to(cr, 0.0, y + 0.5); cairo_line_to(cr, width, y + 0.5);
    }
    cairo_stroke(cr);
    cairo_set_line_width(cr, 1.6);
    set_source_rgba(cr, 0.94, 0.28, 0.66, 0.78);
    cairo_move_to(cr, 0.0, origin_y); cairo_line_to(cr, width, origin_y); cairo_stroke(cr);
    set_source_rgba(cr, 0.44, 0.68, 1.0, 0.78);
    cairo_move_to(cr, origin_x, 0.0); cairo_line_to(cr, origin_x, height); cairo_stroke(cr);
    cairo_arc(cr, origin_x, origin_y, 5.0, 0.0, 2.0 * M_PI);
    set_source_rgba(cr, 0.98, 0.82, 0.95, 0.98);
    cairo_fill(cr);
    cairo_select_font_face(cr, "Sans", CAIRO_FONT_SLANT_NORMAL, CAIRO_FONT_WEIGHT_BOLD);
    cairo_set_font_size(cr, 10.0);
    set_source_rgba(cr, 0.94, 0.28, 0.66, 0.95);
    cairo_move_to(cr, width - 18.0, origin_y - 5.0); cairo_show_text(cr, "X");
    set_source_rgba(cr, 0.44, 0.68, 1.0, 0.95);
    cairo_move_to(cr, origin_x + 6.0, 14.0); cairo_show_text(cr, "Y");
    set_source_rgba(cr, 0.86, 0.78, 0.90, 0.92);
    cairo_move_to(cr, origin_x + 7.0, origin_y - 7.0); cairo_show_text(cr, "0,0");
}

static void sketch_line_path(cairo_t *cr, WcGtk4State *state, int width, int height,
                             double x1, double y1, double x2, double y2)
{
    double sx1, sy1, sx2, sy2;
    sketch_to_screen(state, width, height, x1, y1, &sx1, &sy1);
    sketch_to_screen(state, width, height, x2, y2, &sx2, &sy2);
    cairo_move_to(cr, sx1, sy1);
    cairo_line_to(cr, sx2, sy2);
}

static void draw_sketch_geometry(cairo_t *cr, int width, int height, WcGtk4State *state)
{
    WcGtk4SketchGeometryRow rows[WC_FEATURE_ROW_CAPACITY];
    size_t count = 0;
    size_t i;
    if (state->callbacks != NULL && state->callbacks->sketch_geometry_rows != NULL)
        count = state->callbacks->sketch_geometry_rows(state->user_data, state->active_sketch_id,
                                                       rows, WC_FEATURE_ROW_CAPACITY);
    if (count > WC_FEATURE_ROW_CAPACITY) count = WC_FEATURE_ROW_CAPACITY;
    cairo_set_line_width(cr, 2.0);
    set_source_rgba(cr, 0.98, 0.78, 0.94, 1.0);
    for (i = 0; i < count; ++i) {
        WcGtk4SketchGeometryRow *row = &rows[i];
        if (row->kind == WC_FEATURE_KIND_SKETCH_LINE) {
            sketch_line_path(cr, state, width, height, row->values[0], row->values[1], row->values[2], row->values[3]);
            cairo_stroke(cr);
        } else if (row->kind == WC_FEATURE_KIND_SKETCH_CIRCLE) {
            double sx, sy;
            sketch_to_screen(state, width, height, row->values[0], row->values[1], &sx, &sy);
            cairo_arc(cr, sx, sy, fabs(row->values[2]) * sketch_pixels_per_mm(state), 0.0, 2.0 * M_PI);
            cairo_stroke(cr);
        } else if (row->kind == WC_FEATURE_KIND_SKETCH_RECTANGLE) {
            double x = row->values[0], y = row->values[1], w = row->values[2], h = row->values[3];
            sketch_line_path(cr, state, width, height, x, y, x + w, y); cairo_stroke(cr);
            sketch_line_path(cr, state, width, height, x + w, y, x + w, y + h); cairo_stroke(cr);
            sketch_line_path(cr, state, width, height, x + w, y + h, x, y + h); cairo_stroke(cr);
            sketch_line_path(cr, state, width, height, x, y + h, x, y); cairo_stroke(cr);
        } else if (row->kind == WC_FEATURE_KIND_SKETCH_ARC) {
            int segment;
            double start = row->values[3] * M_PI / 180.0;
            double end = row->values[4] * M_PI / 180.0;
            if (end < start) end += 2.0 * M_PI;
            for (segment = 0; segment <= 48; ++segment) {
                double t = start + (end - start) * ((double)segment / 48.0);
                double x = row->values[0] + cos(t) * row->values[2];
                double y = row->values[1] + sin(t) * row->values[2];
                double sx, sy;
                sketch_to_screen(state, width, height, x, y, &sx, &sy);
                if (segment == 0) cairo_move_to(cr, sx, sy); else cairo_line_to(cr, sx, sy);
            }
            cairo_stroke(cr);
        }
    }
}

static void draw_sketch_preview(cairo_t *cr, int width, int height, WcGtk4State *state)
{
    if (!state->sketch_has_anchor || !state->sketch_cursor_valid)
        return;
    cairo_set_line_width(cr, 1.5);
    cairo_set_dash(cr, (double[]){5.0, 4.0}, 2, 0.0);
    set_source_rgba(cr, 0.46, 0.86, 1.0, 0.95);
    if (state->sketch_tool == WC_SKETCH_TOOL_LINE) {
        sketch_line_path(cr, state, width, height, state->sketch_anchor_x, state->sketch_anchor_y,
                         state->sketch_cursor_x, state->sketch_cursor_y);
        cairo_stroke(cr);
    } else if (state->sketch_tool == WC_SKETCH_TOOL_CIRCLE) {
        double cx, cy;
        double radius = hypot(state->sketch_cursor_x - state->sketch_anchor_x,
                              state->sketch_cursor_y - state->sketch_anchor_y);
        sketch_to_screen(state, width, height, state->sketch_anchor_x, state->sketch_anchor_y, &cx, &cy);
        cairo_arc(cr, cx, cy, radius * sketch_pixels_per_mm(state), 0.0, 2.0 * M_PI);
        cairo_stroke(cr);
    } else if (state->sketch_tool == WC_SKETCH_TOOL_RECTANGLE) {
        double x1 = state->sketch_anchor_x, y1 = state->sketch_anchor_y;
        double x2 = state->sketch_cursor_x, y2 = state->sketch_cursor_y;
        sketch_line_path(cr, state, width, height, x1, y1, x2, y1); cairo_stroke(cr);
        sketch_line_path(cr, state, width, height, x2, y1, x2, y2); cairo_stroke(cr);
        sketch_line_path(cr, state, width, height, x2, y2, x1, y2); cairo_stroke(cr);
        sketch_line_path(cr, state, width, height, x1, y2, x1, y1); cairo_stroke(cr);
    }
    cairo_set_dash(cr, NULL, 0, 0.0);
}

static void draw_cb(GtkDrawingArea *area, cairo_t *cr, int width, int height, gpointer user_data)
{
    WcGtk4State *state = (WcGtk4State *)user_data;
    WcGtk4ModelSnapshot snapshot;
    (void)area;

    set_source_rgba(cr, 0.055, 0.047, 0.085, 1.0);
    cairo_paint(cr);
    if (state->sketch_mode) {
        char title[256];
        draw_sketch_grid(cr, width, height, state);
        draw_sketch_geometry(cr, width, height, state);
        draw_sketch_preview(cr, width, height, state);
        draw_snap_feedback(cr, state);
        cairo_select_font_face(cr, "Sans", CAIRO_FONT_SLANT_NORMAL, CAIRO_FONT_WEIGHT_BOLD);
        cairo_set_font_size(cr, 17.0);
        set_source_rgba(cr, 0.96, 0.76, 0.92, 0.88);
        (void)snprintf(title, sizeof(title), "Sketch — %s", state->active_sketch_name);
        cairo_move_to(cr, 20.0, 30.0); cairo_show_text(cr, title);
        cairo_select_font_face(cr, "Sans", CAIRO_FONT_SLANT_NORMAL, CAIRO_FONT_WEIGHT_NORMAL);
        cairo_set_font_size(cr, 11.0);
        set_source_rgba(cr, 0.75, 0.72, 0.82, 0.84);
        cairo_move_to(cr, 20.0, 48.0);
        cairo_show_text(cr, "Click two points to draw. Wheel: zoom  Middle-drag: pan  Esc: cancel current entity.");
        return;
    }

    draw_grid(cr, width, height, state);
    get_snapshot(state, &snapshot);
    draw_body_bounds(cr, width, height, state, &snapshot);
    draw_all_sketches_3d(cr, width, height, state, &snapshot);
    draw_planar_face_selection(cr, width, height, state);
    draw_selected_body_bounds(cr, width, height, state);
    draw_absolute_csys(cr, width, height, state, &snapshot);
    draw_axis_triad(cr, height, state);

    cairo_select_font_face(cr, "Sans", CAIRO_FONT_SLANT_NORMAL, CAIRO_FONT_WEIGHT_BOLD);
    cairo_set_font_size(cr, 18.0);
    set_source_rgba(cr, 0.96, 0.76, 0.92, 0.68);
    cairo_move_to(cr, 20.0, 30.0);
    cairo_show_text(cr, "WaifuCAD");

    cairo_select_font_face(cr, "Sans", CAIRO_FONT_SLANT_NORMAL, CAIRO_FONT_WEIGHT_NORMAL);
    cairo_set_font_size(cr, 11.0);
    set_source_rgba(cr, 0.75, 0.72, 0.82, 0.72);
    cairo_move_to(cr, 20.0, 48.0);
    if (snapshot.bounds_valid)
        cairo_show_text(cr, "Wheel: zoom   Middle-drag: orbit   WASD: pan   Enter: command line   Esc: viewport");
    else
        cairo_show_text(cr, "Create geometry from the ribbon or command line. Wheel zoom / middle-drag orbit / WASD pan.");
}

static void set_command_text(WcGtk4State *state, const char *text, const char *status)
{
    if (state == NULL || state->command_entry == NULL)
        return;
    gtk_editable_set_text(GTK_EDITABLE(state->command_entry), text != NULL ? text : "");
    gtk_editable_set_position(GTK_EDITABLE(state->command_entry), -1);
    if (status != NULL)
        gtk_label_set_text(GTK_LABEL(state->command_status), status);
    gtk_widget_grab_focus(state->command_entry);
}

static void rebuild_ribbon(WcGtk4State *state);
static void refresh_model_navigator(WcGtk4State *state);
static void ribbon_tab_clicked_cb(GtkButton *button, gpointer user_data);
static void scripts_prepare_clicked_cb(GtkButton *button, gpointer user_data);
static void command_focus_clicked_cb(GtkButton *button, gpointer user_data);
static void section_button_clicked_cb(GtkButton *button, gpointer user_data);

static void command_activate_cb(GtkEntry *entry, gpointer user_data)
{
    WcGtk4State *state = (WcGtk4State *)user_data;
    const char *text = gtk_editable_get_text(GTK_EDITABLE(entry));
    char mutable_command[WC_COMMAND_CAPACITY];
    int status = 0;
    char message[128];
    if (state == NULL || text == NULL || text[0] == '\0') return;
    (void)snprintf(mutable_command, sizeof(mutable_command), "%s", text);
    if (state->callbacks != NULL && state->callbacks->submit_command != NULL)
        status = state->callbacks->submit_command(state->user_data, mutable_command);
    if (status == 0)
        (void)snprintf(message, sizeof(message), "Command complete — press Esc for viewport navigation");
    else
        (void)snprintf(message, sizeof(message), "SCL error %d", status);
    gtk_label_set_text(GTK_LABEL(state->command_status), message);
    if (status == 0) gtk_editable_set_text(GTK_EDITABLE(entry), "");
    update_status(state);
    gtk_widget_queue_draw(state->drawing_area);
}

static void enter_sketch_mode(WcGtk4State *state, uint32_t sketch_id, const char *sketch_name)
{
    if (state == NULL || sketch_id == 0) return;
    clear_snap_timer(state);
    state->sketch_mode = 1;
    state->sketch_support_mode = 0;
    state->active_sketch_id = sketch_id;
    copy_text(state->active_sketch_name, sizeof(state->active_sketch_name), sketch_name != NULL ? sketch_name : "sketch");
    state->sketch_tool = WC_SKETCH_TOOL_LINE;
    state->sketch_has_anchor = 0;
    state->sketch_cursor_valid = 0;
    state->sketch_anchor_snap_feature = 0;
    state->snap_candidate_count = 0;
    state->snap_choice_locked = 0;
    state->selected_feature_id = sketch_id;
    state->selected_feature_kind = WC_FEATURE_KIND_SKETCH;
    state->selected_row_is_feature = 1;
    copy_text(state->active_ribbon_tab, sizeof(state->active_ribbon_tab), "sketch.edit");
    state->yaw = -M_PI / 4.0;
    state->pitch = M_PI / 5.5;
    state->zoom = 1.0;
    state->pan_x = 0.0;
    state->pan_y = 0.0;
    rebuild_ribbon(state);
    refresh_model_navigator(state);
    gtk_label_set_text(GTK_LABEL(state->command_status), "Sketch mode — Line tool active; click two points in the graphics area");
    gtk_widget_grab_focus(state->drawing_area);
    gtk_widget_queue_draw(state->drawing_area);
}

static int selected_support(WcGtk4State *state, WcGtk4SketchSupport *support)
{
    if (state == NULL || support == NULL || state->selected_support_kind == WC_GTK4_SKETCH_SUPPORT_NONE)
        return 0;
    memset(support, 0, sizeof(*support));
    support->kind = state->selected_support_kind;
    support->feature_id = state->selected_support_feature_id;
    support->face_persistent_id = state->selected_face_persistent_id;
    support->csys_plane = state->selected_csys_plane[0] != '\0' ? state->selected_csys_plane : NULL;
    return 1;
}

static void create_sketch_on_support(WcGtk4State *state, const WcGtk4SketchSupport *support)
{
    uint32_t sketch_id = 0;
    const char *sketch_name = NULL;
    int status;
    if (state == NULL || support == NULL || state->callbacks == NULL || state->callbacks->begin_new_sketch == NULL)
        return;
    status = state->callbacks->begin_new_sketch(state->user_data, support, &sketch_id, &sketch_name);
    if (status != 0) {
        char message[160];
        (void)snprintf(message, sizeof(message), "Could not create sketch on selected support (SCL error %d)", status);
        gtk_label_set_text(GTK_LABEL(state->command_status), message);
        return;
    }
    update_status(state);
    enter_sketch_mode(state, sketch_id, sketch_name);
}

static void begin_new_sketch(WcGtk4State *state)
{
    WcGtk4SketchSupport support;
    if (state == NULL) return;
    if (selected_support(state, &support)) {
        create_sketch_on_support(state, &support);
        return;
    }
    state->sketch_support_mode = 1;
    gtk_label_set_text(GTK_LABEL(state->command_status),
        "Sketch: select a datum plane, XY/YZ/XZ plane under a CSYS, or planar face in the viewport/Model Navigator");
    gtk_widget_grab_focus(state->drawing_area);
}

static void begin_edit_sketch(WcGtk4State *state, uint32_t sketch_id)
{
    const char *sketch_name = NULL;
    int status;
    if (state == NULL || state->callbacks == NULL || state->callbacks->edit_sketch == NULL) return;
    status = state->callbacks->edit_sketch(state->user_data, sketch_id, &sketch_name);
    if (status != 0) {
        gtk_label_set_text(GTK_LABEL(state->command_status), "Selected feature is not an editable sketch");
        return;
    }
    enter_sketch_mode(state, sketch_id, sketch_name);
}

static void finish_sketch(WcGtk4State *state)
{
    int status = 0;
    if (state == NULL || !state->sketch_mode) return;
    if (state->callbacks != NULL && state->callbacks->finish_sketch != NULL)
        status = state->callbacks->finish_sketch(state->user_data, state->active_sketch_id);
    if (status != 0) {
        char message[128];
        (void)snprintf(message, sizeof(message), "Finish Sketch failed (SCL error %d)", status);
        gtk_label_set_text(GTK_LABEL(state->command_status), message);
        return;
    }
    clear_snap_timer(state);
    state->sketch_mode = 0;
    state->active_sketch_id = 0;
    state->active_sketch_name[0] = '\0';
    state->sketch_has_anchor = 0;
    state->sketch_cursor_valid = 0;
    state->snap_candidate_count = 0;
    state->active_ribbon_tab[0] = '\0';
    state->zoom = 1.0;
    state->pan_x = 0.0;
    state->pan_y = 0.0;
    rebuild_ribbon(state);
    update_status(state);
    gtk_label_set_text(GTK_LABEL(state->command_status), "Sketch finished — viewport navigation restored");
    gtk_widget_grab_focus(state->drawing_area);
    gtk_widget_queue_draw(state->drawing_area);
}

static void sketch_line_tool_cb(GtkButton *button, gpointer user_data)
{
    WcGtk4State *state = (WcGtk4State *)user_data;
    (void)button;
    state->sketch_tool = WC_SKETCH_TOOL_LINE;
    state->sketch_has_anchor = 0;
    state->sketch_anchor_snap_feature = 0;
    gtk_label_set_text(GTK_LABEL(state->command_status), "Sketch Line — click start point, then end point");
    gtk_widget_grab_focus(state->drawing_area);
    gtk_widget_queue_draw(state->drawing_area);
}

static void sketch_circle_tool_cb(GtkButton *button, gpointer user_data)
{
    WcGtk4State *state = (WcGtk4State *)user_data;
    (void)button;
    state->sketch_tool = WC_SKETCH_TOOL_CIRCLE;
    state->sketch_has_anchor = 0;
    state->sketch_anchor_snap_feature = 0;
    gtk_label_set_text(GTK_LABEL(state->command_status), "Sketch Circle — click centre, then radius point");
    gtk_widget_grab_focus(state->drawing_area);
    gtk_widget_queue_draw(state->drawing_area);
}

static void sketch_rectangle_tool_cb(GtkButton *button, gpointer user_data)
{
    WcGtk4State *state = (WcGtk4State *)user_data;
    (void)button;
    state->sketch_tool = WC_SKETCH_TOOL_RECTANGLE;
    state->sketch_has_anchor = 0;
    state->sketch_anchor_snap_feature = 0;
    gtk_label_set_text(GTK_LABEL(state->command_status), "Sketch Rectangle — click first corner, then opposite corner");
    gtk_widget_grab_focus(state->drawing_area);
    gtk_widget_queue_draw(state->drawing_area);
}

static void finish_sketch_clicked_cb(GtkButton *button, gpointer user_data)
{
    (void)button;
    finish_sketch((WcGtk4State *)user_data);
}


static int feature_dialogue_symbol_valid(const char *text)
{
    const unsigned char *cursor = (const unsigned char *)text;
    if (cursor == NULL || *cursor == 0)
        return 0;
    while (*cursor != 0) {
        if (!(g_ascii_isalnum(*cursor) || *cursor == '_' || *cursor == '-' || *cursor == '.'))
            return 0;
        ++cursor;
    }
    return 1;
}

static const char *feature_dialogue_editor_text(GtkWidget *editor, uint32_t kind)
{
    if (editor == NULL)
        return "";
    if (kind == WC_FEATURE_DIALOGUE_FIELD_BOOLEAN)
        return gtk_check_button_get_active(GTK_CHECK_BUTTON(editor)) ? "1" : "0";
    if (kind == WC_FEATURE_DIALOGUE_FIELD_CHOICE) {
        gpointer item = gtk_drop_down_get_selected_item(GTK_DROP_DOWN(editor));
        return item != NULL ? gtk_string_object_get_string(GTK_STRING_OBJECT(item)) : "";
    }
    return gtk_editable_get_text(GTK_EDITABLE(editor));
}

static void feature_dialogue_append_quoted(GString *command, const char *text)
{
    const unsigned char *cursor = (const unsigned char *)(text != NULL ? text : "");
    g_string_append_c(command, '"');
    while (*cursor != 0) {
        if (*cursor == '\\' || *cursor == '"')
            g_string_append_c(command, '\\');
        if (*cursor == '\n') {
            g_string_append(command, "\\n");
        } else if (*cursor != '\r') {
            g_string_append_c(command, (char)*cursor);
        }
        ++cursor;
    }
    g_string_append_c(command, '"');
}

static void path_chooser_data_free(gpointer user_data, GClosure *closure)
{
    WcPathChooserData *data = (WcPathChooserData *)user_data;
    (void)closure;
    if (data == NULL)
        return;
    if (data->entry != NULL)
        g_object_unref(data->entry);
    g_free(data);
}

static void path_chooser_add_filter(GtkFileChooser *chooser, const char *name,
                                    const char *pattern_a, const char *pattern_b)
{
    GtkFileFilter *filter;
    if (chooser == NULL || name == NULL || pattern_a == NULL)
        return;
    filter = gtk_file_filter_new();
    gtk_file_filter_set_name(filter, name);
    gtk_file_filter_add_pattern(filter, pattern_a);
    if (pattern_b != NULL)
        gtk_file_filter_add_pattern(filter, pattern_b);
    gtk_file_chooser_add_filter(chooser, filter);
    g_object_unref(filter);
}

static int submit_path_command(WcGtk4State *state, WcPathChooserMode mode, const char *path)
{
    GString *command;
    const char *verb;
    int status;
    char message[512];
    if (state == NULL || path == NULL || path[0] == '\0' || state->callbacks == NULL ||
        state->callbacks->submit_command == NULL)
        return 10;
    switch (mode) {
        case WC_PATH_CHOOSER_RUN_SCRIPT: verb = "include"; break;
        case WC_PATH_CHOOSER_START_JOURNAL: verb = "journal_start"; break;
        case WC_PATH_CHOOSER_RUN_JOURNAL: verb = "journal_run"; break;
        default: return 10;
    }
    command = g_string_new(verb);
    g_string_append_c(command, '(');
    feature_dialogue_append_quoted(command, path);
    g_string_append_c(command, ')');
    status = state->callbacks->submit_command(state->user_data, command->str);
    if (status == 0) {
        if (mode == WC_PATH_CHOOSER_RUN_SCRIPT)
            (void)snprintf(message, sizeof(message), "Script completed: %s", path);
        else if (mode == WC_PATH_CHOOSER_START_JOURNAL) {
            state->journal_recording = 1;
            (void)snprintf(message, sizeof(message), "Recording journal: %s", path);
        } else
            (void)snprintf(message, sizeof(message), "Journal replay completed: %s", path);
    } else {
        (void)snprintf(message, sizeof(message), "%s failed (error %d)",
                       mode == WC_PATH_CHOOSER_RUN_SCRIPT ? "Script" :
                       (mode == WC_PATH_CHOOSER_START_JOURNAL ? "Journal recording" : "Journal replay"),
                       status);
        fprintf(stderr, "WaifuCAD file action failed: %s => error %d\n", command->str, status);
    }
    gtk_label_set_text(GTK_LABEL(state->command_status), message);
    update_status(state);
    refresh_model_navigator(state);
    gtk_widget_queue_draw(state->drawing_area);
    g_string_free(command, TRUE);
    return status;
}

static void path_chooser_response_cb(GtkNativeDialog *dialog, int response, gpointer user_data)
{
    WcPathChooserData *data = (WcPathChooserData *)user_data;
    if (data != NULL && response == GTK_RESPONSE_ACCEPT) {
        GFile *file = gtk_file_chooser_get_file(GTK_FILE_CHOOSER(dialog));
        if (file != NULL) {
            char *path = g_file_get_path(file);
            if (path != NULL) {
                if (data->mode == WC_PATH_CHOOSER_FIELD && data->entry != NULL && GTK_IS_EDITABLE(data->entry))
                    gtk_editable_set_text(GTK_EDITABLE(data->entry), path);
                else
                    (void)submit_path_command(data->state, data->mode, path);
                g_free(path);
            } else if (data->state != NULL) {
                gtk_label_set_text(GTK_LABEL(data->state->command_status),
                                   "Please choose a local file path");
            }
            g_object_unref(file);
        }
    }
    g_object_unref(dialog);
}

static void open_path_chooser(WcGtk4State *state, GtkWindow *parent, GtkWidget *entry,
                              WcPathChooserMode mode, const char *title,
                              GtkFileChooserAction action, const char *kind,
                              const char *suggested_name)
{
    GtkFileChooserNative *native;
    GtkFileChooser *chooser;
    WcPathChooserData *data;
    if (state == NULL)
        return;
    native = gtk_file_chooser_native_new(title != NULL ? title : "Choose File",
                                         parent != NULL ? parent : GTK_WINDOW(state->window),
                                         action,
                                         action == GTK_FILE_CHOOSER_ACTION_SAVE ? "_Save" : "_Open",
                                         "_Cancel");
    chooser = GTK_FILE_CHOOSER(native);
    if (action == GTK_FILE_CHOOSER_ACTION_SAVE && suggested_name != NULL && suggested_name[0] != '\0') {
        char *base = g_path_get_basename(suggested_name);
        gtk_file_chooser_set_current_name(chooser, base);
        g_free(base);
    }

    if (kind != NULL && strcmp(kind, "script") == 0)
        path_chooser_add_filter(chooser, "WaifuCAD scripts", "*.wcs", "*.scl");
    else if (kind != NULL && strcmp(kind, "journal") == 0)
        path_chooser_add_filter(chooser, "WaifuCAD journals", "*.wjournal", "*.wcs");
    else if (kind != NULL && strcmp(kind, "openscad") == 0)
        path_chooser_add_filter(chooser, "OpenSCAD", "*.scad", NULL);
    else if (kind != NULL && strcmp(kind, "mesh") == 0)
        path_chooser_add_filter(chooser, "CAD / mesh files", "*.off", "*.stl");
    path_chooser_add_filter(chooser, "All files", "*", NULL);

    data = g_new0(WcPathChooserData, 1);
    data->state = state;
    data->mode = mode;
    data->entry = entry != NULL ? g_object_ref(entry) : NULL;
    g_signal_connect_data(native, "response", G_CALLBACK(path_chooser_response_cb), data,
                          path_chooser_data_free, 0);
    gtk_native_dialog_show(GTK_NATIVE_DIALOG(native));
}

static void feature_dialogue_browse_cb(GtkButton *button, gpointer user_data)
{
    WcFeatureDialogueUi *ui = (WcFeatureDialogueUi *)user_data;
    size_t field_index;
    const char *kind = NULL;
    GtkFileChooserAction action = GTK_FILE_CHOOSER_ACTION_OPEN;
    const char *suggested = NULL;
    if (ui == NULL || ui->state == NULL || ui->descriptor == NULL)
        return;
    field_index = (size_t)GPOINTER_TO_UINT(g_object_get_data(G_OBJECT(button), "wc-field-index"));
    if (field_index >= ui->descriptor->field_count || ui->editors[field_index] == NULL ||
        !GTK_IS_EDITABLE(ui->editors[field_index]))
        return;
    suggested = gtk_editable_get_text(GTK_EDITABLE(ui->editors[field_index]));
    if (ui->descriptor->id != NULL && strstr(ui->descriptor->id, "export") != NULL)
        action = GTK_FILE_CHOOSER_ACTION_SAVE;
    if (ui->descriptor->id != NULL && strstr(ui->descriptor->id, "openscad") != NULL)
        kind = "openscad";
    else if (ui->descriptor->id != NULL && strstr(ui->descriptor->id, "run_script") != NULL)
        kind = "script";
    else
        kind = "mesh";
    open_path_chooser(ui->state, GTK_WINDOW(ui->window), ui->editors[field_index],
                      WC_PATH_CHOOSER_FIELD,
                      action == GTK_FILE_CHOOSER_ACTION_SAVE ? "Choose Export File" : "Choose Import File",
                      action, kind, suggested);
}

static int feature_dialogue_append_value(GString *command,
                                         const WcFeatureDialogueFieldDescriptorV1 *field,
                                         const char *value)
{
    if (command == NULL || field == NULL)
        return 0;
    if ((field->flags & WC_FEATURE_DIALOGUE_FIELD_REQUIRED) != 0u &&
        (value == NULL || value[0] == '\0'))
        return 0;

    switch (field->kind) {
        case WC_FEATURE_DIALOGUE_FIELD_NAME:
        case WC_FEATURE_DIALOGUE_FIELD_FEATURE:
            if (!feature_dialogue_symbol_valid(value))
                return 0;
            g_string_append_c(command, ':');
            g_string_append(command, value);
            return 1;
        case WC_FEATURE_DIALOGUE_FIELD_CHOICE:
            if (!feature_dialogue_symbol_valid(value))
                return 0;
            g_string_append_c(command, ':');
            g_string_append(command, value);
            return 1;
        case WC_FEATURE_DIALOGUE_FIELD_TEXT:
        case WC_FEATURE_DIALOGUE_FIELD_FILE:
            feature_dialogue_append_quoted(command, value);
            return 1;
        case WC_FEATURE_DIALOGUE_FIELD_BOOLEAN:
            g_string_append(command, (value != NULL && strcmp(value, "1") == 0) ? "1" : "0");
            return 1;
        case WC_FEATURE_DIALOGUE_FIELD_VALUE:
        case WC_FEATURE_DIALOGUE_FIELD_RAW:
            if (value == NULL || value[0] == '\0')
                return 0;
            g_string_append(command, value);
            return 1;
        default:
            return 0;
    }
}

static void feature_dialogue_free(gpointer user_data)
{
    WcFeatureDialogueUi *ui = (WcFeatureDialogueUi *)user_data;
    if (ui == NULL)
        return;
    if (ui->state != NULL && ui->state->feature_pick_ui == ui) {
        ui->state->feature_pick_ui = NULL;
        ui->state->feature_pick_field_index = 0;
    }
    if (ui->state != NULL && ui->state->active_feature_dialogue_ui == ui)
        ui->state->active_feature_dialogue_ui = NULL;
    g_free(ui->editors);
    g_free(ui);
}

static const char *feature_dialogue_selection_name(uint32_t selection_kind)
{
    switch (selection_kind) {
        case WC_FEATURE_DIALOGUE_SELECTION_PROFILE: return "profile";
        case WC_FEATURE_DIALOGUE_SELECTION_BODY: return "body";
        case WC_FEATURE_DIALOGUE_SELECTION_PATH: return "path";
        case WC_FEATURE_DIALOGUE_SELECTION_ANY_FEATURE: return "feature";
        default: return "feature";
    }
}

static int feature_dialogue_accept_pick(WcGtk4State *state, uint32_t feature_id, const char *feature_name)
{
    WcFeatureDialogueUi *ui;
    const WcFeatureDialogueFieldDescriptorV1 *field;
    char message[256];
    if (state == NULL || state->feature_pick_ui == NULL || feature_id == 0 || feature_name == NULL)
        return 0;
    ui = state->feature_pick_ui;
    if (ui->descriptor == NULL || state->feature_pick_field_index >= ui->descriptor->field_count)
        return 0;
    field = &ui->descriptor->fields[state->feature_pick_field_index];
    if (state->callbacks == NULL || state->callbacks->feature_dialogue_accept_selection == NULL ||
        state->callbacks->feature_dialogue_accept_selection(state->user_data, ui->descriptor,
            state->feature_pick_field_index, feature_id) == 0) {
        (void)snprintf(message, sizeof(message), "%s is not a valid %s for this field",
                       feature_name, feature_dialogue_selection_name(field->selection_kind));
        gtk_label_set_text(GTK_LABEL(state->command_status), message);
        return 0;
    }
    if (ui->editors[state->feature_pick_field_index] == NULL ||
        !GTK_IS_EDITABLE(ui->editors[state->feature_pick_field_index]))
        return 0;
    gtk_editable_set_text(GTK_EDITABLE(ui->editors[state->feature_pick_field_index]), feature_name);
    (void)snprintf(message, sizeof(message), "%s selected: %s",
                   feature_dialogue_selection_name(field->selection_kind), feature_name);
    gtk_label_set_text(GTK_LABEL(state->command_status), message);
    state->feature_pick_ui = NULL;
    state->feature_pick_field_index = 0;
    if (ui->window != NULL)
        gtk_window_present(GTK_WINDOW(ui->window));
    return 1;
}

static void feature_dialogue_select_cb(GtkButton *button, gpointer user_data)
{
    WcFeatureDialogueUi *ui = (WcFeatureDialogueUi *)user_data;
    size_t field_index;
    const WcFeatureDialogueFieldDescriptorV1 *field;
    char message[256];
    if (ui == NULL || ui->state == NULL || ui->descriptor == NULL || button == NULL)
        return;
    field_index = (size_t)GPOINTER_TO_UINT(g_object_get_data(G_OBJECT(button), "wc-field-index"));
    if (field_index >= ui->descriptor->field_count)
        return;
    field = &ui->descriptor->fields[field_index];
    if (field->kind != WC_FEATURE_DIALOGUE_FIELD_FEATURE ||
        field->selection_kind == WC_FEATURE_DIALOGUE_SELECTION_NONE)
        return;
    ui->state->feature_pick_ui = ui;
    ui->state->feature_pick_field_index = field_index;
    (void)snprintf(message, sizeof(message), "Select %s from the graphics area or Model Navigator; Esc cancels selection",
                   feature_dialogue_selection_name(field->selection_kind));
    gtk_label_set_text(GTK_LABEL(ui->state->command_status), message);
    gtk_widget_set_visible(ui->window, FALSE);
    gtk_window_present(GTK_WINDOW(ui->state->window));
    gtk_widget_grab_focus(ui->state->drawing_area);
}

static void feature_dialogue_cancel_cb(GtkButton *button, gpointer user_data)
{
    WcFeatureDialogueUi *ui = (WcFeatureDialogueUi *)user_data;
    (void)button;
    if (ui != NULL && ui->state != NULL && ui->state->feature_pick_ui == ui) {
        ui->state->feature_pick_ui = NULL;
        ui->state->feature_pick_field_index = 0;
    }
    if (ui != NULL && ui->window != NULL)
        gtk_window_destroy(GTK_WINDOW(ui->window));
}

static void feature_dialogue_edit_sketch_cb(GtkButton *button, gpointer user_data)
{
    WcFeatureDialogueUi *ui = (WcFeatureDialogueUi *)user_data;
    (void)button;
    if (ui == NULL || ui->state == NULL || ui->feature_id == 0)
        return;
    begin_edit_sketch(ui->state, ui->feature_id);
    if (ui->window != NULL)
        gtk_window_destroy(GTK_WINDOW(ui->window));
}

static void feature_dialogue_apply_cb(GtkButton *button, gpointer user_data)
{
    WcFeatureDialogueUi *ui = (WcFeatureDialogueUi *)user_data;
    GString *command;
    size_t i;
    int have_argument = 0;
    int status;
    char message[256];
    (void)button;
    if (ui == NULL || ui->state == NULL || ui->descriptor == NULL ||
        ui->state->callbacks == NULL || ui->state->callbacks->submit_command == NULL)
        return;

    command = g_string_new(NULL);
    if (ui->feature_id != 0) {
        const char *name = NULL;
        if ((ui->descriptor->flags & WC_FEATURE_DIALOGUE_EDITABLE) == 0u ||
            ui->descriptor->edit_kind == NULL) {
            g_string_free(command, TRUE);
            return;
        }
        for (i = 0; i < ui->descriptor->field_count; ++i) {
            const WcFeatureDialogueFieldDescriptorV1 *field = &ui->descriptor->fields[i];
            if (field->kind == WC_FEATURE_DIALOGUE_FIELD_NAME) {
                name = feature_dialogue_editor_text(ui->editors[i], field->kind);
                break;
            }
        }
        if (!feature_dialogue_symbol_valid(name)) {
            gtk_label_set_text(GTK_LABEL(ui->state->command_status), "Feature dialogue: invalid feature name");
            g_string_free(command, TRUE);
            return;
        }
        g_string_append(command, "feature_edit(:");
        g_string_append(command, name);
        g_string_append(command, ", :");
        g_string_append(command, ui->descriptor->edit_kind);
        have_argument = 1;
    } else {
        if (ui->descriptor->command_name == NULL || ui->descriptor->command_name[0] == '\0') {
            g_string_free(command, TRUE);
            return;
        }
        g_string_append(command, ui->descriptor->command_name);
        g_string_append_c(command, '(');
        if (ui->descriptor->argument_prefix != NULL && ui->descriptor->argument_prefix[0] != '\0') {
            g_string_append(command, ui->descriptor->argument_prefix);
            have_argument = 1;
        }
    }

    for (i = 0; i < ui->descriptor->field_count; ++i) {
        const WcFeatureDialogueFieldDescriptorV1 *field = &ui->descriptor->fields[i];
        const char *value;
        if (ui->feature_id != 0 && field->kind == WC_FEATURE_DIALOGUE_FIELD_NAME)
            continue;
        value = feature_dialogue_editor_text(ui->editors[i], field->kind);
        if (have_argument)
            g_string_append(command, ", ");
        if (!feature_dialogue_append_value(command, field, value)) {
            (void)snprintf(message, sizeof(message), "Feature dialogue: invalid or missing %s",
                           field->label != NULL ? field->label : "value");
            gtk_label_set_text(GTK_LABEL(ui->state->command_status), message);
            g_string_free(command, TRUE);
            return;
        }
        have_argument = 1;
    }
    g_string_append_c(command, ')');

    status = ui->state->callbacks->submit_command(ui->state->user_data, command->str);
    if (status != 0) {
        (void)snprintf(message, sizeof(message), "%s rejected (error %d)",
                       ui->feature_id != 0 ? "Feature edit" : "Ribbon action", status);
        gtk_label_set_text(GTK_LABEL(ui->state->command_status), message);
        fprintf(stderr, "Feature dialogue failed: %s => error %d\n", command->str, status);
        g_string_free(command, TRUE);
        return;
    }

    gtk_label_set_text(GTK_LABEL(ui->state->command_status),
                       ui->feature_id != 0 ? "Feature updated" : "Ribbon action completed");
    update_status(ui->state);
    gtk_widget_queue_draw(ui->state->drawing_area);
    g_string_free(command, TRUE);
    if (ui->window != NULL)
        gtk_window_destroy(GTK_WINDOW(ui->window));
}

static int feature_dialogue_name_exists(WcGtk4State *state, const char *name)
{
    WcGtk4FeatureRow *rows;
    size_t count, i;
    int exists = 0;
    if (state == NULL || name == NULL || state->callbacks == NULL ||
        state->callbacks->feature_rows == NULL)
        return 0;
    count = state->callbacks->feature_rows(state->user_data, NULL, 0);
    if (count == 0)
        return 0;
    rows = g_new0(WcGtk4FeatureRow, count);
    state->callbacks->feature_rows(state->user_data, rows, count);
    for (i = 0; i < count; ++i) {
        if (rows[i].name != NULL && strcmp(rows[i].name, name) == 0) {
            exists = 1;
            break;
        }
    }
    g_free(rows);
    return exists;
}

static void feature_dialogue_unique_name(WcGtk4State *state, const char *base,
                                         char *output, size_t capacity)
{
    unsigned int suffix;
    if (output == NULL || capacity == 0)
        return;
    (void)snprintf(output, capacity, "%s", base != NULL && base[0] != '\0' ? base : "feature");
    if (!feature_dialogue_name_exists(state, output))
        return;
    for (suffix = 2; suffix < 100000u; ++suffix) {
        (void)snprintf(output, capacity, "%s_%u",
                       base != NULL && base[0] != '\0' ? base : "feature", suffix);
        if (!feature_dialogue_name_exists(state, output))
            return;
    }
}

static GtkWidget *feature_dialogue_make_editor(WcFeatureDialogueUi *ui, size_t field_index,
                                                const char *initial)
{
    const WcFeatureDialogueFieldDescriptorV1 *field = &ui->descriptor->fields[field_index];
    GtkWidget *editor;
    if (field->kind == WC_FEATURE_DIALOGUE_FIELD_BOOLEAN) {
        editor = gtk_check_button_new();
        gtk_check_button_set_active(GTK_CHECK_BUTTON(editor),
                                    initial != NULL &&
                                    (strcmp(initial, "1") == 0 || strcmp(initial, "true") == 0));
    } else if (field->kind == WC_FEATURE_DIALOGUE_FIELD_CHOICE && field->choices != NULL) {
        gchar **choices = g_strsplit(field->choices, "|", -1);
        guint selected = 0, index = 0;
        editor = gtk_drop_down_new_from_strings((const char * const *)choices);
        while (choices[index] != NULL) {
            if (initial != NULL && strcmp(choices[index], initial) == 0)
                selected = index;
            ++index;
        }
        gtk_drop_down_set_selected(GTK_DROP_DOWN(editor), selected);
        g_strfreev(choices);
    } else {
        editor = gtk_entry_new();
        gtk_editable_set_text(GTK_EDITABLE(editor), initial != NULL ? initial : "");
        gtk_widget_set_hexpand(editor, TRUE);
    }
    if ((field->flags & WC_FEATURE_DIALOGUE_FIELD_READ_ONLY) != 0u ||
        (ui->feature_id != 0 && field->kind == WC_FEATURE_DIALOGUE_FIELD_NAME))
        gtk_widget_set_sensitive(editor, FALSE);
    return editor;
}

static void show_feature_dialogue(WcGtk4State *state,
                                  const WcFeatureDialogueDescriptorV1 *descriptor,
                                  uint32_t feature_id)
{
    WcFeatureDialogueUi *ui;
    GtkWidget *root_box;
    GtkWidget *header;
    GtkWidget *title_box;
    GtkWidget *title;
    GtkWidget *subtitle;
    GtkWidget *picture;
    GtkWidget *scroller;
    GtkWidget *grid;
    GtkWidget *actions;
    GtkWidget *button;
    size_t i;
    if (state == NULL || descriptor == NULL ||
        descriptor->abi_version != WC_FEATURE_DIALOGUE_ABI_V1)
        return;

    ui = g_new0(WcFeatureDialogueUi, 1);
    ui->state = state;
    ui->descriptor = descriptor;
    ui->feature_id = feature_id;
    ui->editors = g_new0(GtkWidget *, descriptor->field_count);
    state->active_feature_dialogue_ui = ui;

    ui->window = gtk_window_new();
    gtk_window_set_title(GTK_WINDOW(ui->window),
                         descriptor->title != NULL ? descriptor->title : "Feature");
    gtk_window_set_default_size(GTK_WINDOW(ui->window), 540, 620);
    gtk_window_set_transient_for(GTK_WINDOW(ui->window), GTK_WINDOW(state->window));
    gtk_window_set_modal(GTK_WINDOW(ui->window), FALSE);
    g_object_set_data_full(G_OBJECT(ui->window), "wc-feature-dialogue-ui",
                           ui, feature_dialogue_free);

    root_box = gtk_box_new(GTK_ORIENTATION_VERTICAL, 10);
    gtk_widget_set_margin_top(root_box, 12);
    gtk_widget_set_margin_bottom(root_box, 12);
    gtk_widget_set_margin_start(root_box, 12);
    gtk_widget_set_margin_end(root_box, 12);

    header = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 12);
    title_box = gtk_box_new(GTK_ORIENTATION_VERTICAL, 4);
    gtk_widget_set_hexpand(title_box, TRUE);
    title = make_label(descriptor->title != NULL ? descriptor->title : "Feature", "wc-title");
    subtitle = make_label(feature_id != 0 ? "Edit feature" : "Create from ribbon", "wc-subtle");
    gtk_box_append(GTK_BOX(title_box), title);
    gtk_box_append(GTK_BOX(title_box), subtitle);
    gtk_box_append(GTK_BOX(header), title_box);
    if (descriptor->waifu_image != NULL && g_file_test(descriptor->waifu_image, G_FILE_TEST_EXISTS)) {
        picture = gtk_picture_new_for_filename(descriptor->waifu_image);
        gtk_widget_set_size_request(picture, 120, 120);
        gtk_widget_set_halign(picture, GTK_ALIGN_END);
        gtk_widget_set_valign(picture, GTK_ALIGN_START);
        gtk_box_append(GTK_BOX(header), picture);
    }
    gtk_box_append(GTK_BOX(root_box), header);

    scroller = gtk_scrolled_window_new();
    gtk_widget_set_vexpand(scroller, TRUE);
    gtk_scrolled_window_set_policy(GTK_SCROLLED_WINDOW(scroller), GTK_POLICY_NEVER, GTK_POLICY_AUTOMATIC);
    grid = gtk_grid_new();
    gtk_grid_set_row_spacing(GTK_GRID(grid), 8);
    gtk_grid_set_column_spacing(GTK_GRID(grid), 12);

    for (i = 0; i < descriptor->field_count; ++i) {
        const WcFeatureDialogueFieldDescriptorV1 *field = &descriptor->fields[i];
        GtkWidget *label = make_label(field->label != NULL ? field->label : field->id, NULL);
        char current[512];
        char unique_name[WC_UI_ID_CAPACITY];
        const char *initial = field->default_value != NULL ? field->default_value : "";
        current[0] = '\0';
        unique_name[0] = '\0';
        if (feature_id != 0 && state->callbacks != NULL &&
            state->callbacks->feature_dialogue_value != NULL &&
            state->callbacks->feature_dialogue_value(state->user_data, feature_id,
                                                      descriptor, i, current,
                                                      sizeof(current)) == 0)
            initial = current;
        else if (feature_id == 0 && field->kind == WC_FEATURE_DIALOGUE_FIELD_FEATURE &&
                 initial[0] == '\0' && state->selected_feature_name[0] != '\0' &&
                 state->selected_feature_id != 0 && state->callbacks != NULL &&
                 state->callbacks->feature_dialogue_accept_selection != NULL &&
                 state->callbacks->feature_dialogue_accept_selection(state->user_data, descriptor,
                     i, state->selected_feature_id) != 0)
            initial = state->selected_feature_name;
        if (feature_id == 0 && field->kind == WC_FEATURE_DIALOGUE_FIELD_NAME) {
            feature_dialogue_unique_name(state, initial, unique_name, sizeof(unique_name));
            initial = unique_name;
        }
        ui->editors[i] = feature_dialogue_make_editor(ui, i, initial);
        gtk_widget_set_valign(label, GTK_ALIGN_CENTER);
        gtk_grid_attach(GTK_GRID(grid), label, 0, (int)i, 1, 1);
        if (field->kind == WC_FEATURE_DIALOGUE_FIELD_FEATURE &&
            field->selection_kind != WC_FEATURE_DIALOGUE_SELECTION_NONE &&
            (field->flags & WC_FEATURE_DIALOGUE_FIELD_READ_ONLY) == 0u) {
            GtkWidget *selector = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 6);
            GtkWidget *select_button = gtk_button_new_with_label("Select…");
            gtk_widget_set_hexpand(ui->editors[i], TRUE);
            gtk_box_append(GTK_BOX(selector), ui->editors[i]);
            g_object_set_data(G_OBJECT(select_button), "wc-field-index", GUINT_TO_POINTER((guint)i));
            g_signal_connect(select_button, "clicked", G_CALLBACK(feature_dialogue_select_cb), ui);
            gtk_box_append(GTK_BOX(selector), select_button);
            gtk_grid_attach(GTK_GRID(grid), selector, 1, (int)i, 1, 1);
        } else if (field->kind == WC_FEATURE_DIALOGUE_FIELD_FILE &&
                   (field->flags & WC_FEATURE_DIALOGUE_FIELD_READ_ONLY) == 0u) {
            GtkWidget *selector = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 6);
            GtkWidget *browse_button = gtk_button_new_with_label("Browse…");
            gtk_widget_set_hexpand(ui->editors[i], TRUE);
            gtk_box_append(GTK_BOX(selector), ui->editors[i]);
            g_object_set_data(G_OBJECT(browse_button), "wc-field-index", GUINT_TO_POINTER((guint)i));
            g_signal_connect(browse_button, "clicked", G_CALLBACK(feature_dialogue_browse_cb), ui);
            gtk_box_append(GTK_BOX(selector), browse_button);
            gtk_grid_attach(GTK_GRID(grid), selector, 1, (int)i, 1, 1);
        } else {
            gtk_grid_attach(GTK_GRID(grid), ui->editors[i], 1, (int)i, 1, 1);
        }
    }
    gtk_scrolled_window_set_child(GTK_SCROLLED_WINDOW(scroller), grid);
    gtk_box_append(GTK_BOX(root_box), scroller);

    actions = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 8);
    gtk_widget_set_halign(actions, GTK_ALIGN_END);
    if ((descriptor->flags & WC_FEATURE_DIALOGUE_SKETCH_EDITOR) != 0u && feature_id != 0) {
        button = gtk_button_new_with_label("Edit Sketch Geometry");
        g_signal_connect(button, "clicked", G_CALLBACK(feature_dialogue_edit_sketch_cb), ui);
        gtk_box_append(GTK_BOX(actions), button);
    }
    if ((feature_id == 0 && descriptor->command_name != NULL) ||
        (feature_id != 0 && (descriptor->flags & WC_FEATURE_DIALOGUE_EDITABLE) != 0u &&
         descriptor->edit_kind != NULL)) {
        button = gtk_button_new_with_label(feature_id != 0 ? "Apply" : "Create");
        gtk_widget_add_css_class(button, "suggested-action");
        g_signal_connect(button, "clicked", G_CALLBACK(feature_dialogue_apply_cb), ui);
        gtk_box_append(GTK_BOX(actions), button);
    }
    button = gtk_button_new_with_label("Cancel");
    g_signal_connect(button, "clicked", G_CALLBACK(feature_dialogue_cancel_cb), ui);
    gtk_box_append(GTK_BOX(actions), button);
    gtk_box_append(GTK_BOX(root_box), actions);

    gtk_window_set_child(GTK_WINDOW(ui->window), root_box);
    gtk_window_present(GTK_WINDOW(ui->window));
}

static void ribbon_command_clicked_cb(GtkButton *button, gpointer user_data)
{
    WcRibbonButtonData *data = (WcRibbonButtonData *)user_data;
    const WcFeatureDialogueDescriptorV1 *dialogue = NULL;
    const char *template_text = "";
    int status;
    char message[256];
    (void)button;
    if (data == NULL || data->state == NULL) return;

    /* Sketch is already a direct interactive graphics workflow. */
    if (strcmp(data->id, "modelling.sketch") == 0) {
        begin_new_sketch(data->state);
        return;
    }

    /* Read-only inspection actions do not need an SCL entry field at all. */
    if (strcmp(data->id, "modelling.measure") == 0 ||
        strcmp(data->id, "modelling.mass_properties") == 0) {
        if (data->state->selected_feature_id == 0) {
            gtk_label_set_text(GTK_LABEL(data->state->command_status),
                               "Select a feature first");
            return;
        }
        if (strcmp(data->id, "modelling.mass_properties") == 0)
            show_mass_properties(data->state, data->state->selected_feature_id);
        else
            show_feature_properties(data->state, data->state->selected_feature_id);
        return;
    }

    if (strcmp(data->id, "modelling.journal_record") == 0) {
        if (data->state->journal_recording) {
            if (data->state->callbacks == NULL || data->state->callbacks->submit_command == NULL)
                return;
            status = data->state->callbacks->submit_command(data->state->user_data, "journal_stop()");
            if (status == 0) {
                data->state->journal_recording = 0;
                gtk_label_set_text(GTK_LABEL(data->state->command_status),
                                   "Journal recording stopped");
            } else {
                (void)snprintf(message, sizeof(message), "Stop journal failed (error %d)", status);
                gtk_label_set_text(GTK_LABEL(data->state->command_status), message);
                fprintf(stderr, "WaifuCAD journal_stop() failed: error %d\n", status);
            }
        } else {
            open_path_chooser(data->state, GTK_WINDOW(data->state->window), NULL,
                              WC_PATH_CHOOSER_START_JOURNAL, "Record Journal",
                              GTK_FILE_CHOOSER_ACTION_SAVE, "journal", "model.wjournal");
        }
        return;
    }

    if (strcmp(data->id, "modelling.run_journal") == 0) {
        open_path_chooser(data->state, GTK_WINDOW(data->state->window), NULL,
                          WC_PATH_CHOOSER_RUN_JOURNAL, "Run Journal",
                          GTK_FILE_CHOOSER_ACTION_OPEN, "journal", NULL);
        return;
    }

    if (strcmp(data->id, "modelling.run_script") == 0) {
        open_path_chooser(data->state, GTK_WINDOW(data->state->window), NULL,
                          WC_PATH_CHOOSER_RUN_SCRIPT, "Run Script",
                          GTK_FILE_CHOOSER_ACTION_OPEN, "script", NULL);
        return;
    }

    if (data->state->callbacks != NULL &&
        data->state->callbacks->feature_dialogue != NULL)
        dialogue = data->state->callbacks->feature_dialogue(data->state->user_data, data->id);
    if (dialogue != NULL) {
        show_feature_dialogue(data->state, dialogue, 0);
        return;
    }

    /*
     * Simple implemented commands without a dialogue execute immediately.
     * The command console remains available as an explicit power-user tool,
     * but ribbon activation never requires the user to edit it.
     */
    if (data->state->callbacks != NULL &&
        data->state->callbacks->ribbon_template != NULL)
        template_text = data->state->callbacks->ribbon_template(data->state->user_data, data->id);
    if (template_text == NULL || template_text[0] == '\0' || template_text[0] == '#') {
        gtk_label_set_text(GTK_LABEL(data->state->command_status),
                           "This ribbon action is not implemented yet");
        return;
    }
    if (data->state->callbacks == NULL || data->state->callbacks->submit_command == NULL)
        return;
    status = data->state->callbacks->submit_command(data->state->user_data, (char *)template_text);
    if (status != 0) {
        (void)snprintf(message, sizeof(message), "%s rejected (SCL error %d)",
                       suffix_after_dot(data->id), status);
        gtk_label_set_text(GTK_LABEL(data->state->command_status), message);
        return;
    }
    update_status(data->state);
    gtk_widget_queue_draw(data->state->drawing_area);
    gtk_label_set_text(GTK_LABEL(data->state->command_status), "Ribbon action completed");
}

static int ribbon_has_tab(const WcGtk4RibbonSnapshot *ribbon, const char *tab_id)
{
    size_t i;
    if (tab_id == NULL || tab_id[0] == '\0')
        return 0;
    if (strcmp(tab_id, "global.sections") == 0 || strcmp(tab_id, "global.mods") == 0)
        return 1;
    if (ribbon == NULL)
        return 0;
    for (i = 0; i < ribbon->tab_count; ++i)
        if (ribbon->tabs[i].id != NULL && strcmp(ribbon->tabs[i].id, tab_id) == 0)
            return 1;
    return 0;
}

static void free_signal_data(gpointer data, GClosure *closure)
{
    (void)closure;
    g_free(data);
}

static int ribbon_compact_mode(WcGtk4State *state, size_t group_count)
{
    int width = state != NULL && state->ribbon_scroller != NULL ? gtk_widget_get_width(state->ribbon_scroller) : 0;
    if (width <= 0 && state != NULL)
        width = state->window_width_hint;
    return group_count > 4 || width < 1180;
}

static GtkWidget *make_ribbon_command_button(WcGtk4State *state, const WcGtk4RibbonCommand *command, int compact)
{
    char label[96];
    GtkWidget *button;
    WcRibbonButtonData *data;
    const char *template_text = "";
    const WcFeatureDialogueDescriptorV1 *dialogue = NULL;
    humanise_identifier(command->id, label, sizeof(label));
    button = make_icon_text_button(command->icon_name, label, compact ? 22 : 34);
    gtk_widget_set_size_request(button, compact ? 58 : 82, compact ? 50 : 76);
    if (compact)
        gtk_widget_add_css_class(button, "wc-ribbon-command-compact");
    data = g_new0(WcRibbonButtonData, 1);
    data->state = state;
    copy_text(data->id, sizeof(data->id), command->id);
    g_signal_connect_data(button, "clicked", G_CALLBACK(ribbon_command_clicked_cb), data,
                          free_signal_data, 0);
    if (state->callbacks != NULL && state->callbacks->feature_dialogue != NULL)
        dialogue = state->callbacks->feature_dialogue(state->user_data, command->id);
    if (state->callbacks != NULL && state->callbacks->ribbon_template != NULL)
        template_text = state->callbacks->ribbon_template(state->user_data, command->id);
    if ((command->flags & WC_RIBBON_FLAG_PLANNED) != 0u) {
        gtk_widget_set_sensitive(button, FALSE);
        gtk_widget_set_tooltip_text(button, "Planned command — data model is not implemented yet");
    } else if (strcmp(command->id, "modelling.sketch") == 0) {
        gtk_widget_set_tooltip_text(button, "Start the interactive Sketch workflow");
    } else if (strcmp(command->id, "modelling.run_script") == 0) {
        gtk_widget_set_tooltip_text(button, "Choose and run a WaifuCAD script");
    } else if (strcmp(command->id, "modelling.run_journal") == 0) {
        gtk_widget_set_tooltip_text(button, "Choose and replay a WaifuCAD journal");
    } else if (strcmp(command->id, "modelling.journal_record") == 0) {
        gtk_widget_set_tooltip_text(button, "Choose a journal file and start/stop recording");
    } else if (dialogue != NULL) {
        gtk_widget_set_tooltip_text(button, "Open feature dialogue");
    } else if (template_text != NULL && template_text[0] != '\0' && template_text[0] != '#') {
        gtk_widget_set_tooltip_text(button, "Run this action immediately");
    } else {
        gtk_widget_set_tooltip_text(button, "This action is not implemented yet");
    }
    return button;
}

static size_t command_group_count(const WcGtk4RibbonSnapshot *ribbon, const char *tab_id, const char *group_id)
{
    size_t i, count = 0;
    if (ribbon == NULL || tab_id == NULL || group_id == NULL)
        return 0;
    for (i = 0; i < ribbon->command_count; ++i)
        if (ribbon->commands[i].tab_id != NULL && ribbon->commands[i].group_id != NULL &&
            strcmp(ribbon->commands[i].tab_id, tab_id) == 0 && strcmp(ribbon->commands[i].group_id, group_id) == 0)
            ++count;
    return count;
}

static GtkWidget *make_ribbon_tab_button(WcGtk4State *state, const char *id, const char *label)
{
    GtkWidget *button = gtk_button_new_with_label(label);
    WcRibbonButtonData *data = g_new0(WcRibbonButtonData, 1);
    gtk_widget_add_css_class(button, "wc-ribbon-tab");
    if (id != NULL && strcmp(id, state->active_ribbon_tab) == 0)
        gtk_widget_add_css_class(button, "wc-ribbon-tab-active");
    data->state = state;
    copy_text(data->id, sizeof(data->id), id);
    g_signal_connect_data(button, "clicked", G_CALLBACK(ribbon_tab_clicked_cb), data,
                          free_signal_data, 0);
    return button;
}

static void build_sections_ribbon_commands(WcGtk4State *state)
{
    const WcGtk4SectionEntry *entries = NULL;
    size_t count = 0, i;
    GtkWidget *frame = gtk_frame_new(NULL);
    GtkWidget *outer = gtk_box_new(GTK_ORIENTATION_VERTICAL, 1);
    GtkWidget *rows = gtk_box_new(GTK_ORIENTATION_VERTICAL, 1);
    GtkWidget *row = NULL;
    size_t row_count = 0;
    gtk_widget_add_css_class(frame, "wc-ribbon-group");
    if (state->callbacks != NULL && state->callbacks->section_entries != NULL)
        entries = state->callbacks->section_entries(state->user_data, &count);
    for (i = 0; entries != NULL && i < count; ++i) {
        char label[96];
        GtkWidget *button;
        WcSectionButtonData *data;
        if (row == NULL || row_count == 4) {
            row = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 1);
            gtk_box_append(GTK_BOX(rows), row);
            row_count = 0;
        }
        humanise_identifier(entries[i].id, label, sizeof(label));
        button = make_icon_text_button(entries[i].icon_name, label, state->ribbon_density > 0 ? 22 : 30);
        gtk_widget_set_size_request(button, state->ribbon_density > 0 ? 62 : 80, state->ribbon_density > 0 ? 50 : 70);
        data = g_new0(WcSectionButtonData, 1);
        data->state = state;
        copy_text(data->id, sizeof(data->id), entries[i].id);
        g_signal_connect_data(button, "clicked", G_CALLBACK(section_button_clicked_cb), data,
                              free_signal_data, 0);
        gtk_box_append(GTK_BOX(row), button);
        ++row_count;
    }
    gtk_box_append(GTK_BOX(outer), rows);
    gtk_box_append(GTK_BOX(outer), make_label("Sections", "wc-ribbon-group-label"));
    gtk_frame_set_child(GTK_FRAME(frame), outer);
    gtk_box_append(GTK_BOX(state->ribbon_commands_box), frame);
    build_mods_ribbon_commands(state);
}

static void build_mods_ribbon_commands(WcGtk4State *state)
{
    GtkWidget *frame = gtk_frame_new(NULL);
    GtkWidget *outer = gtk_box_new(GTK_ORIENTATION_VERTICAL, 3);
    GtkWidget *button = make_icon_text_button("tab_mods", "Manage Mods", 26);
    gtk_widget_add_css_class(frame, "wc-ribbon-group");
    gtk_widget_set_sensitive(button, FALSE);
    gtk_widget_set_tooltip_text(button, "Dynamic Mod discovery is still a P1 roadmap item; the versioned Mod ABI already exists");
    gtk_box_append(GTK_BOX(outer), button);
    gtk_box_append(GTK_BOX(outer), make_label("Mods", "wc-ribbon-group-label"));
    gtk_frame_set_child(GTK_FRAME(frame), outer);
    gtk_box_append(GTK_BOX(state->ribbon_commands_box), frame);
}

static void append_scripts_home_group(WcGtk4State *state)
{
    GtkWidget *frame = gtk_frame_new(NULL);
    GtkWidget *outer = gtk_box_new(GTK_ORIENTATION_VERTICAL, 1);
    GtkWidget *row = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 1);
    GtkWidget *button;
    gtk_widget_add_css_class(frame, "wc-ribbon-group");
    button = make_icon_text_button("cmd_script", "Run Script", state->ribbon_density > 0 ? 22 : 30);
    g_signal_connect(button, "clicked", G_CALLBACK(scripts_prepare_clicked_cb), state);
    gtk_box_append(GTK_BOX(row), button);
    button = make_icon_text_button("cmd_command", "Command Line", state->ribbon_density > 0 ? 22 : 30);
    g_signal_connect(button, "clicked", G_CALLBACK(command_focus_clicked_cb), state);
    gtk_box_append(GTK_BOX(row), button);
    gtk_box_append(GTK_BOX(outer), row);
    gtk_box_append(GTK_BOX(outer), make_label("Scripts", "wc-ribbon-group-label"));
    gtk_frame_set_child(GTK_FRAME(frame), outer);
    gtk_box_append(GTK_BOX(state->ribbon_commands_box), frame);
}

static void build_ribbon_commands(WcGtk4State *state, const WcGtk4RibbonSnapshot *ribbon)
{
    size_t i;
    const char *last_group = NULL;
    GtkWidget *group_rows = NULL;
    GtkWidget *row_box = NULL;
    size_t row_count = 0;
    int compact = 0;
    if (state == NULL || state->ribbon_commands_box == NULL)
        return;
    clear_children(state->ribbon_commands_box);
    if (strcmp(state->active_ribbon_tab, "global.sections") == 0) {
        build_sections_ribbon_commands(state);
        return;
    }
    if (strcmp(state->active_ribbon_tab, "global.mods") == 0) {
        build_mods_ribbon_commands(state);
        return;
    }
    if (ribbon == NULL) {
        gtk_box_append(GTK_BOX(state->ribbon_commands_box),
                       make_label("This Section does not have a contextual ribbon yet.", "wc-subtle"));
        return;
    }

    for (i = 0; i < ribbon->command_count; ++i) {
        const WcGtk4RibbonCommand *command = &ribbon->commands[i];
        if (command->tab_id == NULL || strcmp(command->tab_id, state->active_ribbon_tab) != 0)
            continue;
        if (last_group == NULL || command->group_id == NULL || strcmp(last_group, command->group_id) != 0) {
            char group_label[96];
            GtkWidget *frame;
            GtkWidget *outer;
            size_t group_count = command_group_count(ribbon, state->active_ribbon_tab,
                                                     command->group_id != NULL ? command->group_id : "group");
            humanise_identifier(command->group_id != NULL ? command->group_id : "group", group_label, sizeof(group_label));
            frame = gtk_frame_new(NULL);
            gtk_widget_add_css_class(frame, "wc-ribbon-group");
            outer = gtk_box_new(GTK_ORIENTATION_VERTICAL, 1);
            group_rows = gtk_box_new(GTK_ORIENTATION_VERTICAL, 1);
            gtk_box_append(GTK_BOX(outer), group_rows);
            {
                GtkWidget *caption = gtk_label_new(group_label);
                gtk_widget_add_css_class(caption, "wc-ribbon-group-label");
                gtk_box_append(GTK_BOX(outer), caption);
            }
            gtk_frame_set_child(GTK_FRAME(frame), outer);
            gtk_box_append(GTK_BOX(state->ribbon_commands_box), frame);
            last_group = command->group_id;
            row_box = NULL;
            row_count = 0;
            compact = ribbon_compact_mode(state, group_count);
        }
        if (row_box == NULL || row_count == 4) {
            row_box = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 1);
            gtk_box_append(GTK_BOX(group_rows), row_box);
            row_count = 0;
        }
        gtk_box_append(GTK_BOX(row_box), make_ribbon_command_button(state, command, compact));
        ++row_count;
    }
    if (strstr(state->active_ribbon_tab, ".home") != NULL)
        append_scripts_home_group(state);
}

static GtkWidget *make_sketch_tool_button(const char *icon, const char *label, GCallback callback, WcGtk4State *state)
{
    GtkWidget *button = make_icon_text_button(icon, label, 24);
    gtk_widget_set_size_request(button, 62, 52);
    gtk_widget_add_css_class(button, "wc-ribbon-command-compact");
    g_signal_connect(button, "clicked", callback, state);
    return button;
}

static void build_sketch_ribbon(WcGtk4State *state)
{
    GtkWidget *draw_frame, *draw_outer, *draw_row, *finish_frame, *finish_outer;
    char title[192];
    clear_children(state->ribbon_tabs_box);
    clear_children(state->ribbon_commands_box);
    gtk_box_append(GTK_BOX(state->ribbon_tabs_box), make_ribbon_tab_button(state, "global.sections", "Sections"));
    gtk_box_append(GTK_BOX(state->ribbon_tabs_box), make_ribbon_tab_button(state, "global.mods", "Mods"));
    (void)snprintf(title, sizeof(title), "Sketch • %s", state->active_sketch_name);
    gtk_box_append(GTK_BOX(state->ribbon_tabs_box), make_ribbon_tab_button(state, "sketch.edit", title));
    if (strcmp(state->active_ribbon_tab, "global.sections") == 0) {
        build_sections_ribbon_commands(state);
        return;
    }
    if (strcmp(state->active_ribbon_tab, "global.mods") == 0) {
        build_mods_ribbon_commands(state);
        return;
    }
    if (strcmp(state->active_ribbon_tab, "sketch.edit") != 0)
        copy_text(state->active_ribbon_tab, sizeof(state->active_ribbon_tab), "sketch.edit");

    draw_frame = gtk_frame_new(NULL);
    gtk_widget_add_css_class(draw_frame, "wc-ribbon-group");
    draw_outer = gtk_box_new(GTK_ORIENTATION_VERTICAL, 1);
    draw_row = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 1);
    gtk_box_append(GTK_BOX(draw_row), make_sketch_tool_button("cmd_line", "Line", G_CALLBACK(sketch_line_tool_cb), state));
    gtk_box_append(GTK_BOX(draw_row), make_sketch_tool_button("cmd_circle", "Circle", G_CALLBACK(sketch_circle_tool_cb), state));
    gtk_box_append(GTK_BOX(draw_row), make_sketch_tool_button("cmd_rectangle", "Rectangle", G_CALLBACK(sketch_rectangle_tool_cb), state));
    gtk_box_append(GTK_BOX(draw_outer), draw_row);
    gtk_box_append(GTK_BOX(draw_outer), make_label("Draw", "wc-ribbon-group-label"));
    gtk_frame_set_child(GTK_FRAME(draw_frame), draw_outer);
    gtk_box_append(GTK_BOX(state->ribbon_commands_box), draw_frame);

    finish_frame = gtk_frame_new(NULL);
    gtk_widget_add_css_class(finish_frame, "wc-ribbon-group");
    finish_outer = gtk_box_new(GTK_ORIENTATION_VERTICAL, 1);
    gtk_box_append(GTK_BOX(finish_outer), make_sketch_tool_button("cmd_finish_sketch", "Finish Sketch", G_CALLBACK(finish_sketch_clicked_cb), state));
    gtk_box_append(GTK_BOX(finish_outer), make_label("Sketch", "wc-ribbon-group-label"));
    gtk_frame_set_child(GTK_FRAME(finish_frame), finish_outer);
    gtk_box_append(GTK_BOX(state->ribbon_commands_box), finish_frame);
}

static void rebuild_ribbon(WcGtk4State *state)
{
    const WcGtk4RibbonSnapshot *ribbon = get_active_ribbon(state);
    size_t i;
    if (state == NULL || state->ribbon_tabs_box == NULL)
        return;
    if (state->sketch_mode) {
        build_sketch_ribbon(state);
        return;
    }
    clear_children(state->ribbon_tabs_box);

    gtk_box_append(GTK_BOX(state->ribbon_tabs_box), make_ribbon_tab_button(state, "global.sections", "Sections"));
    gtk_box_append(GTK_BOX(state->ribbon_tabs_box), make_ribbon_tab_button(state, "global.mods", "Mods"));

    if (ribbon == NULL || ribbon->tab_count == 0) {
        if (!ribbon_has_tab(ribbon, state->active_ribbon_tab))
            copy_text(state->active_ribbon_tab, sizeof(state->active_ribbon_tab), "global.sections");
        build_ribbon_commands(state, ribbon);
        return;
    }

    if (!ribbon_has_tab(ribbon, state->active_ribbon_tab))
        copy_text(state->active_ribbon_tab, sizeof(state->active_ribbon_tab), ribbon->tabs[0].id);

    for (i = 0; i < ribbon->tab_count; ++i) {
        char label[96];
        GtkWidget *button;
        WcRibbonButtonData *data;
        humanise_identifier(ribbon->tabs[i].id, label, sizeof(label));
        button = gtk_button_new_with_label(label);
        gtk_widget_add_css_class(button, "wc-ribbon-tab");
        if (ribbon->tabs[i].id != NULL && strcmp(ribbon->tabs[i].id, state->active_ribbon_tab) == 0)
            gtk_widget_add_css_class(button, "wc-ribbon-tab-active");
        data = g_new0(WcRibbonButtonData, 1);
        data->state = state;
        copy_text(data->id, sizeof(data->id), ribbon->tabs[i].id);
        g_signal_connect_data(button, "clicked", G_CALLBACK(ribbon_tab_clicked_cb), data,
                              free_signal_data, 0);
        gtk_box_append(GTK_BOX(state->ribbon_tabs_box), button);
    }
    build_ribbon_commands(state, ribbon);
}

static void ribbon_tab_clicked_cb(GtkButton *button, gpointer user_data)
{
    WcRibbonButtonData *data = (WcRibbonButtonData *)user_data;
    (void)button;
    if (data == NULL || data->state == NULL)
        return;
    copy_text(data->state->active_ribbon_tab, sizeof(data->state->active_ribbon_tab), data->id);
    rebuild_ribbon(data->state);
}

static void choose_section(WcGtk4State *state, const char *section_id)
{
    int ok = 0;
    if (state != NULL && state->sketch_mode && section_id != NULL && strcmp(section_id, "modelling") != 0) {
        finish_sketch(state);
        if (state->sketch_mode)
            return;
    }
    if (state != NULL && state->callbacks != NULL && state->callbacks->choose_section != NULL)
        ok = state->callbacks->choose_section(state->user_data, section_id);
    if (!ok) {
        gtk_label_set_text(GTK_LABEL(state->command_status), "Section change rejected");
        return;
    }
    state->active_ribbon_tab[0] = '\0';
    rebuild_ribbon(state);
    update_status(state);
}

static void section_button_clicked_cb(GtkButton *button, gpointer user_data)
{
    WcSectionButtonData *data = (WcSectionButtonData *)user_data;
    (void)button;
    if (data != NULL && data->state != NULL)
        choose_section(data->state, data->id);
}




static void scripts_prepare_clicked_cb(GtkButton *button, gpointer user_data)
{
    WcGtk4State *state = (WcGtk4State *)user_data;
    (void)button;
    if (state == NULL)
        return;
    open_path_chooser(state, GTK_WINDOW(state->window), NULL,
                      WC_PATH_CHOOSER_RUN_SCRIPT, "Run Script",
                      GTK_FILE_CHOOSER_ACTION_OPEN, "script", NULL);
}

static void command_focus_clicked_cb(GtkButton *button, gpointer user_data)
{
    WcGtk4State *state = (WcGtk4State *)user_data;
    (void)button;
    if (state != NULL)
        gtk_widget_grab_focus(state->command_entry);
}



static gboolean scroll_cb(GtkEventControllerScroll *controller, double dx, double dy, gpointer user_data)
{
    WcGtk4State *state = (WcGtk4State *)user_data;
    double factor;
    double old_zoom;
    int width, height;
    double px, py;
    (void)controller;
    (void)dx;
    if (state == NULL)
        return FALSE;
    factor = pow(1.14, -dy);
    old_zoom = state->zoom;
    state->zoom = clamp_double(old_zoom * factor, 0.05, 40.0);
    factor = state->zoom / old_zoom;
    width = gtk_widget_get_width(state->drawing_area);
    height = gtk_widget_get_height(state->drawing_area);
    px = state->pointer_valid ? state->pointer_x : width * 0.5;
    py = state->pointer_valid ? state->pointer_y : height * 0.5;

    /* Keep the model/sketch point under the cursor fixed while zooming. */
    state->pan_x = px - width * 0.5 - factor * (px - width * 0.5 - state->pan_x);
    state->pan_y = py - height * 0.5 - factor * (py - height * 0.5 - state->pan_y);
    gtk_widget_queue_draw(state->drawing_area);
    return TRUE;
}

static void orbit_drag_begin_cb(GtkGestureDrag *gesture, double start_x, double start_y, gpointer user_data)
{
    WcGtk4State *state = (WcGtk4State *)user_data;
    (void)gesture;
    (void)start_x;
    (void)start_y;
    if (state == NULL)
        return;
    state->drag_yaw = state->yaw;
    state->drag_pitch = state->pitch;
    state->drag_pan_x = state->pan_x;
    state->drag_pan_y = state->pan_y;
    gtk_widget_grab_focus(state->drawing_area);
}

static void orbit_drag_update_cb(GtkGestureDrag *gesture, double offset_x, double offset_y, gpointer user_data)
{
    WcGtk4State *state = (WcGtk4State *)user_data;
    (void)gesture;
    if (state == NULL)
        return;
    if (state->sketch_mode) {
        state->pan_x = state->drag_pan_x + offset_x;
        state->pan_y = state->drag_pan_y + offset_y;
    } else {
        state->yaw = state->drag_yaw + offset_x * 0.008;
        state->pitch = clamp_double(state->drag_pitch + offset_y * 0.008, -1.48, 1.48);
    }
    gtk_widget_queue_draw(state->drawing_area);
}

static void viewport_pressed_cb(GtkGestureClick *gesture, int n_press, double x, double y, gpointer user_data)
{
    WcGtk4State *state = (WcGtk4State *)user_data;
    int width, height;
    double sx, sy;
    (void)gesture;
    (void)n_press;
    if (state == NULL) return;
    state->pointer_x = x;
    state->pointer_y = y;
    state->pointer_valid = 1;
    gtk_widget_grab_focus(state->drawing_area);
    width = gtk_widget_get_width(state->drawing_area);
    height = gtk_widget_get_height(state->drawing_area);

    if (!state->sketch_mode) {
        uint32_t owner_id = 0;
        uint64_t face_id = 0;
        uint32_t body_id = 0;
        uint32_t csys_id = 0;
        char csys_plane[4] = {0};
        if (state->feature_pick_ui != NULL) {
            WcFeatureDialogueUi *ui = state->feature_pick_ui;
            const WcFeatureDialogueFieldDescriptorV1 *field = NULL;
            uint32_t picked = 0;
            char picked_name[WC_UI_ID_CAPACITY];
            if (ui->descriptor != NULL && state->feature_pick_field_index < ui->descriptor->field_count)
                field = &ui->descriptor->fields[state->feature_pick_field_index];
            if (field != NULL) {
                if (field->selection_kind == WC_FEATURE_DIALOGUE_SELECTION_PROFILE)
                    picked = hit_test_sketch(state, width, height, x, y);
                else if (field->selection_kind == WC_FEATURE_DIALOGUE_SELECTION_BODY)
                    picked = hit_test_body(state, width, height, x, y);
                else if (field->selection_kind == WC_FEATURE_DIALOGUE_SELECTION_ANY_FEATURE) {
                    picked = hit_test_body(state, width, height, x, y);
                    if (picked == 0)
                        picked = hit_test_sketch(state, width, height, x, y);
                }
            }
            if (picked != 0 && feature_name_for_id(state, picked, picked_name, sizeof(picked_name))) {
                int accepted = feature_dialogue_accept_pick(state, picked, picked_name);
                if (accepted)
                    select_model_feature(state, picked, field != NULL && field->selection_kind == WC_FEATURE_DIALOGUE_SELECTION_BODY);
            } else {
                gtk_label_set_text(GTK_LABEL(state->command_status),
                    field != NULL && field->selection_kind == WC_FEATURE_DIALOGUE_SELECTION_PATH
                        ? "Path picking is available from Model Navigator; select a path feature there"
                        : "No acceptable feature under the pointer — try the visible sketch/profile or Model Navigator");
            }
            gtk_widget_queue_draw(state->drawing_area);
            return;
        }
        if (state->sketch_support_mode)
            face_id = hit_test_planar_face(state, width, height, x, y, &owner_id);
        if (state->sketch_support_mode && face_id != 0) {
            WcGtk4SketchSupport support;
            state->selected_support_kind = WC_GTK4_SKETCH_SUPPORT_PLANAR_FACE;
            state->selected_support_feature_id = owner_id;
            state->selected_face_persistent_id = face_id;
            state->selected_csys_plane[0] = '\0';
            state->selected_feature_id = owner_id;
            state->selected_row_is_feature = 0;
            if (state->sketch_support_mode && selected_support(state, &support))
                create_sketch_on_support(state, &support);
            else
                gtk_label_set_text(GTK_LABEL(state->command_status),
                    "Planar face selected — click Sketch to create a sketch on this face");
            gtk_widget_queue_draw(state->drawing_area);
            return;
        }
        if (state->sketch_support_mode &&
            hit_test_csys_plane(state, width, height, x, y, &csys_id, csys_plane, sizeof(csys_plane))) {
            WcGtk4SketchSupport support;
            state->selected_support_kind = WC_GTK4_SKETCH_SUPPORT_CSYS_PLANE;
            state->selected_support_feature_id = csys_id;
            state->selected_face_persistent_id = 0;
            copy_text(state->selected_csys_plane, sizeof(state->selected_csys_plane), csys_plane);
            state->selected_feature_id = csys_id;
            state->selected_row_is_feature = 0;
            if (selected_support(state, &support))
                create_sketch_on_support(state, &support);
            gtk_widget_queue_draw(state->drawing_area);
            return;
        }
        if (!state->sketch_support_mode) {
            body_id = hit_test_body(state, width, height, x, y);
            if (body_id == 0) {
                face_id = hit_test_planar_face(state, width, height, x, y, &owner_id);
                if (face_id != 0)
                    body_id = owner_id;
            }
            if (body_id != 0) {
                state->selected_support_kind = WC_GTK4_SKETCH_SUPPORT_NONE;
                state->selected_support_feature_id = 0;
                state->selected_face_persistent_id = 0;
                state->selected_csys_plane[0] = '\0';
                select_model_feature(state, body_id, 1);
                gtk_label_set_text(GTK_LABEL(state->command_status),
                                   "Body selected — right-click for Properties / Fit / Delete");
                gtk_widget_queue_draw(state->drawing_area);
                return;
            }
        }
        if (state->sketch_support_mode)
            gtk_label_set_text(GTK_LABEL(state->command_status),
                "Sketch support required — select a planar face here or a datum/CSYS plane in Model Navigator");
        else {
            state->selected_body_feature_id = 0;
            update_navigator_descendant_highlight(state);
            gtk_label_set_text(GTK_LABEL(state->command_status),
                "Viewport focus — wheel zoom, middle-drag orbit, WASD pan, Enter for command line");
        }
        return;
    }

    update_snap_candidates(state, width, height, x, y);
    if (state->snap_candidate_count > 1 && state->snap_ambiguity_ready && !state->snap_choice_locked) {
        show_snap_choice_dialogue(state);
        return;
    }
    screen_to_sketch(state, width, height, x, y, &sx, &sy);
    if (state->snap_choice_locked) {
        WcSnapCandidate candidate = state->snap_choice;
        commit_sketch_point(state, candidate.x, candidate.y, candidate.feature_id, candidate.point_index);
    } else if (state->snap_candidate_count > 0) {
        WcSnapCandidate candidate = state->snap_candidates[0];
        commit_sketch_point(state, candidate.x, candidate.y, candidate.feature_id, candidate.point_index);
    } else {
        commit_sketch_point(state, sx, sy, 0u, 0u);
    }
}

static void viewport_fit_all_cb(GtkButton *button, gpointer user_data)
{
    WcGtk4State *state = (WcGtk4State *)user_data;
    (void)button;
    fit_all(state);
    if (state != NULL)
        gtk_label_set_text(GTK_LABEL(state->command_status), "Fit — whole model");
}

static void viewport_fit_selected_cb(GtkButton *button, gpointer user_data)
{
    WcGtk4State *state = (WcGtk4State *)user_data;
    (void)button;
    if (state == NULL || state->selected_body_feature_id == 0 ||
        !fit_feature(state, state->selected_body_feature_id)) {
        if (state != NULL)
            gtk_label_set_text(GTK_LABEL(state->command_status), "No selected body with display bounds");
        return;
    }
    gtk_label_set_text(GTK_LABEL(state->command_status), "Fit — selected body");
}

static void viewport_properties_cb(GtkButton *button, gpointer user_data)
{
    WcGtk4State *state = (WcGtk4State *)user_data;
    (void)button;
    if (state != NULL && state->selected_feature_id != 0) {
        const WcFeatureDialogueDescriptorV1 *dialogue = NULL;
        if (state->callbacks != NULL && state->callbacks->feature_dialogue_for_feature != NULL)
            dialogue = state->callbacks->feature_dialogue_for_feature(
                state->user_data, state->selected_feature_id);
        if (dialogue != NULL)
            show_feature_dialogue(state, dialogue, state->selected_feature_id);
        else
            show_feature_properties(state, state->selected_feature_id);
    }
}

static void viewport_context_pressed_cb(GtkGestureClick *gesture, int n_press, double x, double y, gpointer user_data)
{
    WcGtk4State *state = (WcGtk4State *)user_data;
    GtkWidget *popover;
    GtkWidget *box;
    GtkWidget *button;
    GdkRectangle rectangle;
    int width, height;
    uint32_t hit;
    (void)gesture; (void)n_press;
    if (state == NULL || state->sketch_mode)
        return;
    width = gtk_widget_get_width(state->drawing_area);
    height = gtk_widget_get_height(state->drawing_area);
    hit = hit_test_body(state, width, height, x, y);
    if (hit != 0)
        select_model_feature(state, hit, 1);

    popover = gtk_popover_new();
    box = gtk_box_new(GTK_ORIENTATION_VERTICAL, 2);
    button = gtk_button_new_with_label("Fit");
    g_signal_connect(button, "clicked", G_CALLBACK(viewport_fit_all_cb), state);
    gtk_box_append(GTK_BOX(box), button);
    button = gtk_button_new_with_label("Fit Selected");
    gtk_widget_set_sensitive(button, state->selected_body_feature_id != 0);
    g_signal_connect(button, "clicked", G_CALLBACK(viewport_fit_selected_cb), state);
    gtk_box_append(GTK_BOX(box), button);
    button = gtk_button_new_with_label("Properties");
    gtk_widget_set_sensitive(button, state->selected_feature_id != 0);
    g_signal_connect(button, "clicked", G_CALLBACK(viewport_properties_cb), state);
    gtk_box_append(GTK_BOX(box), button);
    gtk_popover_set_child(GTK_POPOVER(popover), box);
    gtk_widget_set_parent(popover, state->drawing_area);
    rectangle.x = (int)x; rectangle.y = (int)y; rectangle.width = 1; rectangle.height = 1;
    gtk_popover_set_pointing_to(GTK_POPOVER(popover), &rectangle);
    gtk_popover_popup(GTK_POPOVER(popover));
    gtk_widget_queue_draw(state->drawing_area);
}

static void viewport_motion_cb(GtkEventControllerMotion *controller, double x, double y, gpointer user_data)
{
    WcGtk4State *state = (WcGtk4State *)user_data;
    int width, height;
    (void)controller;
    if (state == NULL) return;
    state->pointer_x = x;
    state->pointer_y = y;
    state->pointer_valid = 1;
    width = gtk_widget_get_width(state->drawing_area);
    height = gtk_widget_get_height(state->drawing_area);
    if (state->sketch_mode) {
        update_snap_candidates(state, width, height, x, y);
        screen_to_sketch(state, width, height, x, y, &state->sketch_cursor_x, &state->sketch_cursor_y);
        if (state->snap_choice_locked) {
            state->sketch_cursor_x = state->snap_choice.x;
            state->sketch_cursor_y = state->snap_choice.y;
        } else if (state->snap_candidate_count > 0) {
            state->sketch_cursor_x = state->snap_candidates[0].x;
            state->sketch_cursor_y = state->snap_candidates[0].y;
        }
        state->sketch_cursor_valid = 1;
        gtk_widget_queue_draw(state->drawing_area);
    } else {
        uint32_t owner = 0;
        uint64_t face = hit_test_planar_face(state, width, height, x, y, &owner);
        if (face != state->hover_face_persistent_id || owner != state->hover_face_owner_id) {
            state->hover_face_persistent_id = face;
            state->hover_face_owner_id = owner;
            gtk_widget_queue_draw(state->drawing_area);
        }
    }
}

static gboolean key_pressed_cb(GtkEventControllerKey *controller, guint keyval, guint keycode,
                               GdkModifierType modifiers, gpointer user_data)
{
    WcGtk4State *state = (WcGtk4State *)user_data;
    GtkWidget *focus;
    double step;
    (void)controller;
    (void)keycode;
    if (state == NULL)
        return FALSE;

    if (keyval == GDK_KEY_Escape) {
        if (state->feature_pick_ui != NULL) {
            WcFeatureDialogueUi *ui = state->feature_pick_ui;
            state->feature_pick_ui = NULL;
            state->feature_pick_field_index = 0;
            gtk_label_set_text(GTK_LABEL(state->command_status), "Feature selection cancelled");
            if (ui->window != NULL)
                gtk_window_present(GTK_WINDOW(ui->window));
            return TRUE;
        }
        if (state->sketch_mode && state->sketch_has_anchor) {
            state->sketch_has_anchor = 0;
            gtk_label_set_text(GTK_LABEL(state->command_status), "Current sketch entity cancelled");
            gtk_widget_queue_draw(state->drawing_area);
        }
        gtk_widget_grab_focus(state->drawing_area);
        return TRUE;
    }

    focus = gtk_window_get_focus(GTK_WINDOW(state->window));
    if (focus != NULL && GTK_IS_EDITABLE(focus))
        return FALSE;

    if (keyval == GDK_KEY_Return || keyval == GDK_KEY_KP_Enter) {
        gtk_widget_grab_focus(state->command_entry);
        return TRUE;
    }

    step = (modifiers & GDK_SHIFT_MASK) != 0 ? 42.0 : 18.0;
    switch (keyval) {
        case GDK_KEY_w:
        case GDK_KEY_W:
            state->pan_y += step;
            break;
        case GDK_KEY_s:
        case GDK_KEY_S:
            state->pan_y -= step;
            break;
        case GDK_KEY_a:
        case GDK_KEY_A:
            state->pan_x += step;
            break;
        case GDK_KEY_d:
        case GDK_KEY_D:
            state->pan_x -= step;
            break;
        case GDK_KEY_Home:
            state->zoom = 1.0;
            state->pan_x = 0.0;
            state->pan_y = 0.0;
            state->yaw = -M_PI / 4.0;
            state->pitch = M_PI / 5.5;
            break;
        default:
            return FALSE;
    }
    gtk_widget_queue_draw(state->drawing_area);
    return TRUE;
}

static void navigator_model_clicked_cb(GtkButton *button, gpointer user_data)
{
    WcGtk4State *state = (WcGtk4State *)user_data;
    (void)button;
    gtk_stack_set_visible_child_name(GTK_STACK(state->navigator_stack), "model");
    if (state->navigator_paned != NULL && gtk_paned_get_position(GTK_PANED(state->navigator_paned)) < 40)
        gtk_paned_set_position(GTK_PANED(state->navigator_paned), 210);
}

static void navigator_assembly_clicked_cb(GtkButton *button, gpointer user_data)
{
    WcGtk4State *state = (WcGtk4State *)user_data;
    (void)button;
    gtk_stack_set_visible_child_name(GTK_STACK(state->navigator_stack), "assembly");
    if (state->navigator_paned != NULL && gtk_paned_get_position(GTK_PANED(state->navigator_paned)) < 40)
        gtk_paned_set_position(GTK_PANED(state->navigator_paned), 210);
}

static void navigator_ai_clicked_cb(GtkButton *button, gpointer user_data)
{
    WcGtk4State *state = (WcGtk4State *)user_data;
    (void)button;
    update_ai_summary(state);
    gtk_stack_set_visible_child_name(GTK_STACK(state->navigator_stack), "ai");
    if (state->navigator_paned != NULL && gtk_paned_get_position(GTK_PANED(state->navigator_paned)) < 40)
        gtk_paned_set_position(GTK_PANED(state->navigator_paned), 210);
}

static void ai_inspect_clicked_cb(GtkButton *button, gpointer user_data)
{
    WcGtk4State *state = (WcGtk4State *)user_data;
    (void)button;
    update_ai_summary(state);
    gtk_label_set_text(GTK_LABEL(state->command_status), "AI Agent refreshed read-only model summary");
}

static GtkWidget *make_rail_button(const char *icon_name, const char *tooltip)
{
    GtkWidget *button = gtk_button_new();
    gtk_button_set_child(GTK_BUTTON(button), load_svg_image(icon_name, 24));
    gtk_widget_set_tooltip_text(button, tooltip);
    gtk_widget_add_css_class(button, "wc-rail-button");
    gtk_widget_set_size_request(button, 42, 42);
    return button;
}

static void model_row_selected_cb(GtkListBox *box, GtkListBoxRow *row, gpointer user_data)
{
    WcGtk4State *state = (WcGtk4State *)user_data;
    uint64_t *face_id;
    WcGtk4SketchSupport support;
    (void)box;
    if (state == NULL) return;
    state->selected_feature_id = 0;
    state->selected_feature_kind = 0;
    state->selected_feature_exact_status = 0;
    state->selected_feature_depth = 0;
    state->selected_feature_name[0] = '\0';
    state->selected_body_feature_id = 0;
    state->selected_support_kind = WC_GTK4_SKETCH_SUPPORT_NONE;
    state->selected_support_feature_id = 0;
    state->selected_face_persistent_id = 0;
    state->selected_csys_plane[0] = '\0';
    state->selected_row_is_feature = 0;
    if (row == NULL) return;
    state->selected_feature_id = GPOINTER_TO_UINT(g_object_get_data(G_OBJECT(row), "wc-feature-id"));
    state->selected_feature_kind = GPOINTER_TO_UINT(g_object_get_data(G_OBJECT(row), "wc-feature-kind"));
    state->selected_feature_exact_status = GPOINTER_TO_UINT(g_object_get_data(G_OBJECT(row), "wc-exact-status"));
    state->selected_feature_depth = GPOINTER_TO_UINT(g_object_get_data(G_OBJECT(row), "wc-depth"));
    state->selected_support_kind = GPOINTER_TO_UINT(g_object_get_data(G_OBJECT(row), "wc-support-kind"));
    state->selected_support_feature_id = GPOINTER_TO_UINT(g_object_get_data(G_OBJECT(row), "wc-support-feature-id"));
    state->selected_row_is_feature = GPOINTER_TO_INT(g_object_get_data(G_OBJECT(row), "wc-real-feature"));
    {
        const char *row_name = (const char *)g_object_get_data(G_OBJECT(row), "wc-row-name");
        if (row_name != NULL)
            copy_text(state->selected_feature_name, sizeof(state->selected_feature_name), row_name);
    }
    face_id = (uint64_t *)g_object_get_data(G_OBJECT(row), "wc-face-id");
    if (face_id != NULL) state->selected_face_persistent_id = *face_id;
    {
        const char *plane = (const char *)g_object_get_data(G_OBJECT(row), "wc-csys-plane");
        if (plane != NULL) copy_text(state->selected_csys_plane, sizeof(state->selected_csys_plane), plane);
    }
    if (state->selected_row_is_feature && body_bounds_for_feature(state, state->selected_feature_id, NULL))
        state->selected_body_feature_id = state->selected_feature_id;
    update_navigator_descendant_highlight(state);
    if (state->feature_pick_ui != NULL && state->selected_row_is_feature) {
        (void)feature_dialogue_accept_pick(state, state->selected_feature_id, state->selected_feature_name);
        gtk_widget_queue_draw(state->drawing_area);
        return;
    }
    if (state->sketch_support_mode && selected_support(state, &support))
        create_sketch_on_support(state, &support);
    gtk_widget_queue_draw(state->drawing_area);
}

static void model_row_activated_cb(GtkListBox *box, GtkListBoxRow *row, gpointer user_data)
{
    WcGtk4State *state = (WcGtk4State *)user_data;
    uint32_t feature_id;
    uint32_t kind;
    (void)box;
    if (state == NULL || row == NULL) return;
    if (state->active_feature_dialogue_ui != NULL &&
        state->active_feature_dialogue_ui->window != NULL &&
        gtk_widget_get_visible(state->active_feature_dialogue_ui->window))
        return;
    if (!GPOINTER_TO_INT(g_object_get_data(G_OBJECT(row), "wc-real-feature"))) return;
    feature_id = GPOINTER_TO_UINT(g_object_get_data(G_OBJECT(row), "wc-feature-id"));
    kind = GPOINTER_TO_UINT(g_object_get_data(G_OBJECT(row), "wc-feature-kind"));
    state->selected_feature_id = feature_id;
    state->selected_feature_kind = kind;
    state->selected_row_is_feature = 1;
    if (state->callbacks != NULL && state->callbacks->feature_dialogue_for_feature != NULL) {
        const WcFeatureDialogueDescriptorV1 *dialogue =
            state->callbacks->feature_dialogue_for_feature(state->user_data, feature_id);
        if (dialogue != NULL) {
            show_feature_dialogue(state, dialogue, feature_id);
            return;
        }
    }
    /* Unsupported/derived features still get a useful read-only properties window. */
    show_feature_properties(state, feature_id);
}

static void run_feature_action(WcGtk4State *state, int action)
{
    int status;
    uint32_t feature_id;
    char message[192];
    if (state == NULL || state->selected_feature_id == 0 || !state->selected_row_is_feature || state->callbacks == NULL || state->callbacks->feature_action == NULL) {
        if (state != NULL)
            gtk_label_set_text(GTK_LABEL(state->command_status), "Select a model-history feature first");
        return;
    }
    feature_id = state->selected_feature_id;
    status = state->callbacks->feature_action(state->user_data, feature_id, action);
    if (status != 0) {
        if (action == 0)
            (void)snprintf(message, sizeof(message), "Delete rejected (SCL error %d). A dependent feature may still reference it.", status);
        else
            (void)snprintf(message, sizeof(message), "Reorder rejected (SCL error %d). Dependency order must be preserved.", status);
        gtk_label_set_text(GTK_LABEL(state->command_status), message);
        return;
    }
    if (action == 0 && feature_id == state->active_sketch_id) {
        state->sketch_mode = 0;
        state->active_sketch_id = 0;
        state->active_sketch_name[0] = '\0';
        state->sketch_has_anchor = 0;
        rebuild_ribbon(state);
    }
    if (action == 0) {
        state->selected_feature_id = 0;
        state->selected_body_feature_id = 0;
        state->selected_feature_name[0] = '\0';
        state->fit_bounds_valid = 0;
    }
    update_status(state);
    gtk_widget_queue_draw(state->drawing_area);
    gtk_label_set_text(GTK_LABEL(state->command_status), action == 0 ? "Feature deleted" : "Feature reordered");
}

static void show_mass_properties(WcGtk4State *state, uint32_t feature_id)
{
    WcGtk4MassProperties properties;
    GtkWidget *window;
    GtkWidget *box;
    GtkWidget *title;
    GtkWidget *details;
    char text[512];
    int status;
    if (state == NULL || feature_id == 0 || state->callbacks == NULL ||
        state->callbacks->mass_properties == NULL)
        return;
    memset(&properties, 0, sizeof(properties));
    status = state->callbacks->mass_properties(state->user_data, feature_id, &properties);
    if (status != 0 || !properties.valid) {
        gtk_label_set_text(GTK_LABEL(state->command_status),
                           "Mass properties require supported exact solid geometry");
        return;
    }

    window = gtk_window_new();
    gtk_window_set_title(GTK_WINDOW(window), "Mass Properties");
    gtk_window_set_default_size(GTK_WINDOW(window), 390, 260);
    gtk_window_set_transient_for(GTK_WINDOW(window), GTK_WINDOW(state->window));
    box = gtk_box_new(GTK_ORIENTATION_VERTICAL, 8);
    gtk_widget_set_margin_top(box, 12);
    gtk_widget_set_margin_bottom(box, 12);
    gtk_widget_set_margin_start(box, 12);
    gtk_widget_set_margin_end(box, 12);
    title = make_label(state->selected_feature_name[0] != '\0' ?
                       state->selected_feature_name : "Feature", "wc-title");
    gtk_box_append(GTK_BOX(box), title);
    (void)snprintf(text, sizeof(text),
                   "Volume: %.9g\\nSurface area: %.9g\\n\\nCentre of mass\\nX: %.9g\\nY: %.9g\\nZ: %.9g",
                   properties.volume, properties.surface_area,
                   properties.centre_of_mass[0], properties.centre_of_mass[1],
                   properties.centre_of_mass[2]);
    details = make_label(text, "wc-subtle");
    gtk_label_set_selectable(GTK_LABEL(details), TRUE);
    gtk_box_append(GTK_BOX(box), details);
    gtk_window_set_child(GTK_WINDOW(window), box);
    gtk_window_present(GTK_WINDOW(window));
}

static void show_feature_properties(WcGtk4State *state, uint32_t feature_id)
{
    GtkWidget *window;
    GtkWidget *box;
    GtkWidget *title;
    GtkWidget *details;
    WcGtk4BodyRow body;
    char text[768];
    GtkListBoxRow *row;
    if (state == NULL || feature_id == 0)
        return;
    row = model_row_for_feature(state, feature_id);
    if (row != NULL)
        gtk_list_box_select_row(GTK_LIST_BOX(state->model_list), row);
    window = gtk_window_new();
    gtk_window_set_title(GTK_WINDOW(window), "Feature Properties");
    gtk_window_set_default_size(GTK_WINDOW(window), 360, 250);
    gtk_window_set_transient_for(GTK_WINDOW(window), GTK_WINDOW(state->window));
    gtk_window_set_modal(GTK_WINDOW(window), FALSE);
    box = gtk_box_new(GTK_ORIENTATION_VERTICAL, 8);
    gtk_widget_set_margin_top(box, 12);
    gtk_widget_set_margin_bottom(box, 12);
    gtk_widget_set_margin_start(box, 12);
    gtk_widget_set_margin_end(box, 12);
    title = make_label(state->selected_feature_name[0] != '\0' ? state->selected_feature_name : "Feature", "wc-title");
    gtk_box_append(GTK_BOX(box), title);
    if (body_bounds_for_feature(state, feature_id, &body)) {
        (void)snprintf(text, sizeof(text),
            "Feature ID: %u\nKind: %u\nGeometry: %s\nDependency depth: %u\n\nBounds\nX: %.6g .. %.6g\nY: %.6g .. %.6g\nZ: %.6g .. %.6g",
            feature_id, state->selected_feature_kind,
            exact_status_text(state->selected_feature_exact_status), state->selected_feature_depth,
            body.min_x, body.max_x, body.min_y, body.max_y, body.min_z, body.max_z);
    } else {
        (void)snprintf(text, sizeof(text),
            "Feature ID: %u\nKind: %u\nGeometry: %s\nDependency depth: %u",
            feature_id, state->selected_feature_kind,
            exact_status_text(state->selected_feature_exact_status), state->selected_feature_depth);
    }
    details = make_label(text, "wc-subtle");
    gtk_label_set_selectable(GTK_LABEL(details), TRUE);
    gtk_box_append(GTK_BOX(box), details);
    gtk_window_set_child(GTK_WINDOW(window), box);
    gtk_window_present(GTK_WINDOW(window));
}

static void feature_menu_properties_cb(GtkButton *button, gpointer user_data)
{
    WcFeatureMenuData *data = (WcFeatureMenuData *)user_data;
    const WcFeatureDialogueDescriptorV1 *dialogue = NULL;
    (void)button;
    if (data == NULL || data->state == NULL)
        return;
    if (data->state->callbacks != NULL &&
        data->state->callbacks->feature_dialogue_for_feature != NULL)
        dialogue = data->state->callbacks->feature_dialogue_for_feature(
            data->state->user_data, data->feature_id);
    if (dialogue != NULL)
        show_feature_dialogue(data->state, dialogue, data->feature_id);
    else
        show_feature_properties(data->state, data->feature_id);
}

static void feature_menu_fit_cb(GtkButton *button, gpointer user_data)
{
    WcFeatureMenuData *data = (WcFeatureMenuData *)user_data;
    (void)button;
    if (data == NULL || data->state == NULL) return;
    select_model_feature(data->state, data->feature_id, 1);
    if (fit_feature(data->state, data->feature_id))
        gtk_label_set_text(GTK_LABEL(data->state->command_status), "Fit to feature");
    else
        gtk_label_set_text(GTK_LABEL(data->state->command_status), "This feature has no display bounds to fit");
}

static void feature_menu_delete_cb(GtkButton *button, gpointer user_data)
{
    WcFeatureMenuData *data = (WcFeatureMenuData *)user_data;
    (void)button;
    if (data == NULL || data->state == NULL) return;
    select_model_feature(data->state, data->feature_id, 0);
    run_feature_action(data->state, 0);
}

static void feature_menu_edit_sketch_cb(GtkButton *button, gpointer user_data)
{
    WcFeatureMenuData *data = (WcFeatureMenuData *)user_data;
    (void)button;
    if (data == NULL || data->state == NULL) return;
    begin_edit_sketch(data->state, data->feature_id);
}

static WcFeatureMenuData *new_feature_menu_data(WcGtk4State *state, uint32_t feature_id)
{
    WcFeatureMenuData *data = g_new0(WcFeatureMenuData, 1);
    data->state = state;
    data->feature_id = feature_id;
    return data;
}

static void show_feature_context_menu(WcGtk4State *state, GtkWidget *relative_to,
                                      uint32_t feature_id, double x, double y)
{
    GtkWidget *popover;
    GtkWidget *box;
    GtkWidget *button;
    GdkRectangle rectangle;
    if (state == NULL || relative_to == NULL || feature_id == 0)
        return;
    popover = gtk_popover_new();
    box = gtk_box_new(GTK_ORIENTATION_VERTICAL, 2);
    button = gtk_button_new_with_label("Edit / Properties");
    g_signal_connect_data(button, "clicked", G_CALLBACK(feature_menu_properties_cb),
                          new_feature_menu_data(state, feature_id), free_signal_data, 0);
    gtk_box_append(GTK_BOX(box), button);
    button = gtk_button_new_with_label("Fit to Feature");
    gtk_widget_set_sensitive(button, body_bounds_for_feature(state, feature_id, NULL));
    g_signal_connect_data(button, "clicked", G_CALLBACK(feature_menu_fit_cb),
                          new_feature_menu_data(state, feature_id), free_signal_data, 0);
    gtk_box_append(GTK_BOX(box), button);
    if (state->selected_feature_kind == WC_FEATURE_KIND_SKETCH) {
        button = gtk_button_new_with_label("Edit Sketch");
        g_signal_connect_data(button, "clicked", G_CALLBACK(feature_menu_edit_sketch_cb),
                              new_feature_menu_data(state, feature_id), free_signal_data, 0);
        gtk_box_append(GTK_BOX(box), button);
    }
    button = gtk_button_new_with_label("Delete");
    g_signal_connect_data(button, "clicked", G_CALLBACK(feature_menu_delete_cb),
                          new_feature_menu_data(state, feature_id), free_signal_data, 0);
    gtk_box_append(GTK_BOX(box), button);
    gtk_popover_set_child(GTK_POPOVER(popover), box);
    gtk_widget_set_parent(popover, relative_to);
    rectangle.x = (int)x; rectangle.y = (int)y; rectangle.width = 1; rectangle.height = 1;
    gtk_popover_set_pointing_to(GTK_POPOVER(popover), &rectangle);
    gtk_popover_popup(GTK_POPOVER(popover));
}

static void model_context_pressed_cb(GtkGestureClick *gesture, int n_press, double x, double y, gpointer user_data)
{
    WcGtk4State *state = (WcGtk4State *)user_data;
    GtkListBoxRow *row;
    uint32_t feature_id;
    (void)gesture;
    (void)n_press;
    if (state == NULL || state->model_list == NULL) return;
    row = gtk_list_box_get_row_at_y(GTK_LIST_BOX(state->model_list), (int)y);
    if (row == NULL || !GPOINTER_TO_INT(g_object_get_data(G_OBJECT(row), "wc-real-feature")))
        return;
    gtk_list_box_select_row(GTK_LIST_BOX(state->model_list), row);
    feature_id = GPOINTER_TO_UINT(g_object_get_data(G_OBJECT(row), "wc-feature-id"));
    show_feature_context_menu(state, state->model_list, feature_id, x, y);
}

static GdkContentProvider *feature_drag_prepare_cb(GtkDragSource *source, double x, double y, gpointer user_data)
{
    WcFeatureMenuData *data = (WcFeatureMenuData *)user_data;
    char text[32];
    GValue value = G_VALUE_INIT;
    GdkContentProvider *provider;
    (void)source; (void)x; (void)y;
    if (data == NULL || data->feature_id == 0) return NULL;
    (void)snprintf(text, sizeof(text), "%u", data->feature_id);
    g_value_init(&value, G_TYPE_STRING);
    g_value_set_string(&value, text);
    provider = gdk_content_provider_new_for_value(&value);
    g_value_unset(&value);
    return provider;
}

static gboolean feature_drop_cb(GtkDropTarget *target, const GValue *value, double x, double y, gpointer user_data)
{
    WcFeatureDropData *data = (WcFeatureDropData *)user_data;
    const char *text;
    uint32_t source_id;
    int after;
    int status;
    GtkWidget *row_widget;
    char message[192];
    (void)target; (void)x;
    if (data == NULL || data->state == NULL || value == NULL || !G_VALUE_HOLDS_STRING(value))
        return FALSE;
    text = g_value_get_string(value);
    if (text == NULL) return FALSE;
    source_id = (uint32_t)g_ascii_strtoull(text, NULL, 10);
    if (source_id == 0 || source_id == data->target_feature_id)
        return FALSE;
    row_widget = GTK_WIDGET(model_row_for_feature(data->state, data->target_feature_id));
    after = row_widget != NULL && y > gtk_widget_get_height(row_widget) * 0.5;
    if (data->state->callbacks == NULL || data->state->callbacks->feature_reorder == NULL)
        return FALSE;
    status = data->state->callbacks->feature_reorder(data->state->user_data, source_id,
                                                     data->target_feature_id, after ? 1 : 0);
    if (status != 0) {
        (void)snprintf(message, sizeof(message), "Reorder rejected (SCL error %d). A dependency blocks that history position.", status);
        gtk_label_set_text(GTK_LABEL(data->state->command_status), message);
        return FALSE;
    }
    data->state->selected_feature_id = source_id;
    data->state->selected_row_is_feature = 1;
    gtk_widget_queue_draw(data->state->drawing_area);
    g_idle_add(deferred_update_status_cb, data->state);
    gtk_label_set_text(GTK_LABEL(data->state->command_status), "Feature reordered by drag-and-drop");
    return TRUE;
}

static void configure_feature_drag(WcGtk4State *state, GtkWidget *row_widget, uint32_t feature_id)
{
    GtkDragSource *source;
    GtkDropTarget *target;
    WcFeatureMenuData *source_data;
    WcFeatureDropData *drop_data;
    if (state == NULL || row_widget == NULL || feature_id == 0)
        return;
    source = gtk_drag_source_new();
    gtk_drag_source_set_actions(source, GDK_ACTION_MOVE);
    source_data = new_feature_menu_data(state, feature_id);
    g_signal_connect_data(source, "prepare", G_CALLBACK(feature_drag_prepare_cb), source_data, free_signal_data, 0);
    gtk_widget_add_controller(row_widget, GTK_EVENT_CONTROLLER(source));

    target = gtk_drop_target_new(G_TYPE_STRING, GDK_ACTION_MOVE);
    drop_data = g_new0(WcFeatureDropData, 1);
    drop_data->state = state;
    drop_data->target_feature_id = feature_id;
    g_signal_connect_data(target, "drop", G_CALLBACK(feature_drop_cb), drop_data, free_signal_data, 0);
    gtk_widget_add_controller(row_widget, GTK_EVENT_CONTROLLER(target));
}

static GtkWidget *build_model_navigator(WcGtk4State *state)
{
    GtkWidget *box = gtk_box_new(GTK_ORIENTATION_VERTICAL, 3);
    GtkWidget *scroller;
    GtkGesture *context_gesture;
    gtk_widget_add_css_class(box, "wc-panel");
    gtk_widget_add_css_class(box, "wc-model-navigator");
    gtk_widget_set_hexpand(box, FALSE);
    gtk_widget_set_size_request(box, 0, -1);
    gtk_box_append(GTK_BOX(box), make_label("Model Navigator", "wc-title-compact"));
    state->model_name_label = make_label("untitled", "wc-model-name");
    gtk_widget_set_hexpand(state->model_name_label, TRUE);
    gtk_label_set_ellipsize(GTK_LABEL(state->model_name_label), PANGO_ELLIPSIZE_END);
    gtk_box_append(GTK_BOX(box), state->model_name_label);
    state->section_status = make_label("Section: modelling", "wc-subtle");
    gtk_widget_set_visible(state->section_status, FALSE);
    state->model_status = make_label("Features 0", "wc-subtle");
    gtk_label_set_single_line_mode(GTK_LABEL(state->model_status), TRUE);
    gtk_label_set_ellipsize(GTK_LABEL(state->model_status), PANGO_ELLIPSIZE_END);
    gtk_box_append(GTK_BOX(box), state->model_status);
    scroller = gtk_scrolled_window_new();
    gtk_widget_set_vexpand(scroller, TRUE);
    gtk_widget_set_hexpand(scroller, TRUE);
    gtk_widget_set_size_request(scroller, 0, -1);
    gtk_scrolled_window_set_min_content_width(GTK_SCROLLED_WINDOW(scroller), 0);
    gtk_scrolled_window_set_policy(GTK_SCROLLED_WINDOW(scroller), GTK_POLICY_AUTOMATIC, GTK_POLICY_AUTOMATIC);
    gtk_scrolled_window_set_propagate_natural_width(GTK_SCROLLED_WINDOW(scroller), FALSE);
    gtk_scrolled_window_set_overlay_scrolling(GTK_SCROLLED_WINDOW(scroller), FALSE);
    state->model_list = gtk_list_box_new();
    gtk_widget_add_css_class(state->model_list, "wc-model-navigator");
    gtk_list_box_set_selection_mode(GTK_LIST_BOX(state->model_list), GTK_SELECTION_SINGLE);
    gtk_list_box_set_activate_on_single_click(GTK_LIST_BOX(state->model_list), FALSE);
    g_signal_connect(state->model_list, "row-selected", G_CALLBACK(model_row_selected_cb), state);
    g_signal_connect(state->model_list, "row-activated", G_CALLBACK(model_row_activated_cb), state);
    context_gesture = gtk_gesture_click_new();
    gtk_gesture_single_set_button(GTK_GESTURE_SINGLE(context_gesture), GDK_BUTTON_SECONDARY);
    g_signal_connect(context_gesture, "pressed", G_CALLBACK(model_context_pressed_cb), state);
    gtk_widget_add_controller(state->model_list, GTK_EVENT_CONTROLLER(context_gesture));
    gtk_scrolled_window_set_child(GTK_SCROLLED_WINDOW(scroller), state->model_list);
    gtk_box_append(GTK_BOX(box), scroller);
    return box;
}


static void assembly_section_clicked_cb(GtkButton *button, gpointer user_data)
{
    (void)button;
    choose_section((WcGtk4State *)user_data, "assembly");
}

static GtkWidget *build_assembly_navigator(WcGtk4State *state)
{
    GtkWidget *box = gtk_box_new(GTK_ORIENTATION_VERTICAL, 8);
    GtkWidget *button;
    gtk_widget_add_css_class(box, "wc-panel");
    gtk_box_append(GTK_BOX(box), make_label("Assembly Navigator", "wc-title"));
    state->assembly_name_label = make_label("untitled", "wc-model-name");
    gtk_box_append(GTK_BOX(box), state->assembly_name_label);
    gtk_box_append(GTK_BOX(box), make_label("Root occurrence\n  standalone part\n\nAssembly occurrence/load-policy data structures remain planned; suppression and unloading will stay distinct.", "wc-subtle"));
    button = gtk_button_new_with_label("Open Assembly Section");
    g_signal_connect(button, "clicked", G_CALLBACK(assembly_section_clicked_cb), state);
    gtk_widget_set_tooltip_text(button, "Switch to the Assembly application context; document structures are still planned");
    gtk_box_append(GTK_BOX(box), button);
    return box;
}

static GtkWidget *build_ai_navigator(WcGtk4State *state)
{
    GtkWidget *box = gtk_box_new(GTK_ORIENTATION_VERTICAL, 8);
    GtkWidget *button;
    GtkWidget *entry;
    gtk_widget_add_css_class(box, "wc-panel");
    gtk_box_append(GTK_BOX(box), make_label("AI Agent", "wc-title"));
    state->ai_summary_label = make_label("Read-only model context", "wc-subtle");
    gtk_label_set_wrap(GTK_LABEL(state->ai_summary_label), TRUE);
    gtk_box_append(GTK_BOX(box), state->ai_summary_label);
    button = gtk_button_new_with_label("Refresh model summary");
    g_signal_connect(button, "clicked", G_CALLBACK(ai_inspect_clicked_cb), state);
    gtk_box_append(GTK_BOX(box), button);
    entry = gtk_entry_new();
    gtk_entry_set_placeholder_text(GTK_ENTRY(entry), "AI provider connection is not configured yet");
    gtk_widget_set_sensitive(entry, FALSE);
    gtk_box_append(GTK_BOX(box), entry);
    button = gtk_button_new_with_label("Focus SCL command line");
    g_signal_connect(button, "clicked", G_CALLBACK(command_focus_clicked_cb), state);
    gtk_box_append(GTK_BOX(box), button);
    return box;
}

static GtkWidget *build_navigator_rail(WcGtk4State *state)
{
    GtkWidget *rail = gtk_box_new(GTK_ORIENTATION_VERTICAL, 4);
    GtkWidget *button;
    gtk_widget_add_css_class(rail, "wc-nav-rail");
    gtk_widget_set_size_request(rail, 48, -1);
    button = make_rail_button("nav_model", "Model Navigator");
    g_signal_connect(button, "clicked", G_CALLBACK(navigator_model_clicked_cb), state);
    gtk_box_append(GTK_BOX(rail), button);
    button = make_rail_button("nav_assembly", "Assembly Navigator");
    g_signal_connect(button, "clicked", G_CALLBACK(navigator_assembly_clicked_cb), state);
    gtk_box_append(GTK_BOX(rail), button);
    button = make_rail_button("nav_ai", "AI Agent");
    g_signal_connect(button, "clicked", G_CALLBACK(navigator_ai_clicked_cb), state);
    gtk_box_append(GTK_BOX(rail), button);
    return rail;
}

static gboolean set_initial_navigator_width_cb(gpointer user_data)
{
    WcGtk4State *state = (WcGtk4State *)user_data;
    if (state != NULL && state->navigator_paned != NULL)
        gtk_paned_set_position(GTK_PANED(state->navigator_paned), 210);
    return G_SOURCE_REMOVE;
}

static GtkWidget *build_navigator_content(WcGtk4State *state)
{
    state->navigator_stack = gtk_stack_new();
    gtk_stack_set_transition_type(GTK_STACK(state->navigator_stack), GTK_STACK_TRANSITION_TYPE_CROSSFADE);
    /* Do not let the wider Assembly/AI pages determine the Model Navigator's
       requested width.  Each navigator page sizes independently and remains
       left-aligned inside the collapsible pane. */
    gtk_stack_set_hhomogeneous(GTK_STACK(state->navigator_stack), FALSE);
    gtk_stack_set_vhomogeneous(GTK_STACK(state->navigator_stack), FALSE);
    gtk_widget_set_halign(state->navigator_stack, GTK_ALIGN_FILL);
    gtk_widget_set_size_request(state->navigator_stack, 0, -1);
    gtk_stack_add_named(GTK_STACK(state->navigator_stack), build_model_navigator(state), "model");
    gtk_stack_add_named(GTK_STACK(state->navigator_stack), build_assembly_navigator(state), "assembly");
    gtk_stack_add_named(GTK_STACK(state->navigator_stack), build_ai_navigator(state), "ai");
    gtk_stack_set_visible_child_name(GTK_STACK(state->navigator_stack), "model");
    return state->navigator_stack;
}

static gboolean close_request_cb(GtkWindow *window, gpointer user_data)
{
    WcGtk4State *state = (WcGtk4State *)user_data;
    if (state != NULL && state->loop != NULL) {
        gtk_widget_set_visible(GTK_WIDGET(window), FALSE);
        g_main_loop_quit(state->loop);
    }
    return TRUE;
}

static void install_css(const WcGtk4WindowConfig *config)
{
    GtkCssProvider *provider = gtk_css_provider_new();
    char css[8192];
    const char *navigator = config != NULL && config->navigator_background != NULL ? config->navigator_background : "#171321";
    const char *rail = config != NULL && config->navigator_rail_background != NULL ? config->navigator_rail_background : "#100d18";
    (void)snprintf(css, sizeof(css),
        "window { background: #0e0c16; color: #eee8f5; }"
        ".wc-ribbon { background: #1c1728; border-bottom: 1px solid #3b2d49; }"
        ".wc-ribbon-tabs { padding: 2px 6px 0 6px; }"
        ".wc-ribbon-tab { min-height: 26px; padding: 2px 12px; border-radius: 3px 3px 0 0; }"
        ".wc-ribbon-tab-active { background: #34243f; color: #ffb3e3; font-weight: 700; }"
        ".wc-ribbon-groups { padding: 4px 5px 2px 5px; }"
        ".wc-ribbon-group { border-right: 1px solid #43344f; padding: 2px 5px; }"
        ".wc-ribbon-group-label { color: #a9a0b5; font-size: 9px; margin-top: 1px; }"
        ".wc-ribbon-command { min-width: 0; min-height: 0; padding: 3px; font-size: 10px; }"
        ".wc-ribbon-command-compact { padding: 2px; font-size: 9px; }"
        ".wc-title { font-weight: 800; font-size: 16px; color: #f59bd6; }"
        ".wc-title-compact { font-weight: 800; font-size: 12px; color: #f59bd6; }"
        ".wc-model-name { font-weight: 700; font-size: 13px; color: #eee8f5; }"
        ".wc-subtle { color: #aaa2b8; font-size: 11px; }"
        ".wc-panel { background: %s; padding: 6px; }"
        ".wc-model-navigator, .wc-model-navigator list, .wc-model-navigator row, .wc-model-navigator scrolledwindow { background: %s; color: #eee8f5; min-width: 0px; }"
        ".wc-model-navigator row:selected { background: #34243f; color: #ffd1ee; }"
        ".wc-model-navigator row.wc-tree-descendant-selected { background: #291d35; color: #f4c5e6; }"
        ".wc-nav-rail { background: %s; padding: 5px 3px; border-right: 1px solid #372c44; }"
        ".wc-rail-button { min-width: 38px; min-height: 38px; padding: 5px; }"
        ".wc-tree-row { font-size: 10px; color: #ddd4e5; }"
        ".wc-badge-exact { background: #214a35; color: #b7f5d0; border-radius: 8px; padding: 2px 5px; font-size: 9px; }"
        ".wc-badge-preview { background: #4b3a1d; color: #ffe1a0; border-radius: 8px; padding: 2px 5px; font-size: 9px; }"
        ".wc-badge-failed { background: #57262e; color: #ffbdc6; border-radius: 8px; padding: 2px 5px; font-size: 9px; }"
        ".wc-command { background: rgba(25,20,36,0.94); padding: 7px; border-radius: 8px; }"
        ".wc-status { background: #171321; padding: 3px 7px; border-top: 1px solid #31283f; }"
        "button { min-height: 28px; }"
        "entry { min-height: 32px; }",
        navigator, navigator, rail);
#if GTK_CHECK_VERSION(4, 12, 0)
    gtk_css_provider_load_from_string(provider, css);
#else
    gtk_css_provider_load_from_data(provider, css, -1);
#endif
    gtk_style_context_add_provider_for_display(gdk_display_get_default(),
                                                GTK_STYLE_PROVIDER(provider),
                                                GTK_STYLE_PROVIDER_PRIORITY_APPLICATION);
    g_object_unref(provider);
}

static GtkWidget *find_nightcore_picture(void)
{
    const char *paths[] = {
        "waifus/nightcore.png",
        "waifus/sakura_riddle.png",
        "waifus/luotianyi.png",
        NULL
    };
    int i;
    for (i = 0; paths[i] != NULL; ++i) {
        if (g_file_test(paths[i], G_FILE_TEST_EXISTS)) {
            GtkWidget *picture = gtk_picture_new_for_filename(paths[i]);
            gtk_picture_set_can_shrink(GTK_PICTURE(picture), TRUE);
#if GTK_CHECK_VERSION(4, 8, 0)
#endif
            gtk_widget_set_size_request(picture, 112, 88);
            gtk_widget_set_tooltip_text(picture, "Nightcore theme image");
            return picture;
        }
    }
    {
        GtkWidget *placeholder = gtk_box_new(GTK_ORIENTATION_VERTICAL, 2);
        gtk_widget_set_size_request(placeholder, 112, 88);
        gtk_widget_add_css_class(placeholder, "wc-panel");
        gtk_box_append(GTK_BOX(placeholder), load_svg_image("waifucad", 28));
        gtk_box_append(GTK_BOX(placeholder), make_label("nightcore.png\nwaifus/", "wc-subtle"));
        return placeholder;
    }
}

static gboolean ribbon_resize_tick_cb(GtkWidget *widget, GdkFrameClock *clock, gpointer user_data)
{
    WcGtk4State *state = (WcGtk4State *)user_data;
    int width;
    int density;
    (void)widget;
    (void)clock;
    if (state == NULL || state->window == NULL)
        return G_SOURCE_CONTINUE;
    width = gtk_widget_get_width(state->window);
    if (width <= 0)
        return G_SOURCE_CONTINUE;
    density = width < 820 ? 2 : (width < 1180 ? 1 : 0);
    if (density != state->ribbon_density) {
        state->ribbon_density = density;
        state->window_width_hint = width;
        rebuild_ribbon(state);
    }
    return G_SOURCE_CONTINUE;
}

int wc_gtk4_native_available(void)
{
    return 1;
}

int wc_gtk4_run(const WcGtk4WindowConfig *config,
                const WcGtk4Callbacks *callbacks,
                void *user_data)
{
    WcGtk4State state;
    GtkWidget *root;
    GtkWidget *ribbon_area;
    GtkWidget *ribbon_left;
    GtkWidget *workspace;
    GtkWidget *main_paned;
    GtkWidget *navigator_rail;
    GtkWidget *navigator_content;
    GtkWidget *overlay;
    GtkWidget *command_box;
    GtkWidget *status_box;
    GtkEventController *controller;
    GtkGesture *gesture;
    const char *gsk_renderer;
    char renderer_text[768];
    char gtk_text[128];

    if (config == NULL || callbacks == NULL)
        return 10;

    if (config->force_lavapipe) {
        if (g_file_test("/usr/share/vulkan/icd.d/lvp_icd.x86_64.json", G_FILE_TEST_EXISTS))
            g_setenv("VK_ICD_FILENAMES", "/usr/share/vulkan/icd.d/lvp_icd.x86_64.json", TRUE);
        else if (g_file_test("/usr/share/vulkan/icd.d/lvp_icd.json", G_FILE_TEST_EXISTS))
            g_setenv("VK_ICD_FILENAMES", "/usr/share/vulkan/icd.d/lvp_icd.json", TRUE);
        g_setenv("GSK_RENDERER", "vulkan", TRUE);
    } else if (config->gsk_renderer != NULL && config->gsk_renderer[0] != '\0' &&
               strcmp(config->gsk_renderer, "auto") != 0) {
        g_setenv("GSK_RENDERER", config->gsk_renderer, TRUE);
    }

    if (!gtk_init_check())
        return 77;

    memset(&state, 0, sizeof(state));
    state.callbacks = callbacks;
    state.user_data = user_data;
    state.yaw = -M_PI / 4.0;
    state.pitch = M_PI / 5.5;
    state.zoom = 1.0;
    state.sketch_tool = WC_SKETCH_TOOL_LINE;
    state.window_width_hint = config->width;
    state.ribbon_density = config->width < 820 ? 2 : (config->width < 1180 ? 1 : 0);
    wc_gpu_probe(&state.gpu);

    install_css(config);
    state.loop = g_main_loop_new(NULL, FALSE);
    state.window = gtk_window_new();
    gtk_window_set_title(GTK_WINDOW(state.window), config->title != NULL ? config->title : "WaifuCAD");
    gtk_window_set_default_size(GTK_WINDOW(state.window), config->width, config->height);
    g_signal_connect(state.window, "close-request", G_CALLBACK(close_request_cb), &state);
    gtk_widget_add_tick_callback(state.window, ribbon_resize_tick_cb, &state, NULL);

    root = gtk_box_new(GTK_ORIENTATION_VERTICAL, 0);
    gtk_window_set_child(GTK_WINDOW(state.window), root);

    /* Sections and Mods are persistent ribbon tabs; Scripts lives in Home. */

    /* Actual contextual ribbon. The nightcore image lives at the ribbon's top-right. */
    ribbon_area = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 5);
    gtk_widget_add_css_class(ribbon_area, "wc-ribbon");
    gtk_box_append(GTK_BOX(root), ribbon_area);
    ribbon_left = gtk_box_new(GTK_ORIENTATION_VERTICAL, 0);
    gtk_widget_set_hexpand(ribbon_left, TRUE);
    gtk_box_append(GTK_BOX(ribbon_area), ribbon_left);
    state.ribbon_tabs_box = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 2);
    gtk_widget_add_css_class(state.ribbon_tabs_box, "wc-ribbon-tabs");
    gtk_box_append(GTK_BOX(ribbon_left), state.ribbon_tabs_box);
    state.ribbon_scroller = gtk_scrolled_window_new();
    gtk_scrolled_window_set_policy(GTK_SCROLLED_WINDOW(state.ribbon_scroller), GTK_POLICY_AUTOMATIC, GTK_POLICY_NEVER);
    gtk_widget_set_size_request(state.ribbon_scroller, -1, 112);
    state.ribbon_commands_box = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 3);
    gtk_widget_add_css_class(state.ribbon_commands_box, "wc-ribbon-groups");
    gtk_scrolled_window_set_child(GTK_SCROLLED_WINDOW(state.ribbon_scroller), state.ribbon_commands_box);
    gtk_box_append(GTK_BOX(ribbon_left), state.ribbon_scroller);
    state.ribbon_waifu = find_nightcore_picture();
    gtk_widget_set_margin_end(state.ribbon_waifu, 6);
    gtk_widget_set_margin_top(state.ribbon_waifu, 4);
    gtk_widget_set_margin_bottom(state.ribbon_waifu, 4);
    gtk_box_append(GTK_BOX(ribbon_area), state.ribbon_waifu);

    workspace = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 0);
    gtk_widget_set_vexpand(workspace, TRUE);
    gtk_box_append(GTK_BOX(root), workspace);
    navigator_rail = build_navigator_rail(&state);
    gtk_box_append(GTK_BOX(workspace), navigator_rail);

    main_paned = gtk_paned_new(GTK_ORIENTATION_HORIZONTAL);
    state.navigator_paned = main_paned;
    gtk_widget_set_hexpand(main_paned, TRUE);
    gtk_widget_set_vexpand(main_paned, TRUE);
    gtk_box_append(GTK_BOX(workspace), main_paned);
    navigator_content = build_navigator_content(&state);
    gtk_paned_set_start_child(GTK_PANED(main_paned), navigator_content);
    gtk_paned_set_resize_start_child(GTK_PANED(main_paned), FALSE);
    gtk_paned_set_shrink_start_child(GTK_PANED(main_paned), TRUE);

    overlay = gtk_overlay_new();
    gtk_widget_set_hexpand(overlay, TRUE);
    gtk_widget_set_vexpand(overlay, TRUE);
    state.drawing_area = gtk_drawing_area_new();
    gtk_widget_set_focusable(state.drawing_area, TRUE);
    gtk_drawing_area_set_content_width(GTK_DRAWING_AREA(state.drawing_area), 720);
    gtk_drawing_area_set_content_height(GTK_DRAWING_AREA(state.drawing_area), 500);
    gtk_drawing_area_set_draw_func(GTK_DRAWING_AREA(state.drawing_area), draw_cb, &state, NULL);
    gtk_overlay_set_child(GTK_OVERLAY(overlay), state.drawing_area);

    controller = gtk_event_controller_scroll_new(GTK_EVENT_CONTROLLER_SCROLL_VERTICAL);
    g_signal_connect(controller, "scroll", G_CALLBACK(scroll_cb), &state);
    gtk_widget_add_controller(state.drawing_area, controller);
    gesture = gtk_gesture_drag_new();
    gtk_gesture_single_set_button(GTK_GESTURE_SINGLE(gesture), GDK_BUTTON_MIDDLE);
    g_signal_connect(gesture, "drag-begin", G_CALLBACK(orbit_drag_begin_cb), &state);
    g_signal_connect(gesture, "drag-update", G_CALLBACK(orbit_drag_update_cb), &state);
    gtk_widget_add_controller(state.drawing_area, GTK_EVENT_CONTROLLER(gesture));
    gesture = gtk_gesture_click_new();
    gtk_gesture_single_set_button(GTK_GESTURE_SINGLE(gesture), GDK_BUTTON_PRIMARY);
    g_signal_connect(gesture, "pressed", G_CALLBACK(viewport_pressed_cb), &state);
    gtk_widget_add_controller(state.drawing_area, GTK_EVENT_CONTROLLER(gesture));
    gesture = gtk_gesture_click_new();
    gtk_gesture_single_set_button(GTK_GESTURE_SINGLE(gesture), GDK_BUTTON_SECONDARY);
    g_signal_connect(gesture, "pressed", G_CALLBACK(viewport_context_pressed_cb), &state);
    gtk_widget_add_controller(state.drawing_area, GTK_EVENT_CONTROLLER(gesture));
    controller = gtk_event_controller_motion_new();
    g_signal_connect(controller, "motion", G_CALLBACK(viewport_motion_cb), &state);
    gtk_widget_add_controller(state.drawing_area, controller);

    command_box = gtk_box_new(GTK_ORIENTATION_VERTICAL, 3);
    gtk_widget_add_css_class(command_box, "wc-command");
    gtk_widget_set_halign(command_box, GTK_ALIGN_CENTER);
    gtk_widget_set_valign(command_box, GTK_ALIGN_END);
    gtk_widget_set_margin_bottom(command_box, 18);
    gtk_widget_set_size_request(command_box, 660, -1);
    state.command_status = make_label("Viewport ready — Enter focuses command line", "wc-subtle");
    gtk_box_append(GTK_BOX(command_box), state.command_status);
    state.command_entry = gtk_entry_new();
    gtk_entry_set_placeholder_text(GTK_ENTRY(state.command_entry), "Command: box(:body, 80.mm, 50.mm, 10.mm)");
    g_signal_connect(state.command_entry, "activate", G_CALLBACK(command_activate_cb), &state);
    gtk_box_append(GTK_BOX(command_box), state.command_entry);
    gtk_overlay_add_overlay(GTK_OVERLAY(overlay), command_box);
    gtk_paned_set_end_child(GTK_PANED(main_paned), overlay);
    /* The actual 210 px divider is applied after the first GTK allocation.
       Setting it here is too early on GTK 4.12 and can be replaced by the
       start child's natural width, producing the large blank navigator gap. */

    controller = gtk_event_controller_key_new();
    g_signal_connect(controller, "key-pressed", G_CALLBACK(key_pressed_cb), &state);
    gtk_widget_add_controller(state.window, controller);

    status_box = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 10);
    gtk_widget_add_css_class(status_box, "wc-status");
    gsk_renderer = g_getenv("GSK_RENDERER");
    (void)snprintf(gtk_text, sizeof(gtk_text), "GTK %u.%u.%u",
                   gtk_get_major_version(), gtk_get_minor_version(), gtk_get_micro_version());
    gtk_box_append(GTK_BOX(status_box), make_label(gtk_text, "wc-subtle"));
    (void)snprintf(renderer_text, sizeof(renderer_text),
                   "GSK=%s | %s",
                   gsk_renderer != NULL ? gsk_renderer : "auto",
                   state.gpu.summary[0] != '\0' ? state.gpu.summary : "GPU probe unavailable");
    state.renderer_status = make_label(renderer_text, "wc-subtle");
    gtk_widget_set_hexpand(state.renderer_status, TRUE);
    gtk_box_append(GTK_BOX(status_box), state.renderer_status);
    gtk_box_append(GTK_BOX(root), status_box);

    rebuild_ribbon(&state);
    update_status(&state);
    gtk_window_present(GTK_WINDOW(state.window));
    g_idle_add(set_initial_navigator_width_cb, &state);
    gtk_widget_grab_focus(state.drawing_area);
    g_main_loop_run(state.loop);

    clear_snap_timer(&state);
    if (GTK_IS_WINDOW(state.window))
        gtk_window_destroy(GTK_WINDOW(state.window));
    g_main_loop_unref(state.loop);
    return 0;
}

