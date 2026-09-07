module waifucad.gui.frontends.cocoa.frontend;

import core.stdc.stdio : snprintf;
import core.stdc.string : strcmp;
import waifucad.gui.api : GuiFrontendV1, WC_GUI_FRONTEND_ABI_V1;
import waifucad.gui.command_console : CommandConsoleState;
import waifucad.gui.ribbon_actions : ribbonCommandTemplate;
import waifucad.gui.ribbon_host : RibbonHostState;
import waifucad.journal.backend_api : ScriptContext;
import waifucad.kernel.model : Model;
import waifucad.kernel.types : ExactGeometryStatus, FeatureKind;
import waifucad.sections.ribbon : RibbonCommandFlags;

/*
 * Cocoa/AppKit is the native macOS front-end. This module owns the D side of
 * the wc_cocoa.h C ABI: the Objective-C bridge (native/gui/cocoa/wc_cocoa.m)
 * renders the window/ribbon/console/viewport and calls back through these
 * trampolines, which keep every model mutation on the shared semantic
 * SCL/journal command path, exactly like the GTK4 front-end.
 */

extern(C) struct WcCocoaWindowConfig
{
    int width;
    int height;
    const(char)* title;
    const(char)* themeId;
    const(char)* navigatorBackground;
    const(char)* navigatorRailBackground;
    const(char)* rendererHint;
    int forceSoftwareVulkan;
}

extern(C) struct WcCocoaSectionEntry
{
    const(char)* id;
    const(char)* icon;
    int active;
}

extern(C) struct WcCocoaRibbonCommand
{
    const(char)* id;
    const(char)* label;
    const(char)* tabId;
    const(char)* icon;
    const(char)* tabIcon;
    int planned;
}

extern(C) struct WcCocoaBodyRow
{
    uint featureId;
    const(char)* name;
    int exact;
    double[6] bounds;
}

extern(C) alias WcCocoaSubmitCommandFn = int function(void*, char*) nothrow @nogc;
extern(C) alias WcCocoaSectionEntriesFn = size_t function(void*, WcCocoaSectionEntry*, size_t) nothrow @nogc;
extern(C) alias WcCocoaChooseSectionFn = int function(void*, const(char)*) nothrow @nogc;
extern(C) alias WcCocoaRibbonCommandsFn = size_t function(void*, WcCocoaRibbonCommand*, size_t) nothrow @nogc;
extern(C) alias WcCocoaRunRibbonCommandFn = int function(void*, const(char)*) nothrow @nogc;
extern(C) alias WcCocoaBodyRowsFn = size_t function(void*, WcCocoaBodyRow*, size_t) nothrow @nogc;

extern(C) struct WcCocoaCallbacks
{
    WcCocoaSubmitCommandFn submitCommand;
    WcCocoaSectionEntriesFn sectionEntries;
    WcCocoaChooseSectionFn chooseSection;
    WcCocoaRibbonCommandsFn ribbonCommands;
    WcCocoaRunRibbonCommandFn runRibbonCommand;
    WcCocoaBodyRowsFn bodyRows;
}

extern(C) int wc_cocoa_native_available() nothrow @nogc;
extern(C) int wc_cocoa_run(const WcCocoaWindowConfig* config,
                           const WcCocoaCallbacks* callbacks,
                           void* userData) nothrow @nogc;

private struct CocoaFrontendContext
{
    Model* model;
    ScriptContext* script;
    RibbonHostState* ribbonHost;
    CommandConsoleState* commandConsole;
}

// Descriptor for the front-end registry.
GuiFrontendV1 cocoaDescriptor() nothrow @nogc
{
    GuiFrontendV1 result;
    result.abiVersion = WC_GUI_FRONTEND_ABI_V1;
    result.id = "cocoa".ptr;
    result.displayName = "Cocoa / AppKit".ptr;
    return result;
}

bool cocoaNativeAvailable() nothrow @nogc
{
    return wc_cocoa_native_available() != 0;
}

/* Mirrors the GTK4 graphics display policy: bodies and body-producing
   operations are viewport-displayable; sketches/datums/annotations are not. */
private bool cocoaGraphicsShowsBody(FeatureKind kind) nothrow @nogc
{
    switch (kind)
    {
        case FeatureKind.extrude:
        case FeatureKind.revolve:
        case FeatureKind.sweep:
        case FeatureKind.loft:
        case FeatureKind.dumbBody:
        case FeatureKind.import3d:
        case FeatureKind.heightSurface:
        case FeatureKind.box:
        case FeatureKind.cylinder:
        case FeatureKind.sphere:
        case FeatureKind.coneFrustum:
        case FeatureKind.torus:
        case FeatureKind.polyhedron:
        case FeatureKind.translate:
        case FeatureKind.rotate:
        case FeatureKind.rotateAxis:
        case FeatureKind.scale:
        case FeatureKind.resize:
        case FeatureKind.mirror:
        case FeatureKind.multMatrix:
        case FeatureKind.colour:
        case FeatureKind.displayModifier:
        case FeatureKind.hull:
        case FeatureKind.minkowski:
        case FeatureKind.booleanUnion:
        case FeatureKind.booleanSubtract:
        case FeatureKind.booleanIntersect:
        case FeatureKind.renderBarrier:
        case FeatureKind.fillet:
        case FeatureKind.chamfer:
        case FeatureKind.shell:
            return true;
        default:
            return false;
    }
}

private extern(C) int cocoaSubmitCommand(void* opaque, char* command) nothrow @nogc
{
    auto context = cast(CocoaFrontendContext*)opaque;
    if (context is null || context.commandConsole is null || context.script is null || command is null)
        return 10;
    return context.commandConsole.submit(context.script, command);
}

private extern(C) size_t cocoaSectionEntries(void* opaque, WcCocoaSectionEntry* rows, size_t capacity) nothrow @nogc
{
    auto context = cast(CocoaFrontendContext*)opaque;
    if (context is null || context.ribbonHost is null)
        return 0;
    size_t count = 0;
    auto entries = context.ribbonHost.sectionLauncherEntries(&count);
    if (entries is null)
        return 0;
    size_t written = 0;
    foreach (i; 0 .. count)
    {
        if (rows !is null && written < capacity)
        {
            rows[written].id = entries[i].id;
            rows[written].icon = entries[i].iconName;
            rows[written].active = context.ribbonHost.sections.isActive(entries[i].id) ? 1 : 0;
        }
        ++written;
    }
    return written;
}

private extern(C) int cocoaChooseSection(void* opaque, const(char)* sectionId) nothrow @nogc
{
    auto context = cast(CocoaFrontendContext*)opaque;
    if (context is null || context.ribbonHost is null || sectionId is null)
        return 10;
    return context.ribbonHost.chooseSection(sectionId) ? 0 : 11;
}

private extern(C) size_t cocoaRibbonCommands(void* opaque, WcCocoaRibbonCommand* rows, size_t capacity) nothrow @nogc
{
    auto context = cast(CocoaFrontendContext*)opaque;
    if (context is null || context.ribbonHost is null)
        return 0;
    auto ribbon = context.ribbonHost.contextualRibbon();
    if (ribbon is null || ribbon.commands is null)
        return 0;
    size_t written = 0;
    foreach (i; 0 .. ribbon.commandCount)
    {
        if (rows !is null && written < capacity)
        {
            rows[written].id = ribbon.commands[i].id;
            rows[written].label = ribbon.commands[i].localisationKey !is null
                ? ribbon.commands[i].localisationKey
                : ribbon.commands[i].id;
            rows[written].tabId = ribbon.commands[i].tabId;
            rows[written].icon = ribbon.commands[i].iconName;
            rows[written].tabIcon = null;
            foreach (t; 0 .. ribbon.tabCount)
            {
                if (ribbon.tabs[t].id !is null && ribbon.commands[i].tabId !is null &&
                    strcmp(ribbon.tabs[t].id, ribbon.commands[i].tabId) == 0)
                {
                    rows[written].tabIcon = ribbon.tabs[t].iconName;
                    break;
                }
            }
            rows[written].planned = (ribbon.commands[i].flags & RibbonCommandFlags.planned) != 0 ? 1 : 0;
        }
        ++written;
    }
    return written;
}

/* Ribbon buttons execute their semantic SCL template through the shared
   console path. Data-driven feature dialogues remain GTK4-only for now; the
   Cocoa bridge reports the SCL result in its status line instead. */
private extern(C) int cocoaRunRibbonCommand(void* opaque, const(char)* commandId) nothrow @nogc
{
    auto context = cast(CocoaFrontendContext*)opaque;
    if (context is null || context.commandConsole is null || context.script is null || commandId is null)
        return 10;
    auto commandTemplate = ribbonCommandTemplate(commandId);
    if (commandTemplate is null || commandTemplate[0] == 0)
        return 11;
    char[512] buffer;
    auto written = snprintf(buffer.ptr, buffer.length, "%s", commandTemplate);
    if (written <= 0 || cast(size_t)written >= buffer.length)
        return 12;
    return context.commandConsole.submit(context.script, buffer.ptr);
}

private extern(C) size_t cocoaBodyRows(void* opaque, WcCocoaBodyRow* rows, size_t capacity) nothrow @nogc
{
    auto context = cast(CocoaFrontendContext*)opaque;
    if (context is null || context.model is null)
        return 0;
    size_t visible = 0;
    foreach (i; 0 .. context.model.featureCount)
    {
        auto feature = &context.model.features[i];
        if (!cocoaGraphicsShowsBody(feature.kind) || !context.model.previewBounds[i].valid)
            continue;
        if (rows !is null && visible < capacity)
        {
            auto bounds = &context.model.previewBounds[i];
            rows[visible].featureId = feature.id;
            rows[visible].name = feature.name.ptr();
            rows[visible].exact = context.model.exactStatus[i] == ExactGeometryStatus.exact ? 1 : 0;
            rows[visible].bounds[0] = bounds.minX;
            rows[visible].bounds[1] = bounds.minY;
            rows[visible].bounds[2] = bounds.minZ;
            rows[visible].bounds[3] = bounds.maxX;
            rows[visible].bounds[4] = bounds.maxY;
            rows[visible].bounds[5] = bounds.maxZ;
        }
        ++visible;
    }
    return visible;
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
    if (model is null || script is null || ribbonHost is null || commandConsole is null)
        return 10;

    CocoaFrontendContext frontendContext;
    frontendContext.model = model;
    frontendContext.script = script;
    frontendContext.ribbonHost = ribbonHost;
    frontendContext.commandConsole = commandConsole;

    WcCocoaWindowConfig config;
    config.width = width;
    config.height = height;
    config.title = title;
    config.themeId = themeId;
    config.navigatorBackground = navigatorBackground;
    config.navigatorRailBackground = navigatorRailBackground;
    config.rendererHint = rendererHint;
    config.forceSoftwareVulkan = forceSoftwareVulkan ? 1 : 0;

    WcCocoaCallbacks callbacks;
    callbacks.submitCommand = &cocoaSubmitCommand;
    callbacks.sectionEntries = &cocoaSectionEntries;
    callbacks.chooseSection = &cocoaChooseSection;
    callbacks.ribbonCommands = &cocoaRibbonCommands;
    callbacks.runRibbonCommand = &cocoaRunRibbonCommand;
    callbacks.bodyRows = &cocoaBodyRows;

    return wc_cocoa_run(&config, &callbacks, &frontendContext);
}
