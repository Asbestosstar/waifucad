module waifucad.gui.frontends.cocoa.frontend;

import core.stdc.stdio : snprintf;
import waifucad.gui.api : GuiFrontendV1, WC_GUI_FRONTEND_ABI_V1;
import waifucad.gui.command_console : CommandConsoleState;
import waifucad.gui.ribbon_actions : ribbonCommandTemplate;
import waifucad.gui.ribbon_host : RibbonHostState;
import waifucad.journal.backend_api : ScriptContext;
import waifucad.kernel.datums : DatumFrame, datumFeatureFrame, sketchFrame;
import waifucad.kernel.model : Model;
import waifucad.kernel.types : ExactGeometryStatus, FeatureKind, OperandKind;
import waifucad.brep.naming : persistentTopologyOwner, persistentTopologySlot;
import waifucad.brep.properties : massProperties;
import waifucad.brep.types : BRepSurfaceKind;
import waifucad.sections.api : SectionDescriptorV1;
import waifucad.sections.ribbon : SectionRibbonV1;

/*
 * Cocoa/AppKit is the native macOS front-end. This module owns the D side of
 * the wc_cocoa.h C ABI, which mirrors the GTK4 bridge ABI: the same
 * toolkit-neutral ribbon/section descriptors are passed straight through and
 * the same semantic row data feeds both hosts. Every model mutation from the
 * AppKit bridge arrives as a semantic SCL command through the shared console
 * path, exactly like GTK4; nothing here exposes raw model pointers to the
 * toolkit beyond borrowed descriptor/row data with the same lifetimes GTK4
 * already relies on.
 *
 * Not yet wired for Cocoa (tracked parity work): data-driven feature
 * dialogues and interactive sketch mode (begin/edit/finish, sketch_add_*).
 */

enum WC_COCOA_FACE_MAX_POINTS = 24u;

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

extern(C) struct WcCocoaModelSnapshot
{
    const(char)* modelName;
    double minX, minY, minZ;
    double maxX, maxY, maxZ;
    uint featureCount;
    uint exactCount;
    uint previewCount;
    uint failedCount;
    int boundsValid;
}

extern(C) struct WcCocoaFeatureRow
{
    uint id;
    const(char)* name;
    const(char)* kindName;
    uint kind;
    uint exactStatus;
    uint dependencyDepth;
    uint dirty;
}

extern(C) struct WcCocoaBodyRow
{
    uint featureId;
    const(char)* name;
    uint kind;
    uint exactStatus;
    double minX, minY, minZ;
    double maxX, maxY, maxZ;
}

extern(C) struct WcCocoaMassProperties
{
    int valid;
    double volume;
    double surfaceArea;
    double[3] centreOfMass;
}

extern(C) struct WcCocoaCsysRow
{
    uint featureId;
    const(char)* name;
    double[3] origin;
    double[3] xAxis;
    double[3] yAxis;
    double[3] zAxis;
}

extern(C) struct WcCocoaSketchGeometryRow
{
    uint id;
    uint sketchId;
    uint kind;
    double[6] values;
    int frameValid;
    double[3] frameOrigin;
    double[3] frameXAxis;
    double[3] frameYAxis;
}

extern(C) struct WcCocoaPlanarFaceRow
{
    ulong persistentId;
    uint ownerFeatureId;
    uint semanticSlot;
    const(char)* ownerName;
    uint pointCount;
    double[WC_COCOA_FACE_MAX_POINTS * 3u] points;
}

/* Layout-compatible with SectionDescriptorV1 (borrowed pointer array). */
extern(C) struct WcCocoaSectionEntry
{
    uint abiVersion;
    const(char)* id;
    const(char)* localisationKey;
    const(char)* iconName;
    uint capabilities;
}

/* Layout-compatible with RibbonTabDescriptorV1 / RibbonCommandDescriptorV1 /
   SectionRibbonV1 so the contextual ribbon is passed straight through. */
extern(C) struct WcCocoaRibbonTab
{
    const(char)* id;
    const(char)* localisationKey;
    const(char)* iconName;
}

extern(C) struct WcCocoaRibbonCommand
{
    const(char)* id;
    const(char)* localisationKey;
    const(char)* iconName;
    const(char)* tabId;
    const(char)* groupId;
    uint flags;
}

extern(C) struct WcCocoaRibbonSnapshot
{
    const(char)* sectionId;
    const(WcCocoaRibbonTab)* tabs;
    size_t tabCount;
    const(WcCocoaRibbonCommand)* commands;
    size_t commandCount;
}

extern(C) alias WcCocoaSubmitCommandFn = int function(void*, char*) nothrow @nogc;
extern(C) alias WcCocoaChooseSectionFn = int function(void*, const(char)*) nothrow @nogc;
extern(C) alias WcCocoaActiveSectionFn = const(char)* function(void*) nothrow @nogc;
extern(C) alias WcCocoaSnapshotFn = void function(void*, WcCocoaModelSnapshot*) nothrow @nogc;
extern(C) alias WcCocoaFeatureRowsFn = size_t function(void*, WcCocoaFeatureRow*, size_t) nothrow @nogc;
extern(C) alias WcCocoaBodyRowsFn = size_t function(void*, WcCocoaBodyRow*, size_t) nothrow @nogc;
extern(C) alias WcCocoaMassPropertiesFn = int function(void*, uint, WcCocoaMassProperties*) nothrow @nogc;
extern(C) alias WcCocoaCsysRowsFn = size_t function(void*, WcCocoaCsysRow*, size_t) nothrow @nogc;
extern(C) alias WcCocoaSectionEntriesFn = const(WcCocoaSectionEntry)* function(void*, size_t*) nothrow @nogc;
extern(C) alias WcCocoaActiveRibbonFn = const(WcCocoaRibbonSnapshot)* function(void*) nothrow @nogc;
extern(C) alias WcCocoaRibbonTemplateFn = const(char)* function(void*, const(char)*) nothrow @nogc;
extern(C) alias WcCocoaSketchGeometryRowsFn = size_t function(void*, uint, WcCocoaSketchGeometryRow*, size_t) nothrow @nogc;
extern(C) alias WcCocoaPlanarFaceRowsFn = size_t function(void*, WcCocoaPlanarFaceRow*, size_t) nothrow @nogc;
extern(C) alias WcCocoaFeatureActionFn = int function(void*, uint, int) nothrow @nogc;
extern(C) alias WcCocoaFeatureReorderFn = int function(void*, uint, uint, int) nothrow @nogc;

extern(C) struct WcCocoaCallbacks
{
    WcCocoaSubmitCommandFn submitCommand;
    WcCocoaChooseSectionFn chooseSection;
    WcCocoaActiveSectionFn activeSection;
    WcCocoaSnapshotFn modelSnapshot;
    WcCocoaFeatureRowsFn featureRows;
    WcCocoaBodyRowsFn bodyRows;
    WcCocoaMassPropertiesFn massProperties;
    WcCocoaCsysRowsFn csysRows;
    WcCocoaSectionEntriesFn sectionEntries;
    WcCocoaActiveRibbonFn activeRibbon;
    WcCocoaRibbonTemplateFn ribbonTemplate;
    WcCocoaSketchGeometryRowsFn sketchGeometryRows;
    WcCocoaPlanarFaceRowsFn planarFaceRows;
    WcCocoaFeatureActionFn featureAction;
    WcCocoaFeatureReorderFn featureReorder;
}

extern(C) int wc_cocoa_native_available() nothrow @nogc;
extern(C) int wc_cocoa_run(const WcCocoaWindowConfig*, const WcCocoaCallbacks*, void*) nothrow @nogc;

struct CocoaFrontendContext
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

private int submitGenerated(CocoaFrontendContext* context, char* command) nothrow @nogc
{
    if (context is null || context.commandConsole is null || context.script is null || command is null)
        return 10;
    return context.commandConsole.submit(context.script, command);
}

private extern(C) int cocoaSubmitCommand(void* opaque, char* command) nothrow @nogc
{
    return submitGenerated(cast(CocoaFrontendContext*)opaque, command);
}

private extern(C) int cocoaChooseSection(void* opaque, const(char)* sectionId) nothrow @nogc
{
    auto context = cast(CocoaFrontendContext*)opaque;
    if (context is null || context.ribbonHost is null || sectionId is null)
        return 0;
    return context.ribbonHost.chooseSection(sectionId) ? 1 : 0;
}

private extern(C) const(char)* cocoaActiveSection(void* opaque) nothrow @nogc
{
    auto context = cast(CocoaFrontendContext*)opaque;
    if (context is null || context.ribbonHost is null)
        return "none".ptr;
    return context.ribbonHost.sections.activeId();
}

private const(char)* featureKindName(FeatureKind kind) nothrow @nogc
{
    final switch (kind)
    {
        case FeatureKind.none: return "none".ptr;
        case FeatureKind.sketch: return "sketch".ptr;
        case FeatureKind.sketchLine: return "sketch line".ptr;
        case FeatureKind.sketchArc: return "sketch arc".ptr;
        case FeatureKind.sketchCircle: return "sketch circle".ptr;
        case FeatureKind.sketchRectangle: return "sketch rectangle".ptr;
        case FeatureKind.sketchPolygon: return "sketch polygon".ptr;
        case FeatureKind.sketchText: return "sketch text".ptr;
        case FeatureKind.datumPlane: return "datum plane".ptr;
        case FeatureKind.datumAxis: return "datum axis".ptr;
        case FeatureKind.datumCsys: return "datum CSYS".ptr;
        case FeatureKind.extrude: return "extrude".ptr;
        case FeatureKind.revolve: return "revolve".ptr;
        case FeatureKind.sweep: return "sweep".ptr;
        case FeatureKind.loft: return "loft".ptr;
        case FeatureKind.freePoint: return "point".ptr;
        case FeatureKind.freeLine: return "line".ptr;
        case FeatureKind.freeArc: return "arc".ptr;
        case FeatureKind.freeCircle: return "circle".ptr;
        case FeatureKind.freeSpline: return "spline".ptr;
        case FeatureKind.dumbBody: return "dumb body".ptr;
        case FeatureKind.import2d: return "2D import".ptr;
        case FeatureKind.import3d: return "3D import".ptr;
        case FeatureKind.heightSurface: return "height surface".ptr;
        case FeatureKind.box: return "box".ptr;
        case FeatureKind.cylinder: return "cylinder".ptr;
        case FeatureKind.sphere: return "sphere".ptr;
        case FeatureKind.coneFrustum: return "cone/frustum".ptr;
        case FeatureKind.torus: return "torus".ptr;
        case FeatureKind.polyhedron: return "polyhedron".ptr;
        case FeatureKind.circle2d: return "2D circle".ptr;
        case FeatureKind.square2d: return "2D square".ptr;
        case FeatureKind.polygon2d: return "2D polygon".ptr;
        case FeatureKind.text2d: return "2D text".ptr;
        case FeatureKind.translate: return "translate".ptr;
        case FeatureKind.rotate: return "rotate".ptr;
        case FeatureKind.rotateAxis: return "axis rotate".ptr;
        case FeatureKind.scale: return "scale".ptr;
        case FeatureKind.resize: return "resize".ptr;
        case FeatureKind.mirror: return "mirror".ptr;
        case FeatureKind.multMatrix: return "matrix".ptr;
        case FeatureKind.colour: return "colour".ptr;
        case FeatureKind.displayModifier: return "display modifier".ptr;
        case FeatureKind.offset2d: return "offset".ptr;
        case FeatureKind.projection: return "projection".ptr;
        case FeatureKind.hull: return "hull".ptr;
        case FeatureKind.minkowski: return "minkowski".ptr;
        case FeatureKind.booleanUnion: return "union".ptr;
        case FeatureKind.booleanSubtract: return "subtract".ptr;
        case FeatureKind.booleanIntersect: return "intersect".ptr;
        case FeatureKind.renderBarrier: return "render".ptr;
        case FeatureKind.fillet: return "fillet".ptr;
        case FeatureKind.chamfer: return "chamfer".ptr;
        case FeatureKind.shell: return "shell".ptr;
    }
}

private extern(C) void cocoaModelSnapshot(void* opaque, WcCocoaModelSnapshot* snapshot) nothrow @nogc
{
    auto context = cast(CocoaFrontendContext*)opaque;
    if (snapshot is null)
        return;
    *snapshot = WcCocoaModelSnapshot.init;
    if (context is null || context.model is null)
        return;

    auto model = context.model;
    snapshot.modelName = model.name.ptr();
    snapshot.featureCount = cast(uint)model.featureCount;
    foreach (i; 0 .. model.featureCount)
    {
        final switch (model.exactStatus[i])
        {
            case ExactGeometryStatus.exact: ++snapshot.exactCount; break;
            case ExactGeometryStatus.previewOnly: ++snapshot.previewCount; break;
            case ExactGeometryStatus.failed: ++snapshot.failedCount; break;
            case ExactGeometryStatus.none: break;
        }

        auto bounds = &model.previewBounds[i];
        if (!bounds.valid)
            continue;
        if (snapshot.boundsValid == 0)
        {
            snapshot.minX = bounds.minX;
            snapshot.minY = bounds.minY;
            snapshot.minZ = bounds.minZ;
            snapshot.maxX = bounds.maxX;
            snapshot.maxY = bounds.maxY;
            snapshot.maxZ = bounds.maxZ;
            snapshot.boundsValid = 1;
        }
        else
        {
            if (bounds.minX < snapshot.minX) snapshot.minX = bounds.minX;
            if (bounds.minY < snapshot.minY) snapshot.minY = bounds.minY;
            if (bounds.minZ < snapshot.minZ) snapshot.minZ = bounds.minZ;
            if (bounds.maxX > snapshot.maxX) snapshot.maxX = bounds.maxX;
            if (bounds.maxY > snapshot.maxY) snapshot.maxY = bounds.maxY;
            if (bounds.maxZ > snapshot.maxZ) snapshot.maxZ = bounds.maxZ;
        }
    }
}

private bool navigatorShowsFeature(FeatureKind kind) nothrow @nogc
{
    return kind != FeatureKind.sketchLine && kind != FeatureKind.sketchArc &&
           kind != FeatureKind.sketchCircle && kind != FeatureKind.sketchRectangle &&
           kind != FeatureKind.sketchPolygon && kind != FeatureKind.sketchText;
}

/* Mirrors the GTK4 graphics display policy: bodies and body-producing
   operations are viewport-displayable; sketches/datums/annotations are not. */
private bool graphicsShowsBody(FeatureKind kind) nothrow @nogc
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

private extern(C) size_t cocoaFeatureRows(void* opaque, WcCocoaFeatureRow* rows, size_t capacity) nothrow @nogc
{
    auto context = cast(CocoaFrontendContext*)opaque;
    if (context is null || context.model is null)
        return 0;
    size_t visible = 0;
    foreach (i; 0 .. context.model.featureCount)
    {
        auto feature = &context.model.features[i];
        if (!navigatorShowsFeature(feature.kind))
            continue;
        if (rows !is null && visible < capacity)
        {
            rows[visible].id = feature.id;
            rows[visible].name = feature.name.ptr();
            rows[visible].kindName = featureKindName(feature.kind);
            rows[visible].kind = cast(uint)feature.kind;
            rows[visible].exactStatus = cast(uint)context.model.exactStatus[i];
            rows[visible].dependencyDepth = feature.dependencyDepth;
            rows[visible].dirty = feature.dirty ? 1u : 0u;
        }
        ++visible;
    }
    return visible;
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
        if (!graphicsShowsBody(feature.kind) || !context.model.previewBounds[i].valid)
            continue;
        if (rows !is null && visible < capacity)
        {
            auto bounds = &context.model.previewBounds[i];
            rows[visible].featureId = feature.id;
            rows[visible].name = feature.name.ptr();
            rows[visible].kind = cast(uint)feature.kind;
            rows[visible].exactStatus = cast(uint)context.model.exactStatus[i];
            rows[visible].minX = bounds.minX;
            rows[visible].minY = bounds.minY;
            rows[visible].minZ = bounds.minZ;
            rows[visible].maxX = bounds.maxX;
            rows[visible].maxY = bounds.maxY;
            rows[visible].maxZ = bounds.maxZ;
        }
        ++visible;
    }
    return visible;
}

private extern(C) int cocoaMassProperties(void* opaque, uint featureId, WcCocoaMassProperties* result) nothrow @nogc
{
    auto context = cast(CocoaFrontendContext*)opaque;
    if (context is null || context.model is null || result is null)
        return 10;
    *result = WcCocoaMassProperties.init;
    auto index = context.model.featureIndexById(featureId);
    if (index >= context.model.featureCount ||
        context.model.exactStatus[index] != ExactGeometryStatus.exact ||
        context.model.exactSolidIds[index] == 0)
        return 11;
    auto properties = massProperties(&context.model.exactGeometry, context.model.exactSolidIds[index]);
    if (!properties.valid)
        return 12;
    result.valid = 1;
    result.volume = properties.volume;
    result.surfaceArea = properties.surfaceArea;
    result.centreOfMass[0] = properties.centreOfMass.x;
    result.centreOfMass[1] = properties.centreOfMass.y;
    result.centreOfMass[2] = properties.centreOfMass.z;
    return 0;
}

private extern(C) size_t cocoaCsysRows(void* opaque, WcCocoaCsysRow* rows, size_t capacity) nothrow @nogc
{
    auto context = cast(CocoaFrontendContext*)opaque;
    if (context is null || context.model is null)
        return 0;
    size_t visible = 0;
    foreach (i; 0 .. context.model.featureCount)
    {
        auto feature = &context.model.features[i];
        if (feature.kind != FeatureKind.datumCsys)
            continue;
        DatumFrame frame;
        if (!datumFeatureFrame(context.model, feature.id, &frame) || !frame.valid)
            continue;
        if (rows !is null && visible < capacity)
        {
            rows[visible].featureId = feature.id;
            rows[visible].name = feature.name.ptr();
            rows[visible].origin[0] = frame.origin.x; rows[visible].origin[1] = frame.origin.y; rows[visible].origin[2] = frame.origin.z;
            rows[visible].xAxis[0] = frame.xAxis.x; rows[visible].xAxis[1] = frame.xAxis.y; rows[visible].xAxis[2] = frame.xAxis.z;
            rows[visible].yAxis[0] = frame.yAxis.x; rows[visible].yAxis[1] = frame.yAxis.y; rows[visible].yAxis[2] = frame.yAxis.z;
            rows[visible].zAxis[0] = frame.zAxis.x; rows[visible].zAxis[1] = frame.zAxis.y; rows[visible].zAxis[2] = frame.zAxis.z;
        }
        ++visible;
    }
    return visible;
}

private extern(C) const(WcCocoaSectionEntry)* cocoaSectionEntries(void* opaque, size_t* count) nothrow @nogc
{
    auto context = cast(CocoaFrontendContext*)opaque;
    if (context is null || context.ribbonHost is null)
    {
        if (count !is null) *count = 0;
        return null;
    }
    SectionDescriptorV1* entries = context.ribbonHost.sectionLauncherEntries(count);
    return cast(const(WcCocoaSectionEntry)*)entries;
}

private extern(C) const(WcCocoaRibbonSnapshot)* cocoaActiveRibbon(void* opaque) nothrow @nogc
{
    auto context = cast(CocoaFrontendContext*)opaque;
    if (context is null || context.ribbonHost is null)
        return null;
    const(SectionRibbonV1)* ribbon = context.ribbonHost.contextualRibbon();
    return cast(const(WcCocoaRibbonSnapshot)*)ribbon;
}

private extern(C) const(char)* cocoaRibbonTemplate(void* opaque, const(char)* commandId) nothrow @nogc
{
    return ribbonCommandTemplate(commandId);
}

private extern(C) size_t cocoaSketchGeometryRows(void* opaque, uint sketchId, WcCocoaSketchGeometryRow* rows, size_t capacity) nothrow @nogc
{
    auto context = cast(CocoaFrontendContext*)opaque;
    if (context is null || context.model is null)
        return 0;
    size_t count = 0;
    foreach (i; 0 .. context.model.featureCount)
    {
        auto feature = &context.model.features[i];
        if (feature.operandCount == 0 || feature.operands[0].kind != OperandKind.feature || feature.operands[0].featureId != sketchId)
            continue;
        bool supported = feature.kind == FeatureKind.sketchLine || feature.kind == FeatureKind.sketchArc ||
                         feature.kind == FeatureKind.sketchCircle || feature.kind == FeatureKind.sketchRectangle;
        if (!supported)
            continue;
        if (rows !is null && count < capacity)
        {
            auto row = &rows[count];
            *row = WcCocoaSketchGeometryRow.init;
            row.id = feature.id;
            row.sketchId = sketchId;
            row.kind = cast(uint)feature.kind;
            auto sketch = context.model.featureById(sketchId);
            DatumFrame frame;
            if (sketch !is null && sketch.kind == FeatureKind.sketch &&
                sketchFrame(context.model, sketchId, &frame) && frame.valid)
            {
                row.frameValid = 1;
                row.frameOrigin[0] = frame.origin.x; row.frameOrigin[1] = frame.origin.y; row.frameOrigin[2] = frame.origin.z;
                row.frameXAxis[0] = frame.xAxis.x; row.frameXAxis[1] = frame.xAxis.y; row.frameXAxis[2] = frame.xAxis.z;
                row.frameYAxis[0] = frame.yAxis.x; row.frameYAxis[1] = frame.yAxis.y; row.frameYAxis[2] = frame.yAxis.z;
            }
            switch (feature.kind)
            {
                case FeatureKind.sketchLine:
                    if (feature.operandCount >= 5)
                        foreach (j; 0 .. 4) row.values[j] = context.model.resolveOperand(&feature.operands[j + 1]);
                    break;
                case FeatureKind.sketchArc:
                    if (feature.operandCount >= 6)
                        foreach (j; 0 .. 5) row.values[j] = context.model.resolveOperand(&feature.operands[j + 1]);
                    break;
                case FeatureKind.sketchCircle:
                    if (feature.operandCount >= 4)
                    {
                        row.values[0] = context.model.resolveOperand(&feature.operands[1]);
                        row.values[1] = context.model.resolveOperand(&feature.operands[2]);
                        row.values[2] = context.model.resolveOperand(&feature.operands[3]);
                    }
                    else if (feature.operandCount >= 2)
                        row.values[2] = context.model.resolveOperand(&feature.operands[1]);
                    break;
                case FeatureKind.sketchRectangle:
                    if (feature.operandCount >= 5)
                    {
                        row.values[0] = context.model.resolveOperand(&feature.operands[1]);
                        row.values[1] = context.model.resolveOperand(&feature.operands[2]);
                        row.values[2] = context.model.resolveOperand(&feature.operands[3]);
                        row.values[3] = context.model.resolveOperand(&feature.operands[4]);
                    }
                    else if (feature.operandCount >= 3)
                    {
                        auto width = context.model.resolveOperand(&feature.operands[1]);
                        auto height = context.model.resolveOperand(&feature.operands[2]);
                        auto centred = feature.operandCount >= 4 && context.model.resolveOperand(&feature.operands[3]) != 0.0;
                        row.values[0] = centred ? -width * 0.5 : 0.0;
                        row.values[1] = centred ? -height * 0.5 : 0.0;
                        row.values[2] = width;
                        row.values[3] = height;
                    }
                    break;
                default: break;
            }
        }
        ++count;
    }
    return count;
}

private extern(C) size_t cocoaPlanarFaceRows(void* opaque, WcCocoaPlanarFaceRow* rows, size_t capacity) nothrow @nogc
{
    auto context = cast(CocoaFrontendContext*)opaque;
    if (context is null || context.model is null) return 0;
    auto arena = &context.model.exactGeometry;
    size_t count = 0;
    foreach (i; 0 .. arena.faceCount)
    {
        auto face = &arena.faces[i];
        if (face.surfaceKind != BRepSurfaceKind.plane || face.persistentId == 0) continue;
        auto ownerId = persistentTopologyOwner(face.persistentId);
        auto owner = context.model.featureById(ownerId);
        if (owner is null) continue;
        if (rows !is null && count < capacity)
        {
            auto row = &rows[count];
            *row = WcCocoaPlanarFaceRow.init;
            row.persistentId = face.persistentId;
            row.ownerFeatureId = ownerId;
            row.ownerName = owner.name.ptr();
            uint slot = 0;
            if (persistentTopologySlot(face.persistentId, &slot)) row.semanticSlot = slot;
            auto loop = arena.loop(face.outerLoop);
            if (loop !is null && loop.firstCoedge != 0)
            {
                auto coedgeId = loop.firstCoedge;
                foreach (step; 0 .. loop.coedgeCount)
                {
                    if (row.pointCount >= WC_COCOA_FACE_MAX_POINTS) break;
                    auto coedge = arena.coedge(coedgeId);
                    if (coedge is null) break;
                    auto edge = arena.edge(coedge.edge);
                    if (edge is null) break;
                    auto vertexId = coedge.reversed ? edge.endVertex : edge.startVertex;
                    auto vertex = arena.vertex(vertexId);
                    if (vertex !is null)
                    {
                        auto offset = row.pointCount * 3u;
                        row.points[offset] = vertex.point.x;
                        row.points[offset + 1] = vertex.point.y;
                        row.points[offset + 2] = vertex.point.z;
                        ++row.pointCount;
                    }
                    coedgeId = coedge.next;
                    if (coedgeId == 0 || coedgeId == loop.firstCoedge) break;
                }
            }
        }
        ++count;
    }
    return count;
}

private extern(C) int cocoaFeatureAction(void* opaque, uint featureId, int action) nothrow @nogc
{
    auto context = cast(CocoaFrontendContext*)opaque;
    if (context is null || context.model is null)
        return 10;
    auto feature = context.model.featureById(featureId);
    if (feature is null)
        return 15;
    char[192] command;
    const(char)* operation = action == 0 ? "feature_delete".ptr : (action < 0 ? "feature_move_up".ptr : "feature_move_down".ptr);
    snprintf(command.ptr, command.length, "%s(:%s)", operation, feature.name.ptr());
    return submitGenerated(context, command.ptr);
}

private extern(C) int cocoaFeatureReorder(void* opaque, uint featureId, uint targetFeatureId, int afterTarget) nothrow @nogc
{
    auto context = cast(CocoaFrontendContext*)opaque;
    if (context is null || context.model is null || featureId == 0 || targetFeatureId == 0 || featureId == targetFeatureId)
        return 10;
    auto feature = context.model.featureById(featureId);
    auto target = context.model.featureById(targetFeatureId);
    if (feature is null || target is null)
        return 15;
    char[256] command;
    snprintf(command.ptr, command.length, "%s(:%s, :%s)",
             afterTarget != 0 ? "feature_move_after".ptr : "feature_move_before".ptr,
             feature.name.ptr(), target.name.ptr());
    return submitGenerated(context, command.ptr);
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

    CocoaFrontendContext context;
    context.model = model;
    context.script = script;
    context.ribbonHost = ribbonHost;
    context.commandConsole = commandConsole;

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
    callbacks.chooseSection = &cocoaChooseSection;
    callbacks.activeSection = &cocoaActiveSection;
    callbacks.modelSnapshot = &cocoaModelSnapshot;
    callbacks.featureRows = &cocoaFeatureRows;
    callbacks.bodyRows = &cocoaBodyRows;
    callbacks.massProperties = &cocoaMassProperties;
    callbacks.csysRows = &cocoaCsysRows;
    callbacks.sectionEntries = &cocoaSectionEntries;
    callbacks.activeRibbon = &cocoaActiveRibbon;
    callbacks.ribbonTemplate = &cocoaRibbonTemplate;
    callbacks.sketchGeometryRows = &cocoaSketchGeometryRows;
    callbacks.planarFaceRows = &cocoaPlanarFaceRows;
    callbacks.featureAction = &cocoaFeatureAction;
    callbacks.featureReorder = &cocoaFeatureReorder;

    return wc_cocoa_run(&config, &callbacks, &context);
}
