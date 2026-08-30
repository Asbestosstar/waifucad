module waifucad.gui.frontends.gtk4.frontend;

import core.stdc.stdio : snprintf;
import waifucad.gui.api : GuiFrontendV1, WC_GUI_FRONTEND_ABI_V1;
import waifucad.gui.ribbon_host : RibbonHostState;
import waifucad.gui.ribbon_actions : ribbonCommandTemplate;
import waifucad.gui.feature_dialogues : FeatureDialogueDescriptorV1, FeatureDialogueFieldSource,
    featureDialogueForCommand, featureDialogueForFeature, featureDialogueAcceptsSelection;
import waifucad.gui.command_console : CommandConsoleState;
import waifucad.journal.backend_api : ScriptContext;
import waifucad.kernel.model : Model;
import waifucad.kernel.types : ExactGeometryStatus, FeatureKind, OperandKind;
import waifucad.kernel.datums : DatumFrame, datumFeatureFrame, sketchFrame;
import waifucad.brep.types : BRepSurfaceKind;
import waifucad.brep.properties : massProperties;
import waifucad.brep.naming : persistentTopologyOwner, persistentTopologySlot;
import waifucad.sections.api : SectionDescriptorV1;
import waifucad.sections.ribbon : SectionRibbonV1;

struct WcGtk4WindowConfig
{
    int width;
    int height;
    const(char)* title;
    const(char)* themeId;
    const(char)* navigatorBackground;
    const(char)* navigatorRailBackground;
    const(char)* gskRenderer;
    int forceLavapipe;
}

struct WcGtk4ModelSnapshot
{
    const(char)* modelName;
    double minX;
    double minY;
    double minZ;
    double maxX;
    double maxY;
    double maxZ;
    uint featureCount;
    uint exactCount;
    uint previewCount;
    uint failedCount;
    int boundsValid;
}

struct WcGtk4FeatureRow
{
    uint id;
    const(char)* name;
    const(char)* kindName;
    uint kind;
    uint exactStatus;
    uint dependencyDepth;
    uint dirty;
}

struct WcGtk4BodyRow
{
    uint featureId;
    const(char)* name;
    uint kind;
    uint exactStatus;
    double minX;
    double minY;
    double minZ;
    double maxX;
    double maxY;
    double maxZ;
}

struct WcGtk4MassProperties
{
    int valid;
    double volume;
    double surfaceArea;
    double[3] centreOfMass;
}

struct WcGtk4CsysRow
{
    uint featureId;
    const(char)* name;
    double[3] origin;
    double[3] xAxis;
    double[3] yAxis;
    double[3] zAxis;
}

struct WcGtk4SketchGeometryRow
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

enum WC_GTK4_FACE_MAX_POINTS = 24;

struct WcGtk4PlanarFaceRow
{
    ulong persistentId;
    uint ownerFeatureId;
    uint semanticSlot;
    const(char)* ownerName;
    uint pointCount;
    double[WC_GTK4_FACE_MAX_POINTS * 3] points;
}

enum WcGtk4SketchSupportKind : uint
{
    none = 0,
    datumPlane = 1,
    csysPlane = 2,
    planarFace = 3
}

struct WcGtk4SketchSupport
{
    uint kind;
    uint featureId;
    ulong facePersistentId;
    const(char)* csysPlane;
}

/* These layouts intentionally mirror the toolkit-neutral Section/ribbon ABI. */
struct WcGtk4SectionEntry
{
    uint abiVersion;
    const(char)* id;
    const(char)* localisationKey;
    const(char)* iconName;
    uint capabilities;
}

struct WcGtk4RibbonTab
{
    const(char)* id;
    const(char)* localisationKey;
    const(char)* iconName;
}

struct WcGtk4RibbonCommand
{
    const(char)* id;
    const(char)* localisationKey;
    const(char)* iconName;
    const(char)* tabId;
    const(char)* groupId;
    uint flags;
}

struct WcGtk4RibbonSnapshot
{
    const(char)* sectionId;
    const(WcGtk4RibbonTab)* tabs;
    size_t tabCount;
    const(WcGtk4RibbonCommand)* commands;
    size_t commandCount;
}

extern(C) alias WcGtk4SubmitCommandFn = int function(void*, char*) nothrow @nogc;
extern(C) alias WcGtk4ChooseSectionFn = int function(void*, const(char)*) nothrow @nogc;
extern(C) alias WcGtk4ActiveSectionFn = const(char)* function(void*) nothrow @nogc;
extern(C) alias WcGtk4SnapshotFn = void function(void*, WcGtk4ModelSnapshot*) nothrow @nogc;
extern(C) alias WcGtk4FeatureRowsFn = size_t function(void*, WcGtk4FeatureRow*, size_t) nothrow @nogc;
extern(C) alias WcGtk4BodyRowsFn = size_t function(void*, WcGtk4BodyRow*, size_t) nothrow @nogc;
extern(C) alias WcGtk4MassPropertiesFn = int function(void*, uint, WcGtk4MassProperties*) nothrow @nogc;
extern(C) alias WcGtk4CsysRowsFn = size_t function(void*, WcGtk4CsysRow*, size_t) nothrow @nogc;
extern(C) alias WcGtk4SectionEntriesFn = const(WcGtk4SectionEntry)* function(void*, size_t*) nothrow @nogc;
extern(C) alias WcGtk4ActiveRibbonFn = const(WcGtk4RibbonSnapshot)* function(void*) nothrow @nogc;
extern(C) alias WcGtk4RibbonTemplateFn = const(char)* function(void*, const(char)*) nothrow @nogc;
extern(C) alias WcGtk4FeatureDialogueFn = const(FeatureDialogueDescriptorV1)* function(void*, const(char)*) nothrow @nogc;
extern(C) alias WcGtk4FeatureDialogueForFeatureFn = const(FeatureDialogueDescriptorV1)* function(void*, uint) nothrow @nogc;
extern(C) alias WcGtk4FeatureDialogueValueFn = int function(void*, uint, const(FeatureDialogueDescriptorV1)*, size_t, char*, size_t) nothrow @nogc;
extern(C) alias WcGtk4FeatureDialogueAcceptSelectionFn = int function(void*, const(FeatureDialogueDescriptorV1)*, size_t, uint) nothrow @nogc;
extern(C) alias WcGtk4BeginNewSketchFn = int function(void*, const(WcGtk4SketchSupport)*, uint*, const(char)**) nothrow @nogc;
extern(C) alias WcGtk4EditSketchFn = int function(void*, uint, const(char)**) nothrow @nogc;
extern(C) alias WcGtk4FinishSketchFn = int function(void*, uint) nothrow @nogc;
extern(C) alias WcGtk4SketchGeometryRowsFn = size_t function(void*, uint, WcGtk4SketchGeometryRow*, size_t) nothrow @nogc;
extern(C) alias WcGtk4PlanarFaceRowsFn = size_t function(void*, WcGtk4PlanarFaceRow*, size_t) nothrow @nogc;
extern(C) alias WcGtk4SketchAddLineFn = int function(void*, uint, double, double, double, double, uint, uint, uint, uint) nothrow @nogc;
extern(C) alias WcGtk4SketchAddCircleFn = int function(void*, uint, double, double, double) nothrow @nogc;
extern(C) alias WcGtk4SketchAddRectangleFn = int function(void*, uint, double, double, double, double) nothrow @nogc;
extern(C) alias WcGtk4FeatureActionFn = int function(void*, uint, int) nothrow @nogc;
extern(C) alias WcGtk4FeatureReorderFn = int function(void*, uint, uint, int) nothrow @nogc;

struct WcGtk4Callbacks
{
    WcGtk4SubmitCommandFn submitCommand;
    WcGtk4ChooseSectionFn chooseSection;
    WcGtk4ActiveSectionFn activeSection;
    WcGtk4SnapshotFn modelSnapshot;
    WcGtk4FeatureRowsFn featureRows;
    WcGtk4BodyRowsFn bodyRows;
    WcGtk4MassPropertiesFn massProperties;
    WcGtk4CsysRowsFn csysRows;
    WcGtk4SectionEntriesFn sectionEntries;
    WcGtk4ActiveRibbonFn activeRibbon;
    WcGtk4RibbonTemplateFn ribbonTemplate;
    WcGtk4FeatureDialogueFn featureDialogue;
    WcGtk4FeatureDialogueForFeatureFn featureDialogueForFeature;
    WcGtk4FeatureDialogueValueFn featureDialogueValue;
    WcGtk4FeatureDialogueAcceptSelectionFn featureDialogueAcceptSelection;
    WcGtk4BeginNewSketchFn beginNewSketch;
    WcGtk4EditSketchFn editSketch;
    WcGtk4FinishSketchFn finishSketch;
    WcGtk4SketchGeometryRowsFn sketchGeometryRows;
    WcGtk4PlanarFaceRowsFn planarFaceRows;
    WcGtk4SketchAddLineFn sketchAddLine;
    WcGtk4SketchAddCircleFn sketchAddCircle;
    WcGtk4SketchAddRectangleFn sketchAddRectangle;
    WcGtk4FeatureActionFn featureAction;
    WcGtk4FeatureReorderFn featureReorder;
}

struct Gtk4FrontendContext
{
    Model* model;
    ScriptContext* script;
    RibbonHostState* ribbonHost;
    CommandConsoleState* commandConsole;
}

extern(C) int wc_gtk4_native_available() nothrow @nogc;
extern(C) int wc_gtk4_run(const WcGtk4WindowConfig*, const WcGtk4Callbacks*, void*) nothrow @nogc;

private extern(C) int gtk4SubmitCommand(void* opaque, char* command) nothrow @nogc
{
    auto context = cast(Gtk4FrontendContext*)opaque;
    if (context is null || context.commandConsole is null || context.script is null)
        return 10;
    return context.commandConsole.submit(context.script, command);
}

private extern(C) int gtk4ChooseSection(void* opaque, const(char)* sectionId) nothrow @nogc
{
    auto context = cast(Gtk4FrontendContext*)opaque;
    if (context is null || context.ribbonHost is null || sectionId is null)
        return 0;
    return context.ribbonHost.chooseSection(sectionId) ? 1 : 0;
}

private extern(C) const(char)* gtk4ActiveSection(void* opaque) nothrow @nogc
{
    auto context = cast(Gtk4FrontendContext*)opaque;
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

private extern(C) void gtk4ModelSnapshot(void* opaque, WcGtk4ModelSnapshot* snapshot) nothrow @nogc
{
    auto context = cast(Gtk4FrontendContext*)opaque;
    if (snapshot is null)
        return;
    *snapshot = WcGtk4ModelSnapshot.init;
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

private extern(C) size_t gtk4FeatureRows(void* opaque, WcGtk4FeatureRow* rows, size_t capacity) nothrow @nogc
{
    auto context = cast(Gtk4FrontendContext*)opaque;
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

private extern(C) size_t gtk4BodyRows(void* opaque, WcGtk4BodyRow* rows, size_t capacity) nothrow @nogc
{
    auto context = cast(Gtk4FrontendContext*)opaque;
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

private extern(C) int gtk4MassProperties(void* opaque, uint featureId, WcGtk4MassProperties* result) nothrow @nogc
{
    auto context = cast(Gtk4FrontendContext*)opaque;
    if (context is null || context.model is null || result is null)
        return 10;
    *result = WcGtk4MassProperties.init;
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

private extern(C) size_t gtk4CsysRows(void* opaque, WcGtk4CsysRow* rows, size_t capacity) nothrow @nogc
{
    auto context = cast(Gtk4FrontendContext*)opaque;
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

private bool makeUniqueFeatureName(Model* model, const(char)* stem, char* output, size_t capacity) nothrow @nogc
{
    if (model is null || stem is null || output is null || capacity < 4)
        return false;
    foreach (index; 1u .. 100000u)
    {
        snprintf(output, capacity, "%s%u", stem, index);
        if (model.findFeature(output) == 0)
            return true;
    }
    return false;
}

private bool makeUniqueConstraintName(Model* model, const(char)* stem, char* output, size_t capacity) nothrow @nogc
{
    if (model is null || stem is null || output is null || capacity < 4)
        return false;
    foreach (index; 1u .. 100000u)
    {
        snprintf(output, capacity, "%s%u", stem, index);
        bool exists = false;
        foreach (i; 0 .. model.sketchConstraintCount)
        {
            if (model.sketchConstraints[i].name.equals(output))
            {
                exists = true;
                break;
            }
        }
        if (!exists)
            return true;
    }
    return false;
}

private int submitGenerated(Gtk4FrontendContext* context, char* command) nothrow @nogc
{
    if (context is null || context.commandConsole is null || context.script is null || command is null)
        return 10;
    return context.commandConsole.submit(context.script, command);
}

private bool unsigned64Text(ulong value, char* output, size_t capacity) nothrow @nogc
{
    if (output is null || capacity < 2 || value == 0) return false;
    char[32] reversed;
    size_t count = 0;
    while (value != 0 && count < reversed.length)
    {
        reversed[count++] = cast(char)('0' + value % 10UL);
        value /= 10UL;
    }
    if (count + 1 > capacity) return false;
    foreach (i; 0 .. count) output[i] = reversed[count - 1 - i];
    output[count] = 0;
    return true;
}

private extern(C) const(FeatureDialogueDescriptorV1)* gtk4FeatureDialogue(void* opaque, const(char)* commandId) nothrow @nogc
{
    return featureDialogueForCommand(commandId);
}

private extern(C) const(FeatureDialogueDescriptorV1)* gtk4FeatureDialogueForFeature(void* opaque, uint featureId) nothrow @nogc
{
    auto context = cast(Gtk4FrontendContext*)opaque;
    if (context is null || context.model is null)
        return null;
    return featureDialogueForFeature(context.model.featureById(featureId));
}

private extern(C) int gtk4FeatureDialogueValue(void* opaque, uint featureId,
                                                const(FeatureDialogueDescriptorV1)* descriptor,
                                                size_t fieldIndex, char* output,
                                                size_t capacity) nothrow @nogc
{
    auto context = cast(Gtk4FrontendContext*)opaque;
    if (context is null || context.model is null || descriptor is null ||
        output is null || capacity == 0 || fieldIndex >= descriptor.fieldCount)
        return 10;
    output[0] = 0;
    auto feature = context.model.featureById(featureId);
    if (feature is null)
        return 11;
    auto field = &descriptor.fields[fieldIndex];
    final switch (cast(FeatureDialogueFieldSource)field.source)
    {
        case FeatureDialogueFieldSource.none:
            if (field.defaultValue !is null)
                snprintf(output, capacity, "%s", field.defaultValue);
            return 0;
        case FeatureDialogueFieldSource.featureName:
            snprintf(output, capacity, "%s", feature.name.ptr());
            return 0;
        case FeatureDialogueFieldSource.payload:
            snprintf(output, capacity, "%s", feature.payload.ptr());
            return 0;
        case FeatureDialogueFieldSource.payload2:
            snprintf(output, capacity, "%s", feature.payload2.ptr());
            return 0;
        case FeatureDialogueFieldSource.operand:
            if (field.sourceIndex >= feature.operandCount)
                return 12;
            auto operand = &feature.operands[field.sourceIndex];
            final switch (operand.kind)
            {
                case OperandKind.literal:
                    snprintf(output, capacity, "%.12g", operand.literal);
                    return 0;
                case OperandKind.parameter:
                    auto parameter = context.model.parameterById(operand.parameterId);
                    if (parameter is null) return 13;
                    // Value fields are emitted as raw Ruby-like SCL, so keep
                    // parameter operands explicit symbols rather than turning
                    // them into an unrelated script-runtime identifier.
                    snprintf(output, capacity, ":%s", parameter.name.ptr());
                    return 0;
                case OperandKind.feature:
                    auto source = context.model.featureById(operand.featureId);
                    if (source is null) return 14;
                    snprintf(output, capacity, "%s", source.name.ptr());
                    return 0;
            }
    }
}

private extern(C) int gtk4FeatureDialogueAcceptSelection(void* opaque,
                                                        const(FeatureDialogueDescriptorV1)* descriptor,
                                                        size_t fieldIndex, uint featureId) nothrow @nogc
{
    auto context = cast(Gtk4FrontendContext*)opaque;
    if (context is null || context.model is null)
        return 0;
    return featureDialogueAcceptsSelection(context.model, descriptor, fieldIndex, featureId) ? 1 : 0;
}

private extern(C) int gtk4BeginNewSketch(void* opaque, const(WcGtk4SketchSupport)* support, uint* sketchId, const(char)** sketchName) nothrow @nogc
{
    auto context = cast(Gtk4FrontendContext*)opaque;
    if (context is null || context.model is null || support is null || sketchId is null || sketchName is null)
        return 10;
    char[64] name;
    if (!makeUniqueFeatureName(context.model, "sketch".ptr, name.ptr, name.length))
        return 11;

    const(char)* supportName = null;
    char[64] generatedSupport;
    char[512] command;
    auto kind = cast(WcGtk4SketchSupportKind)support.kind;
    if (kind == WcGtk4SketchSupportKind.datumPlane)
    {
        auto feature = context.model.featureById(support.featureId);
        if (feature is null || feature.kind != FeatureKind.datumPlane) return 15;
        supportName = feature.name.ptr();
    }
    else if (kind == WcGtk4SketchSupportKind.csysPlane)
    {
        auto feature = context.model.featureById(support.featureId);
        if (feature is null || feature.kind != FeatureKind.datumCsys || support.csysPlane is null) return 16;
        if (!makeUniqueFeatureName(context.model, "sketch_support".ptr, generatedSupport.ptr, generatedSupport.length)) return 17;
        snprintf(command.ptr, command.length, "datum_plane_from_csys(:%s, :%s, :%s)",
                 generatedSupport.ptr, feature.name.ptr(), support.csysPlane);
        auto result = submitGenerated(context, command.ptr);
        if (result != 0) return result;
        supportName = generatedSupport.ptr;
    }
    else if (kind == WcGtk4SketchSupportKind.planarFace)
    {
        auto owner = context.model.featureById(support.featureId);
        if (owner is null || support.facePersistentId == 0) return 18;
        char[32] persistentText;
        if (!unsigned64Text(support.facePersistentId, persistentText.ptr, persistentText.length)) return 19;
        if (!makeUniqueFeatureName(context.model, "sketch_support".ptr, generatedSupport.ptr, generatedSupport.length)) return 20;
        snprintf(command.ptr, command.length, "datum_plane_from_face(:%s, :%s, %s)",
                 generatedSupport.ptr, owner.name.ptr(), persistentText.ptr);
        auto result = submitGenerated(context, command.ptr);
        if (result != 0) return result;
        supportName = generatedSupport.ptr;
    }
    else
        return 21;

    snprintf(command.ptr, command.length, "sketch(:%s, :%s)", name.ptr, supportName);
    auto result = submitGenerated(context, command.ptr);
    if (result != 0)
        return result;
    auto id = context.model.findFeature(name.ptr);
    auto feature = context.model.featureById(id);
    if (feature is null || feature.kind != FeatureKind.sketch)
        return 12;
    *sketchId = id;
    *sketchName = feature.name.ptr();
    return 0;
}

private extern(C) int gtk4EditSketch(void* opaque, uint sketchId, const(char)** sketchName) nothrow @nogc
{
    auto context = cast(Gtk4FrontendContext*)opaque;
    if (context is null || context.model is null || sketchName is null)
        return 10;
    auto feature = context.model.featureById(sketchId);
    if (feature is null || feature.kind != FeatureKind.sketch)
        return 13;
    *sketchName = feature.name.ptr();
    return 0;
}

private extern(C) int gtk4FinishSketch(void* opaque, uint sketchId) nothrow @nogc
{
    auto context = cast(Gtk4FrontendContext*)opaque;
    if (context is null || context.model is null)
        return 10;
    auto feature = context.model.featureById(sketchId);
    if (feature is null || feature.kind != FeatureKind.sketch)
        return 13;
    char[128] command;
    snprintf(command.ptr, command.length, "end_sketch(:%s)", feature.name.ptr());
    return submitGenerated(context, command.ptr);
}

private extern(C) size_t gtk4SketchGeometryRows(void* opaque, uint sketchId, WcGtk4SketchGeometryRow* rows, size_t capacity) nothrow @nogc
{
    auto context = cast(Gtk4FrontendContext*)opaque;
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
            *row = WcGtk4SketchGeometryRow.init;
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

private extern(C) size_t gtk4PlanarFaceRows(void* opaque, WcGtk4PlanarFaceRow* rows, size_t capacity) nothrow @nogc
{
    auto context = cast(Gtk4FrontendContext*)opaque;
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
            *row = WcGtk4PlanarFaceRow.init;
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
                    if (row.pointCount >= WC_GTK4_FACE_MAX_POINTS) break;
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

private int submitSketchGeometry(Gtk4FrontendContext* context, uint sketchId, const(char)* suffix, const(char)* format,
                                 double a, double b, double c, double d) nothrow @nogc
{
    if (context is null || context.model is null)
        return 10;
    auto sketch = context.model.featureById(sketchId);
    if (sketch is null || sketch.kind != FeatureKind.sketch)
        return 13;
    char[64] stem;
    snprintf(stem.ptr, stem.length, "%s_%s", sketch.name.ptr(), suffix);
    char[64] name;
    if (!makeUniqueFeatureName(context.model, stem.ptr, name.ptr, name.length))
        return 14;
    char[384] command;
    snprintf(command.ptr, command.length, format, name.ptr, sketch.name.ptr(), a, b, c, d);
    return submitGenerated(context, command.ptr);
}

private extern(C) int gtk4SketchAddLine(void* opaque, uint sketchId, double x1, double y1, double x2, double y2,
                                          uint firstSnapFeature, uint firstSnapPoint,
                                          uint secondSnapFeature, uint secondSnapPoint) nothrow @nogc
{
    auto context = cast(Gtk4FrontendContext*)opaque;
    if (context is null || context.model is null) return 10;
    auto sketch = context.model.featureById(sketchId);
    if (sketch is null || sketch.kind != FeatureKind.sketch) return 13;
    char[64] stem; snprintf(stem.ptr, stem.length, "%s_line", sketch.name.ptr());
    char[64] name; if (!makeUniqueFeatureName(context.model, stem.ptr, name.ptr, name.length)) return 14;
    char[384] command;
    snprintf(command.ptr, command.length, "sketch_line(:%s, :%s, %.6f.mm, %.6f.mm, %.6f.mm, %.6f.mm)",
             name.ptr, sketch.name.ptr(), x1, y1, x2, y2);
    auto result = submitGenerated(context, command.ptr);
    if (result != 0) return result;

    uint[2] snapFeatures = [firstSnapFeature, secondSnapFeature];
    uint[2] snapPoints = [firstSnapPoint, secondSnapPoint];
    foreach (newPoint; 0u .. 2u)
    {
        if (snapFeatures[newPoint] == 0) continue;
        auto existing = context.model.featureById(snapFeatures[newPoint]);
        if (existing is null || existing.kind != FeatureKind.sketchLine) continue;
        char[64] constraintName;
        if (!makeUniqueConstraintName(context.model, "snap".ptr, constraintName.ptr, constraintName.length)) return 22;
        snprintf(command.ptr, command.length,
                 "sketch_constraint(:coincident, :%s, :%s, :%s, %u, :%s, %u)",
                 constraintName.ptr, sketch.name.ptr(), name.ptr, newPoint, existing.name.ptr(), snapPoints[newPoint]);
        result = submitGenerated(context, command.ptr);
        if (result != 0) return result;
    }
    return 0;
}

private extern(C) int gtk4SketchAddCircle(void* opaque, uint sketchId, double cx, double cy, double radius) nothrow @nogc
{
    return submitSketchGeometry(cast(Gtk4FrontendContext*)opaque, sketchId, "circle".ptr,
        "sketch_circle_at(:%s, :%s, %.6f.mm, %.6f.mm, %.6f.mm)".ptr, cx, cy, radius, 0.0);
}

private extern(C) int gtk4SketchAddRectangle(void* opaque, uint sketchId, double x, double y, double width, double height) nothrow @nogc
{
    return submitSketchGeometry(cast(Gtk4FrontendContext*)opaque, sketchId, "rect".ptr,
        "sketch_rect_at(:%s, :%s, %.6f.mm, %.6f.mm, %.6f.mm, %.6f.mm)".ptr, x, y, width, height);
}

private extern(C) int gtk4FeatureAction(void* opaque, uint featureId, int action) nothrow @nogc
{
    auto context = cast(Gtk4FrontendContext*)opaque;
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

private extern(C) int gtk4FeatureReorder(void* opaque, uint featureId, uint targetFeatureId, int afterTarget) nothrow @nogc
{
    auto context = cast(Gtk4FrontendContext*)opaque;
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

private extern(C) const(WcGtk4SectionEntry)* gtk4SectionEntries(void* opaque, size_t* count) nothrow @nogc
{
    auto context = cast(Gtk4FrontendContext*)opaque;
    if (context is null || context.ribbonHost is null)
    {
        if (count !is null) *count = 0;
        return null;
    }
    SectionDescriptorV1* entries = context.ribbonHost.sectionLauncherEntries(count);
    return cast(const(WcGtk4SectionEntry)*)entries;
}

private extern(C) const(WcGtk4RibbonSnapshot)* gtk4ActiveRibbon(void* opaque) nothrow @nogc
{
    auto context = cast(Gtk4FrontendContext*)opaque;
    if (context is null || context.ribbonHost is null)
        return null;
    const(SectionRibbonV1)* ribbon = context.ribbonHost.contextualRibbon();
    return cast(const(WcGtk4RibbonSnapshot)*)ribbon;
}

private extern(C) const(char)* gtk4RibbonTemplate(void* opaque, const(char)* commandId) nothrow @nogc
{
    return ribbonCommandTemplate(commandId);
}

bool gtk4NativeAvailable() nothrow @nogc
{
    return wc_gtk4_native_available() != 0;
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
                  const(char)* gskRenderer,
                  bool forceLavapipe) nothrow @nogc
{
    if (model is null || script is null || ribbonHost is null || commandConsole is null)
        return 10;

    Gtk4FrontendContext context;
    context.model = model;
    context.script = script;
    context.ribbonHost = ribbonHost;
    context.commandConsole = commandConsole;

    WcGtk4WindowConfig config;
    config.width = width;
    config.height = height;
    config.title = title;
    config.themeId = themeId;
    config.navigatorBackground = navigatorBackground;
    config.navigatorRailBackground = navigatorRailBackground;
    config.gskRenderer = gskRenderer;
    config.forceLavapipe = forceLavapipe ? 1 : 0;

    WcGtk4Callbacks callbacks;
    callbacks.submitCommand = &gtk4SubmitCommand;
    callbacks.chooseSection = &gtk4ChooseSection;
    callbacks.activeSection = &gtk4ActiveSection;
    callbacks.modelSnapshot = &gtk4ModelSnapshot;
    callbacks.featureRows = &gtk4FeatureRows;
    callbacks.bodyRows = &gtk4BodyRows;
    callbacks.massProperties = &gtk4MassProperties;
    callbacks.csysRows = &gtk4CsysRows;
    callbacks.sectionEntries = &gtk4SectionEntries;
    callbacks.activeRibbon = &gtk4ActiveRibbon;
    callbacks.ribbonTemplate = &gtk4RibbonTemplate;
    callbacks.featureDialogue = &gtk4FeatureDialogue;
    callbacks.featureDialogueForFeature = &gtk4FeatureDialogueForFeature;
    callbacks.featureDialogueValue = &gtk4FeatureDialogueValue;
    callbacks.featureDialogueAcceptSelection = &gtk4FeatureDialogueAcceptSelection;
    callbacks.beginNewSketch = &gtk4BeginNewSketch;
    callbacks.editSketch = &gtk4EditSketch;
    callbacks.finishSketch = &gtk4FinishSketch;
    callbacks.sketchGeometryRows = &gtk4SketchGeometryRows;
    callbacks.planarFaceRows = &gtk4PlanarFaceRows;
    callbacks.sketchAddLine = &gtk4SketchAddLine;
    callbacks.sketchAddCircle = &gtk4SketchAddCircle;
    callbacks.sketchAddRectangle = &gtk4SketchAddRectangle;
    callbacks.featureAction = &gtk4FeatureAction;
    callbacks.featureReorder = &gtk4FeatureReorder;
    return wc_gtk4_run(&config, &callbacks, &context);
}

GuiFrontendV1 gtk4Descriptor() nothrow @nogc
{
    GuiFrontendV1 result;
    result.abiVersion = WC_GUI_FRONTEND_ABI_V1;
    result.id = "gtk4".ptr;
    result.displayName = "GTK4".ptr;
    return result;
}

