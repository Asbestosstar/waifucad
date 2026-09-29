#ifndef WAIFUCAD_WC_GTK4_H
#define WAIFUCAD_WC_GTK4_H

/* GTK4 front-end compatibility shim.
 *
 * The ABI itself lives once in native/gui/shared/wc_gui_abi.h and is shared
 * by every GUI front-end; this header only maps the historical Gtk4-prefixed
 * names onto the neutral types so the GTK4 bridge keeps compiling unchanged.
 * New code should use the neutral WcGui* names directly. */

#include "../shared/wc_gui_abi.h"
#include "../shared/wc_feature_dialogue.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef WcGuiWindowConfig WcGtk4WindowConfig;
typedef WcGuiModelSnapshot WcGtk4ModelSnapshot;
typedef WcGuiFeatureRow WcGtk4FeatureRow;
typedef WcGuiBodyRow WcGtk4BodyRow;
typedef WcGuiMassProperties WcGtk4MassProperties;
typedef WcGuiCsysRow WcGtk4CsysRow;
typedef WcGuiSketchGeometryRow WcGtk4SketchGeometryRow;
typedef WcGuiPlanarFaceRow WcGtk4PlanarFaceRow;
typedef WcGuiSketchSupportKind WcGtk4SketchSupportKind;
typedef WcGuiSketchSupport WcGtk4SketchSupport;
typedef WcGuiSectionEntry WcGtk4SectionEntry;
typedef WcGuiRibbonTab WcGtk4RibbonTab;
typedef WcGuiRibbonCommand WcGtk4RibbonCommand;
typedef WcGuiRibbonSnapshot WcGtk4RibbonSnapshot;
typedef WcGuiCallbacks WcGtk4Callbacks;

#define WC_GTK4_FACE_MAX_POINTS WC_GUI_FACE_MAX_POINTS
#define WC_GTK4_SKETCH_SUPPORT_NONE WC_GUI_SKETCH_SUPPORT_NONE
#define WC_GTK4_SKETCH_SUPPORT_DATUM_PLANE WC_GUI_SKETCH_SUPPORT_DATUM_PLANE
#define WC_GTK4_SKETCH_SUPPORT_CSYS_PLANE WC_GUI_SKETCH_SUPPORT_CSYS_PLANE
#define WC_GTK4_SKETCH_SUPPORT_PLANAR_FACE WC_GUI_SKETCH_SUPPORT_PLANAR_FACE

typedef WcGuiSubmitCommandFn WcGtk4SubmitCommandFn;
typedef WcGuiChooseSectionFn WcGtk4ChooseSectionFn;
typedef WcGuiActiveSectionFn WcGtk4ActiveSectionFn;
typedef WcGuiSnapshotFn WcGtk4SnapshotFn;
typedef WcGuiFeatureRowsFn WcGtk4FeatureRowsFn;
typedef WcGuiBodyRowsFn WcGtk4BodyRowsFn;
typedef WcGuiMassPropertiesFn WcGtk4MassPropertiesFn;
typedef WcGuiCsysRowsFn WcGtk4CsysRowsFn;
typedef WcGuiSectionEntriesFn WcGtk4SectionEntriesFn;
typedef WcGuiActiveRibbonFn WcGtk4ActiveRibbonFn;
typedef WcGuiRibbonTemplateFn WcGtk4RibbonTemplateFn;
typedef WcGuiFeatureDialogueFn WcGtk4FeatureDialogueFn;
typedef WcGuiFeatureDialogueForFeatureFn WcGtk4FeatureDialogueForFeatureFn;
typedef WcGuiFeatureDialogueValueFn WcGtk4FeatureDialogueValueFn;
typedef WcGuiFeatureDialogueAcceptSelectionFn WcGtk4FeatureDialogueAcceptSelectionFn;
typedef WcGuiBeginNewSketchFn WcGtk4BeginNewSketchFn;
typedef WcGuiEditSketchFn WcGtk4EditSketchFn;
typedef WcGuiFinishSketchFn WcGtk4FinishSketchFn;
typedef WcGuiSketchGeometryRowsFn WcGtk4SketchGeometryRowsFn;
typedef WcGuiPlanarFaceRowsFn WcGtk4PlanarFaceRowsFn;
typedef WcGuiSketchAddLineFn WcGtk4SketchAddLineFn;
typedef WcGuiSketchAddCircleFn WcGtk4SketchAddCircleFn;
typedef WcGuiSketchAddRectangleFn WcGtk4SketchAddRectangleFn;
typedef WcGuiFeatureActionFn WcGtk4FeatureActionFn;
typedef WcGuiFeatureReorderFn WcGtk4FeatureReorderFn;

int wc_gtk4_native_available(void);
int wc_gtk4_run(const WcGtk4WindowConfig *config,
                const WcGtk4Callbacks *callbacks,
                void *user_data);

#ifdef __cplusplus
}
#endif

#endif
