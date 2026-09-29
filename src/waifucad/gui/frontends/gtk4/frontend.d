/* GTK4 front-end.
 *
 * Thin binding over the shared toolkit-neutral front-end core
 * (waifucad.gui.frontends.common.frontend): this module only declares the
 * native GTK4 bridge symbols and instantiates the shared entry-point
 * templates. Behavioural changes belong in the shared core so every front-end
 * picks them up at once. The prefixed aliases keep the historical GTK4 names
 * valid for existing callers and regression contracts. */
module waifucad.gui.frontends.gtk4.frontend;

public import waifucad.gui.frontends.common.frontend;

import waifucad.gui.api : GuiFrontendV1, guiFrontendDescriptor;
import waifucad.gui.ribbon_host : RibbonHostState;
import waifucad.gui.command_console : CommandConsoleState;
import waifucad.journal.backend_api : ScriptContext;
import waifucad.kernel.model : Model;

extern(C) int wc_gtk4_native_available() nothrow @nogc;
extern(C) int wc_gtk4_run(const(WcGuiWindowConfig)*, const(WcGuiCallbacks)*, void*) nothrow @nogc;

// Historical prefixed names for the shared ABI structs and callback types.
alias WcGtk4WindowConfig = WcGuiWindowConfig;
alias WcGtk4ModelSnapshot = WcGuiModelSnapshot;
alias WcGtk4FeatureRow = WcGuiFeatureRow;
alias WcGtk4BodyRow = WcGuiBodyRow;
alias WcGtk4MassProperties = WcGuiMassProperties;
alias WcGtk4CsysRow = WcGuiCsysRow;
alias WcGtk4SketchGeometryRow = WcGuiSketchGeometryRow;
alias WcGtk4PlanarFaceRow = WcGuiPlanarFaceRow;
alias WcGtk4SketchSupportKind = WcGuiSketchSupportKind;
alias WcGtk4SketchSupport = WcGuiSketchSupport;
alias WcGtk4SectionEntry = WcGuiSectionEntry;
alias WcGtk4RibbonTab = WcGuiRibbonTab;
alias WcGtk4RibbonCommand = WcGuiRibbonCommand;
alias WcGtk4RibbonSnapshot = WcGuiRibbonSnapshot;
alias WcGtk4Callbacks = WcGuiCallbacks;
alias Gtk4FrontendContext = GuiFrontendContext;

enum WC_GTK4_FACE_MAX_POINTS = WC_GUI_FACE_MAX_POINTS;

alias WcGtk4SubmitCommandFn = WcGuiSubmitCommandFn;
alias WcGtk4ChooseSectionFn = WcGuiChooseSectionFn;
alias WcGtk4ActiveSectionFn = WcGuiActiveSectionFn;
alias WcGtk4SnapshotFn = WcGuiSnapshotFn;
alias WcGtk4FeatureRowsFn = WcGuiFeatureRowsFn;
alias WcGtk4BodyRowsFn = WcGuiBodyRowsFn;
alias WcGtk4MassPropertiesFn = WcGuiMassPropertiesFn;
alias WcGtk4CsysRowsFn = WcGuiCsysRowsFn;
alias WcGtk4SectionEntriesFn = WcGuiSectionEntriesFn;
alias WcGtk4ActiveRibbonFn = WcGuiActiveRibbonFn;
alias WcGtk4RibbonTemplateFn = WcGuiRibbonTemplateFn;
alias WcGtk4FeatureDialogueFn = WcGuiFeatureDialogueFn;
alias WcGtk4FeatureDialogueForFeatureFn = WcGuiFeatureDialogueForFeatureFn;
alias WcGtk4FeatureDialogueValueFn = WcGuiFeatureDialogueValueFn;
alias WcGtk4FeatureDialogueAcceptSelectionFn = WcGuiFeatureDialogueAcceptSelectionFn;
alias WcGtk4BeginNewSketchFn = WcGuiBeginNewSketchFn;
alias WcGtk4EditSketchFn = WcGuiEditSketchFn;
alias WcGtk4FinishSketchFn = WcGuiFinishSketchFn;
alias WcGtk4SketchGeometryRowsFn = WcGuiSketchGeometryRowsFn;
alias WcGtk4PlanarFaceRowsFn = WcGuiPlanarFaceRowsFn;
alias WcGtk4SketchAddLineFn = WcGuiSketchAddLineFn;
alias WcGtk4SketchAddCircleFn = WcGuiSketchAddCircleFn;
alias WcGtk4SketchAddRectangleFn = WcGuiSketchAddRectangleFn;
alias WcGtk4FeatureActionFn = WcGuiFeatureActionFn;
alias WcGtk4FeatureReorderFn = WcGuiFeatureReorderFn;

// Historical prefixed names for the shared callback implementations.
alias gtk4SubmitCommand = guiSubmitCommand;
alias gtk4ChooseSection = guiChooseSection;
alias gtk4ActiveSection = guiActiveSection;
alias gtk4ModelSnapshot = guiModelSnapshot;
alias gtk4FeatureRows = guiFeatureRows;
alias gtk4BodyRows = guiBodyRows;
alias gtk4MassProperties = guiMassProperties;
alias gtk4CsysRows = guiCsysRows;
alias gtk4SectionEntries = guiSectionEntries;
alias gtk4ActiveRibbon = guiActiveRibbon;
alias gtk4RibbonTemplate = guiRibbonTemplate;
alias gtk4FeatureDialogue = guiFeatureDialogue;
alias gtk4FeatureDialogueForFeature = guiFeatureDialogueForFeature;
alias gtk4FeatureDialogueValue = guiFeatureDialogueValue;
alias gtk4FeatureDialogueAcceptSelection = guiFeatureDialogueAcceptSelection;
alias gtk4BeginNewSketch = guiBeginNewSketch;
alias gtk4EditSketch = guiEditSketch;
alias gtk4FinishSketch = guiFinishSketch;
alias gtk4SketchGeometryRows = guiSketchGeometryRows;
alias gtk4PlanarFaceRows = guiPlanarFaceRows;
alias gtk4SketchAddLine = guiSketchAddLine;
alias gtk4SketchAddCircle = guiSketchAddCircle;
alias gtk4SketchAddRectangle = guiSketchAddRectangle;
alias gtk4FeatureAction = guiFeatureAction;
alias gtk4FeatureReorder = guiFeatureReorder;

bool gtk4NativeAvailable() nothrow @nogc
{
    return guiFrontendAvailable!wc_gtk4_native_available();
}

int runGtk4Native(Model* model,
                  ScriptContext* script,
                  RibbonHostState* ribbonHost,
                  CommandConsoleState* commandConsole,
                  int width,
                  int height,
                  const(char)* title,
                  const(char)* themeId,
                  const(char)* navigatorBackground,
                  const(char)* navigatorRailBackground,
                  const(char)* rendererHint,
                  bool forceSoftwareVulkan) nothrow @nogc
{
    return runGuiFrontend!wc_gtk4_run(model, script, ribbonHost, commandConsole,
        width, height, title, themeId, navigatorBackground, navigatorRailBackground,
        rendererHint, forceSoftwareVulkan);
}

GuiFrontendV1 gtk4Descriptor() nothrow @nogc
{
    return guiFrontendDescriptor("gtk4".ptr, "GTK4".ptr);
}
