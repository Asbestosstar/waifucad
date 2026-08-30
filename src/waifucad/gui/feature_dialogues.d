module waifucad.gui.feature_dialogues;

import core.stdc.string : strcmp;
import waifucad.kernel.model : Model;
import waifucad.kernel.profiles : ProfileRegion, resolveProfile;
import waifucad.kernel.types : EntityId, Feature, FeatureKind;

enum WC_FEATURE_DIALOGUE_ABI_V1 = 1u;
enum WC_FEATURE_DIALOGUE_NO_SOURCE = uint.max;

enum FeatureDialogueFieldKind : uint
{
    name = 1,
    value = 2,
    featureReference = 3,
    text = 4,
    boolean = 5,
    filePath = 6,
    choice = 7,
    raw = 8
}

enum FeatureDialogueFieldSource : uint
{
    none = 0,
    featureName = 1,
    operand = 2,
    payload = 3,
    payload2 = 4
}

enum FeatureDialogueSelectionKind : uint
{
    none = 0,
    anyFeature = 1,
    profile = 2,
    body = 3,
    path = 4
}

enum FeatureDialogueFieldFlags : uint
{
    none = 0,
    required = 1u << 0,
    readOnly = 1u << 1
}

enum FeatureDialogueFlags : uint
{
    none = 0,
    editable = 1u << 0,
    sketchGeometryEditor = 1u << 1,
    operation = 1u << 2
}

/*
 * Feature dialogues are toolkit-neutral data.  GTK/Qt/Motif/Xlib front-ends
 * render this ABI; Mods and later script/FeatureScript adapters can produce the
 * same descriptors without embedding toolkit widgets or bypassing SCL.
 */
struct FeatureDialogueFieldDescriptorV1
{
    const(char)* id;
    const(char)* label;
    uint kind;
    const(char)* defaultValue;
    const(char)* choices;       // pipe-separated for choice fields
    uint source;
    uint sourceIndex;
    uint flags;
    uint selectionKind;
}

struct FeatureDialogueDescriptorV1
{
    uint abiVersion;
    const(char)* id;            // normally the ribbon command id
    const(char)* title;
    const(char)* commandName;   // Ruby-like SCL command used for creation/action
    const(char)* argumentPrefix;// optional fixed SCL arguments before fields
    const(char)* editKind;      // feature_edit kind; null for non-editable actions
    const(char)* waifuImage;
    const(FeatureDialogueFieldDescriptorV1)* fields;
    size_t fieldCount;
    uint flags;
}

private FeatureDialogueFieldDescriptorV1 field(
    const(char)* id, const(char)* label, FeatureDialogueFieldKind kind,
    const(char)* defaultValue, FeatureDialogueFieldSource source = FeatureDialogueFieldSource.none,
    uint sourceIndex = WC_FEATURE_DIALOGUE_NO_SOURCE,
    uint flags = cast(uint)FeatureDialogueFieldFlags.required,
    const(char)* choices = null,
    FeatureDialogueSelectionKind selectionKind = FeatureDialogueSelectionKind.none) pure nothrow @nogc
{
    FeatureDialogueFieldDescriptorV1 result;
    result.id = id;
    result.label = label;
    result.kind = cast(uint)kind;
    result.defaultValue = defaultValue;
    result.choices = choices;
    result.source = cast(uint)source;
    result.sourceIndex = sourceIndex;
    result.flags = flags;
    result.selectionKind = cast(uint)selectionKind;
    return result;
}

private FeatureDialogueDescriptorV1 dialogue(
    const(char)* id, const(char)* title, const(char)* commandName,
    const(char)* editKind, const(FeatureDialogueFieldDescriptorV1)* fields,
    size_t fieldCount, uint flags = cast(uint)FeatureDialogueFlags.editable,
    const(char)* argumentPrefix = null,
    const(char)* waifuImage = "waifus/nightcore.png".ptr) pure nothrow @nogc
{
    FeatureDialogueDescriptorV1 result;
    result.abiVersion = WC_FEATURE_DIALOGUE_ABI_V1;
    result.id = id;
    result.title = title;
    result.commandName = commandName;
    result.argumentPrefix = argumentPrefix;
    result.editKind = editKind;
    result.waifuImage = waifuImage;
    result.fields = fields;
    result.fieldCount = fieldCount;
    result.flags = flags;
    return result;
}

private __gshared const FeatureDialogueFieldDescriptorV1[7] extrudeFields = [
    field("name".ptr, "Name".ptr, FeatureDialogueFieldKind.name, "extrude1".ptr, FeatureDialogueFieldSource.featureName),
    field("profile".ptr, "Profile".ptr, FeatureDialogueFieldKind.featureReference, "".ptr, FeatureDialogueFieldSource.operand, 0,
          cast(uint)FeatureDialogueFieldFlags.required, null, FeatureDialogueSelectionKind.profile),
    field("distance".ptr, "Distance".ptr, FeatureDialogueFieldKind.value, "10.mm".ptr, FeatureDialogueFieldSource.operand, 1),
    field("twist".ptr, "Twist".ptr, FeatureDialogueFieldKind.value, "0".ptr, FeatureDialogueFieldSource.operand, 2),
    field("slices".ptr, "Slices".ptr, FeatureDialogueFieldKind.value, "0".ptr, FeatureDialogueFieldSource.operand, 3),
    field("centred".ptr, "Centred".ptr, FeatureDialogueFieldKind.boolean, "0".ptr, FeatureDialogueFieldSource.operand, 4),
    field("convexity".ptr, "Convexity hint".ptr, FeatureDialogueFieldKind.value, "0".ptr, FeatureDialogueFieldSource.operand, 5)
];

private __gshared const FeatureDialogueFieldDescriptorV1[4] revolveFields = [
    field("name".ptr, "Name".ptr, FeatureDialogueFieldKind.name, "revolve1".ptr, FeatureDialogueFieldSource.featureName),
    field("profile".ptr, "Profile".ptr, FeatureDialogueFieldKind.featureReference, "".ptr, FeatureDialogueFieldSource.operand, 0,
          cast(uint)FeatureDialogueFieldFlags.required, null, FeatureDialogueSelectionKind.profile),
    field("angle".ptr, "Angle".ptr, FeatureDialogueFieldKind.value, "360.deg".ptr, FeatureDialogueFieldSource.operand, 1),
    field("convexity".ptr, "Convexity hint".ptr, FeatureDialogueFieldKind.value, "0".ptr, FeatureDialogueFieldSource.operand, 2)
];

private __gshared const FeatureDialogueFieldDescriptorV1[3] sweepFields = [
    field("name".ptr, "Name".ptr, FeatureDialogueFieldKind.name, "sweep1".ptr, FeatureDialogueFieldSource.featureName),
    field("profile".ptr, "Profile".ptr, FeatureDialogueFieldKind.featureReference, "".ptr, FeatureDialogueFieldSource.operand, 0,
          cast(uint)FeatureDialogueFieldFlags.required, null, FeatureDialogueSelectionKind.profile),
    field("path".ptr, "Path".ptr, FeatureDialogueFieldKind.featureReference, "".ptr, FeatureDialogueFieldSource.operand, 1,
          cast(uint)FeatureDialogueFieldFlags.required, null, FeatureDialogueSelectionKind.path)
];

private __gshared const FeatureDialogueFieldDescriptorV1[3] loftFields = [
    field("name".ptr, "Name".ptr, FeatureDialogueFieldKind.name, "loft1".ptr, FeatureDialogueFieldSource.featureName),
    field("profile_a".ptr, "First profile".ptr, FeatureDialogueFieldKind.featureReference, "".ptr, FeatureDialogueFieldSource.operand, 0,
          cast(uint)FeatureDialogueFieldFlags.required, null, FeatureDialogueSelectionKind.profile),
    field("profile_b".ptr, "Second profile".ptr, FeatureDialogueFieldKind.featureReference, "".ptr, FeatureDialogueFieldSource.operand, 1,
          cast(uint)FeatureDialogueFieldFlags.required, null, FeatureDialogueSelectionKind.profile)
];

private __gshared const FeatureDialogueFieldDescriptorV1[3] binaryFields = [
    field("name".ptr, "Name".ptr, FeatureDialogueFieldKind.name, "result1".ptr, FeatureDialogueFieldSource.featureName),
    field("body_a".ptr, "First body".ptr, FeatureDialogueFieldKind.featureReference, "".ptr, FeatureDialogueFieldSource.operand, 0,
          cast(uint)FeatureDialogueFieldFlags.required, null, FeatureDialogueSelectionKind.body),
    field("body_b".ptr, "Second body".ptr, FeatureDialogueFieldKind.featureReference, "".ptr, FeatureDialogueFieldSource.operand, 1,
          cast(uint)FeatureDialogueFieldFlags.required, null, FeatureDialogueSelectionKind.body)
];

private __gshared const FeatureDialogueFieldDescriptorV1[3] unaryAmountFields = [
    field("name".ptr, "Name".ptr, FeatureDialogueFieldKind.name, "feature1".ptr, FeatureDialogueFieldSource.featureName),
    field("body".ptr, "Body".ptr, FeatureDialogueFieldKind.featureReference, "".ptr, FeatureDialogueFieldSource.operand, 0,
          cast(uint)FeatureDialogueFieldFlags.required, null, FeatureDialogueSelectionKind.body),
    field("amount".ptr, "Amount".ptr, FeatureDialogueFieldKind.value, "2.mm".ptr, FeatureDialogueFieldSource.operand, 1)
];

private __gshared const FeatureDialogueFieldDescriptorV1[7] lineFields = [
    field("name".ptr, "Name".ptr, FeatureDialogueFieldKind.name, "line1".ptr, FeatureDialogueFieldSource.featureName),
    field("x1".ptr, "Start X".ptr, FeatureDialogueFieldKind.value, "0".ptr, FeatureDialogueFieldSource.operand, 0),
    field("y1".ptr, "Start Y".ptr, FeatureDialogueFieldKind.value, "0".ptr, FeatureDialogueFieldSource.operand, 1),
    field("z1".ptr, "Start Z".ptr, FeatureDialogueFieldKind.value, "0".ptr, FeatureDialogueFieldSource.operand, 2),
    field("x2".ptr, "End X".ptr, FeatureDialogueFieldKind.value, "50.mm".ptr, FeatureDialogueFieldSource.operand, 3),
    field("y2".ptr, "End Y".ptr, FeatureDialogueFieldKind.value, "0".ptr, FeatureDialogueFieldSource.operand, 4),
    field("z2".ptr, "End Z".ptr, FeatureDialogueFieldKind.value, "0".ptr, FeatureDialogueFieldSource.operand, 5)
];

private __gshared const FeatureDialogueFieldDescriptorV1[7] arcFields = [
    field("name".ptr, "Name".ptr, FeatureDialogueFieldKind.name, "arc1".ptr, FeatureDialogueFieldSource.featureName),
    field("cx".ptr, "Centre X".ptr, FeatureDialogueFieldKind.value, "0".ptr, FeatureDialogueFieldSource.operand, 0),
    field("cy".ptr, "Centre Y".ptr, FeatureDialogueFieldKind.value, "0".ptr, FeatureDialogueFieldSource.operand, 1),
    field("cz".ptr, "Centre Z".ptr, FeatureDialogueFieldKind.value, "0".ptr, FeatureDialogueFieldSource.operand, 2),
    field("radius".ptr, "Radius".ptr, FeatureDialogueFieldKind.value, "25.mm".ptr, FeatureDialogueFieldSource.operand, 3),
    field("start".ptr, "Start angle".ptr, FeatureDialogueFieldKind.value, "0.deg".ptr, FeatureDialogueFieldSource.operand, 4),
    field("end".ptr, "End angle".ptr, FeatureDialogueFieldKind.value, "90.deg".ptr, FeatureDialogueFieldSource.operand, 5)
];

private __gshared const FeatureDialogueFieldDescriptorV1[5] circleFields = [
    field("name".ptr, "Name".ptr, FeatureDialogueFieldKind.name, "circle1".ptr, FeatureDialogueFieldSource.featureName),
    field("cx".ptr, "Centre X".ptr, FeatureDialogueFieldKind.value, "0".ptr, FeatureDialogueFieldSource.operand, 0),
    field("cy".ptr, "Centre Y".ptr, FeatureDialogueFieldKind.value, "0".ptr, FeatureDialogueFieldSource.operand, 1),
    field("cz".ptr, "Centre Z".ptr, FeatureDialogueFieldKind.value, "0".ptr, FeatureDialogueFieldSource.operand, 2),
    field("radius".ptr, "Radius".ptr, FeatureDialogueFieldKind.value, "25.mm".ptr, FeatureDialogueFieldSource.operand, 3)
];

private __gshared const FeatureDialogueFieldDescriptorV1[7] splineFields = [
    field("name".ptr, "Name".ptr, FeatureDialogueFieldKind.name, "spline1".ptr, FeatureDialogueFieldSource.featureName),
    field("min_x".ptr, "Minimum X".ptr, FeatureDialogueFieldKind.value, "0".ptr, FeatureDialogueFieldSource.operand, 0),
    field("min_y".ptr, "Minimum Y".ptr, FeatureDialogueFieldKind.value, "0".ptr, FeatureDialogueFieldSource.operand, 1),
    field("min_z".ptr, "Minimum Z".ptr, FeatureDialogueFieldKind.value, "0".ptr, FeatureDialogueFieldSource.operand, 2),
    field("max_x".ptr, "Maximum X".ptr, FeatureDialogueFieldKind.value, "50.mm".ptr, FeatureDialogueFieldSource.operand, 3),
    field("max_y".ptr, "Maximum Y".ptr, FeatureDialogueFieldKind.value, "30.mm".ptr, FeatureDialogueFieldSource.operand, 4),
    field("max_z".ptr, "Maximum Z".ptr, FeatureDialogueFieldKind.value, "10.mm".ptr, FeatureDialogueFieldSource.operand, 5)
];

private __gshared const FeatureDialogueFieldDescriptorV1[10] planeFields = [
    field("name".ptr, "Name".ptr, FeatureDialogueFieldKind.name, "plane1".ptr, FeatureDialogueFieldSource.featureName),
    field("ox".ptr, "Origin X".ptr, FeatureDialogueFieldKind.value, "0".ptr, FeatureDialogueFieldSource.operand, 0),
    field("oy".ptr, "Origin Y".ptr, FeatureDialogueFieldKind.value, "0".ptr, FeatureDialogueFieldSource.operand, 1),
    field("oz".ptr, "Origin Z".ptr, FeatureDialogueFieldKind.value, "0".ptr, FeatureDialogueFieldSource.operand, 2),
    field("nx".ptr, "Normal X".ptr, FeatureDialogueFieldKind.value, "0".ptr, FeatureDialogueFieldSource.operand, 3),
    field("ny".ptr, "Normal Y".ptr, FeatureDialogueFieldKind.value, "0".ptr, FeatureDialogueFieldSource.operand, 4),
    field("nz".ptr, "Normal Z".ptr, FeatureDialogueFieldKind.value, "1".ptr, FeatureDialogueFieldSource.operand, 5),
    field("xx".ptr, "X axis X".ptr, FeatureDialogueFieldKind.value, "1".ptr, FeatureDialogueFieldSource.operand, 6),
    field("xy".ptr, "X axis Y".ptr, FeatureDialogueFieldKind.value, "0".ptr, FeatureDialogueFieldSource.operand, 7),
    field("xz".ptr, "X axis Z".ptr, FeatureDialogueFieldKind.value, "0".ptr, FeatureDialogueFieldSource.operand, 8)
];

private __gshared const FeatureDialogueFieldDescriptorV1[7] axisFields = [
    field("name".ptr, "Name".ptr, FeatureDialogueFieldKind.name, "axis1".ptr, FeatureDialogueFieldSource.featureName),
    field("ox".ptr, "Origin X".ptr, FeatureDialogueFieldKind.value, "0".ptr, FeatureDialogueFieldSource.operand, 0),
    field("oy".ptr, "Origin Y".ptr, FeatureDialogueFieldKind.value, "0".ptr, FeatureDialogueFieldSource.operand, 1),
    field("oz".ptr, "Origin Z".ptr, FeatureDialogueFieldKind.value, "0".ptr, FeatureDialogueFieldSource.operand, 2),
    field("dx".ptr, "Direction X".ptr, FeatureDialogueFieldKind.value, "0".ptr, FeatureDialogueFieldSource.operand, 3),
    field("dy".ptr, "Direction Y".ptr, FeatureDialogueFieldKind.value, "0".ptr, FeatureDialogueFieldSource.operand, 4),
    field("dz".ptr, "Direction Z".ptr, FeatureDialogueFieldKind.value, "1".ptr, FeatureDialogueFieldSource.operand, 5)
];

private __gshared const FeatureDialogueFieldDescriptorV1[10] csysFields = [
    field("name".ptr, "Name".ptr, FeatureDialogueFieldKind.name, "csys1".ptr, FeatureDialogueFieldSource.featureName),
    field("ox".ptr, "Origin X".ptr, FeatureDialogueFieldKind.value, "0".ptr, FeatureDialogueFieldSource.operand, 0),
    field("oy".ptr, "Origin Y".ptr, FeatureDialogueFieldKind.value, "0".ptr, FeatureDialogueFieldSource.operand, 1),
    field("oz".ptr, "Origin Z".ptr, FeatureDialogueFieldKind.value, "0".ptr, FeatureDialogueFieldSource.operand, 2),
    field("xx".ptr, "X axis X".ptr, FeatureDialogueFieldKind.value, "1".ptr, FeatureDialogueFieldSource.operand, 3),
    field("xy".ptr, "X axis Y".ptr, FeatureDialogueFieldKind.value, "0".ptr, FeatureDialogueFieldSource.operand, 4),
    field("xz".ptr, "X axis Z".ptr, FeatureDialogueFieldKind.value, "0".ptr, FeatureDialogueFieldSource.operand, 5),
    field("yx".ptr, "Y axis X".ptr, FeatureDialogueFieldKind.value, "0".ptr, FeatureDialogueFieldSource.operand, 6),
    field("yy".ptr, "Y axis Y".ptr, FeatureDialogueFieldKind.value, "1".ptr, FeatureDialogueFieldSource.operand, 7),
    field("yz".ptr, "Y axis Z".ptr, FeatureDialogueFieldKind.value, "0".ptr, FeatureDialogueFieldSource.operand, 8)
];

private __gshared const FeatureDialogueFieldDescriptorV1[2] sketchFields = [
    field("name".ptr, "Name".ptr, FeatureDialogueFieldKind.name, "sketch".ptr, FeatureDialogueFieldSource.featureName,
          WC_FEATURE_DIALOGUE_NO_SOURCE, cast(uint)FeatureDialogueFieldFlags.readOnly),
    field("support".ptr, "Support".ptr, FeatureDialogueFieldKind.text, "".ptr, FeatureDialogueFieldSource.payload,
          WC_FEATURE_DIALOGUE_NO_SOURCE, cast(uint)FeatureDialogueFieldFlags.readOnly)
];

private __gshared const FeatureDialogueFieldDescriptorV1[11] scadImportFields = [
    field("name".ptr, "Name".ptr, FeatureDialogueFieldKind.name, "imported_body".ptr),
    field("file".ptr, "OpenSCAD file".ptr, FeatureDialogueFieldKind.filePath, "model.scad".ptr),
    field("engine".ptr, "Evaluation engine".ptr, FeatureDialogueFieldKind.choice, "auto".ptr,
          FeatureDialogueFieldSource.none, WC_FEATURE_DIALOGUE_NO_SOURCE, cast(uint)FeatureDialogueFieldFlags.required, "auto|internal|external".ptr),
    field("scale".ptr, "Scale".ptr, FeatureDialogueFieldKind.value, "1".ptr),
    field("fn".ptr, "$fn".ptr, FeatureDialogueFieldKind.value, "64".ptr),
    field("fa".ptr, "$fa".ptr, FeatureDialogueFieldKind.value, "8".ptr),
    field("fs".ptr, "$fs".ptr, FeatureDialogueFieldKind.value, "0.5".ptr),
    field("backend".ptr, "External backend".ptr, FeatureDialogueFieldKind.choice, "auto".ptr,
          FeatureDialogueFieldSource.none, WC_FEATURE_DIALOGUE_NO_SOURCE, cast(uint)FeatureDialogueFieldFlags.required, "auto|manifold|cgal".ptr),
    field("centre".ptr, "Centre on origin".ptr, FeatureDialogueFieldKind.boolean, "0".ptr),
    field("weld".ptr, "Weld tolerance".ptr, FeatureDialogueFieldKind.value, "0.00001".ptr),
    field("closed".ptr, "Require closed mesh".ptr, FeatureDialogueFieldKind.boolean, "1".ptr)
];

private __gshared const FeatureDialogueFieldDescriptorV1[8] dumbImportFields = [
    field("name".ptr, "Name".ptr, FeatureDialogueFieldKind.name, "imported_body".ptr),
    field("file".ptr, "File".ptr, FeatureDialogueFieldKind.filePath, "model.off".ptr),
    field("min_x".ptr, "Minimum X".ptr, FeatureDialogueFieldKind.value, "0".ptr),
    field("min_y".ptr, "Minimum Y".ptr, FeatureDialogueFieldKind.value, "0".ptr),
    field("min_z".ptr, "Minimum Z".ptr, FeatureDialogueFieldKind.value, "0".ptr),
    field("max_x".ptr, "Maximum X".ptr, FeatureDialogueFieldKind.value, "100.mm".ptr),
    field("max_y".ptr, "Maximum Y".ptr, FeatureDialogueFieldKind.value, "100.mm".ptr),
    field("max_z".ptr, "Maximum Z".ptr, FeatureDialogueFieldKind.value, "100.mm".ptr)
];

private __gshared const FeatureDialogueFieldDescriptorV1[2] scadExportFields = [
    field("file".ptr, "OpenSCAD file".ptr, FeatureDialogueFieldKind.filePath, "model.scad".ptr),
    // Raw allows either :all/:all_dumb or a specific feature symbol such as :body.
    field("scope".ptr, "Feature or scope".ptr, FeatureDialogueFieldKind.raw, ":all".ptr)
];

private __gshared const FeatureDialogueFieldDescriptorV1[1] scriptFields = [
    field("file".ptr, "Script file".ptr, FeatureDialogueFieldKind.filePath, "script.wcs".ptr)
];

private __gshared const FeatureDialogueFieldDescriptorV1[5] pmiLinearFields = [
    field("name".ptr, "Name".ptr, FeatureDialogueFieldKind.name, "dimension1".ptr),
    field("text".ptr, "Displayed text".ptr, FeatureDialogueFieldKind.text, "0 mm".ptr),
    field("feature".ptr, "Associated feature".ptr, FeatureDialogueFieldKind.featureReference, "".ptr, FeatureDialogueFieldSource.none,
          WC_FEATURE_DIALOGUE_NO_SOURCE, cast(uint)FeatureDialogueFieldFlags.required, null, FeatureDialogueSelectionKind.anyFeature),
    field("subkind".ptr, "Subentity kind".ptr, FeatureDialogueFieldKind.value, "0".ptr),
    field("subindex".ptr, "Subentity index".ptr, FeatureDialogueFieldKind.value, "0".ptr)
];

private __gshared const FeatureDialogueFieldDescriptorV1[2] pmiNoteFields = [
    field("name".ptr, "Name".ptr, FeatureDialogueFieldKind.name, "note1".ptr),
    field("text".ptr, "Text".ptr, FeatureDialogueFieldKind.text, "NOTE".ptr)
];

private __gshared const FeatureDialogueFieldDescriptorV1[2] pmiShowFields = [
    field("name".ptr, "Annotation name".ptr, FeatureDialogueFieldKind.name, "annotation".ptr),
    field("visible".ptr, "Visible".ptr, FeatureDialogueFieldKind.boolean, "1".ptr)
];

private __gshared const FeatureDialogueDescriptorV1 extrudeDialogue =
    dialogue("modelling.extrude".ptr, "Extrude".ptr, "extrude".ptr, "extrude".ptr, extrudeFields.ptr, extrudeFields.length, cast(uint)FeatureDialogueFlags.editable, null, "waifus/amane_kanata.png".ptr);
private __gshared const FeatureDialogueDescriptorV1 revolveDialogue =
    dialogue("modelling.revolve".ptr, "Revolve".ptr, "revolve".ptr, "revolve".ptr, revolveFields.ptr, revolveFields.length, cast(uint)FeatureDialogueFlags.editable, null, "waifus/anya_nyabyss.png".ptr);
private __gshared const FeatureDialogueDescriptorV1 sweepDialogue =
    dialogue("modelling.sweep".ptr, "Sweep".ptr, "sweep".ptr, "sweep".ptr, sweepFields.ptr, sweepFields.length, cast(uint)FeatureDialogueFlags.editable, null, "waifus/chiiaru.png".ptr);
private __gshared const FeatureDialogueDescriptorV1 loftDialogue =
    dialogue("modelling.loft".ptr, "Loft".ptr, "loft".ptr, "loft".ptr, loftFields.ptr, loftFields.length, cast(uint)FeatureDialogueFlags.editable, null, "waifus/chiiaru_v2.png".ptr);
private __gshared const FeatureDialogueDescriptorV1 unionDialogue =
    dialogue("modelling.union".ptr, "Union".ptr, "union".ptr, "union".ptr, binaryFields.ptr, binaryFields.length, cast(uint)FeatureDialogueFlags.editable, null, "waifus/clio.png".ptr);
private __gshared const FeatureDialogueDescriptorV1 subtractDialogue =
    dialogue("modelling.subtract".ptr, "Subtract".ptr, "subtract".ptr, "subtract".ptr, binaryFields.ptr, binaryFields.length, cast(uint)FeatureDialogueFlags.editable, null, "waifus/einelotta.png".ptr);
private __gshared const FeatureDialogueDescriptorV1 intersectDialogue =
    dialogue("modelling.intersect".ptr, "Intersect".ptr, "intersect".ptr, "intersect".ptr, binaryFields.ptr, binaryFields.length, cast(uint)FeatureDialogueFlags.editable, null, "waifus/eon_of_stars.png".ptr);
private __gshared const FeatureDialogueDescriptorV1 filletDialogue =
    dialogue("modelling.fillet".ptr, "Fillet".ptr, "fillet".ptr, "fillet".ptr, unaryAmountFields.ptr, unaryAmountFields.length, cast(uint)FeatureDialogueFlags.editable, null, "waifus/gura.png".ptr);
private __gshared const FeatureDialogueDescriptorV1 chamferDialogue =
    dialogue("modelling.chamfer".ptr, "Chamfer".ptr, "chamfer".ptr, "chamfer".ptr, unaryAmountFields.ptr, unaryAmountFields.length, cast(uint)FeatureDialogueFlags.editable, null, "waifus/ike_eveland.png".ptr);
private __gshared const FeatureDialogueDescriptorV1 shellDialogue =
    dialogue("modelling.shell".ptr, "Shell".ptr, "shell".ptr, "shell".ptr, unaryAmountFields.ptr, unaryAmountFields.length, cast(uint)FeatureDialogueFlags.editable, null, "waifus/illythedizzy.png".ptr);
private __gshared const FeatureDialogueDescriptorV1 lineDialogue =
    dialogue("modelling.free_line".ptr, "Line".ptr, "line".ptr, "line".ptr, lineFields.ptr, lineFields.length, cast(uint)FeatureDialogueFlags.editable, null, "waifus/ironmouse.png".ptr);
private __gshared const FeatureDialogueDescriptorV1 arcDialogue =
    dialogue("modelling.free_arc".ptr, "Arc".ptr, "arc".ptr, "arc".ptr, arcFields.ptr, arcFields.length, cast(uint)FeatureDialogueFlags.editable, null, "waifus/jelly_stara.png".ptr);
private __gshared const FeatureDialogueDescriptorV1 circleDialogue =
    dialogue("modelling.free_circle".ptr, "Circle".ptr, "curve_circle".ptr, "curve_circle".ptr, circleFields.ptr, circleFields.length, cast(uint)FeatureDialogueFlags.editable, null, "waifus/luotianyi.png".ptr);
private __gshared const FeatureDialogueDescriptorV1 splineDialogue =
    dialogue("modelling.free_spline".ptr, "Spline Bounds".ptr, "spline_bbox".ptr, "spline_bbox".ptr, splineFields.ptr, splineFields.length, cast(uint)FeatureDialogueFlags.editable, null, "waifus/maid_mint.png".ptr);
private __gshared const FeatureDialogueDescriptorV1 planeDialogue =
    dialogue("modelling.datum_plane".ptr, "Datum Plane".ptr, "datum_plane".ptr, "datum_plane".ptr, planeFields.ptr, planeFields.length, cast(uint)FeatureDialogueFlags.editable, null, "waifus/minaly_xo.png".ptr);
private __gshared const FeatureDialogueDescriptorV1 axisDialogue =
    dialogue("modelling.datum_axis".ptr, "Datum Axis".ptr, "datum_axis".ptr, "datum_axis".ptr, axisFields.ptr, axisFields.length, cast(uint)FeatureDialogueFlags.editable, null, "waifus/momose_nina.png".ptr);
private __gshared const FeatureDialogueDescriptorV1 csysDialogue =
    dialogue("modelling.datum_csys".ptr, "Datum CSYS".ptr, "datum_csys".ptr, "datum_csys".ptr, csysFields.ptr, csysFields.length, cast(uint)FeatureDialogueFlags.editable, null, "waifus/nanashi_mumei.png".ptr);
private __gshared const FeatureDialogueDescriptorV1 sketchEditDialogue =
    dialogue("modelling.sketch".ptr, "Sketch".ptr, null, null, sketchFields.ptr, sketchFields.length,
             cast(uint)FeatureDialogueFlags.sketchGeometryEditor, null, "waifus/niwa.png".ptr);

private __gshared const FeatureDialogueDescriptorV1 scadImportDialogue =
    dialogue("modelling.import_openscad".ptr, "Import OpenSCAD".ptr, "scad_import".ptr, null,
             scadImportFields.ptr, scadImportFields.length, cast(uint)FeatureDialogueFlags.operation, null, "waifus/panko.png".ptr);
private __gshared const FeatureDialogueDescriptorV1 dumbImportDialogue =
    dialogue("modelling.import_dumb_body".ptr, "Import Dumb Body".ptr, "import".ptr, null,
             dumbImportFields.ptr, dumbImportFields.length, cast(uint)FeatureDialogueFlags.operation, null, "waifus/rei_bubbles.png".ptr);
private __gshared const FeatureDialogueDescriptorV1 scadExportDialogue =
    dialogue("modelling.export_openscad".ptr, "Export OpenSCAD".ptr, "scad_export".ptr, null,
             scadExportFields.ptr, scadExportFields.length, cast(uint)FeatureDialogueFlags.operation, null, "waifus/rima_evenstar.png".ptr);
private __gshared const FeatureDialogueDescriptorV1 runScriptDialogue =
    dialogue("modelling.run_script".ptr, "Run Script".ptr, "include".ptr, null,
             scriptFields.ptr, scriptFields.length, cast(uint)FeatureDialogueFlags.operation, null, "waifus/rosemi.png".ptr);

private __gshared const FeatureDialogueDescriptorV1 pmiQuickDialogue =
    dialogue("pmi.quick_dimension".ptr, "Quick Dimension".ptr, "pmi_add".ptr, null,
             pmiLinearFields.ptr, 5, cast(uint)FeatureDialogueFlags.operation, ":linear_dimension".ptr, "waifus/saba.png".ptr);
private __gshared const FeatureDialogueDescriptorV1 pmiLinearDialogue =
    dialogue("pmi.linear_dimension".ptr, "Linear Dimension".ptr, "pmi_add".ptr, null,
             pmiLinearFields.ptr, 5, cast(uint)FeatureDialogueFlags.operation, ":linear_dimension".ptr, "waifus/sakura_riddle.png".ptr);
private __gshared const FeatureDialogueDescriptorV1 pmiAngularDialogue =
    dialogue("pmi.angular_dimension".ptr, "Angular Dimension".ptr, "pmi_add".ptr, null,
             pmiLinearFields.ptr, 5, cast(uint)FeatureDialogueFlags.operation, ":angular_dimension".ptr, "waifus/shion.png".ptr);
private __gshared const FeatureDialogueDescriptorV1 pmiRadialDialogue =
    dialogue("pmi.radial_dimension".ptr, "Radial Dimension".ptr, "pmi_add".ptr, null,
             pmiLinearFields.ptr, 5, cast(uint)FeatureDialogueFlags.operation, ":radial_dimension".ptr, "waifus/sketchyvt.png".ptr);
private __gshared const FeatureDialogueDescriptorV1 pmiDiameterDialogue =
    dialogue("pmi.diameter_dimension".ptr, "Diameter Dimension".ptr, "pmi_add".ptr, null,
             pmiLinearFields.ptr, 5, cast(uint)FeatureDialogueFlags.operation, ":diameter_dimension".ptr, "waifus/sylent_bell.png".ptr);
private __gshared const FeatureDialogueDescriptorV1 pmiDatumDialogue =
    dialogue("pmi.datum_feature".ptr, "Datum Feature".ptr, "pmi_add".ptr, null,
             pmiLinearFields.ptr, 5, cast(uint)FeatureDialogueFlags.operation, ":datum_feature".ptr, "waifus/vallure.png".ptr);
private __gshared const FeatureDialogueDescriptorV1 pmiFcfDialogue =
    dialogue("pmi.feature_control_frame".ptr, "Feature Control Frame".ptr, "pmi_add".ptr, null,
             pmiLinearFields.ptr, 5, cast(uint)FeatureDialogueFlags.operation, ":feature_control_frame".ptr, "waifus/wendy_mizumi.png".ptr);
private __gshared const FeatureDialogueDescriptorV1 pmiSurfaceDialogue =
    dialogue("pmi.surface_texture".ptr, "Surface Texture".ptr, "pmi_add".ptr, null,
             pmiLinearFields.ptr, 5, cast(uint)FeatureDialogueFlags.operation, ":surface_texture".ptr, "waifus/wilhelmia_frost.png".ptr);
private __gshared const FeatureDialogueDescriptorV1 pmiWeldDialogue =
    dialogue("pmi.weld_symbol".ptr, "Weld Symbol".ptr, "pmi_add".ptr, null,
             pmiLinearFields.ptr, 5, cast(uint)FeatureDialogueFlags.operation, ":weld_symbol".ptr, "waifus/yumeiri_reyu.png".ptr);
private __gshared const FeatureDialogueDescriptorV1 pmiNoteDialogue =
    dialogue("pmi.note".ptr, "Note".ptr, "pmi_add".ptr, null,
             pmiNoteFields.ptr, pmiNoteFields.length, cast(uint)FeatureDialogueFlags.operation, ":note".ptr, "waifus/yunenoms.png".ptr);
private __gshared const FeatureDialogueDescriptorV1 pmiGeneralNoteDialogue =
    dialogue("pmi.general_note".ptr, "General Note".ptr, "pmi_add".ptr, null,
             pmiNoteFields.ptr, pmiNoteFields.length, cast(uint)FeatureDialogueFlags.operation, ":note".ptr, "waifus/kiara_ame.png".ptr);
private __gshared const FeatureDialogueDescriptorV1 pmiShowDialogue =
    dialogue("pmi.show_hide".ptr, "Show / Hide PMI".ptr, "pmi_visible".ptr, null,
             pmiShowFields.ptr, pmiShowFields.length, cast(uint)FeatureDialogueFlags.operation, null, "waifus/mausleepsvt.png".ptr);

private bool isBodyFeatureKind(FeatureKind kind) nothrow @nogc
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

bool featureDialogueAcceptsSelection(Model* model, const(FeatureDialogueDescriptorV1)* descriptor,
                                     size_t fieldIndex, EntityId featureId) nothrow @nogc
{
    if (model is null || descriptor is null || fieldIndex >= descriptor.fieldCount || featureId == 0)
        return false;
    auto feature = model.featureById(featureId);
    if (feature is null)
        return false;
    auto selection = cast(FeatureDialogueSelectionKind)descriptor.fields[fieldIndex].selectionKind;
    final switch (selection)
    {
        case FeatureDialogueSelectionKind.none:
            return false;
        case FeatureDialogueSelectionKind.anyFeature:
            return true;
        case FeatureDialogueSelectionKind.profile:
        {
            // A Sketch container is deliberately a first-class profile. resolveProfile
            // accepts a single region or one closed line/arc loop owned by that sketch.
            ProfileRegion profile;
            return resolveProfile(model, featureId, &profile);
        }
        case FeatureDialogueSelectionKind.body:
            return isBodyFeatureKind(feature.kind);
        case FeatureDialogueSelectionKind.path:
            return feature.kind == FeatureKind.freeLine || feature.kind == FeatureKind.freeArc ||
                   feature.kind == FeatureKind.freeSpline || feature.kind == FeatureKind.sketchLine ||
                   feature.kind == FeatureKind.sketchArc;
    }
}

const(FeatureDialogueDescriptorV1)* featureDialogueForCommand(const(char)* commandId) nothrow @nogc
{
    if (commandId is null) return null;
    if (strcmp(commandId, "modelling.extrude".ptr) == 0) return &extrudeDialogue;
    if (strcmp(commandId, "modelling.revolve".ptr) == 0) return &revolveDialogue;
    if (strcmp(commandId, "modelling.sweep".ptr) == 0) return &sweepDialogue;
    if (strcmp(commandId, "modelling.loft".ptr) == 0) return &loftDialogue;
    if (strcmp(commandId, "modelling.union".ptr) == 0) return &unionDialogue;
    if (strcmp(commandId, "modelling.subtract".ptr) == 0) return &subtractDialogue;
    if (strcmp(commandId, "modelling.intersect".ptr) == 0) return &intersectDialogue;
    if (strcmp(commandId, "modelling.fillet".ptr) == 0) return &filletDialogue;
    if (strcmp(commandId, "modelling.chamfer".ptr) == 0) return &chamferDialogue;
    if (strcmp(commandId, "modelling.shell".ptr) == 0) return &shellDialogue;
    if (strcmp(commandId, "modelling.free_line".ptr) == 0) return &lineDialogue;
    if (strcmp(commandId, "modelling.free_arc".ptr) == 0) return &arcDialogue;
    if (strcmp(commandId, "modelling.free_circle".ptr) == 0) return &circleDialogue;
    if (strcmp(commandId, "modelling.free_spline".ptr) == 0) return &splineDialogue;
    if (strcmp(commandId, "modelling.datum_plane".ptr) == 0) return &planeDialogue;
    if (strcmp(commandId, "modelling.datum_axis".ptr) == 0) return &axisDialogue;
    if (strcmp(commandId, "modelling.datum_csys".ptr) == 0) return &csysDialogue;
    if (strcmp(commandId, "modelling.import_openscad".ptr) == 0) return &scadImportDialogue;
    if (strcmp(commandId, "modelling.import_dumb_body".ptr) == 0) return &dumbImportDialogue;
    if (strcmp(commandId, "modelling.export_openscad".ptr) == 0) return &scadExportDialogue;
    if (strcmp(commandId, "modelling.run_script".ptr) == 0) return &runScriptDialogue;
    if (strcmp(commandId, "pmi.quick_dimension".ptr) == 0) return &pmiQuickDialogue;
    if (strcmp(commandId, "pmi.note".ptr) == 0) return &pmiNoteDialogue;
    if (strcmp(commandId, "pmi.show_hide".ptr) == 0) return &pmiShowDialogue;
    if (strcmp(commandId, "pmi.linear_dimension".ptr) == 0) return &pmiLinearDialogue;
    if (strcmp(commandId, "pmi.angular_dimension".ptr) == 0) return &pmiAngularDialogue;
    if (strcmp(commandId, "pmi.radial_dimension".ptr) == 0) return &pmiRadialDialogue;
    if (strcmp(commandId, "pmi.diameter_dimension".ptr) == 0) return &pmiDiameterDialogue;
    if (strcmp(commandId, "pmi.datum_feature".ptr) == 0) return &pmiDatumDialogue;
    if (strcmp(commandId, "pmi.feature_control_frame".ptr) == 0) return &pmiFcfDialogue;
    if (strcmp(commandId, "pmi.surface_texture".ptr) == 0) return &pmiSurfaceDialogue;
    if (strcmp(commandId, "pmi.weld_symbol".ptr) == 0) return &pmiWeldDialogue;
    if (strcmp(commandId, "pmi.general_note".ptr) == 0) return &pmiGeneralNoteDialogue;
    return null;
}

const(FeatureDialogueDescriptorV1)* featureDialogueForFeature(const(Feature)* feature) nothrow @nogc
{
    if (feature is null) return null;
    switch (feature.kind)
    {
        case FeatureKind.sketch: return &sketchEditDialogue;
        case FeatureKind.extrude: return feature.operandCount == 6 ? &extrudeDialogue : null;
        case FeatureKind.revolve: return feature.operandCount == 3 ? &revolveDialogue : null;
        case FeatureKind.sweep: return feature.operandCount == 2 ? &sweepDialogue : null;
        case FeatureKind.loft: return feature.operandCount == 2 ? &loftDialogue : null;
        case FeatureKind.booleanUnion: return feature.operandCount == 2 ? &unionDialogue : null;
        case FeatureKind.booleanSubtract: return feature.operandCount == 2 ? &subtractDialogue : null;
        case FeatureKind.booleanIntersect: return feature.operandCount == 2 ? &intersectDialogue : null;
        case FeatureKind.fillet: return feature.operandCount == 2 ? &filletDialogue : null;
        case FeatureKind.chamfer: return feature.operandCount == 2 ? &chamferDialogue : null;
        case FeatureKind.shell: return feature.operandCount == 2 ? &shellDialogue : null;
        case FeatureKind.freeLine: return feature.operandCount == 6 ? &lineDialogue : null;
        case FeatureKind.freeArc: return feature.operandCount == 6 ? &arcDialogue : null;
        case FeatureKind.freeCircle: return feature.operandCount == 4 ? &circleDialogue : null;
        case FeatureKind.freeSpline: return feature.operandCount == 6 && feature.payload.length == 0 ? &splineDialogue : null;
        case FeatureKind.datumPlane:
            return feature.operandCount == 9 && feature.payload.length == 0 ? &planeDialogue : null;
        case FeatureKind.datumAxis:
            return feature.operandCount == 6 && feature.payload.length == 0 ? &axisDialogue : null;
        case FeatureKind.datumCsys:
            if (feature.name.equals("absolute_csys".ptr)) return null;
            return feature.operandCount == 9 && feature.payload.length == 0 ? &csysDialogue : null;
        default: return null;
    }
}
