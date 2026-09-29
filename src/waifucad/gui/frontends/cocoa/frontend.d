/* Cocoa/AppKit front-end.
 *
 * Thin binding over the shared toolkit-neutral front-end core
 * (waifucad.gui.frontends.common.frontend): this module only declares the
 * native AppKit/Metal bridge symbols and instantiates the shared entry-point
 * templates. Behavioural changes belong in the shared core so every front-end
 * picks them up at once. The prefixed aliases keep the historical Cocoa names
 * valid for existing callers and regression contracts. */
module waifucad.gui.frontends.cocoa.frontend;

public import waifucad.gui.frontends.common.frontend;

import waifucad.gui.api : GuiFrontendV1, guiFrontendDescriptor;
import waifucad.gui.ribbon_host : RibbonHostState;
import waifucad.gui.command_console : CommandConsoleState;
import waifucad.journal.backend_api : ScriptContext;
import waifucad.kernel.model : Model;

extern(C) int wc_cocoa_native_available() nothrow @nogc;
extern(C) int wc_cocoa_run(const(WcGuiWindowConfig)*, const(WcGuiCallbacks)*, void*) nothrow @nogc;

// Historical prefixed names for the shared ABI structs and callback types.
alias WcCocoaWindowConfig = WcGuiWindowConfig;
alias WcCocoaModelSnapshot = WcGuiModelSnapshot;
alias WcCocoaFeatureRow = WcGuiFeatureRow;
alias WcCocoaBodyRow = WcGuiBodyRow;
alias WcCocoaMassProperties = WcGuiMassProperties;
alias WcCocoaCsysRow = WcGuiCsysRow;
alias WcCocoaSketchGeometryRow = WcGuiSketchGeometryRow;
alias WcCocoaPlanarFaceRow = WcGuiPlanarFaceRow;
alias WcCocoaSketchSupportKind = WcGuiSketchSupportKind;
alias WcCocoaSketchSupport = WcGuiSketchSupport;
alias WcCocoaSectionEntry = WcGuiSectionEntry;
alias WcCocoaRibbonTab = WcGuiRibbonTab;
alias WcCocoaRibbonCommand = WcGuiRibbonCommand;
alias WcCocoaRibbonSnapshot = WcGuiRibbonSnapshot;
alias WcCocoaCallbacks = WcGuiCallbacks;
alias CocoaFrontendContext = GuiFrontendContext;

enum WC_COCOA_FACE_MAX_POINTS = WC_GUI_FACE_MAX_POINTS;

alias WcCocoaSubmitCommandFn = WcGuiSubmitCommandFn;
alias WcCocoaChooseSectionFn = WcGuiChooseSectionFn;
alias WcCocoaActiveSectionFn = WcGuiActiveSectionFn;
alias WcCocoaSnapshotFn = WcGuiSnapshotFn;
alias WcCocoaFeatureRowsFn = WcGuiFeatureRowsFn;
alias WcCocoaBodyRowsFn = WcGuiBodyRowsFn;
alias WcCocoaMassPropertiesFn = WcGuiMassPropertiesFn;
alias WcCocoaCsysRowsFn = WcGuiCsysRowsFn;
alias WcCocoaSectionEntriesFn = WcGuiSectionEntriesFn;
alias WcCocoaActiveRibbonFn = WcGuiActiveRibbonFn;
alias WcCocoaRibbonTemplateFn = WcGuiRibbonTemplateFn;
alias WcCocoaFeatureDialogueFn = WcGuiFeatureDialogueFn;
alias WcCocoaFeatureDialogueForFeatureFn = WcGuiFeatureDialogueForFeatureFn;
alias WcCocoaFeatureDialogueValueFn = WcGuiFeatureDialogueValueFn;
alias WcCocoaFeatureDialogueAcceptSelectionFn = WcGuiFeatureDialogueAcceptSelectionFn;
alias WcCocoaBeginNewSketchFn = WcGuiBeginNewSketchFn;
alias WcCocoaEditSketchFn = WcGuiEditSketchFn;
alias WcCocoaFinishSketchFn = WcGuiFinishSketchFn;
alias WcCocoaSketchGeometryRowsFn = WcGuiSketchGeometryRowsFn;
alias WcCocoaPlanarFaceRowsFn = WcGuiPlanarFaceRowsFn;
alias WcCocoaSketchAddLineFn = WcGuiSketchAddLineFn;
alias WcCocoaSketchAddCircleFn = WcGuiSketchAddCircleFn;
alias WcCocoaSketchAddRectangleFn = WcGuiSketchAddRectangleFn;
alias WcCocoaFeatureActionFn = WcGuiFeatureActionFn;
alias WcCocoaFeatureReorderFn = WcGuiFeatureReorderFn;

// Historical prefixed names for the shared callback implementations.
alias cocoaSubmitCommand = guiSubmitCommand;
alias cocoaChooseSection = guiChooseSection;
alias cocoaActiveSection = guiActiveSection;
alias cocoaModelSnapshot = guiModelSnapshot;
alias cocoaFeatureRows = guiFeatureRows;
alias cocoaBodyRows = guiBodyRows;
alias cocoaMassProperties = guiMassProperties;
alias cocoaCsysRows = guiCsysRows;
alias cocoaSectionEntries = guiSectionEntries;
alias cocoaActiveRibbon = guiActiveRibbon;
alias cocoaRibbonTemplate = guiRibbonTemplate;
alias cocoaFeatureDialogue = guiFeatureDialogue;
alias cocoaFeatureDialogueForFeature = guiFeatureDialogueForFeature;
alias cocoaFeatureDialogueValue = guiFeatureDialogueValue;
alias cocoaFeatureDialogueAcceptSelection = guiFeatureDialogueAcceptSelection;
alias cocoaBeginNewSketch = guiBeginNewSketch;
alias cocoaEditSketch = guiEditSketch;
alias cocoaFinishSketch = guiFinishSketch;
alias cocoaSketchGeometryRows = guiSketchGeometryRows;
alias cocoaPlanarFaceRows = guiPlanarFaceRows;
alias cocoaSketchAddLine = guiSketchAddLine;
alias cocoaSketchAddCircle = guiSketchAddCircle;
alias cocoaSketchAddRectangle = guiSketchAddRectangle;
alias cocoaFeatureAction = guiFeatureAction;
alias cocoaFeatureReorder = guiFeatureReorder;

bool cocoaNativeAvailable() nothrow @nogc
{
    return guiFrontendAvailable!wc_cocoa_native_available();
}

int runCocoaNative(Model* model,
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
    return runGuiFrontend!wc_cocoa_run(model, script, ribbonHost, commandConsole,
        width, height, title, themeId, navigatorBackground, navigatorRailBackground,
        rendererHint, forceSoftwareVulkan);
}

GuiFrontendV1 cocoaDescriptor() nothrow @nogc
{
    return guiFrontendDescriptor("cocoa".ptr, "Cocoa / AppKit".ptr);
}
