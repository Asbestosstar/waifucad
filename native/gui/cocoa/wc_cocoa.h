#ifndef WC_COCOA_H
#define WC_COCOA_H

/* Cocoa/AppKit front-end compatibility shim.
 *
 * The ABI itself lives once in native/gui/shared/wc_gui_abi.h and is shared
 * by every GUI front-end; this header only maps the historical Cocoa-prefixed
 * names onto the neutral types so the AppKit/Metal bridge keeps compiling
 * unchanged. New code should use the neutral WcGui* names directly. */

#include "../shared/wc_gui_abi.h"
#include "../shared/wc_feature_dialogue.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef WcGuiWindowConfig WcCocoaWindowConfig;
typedef WcGuiModelSnapshot WcCocoaModelSnapshot;
typedef WcGuiFeatureRow WcCocoaFeatureRow;
typedef WcGuiBodyRow WcCocoaBodyRow;
typedef WcGuiMassProperties WcCocoaMassProperties;
typedef WcGuiCsysRow WcCocoaCsysRow;
typedef WcGuiSketchGeometryRow WcCocoaSketchGeometryRow;
typedef WcGuiPlanarFaceRow WcCocoaPlanarFaceRow;
typedef WcGuiSketchSupportKind WcCocoaSketchSupportKind;
typedef WcGuiSketchSupport WcCocoaSketchSupport;
typedef WcGuiSectionEntry WcCocoaSectionEntry;
typedef WcGuiRibbonTab WcCocoaRibbonTab;
typedef WcGuiRibbonCommand WcCocoaRibbonCommand;
typedef WcGuiRibbonSnapshot WcCocoaRibbonSnapshot;
typedef WcGuiCallbacks WcCocoaCallbacks;

#define WC_COCOA_UI_ID_CAPACITY WC_GUI_UI_ID_CAPACITY
#define WC_COCOA_FEATURE_ROW_CAPACITY WC_GUI_FEATURE_ROW_CAPACITY
#define WC_COCOA_FACE_ROW_CAPACITY WC_GUI_FACE_ROW_CAPACITY
#define WC_COCOA_BODY_ROW_CAPACITY WC_GUI_BODY_ROW_CAPACITY
#define WC_COCOA_CSYS_ROW_CAPACITY WC_GUI_CSYS_ROW_CAPACITY
#define WC_COCOA_FACE_MAX_POINTS WC_GUI_FACE_MAX_POINTS

#define WC_COCOA_FEATURE_KIND_SKETCH WC_GUI_FEATURE_KIND_SKETCH
#define WC_COCOA_FEATURE_KIND_SKETCH_LINE WC_GUI_FEATURE_KIND_SKETCH_LINE
#define WC_COCOA_FEATURE_KIND_SKETCH_ARC WC_GUI_FEATURE_KIND_SKETCH_ARC
#define WC_COCOA_FEATURE_KIND_SKETCH_CIRCLE WC_GUI_FEATURE_KIND_SKETCH_CIRCLE
#define WC_COCOA_FEATURE_KIND_SKETCH_RECTANGLE WC_GUI_FEATURE_KIND_SKETCH_RECTANGLE
#define WC_COCOA_FEATURE_KIND_DATUM_PLANE WC_GUI_FEATURE_KIND_DATUM_PLANE
#define WC_COCOA_FEATURE_KIND_DATUM_CSYS WC_GUI_FEATURE_KIND_DATUM_CSYS

#define WC_COCOA_RIBBON_FLAG_PLANNED WC_GUI_RIBBON_FLAG_PLANNED

#define WC_COCOA_SKETCH_SUPPORT_NONE WC_GUI_SKETCH_SUPPORT_NONE
#define WC_COCOA_SKETCH_SUPPORT_DATUM_PLANE WC_GUI_SKETCH_SUPPORT_DATUM_PLANE
#define WC_COCOA_SKETCH_SUPPORT_CSYS_PLANE WC_GUI_SKETCH_SUPPORT_CSYS_PLANE
#define WC_COCOA_SKETCH_SUPPORT_PLANAR_FACE WC_GUI_SKETCH_SUPPORT_PLANAR_FACE

typedef WcGuiSubmitCommandFn WcCocoaSubmitCommandFn;
typedef WcGuiChooseSectionFn WcCocoaChooseSectionFn;
typedef WcGuiActiveSectionFn WcCocoaActiveSectionFn;
typedef WcGuiSnapshotFn WcCocoaSnapshotFn;
typedef WcGuiFeatureRowsFn WcCocoaFeatureRowsFn;
typedef WcGuiBodyRowsFn WcCocoaBodyRowsFn;
typedef WcGuiMassPropertiesFn WcCocoaMassPropertiesFn;
typedef WcGuiCsysRowsFn WcCocoaCsysRowsFn;
typedef WcGuiSectionEntriesFn WcCocoaSectionEntriesFn;
typedef WcGuiActiveRibbonFn WcCocoaActiveRibbonFn;
typedef WcGuiRibbonTemplateFn WcCocoaRibbonTemplateFn;
typedef WcGuiFeatureDialogueFn WcCocoaFeatureDialogueFn;
typedef WcGuiFeatureDialogueForFeatureFn WcCocoaFeatureDialogueForFeatureFn;
typedef WcGuiFeatureDialogueValueFn WcCocoaFeatureDialogueValueFn;
typedef WcGuiFeatureDialogueAcceptSelectionFn WcCocoaFeatureDialogueAcceptSelectionFn;
typedef WcGuiBeginNewSketchFn WcCocoaBeginNewSketchFn;
typedef WcGuiEditSketchFn WcCocoaEditSketchFn;
typedef WcGuiFinishSketchFn WcCocoaFinishSketchFn;
typedef WcGuiSketchGeometryRowsFn WcCocoaSketchGeometryRowsFn;
typedef WcGuiPlanarFaceRowsFn WcCocoaPlanarFaceRowsFn;
typedef WcGuiSketchAddLineFn WcCocoaSketchAddLineFn;
typedef WcGuiSketchAddCircleFn WcCocoaSketchAddCircleFn;
typedef WcGuiSketchAddRectangleFn WcCocoaSketchAddRectangleFn;
typedef WcGuiFeatureActionFn WcCocoaFeatureActionFn;
typedef WcGuiFeatureReorderFn WcCocoaFeatureReorderFn;

int wc_cocoa_native_available(void);
int wc_cocoa_run(const WcCocoaWindowConfig *config,
                const WcCocoaCallbacks *callbacks,
                void *user_data);

#ifdef __cplusplus
}
#endif

#endif
