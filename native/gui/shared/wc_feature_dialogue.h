#ifndef WAIFUCAD_WC_FEATURE_DIALOGUE_H
#define WAIFUCAD_WC_FEATURE_DIALOGUE_H

/*
 * Toolkit-neutral native mirror of FeatureDialogueDescriptorV1.
 *
 * GTK4, Cocoa/AppKit and future native front-ends consume this exact ABI.
 * Feature semantics remain owned by src/waifucad/gui/feature_dialogues.d;
 * toolkits render these descriptors and send accepted edits/selections back
 * through the semantic SCL/journal callbacks rather than mutating the model.
 */

#include <stddef.h>
#include <stdint.h>

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

#endif
