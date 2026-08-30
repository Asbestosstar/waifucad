module waifucad.kernel.types;

import waifucad.core.fixed_string : FixedString64, FixedString256;

alias EntityId = uint;

enum Unit : ubyte
{
    unitless,
    millimetre,
    degree
}

/*
 * ModellingRole is intentionally separate from FeatureKind.  It records the
 * modelling intent that NX-like workflows care about: associative sketch-led
 * design is preferred, while rough curves and dumb bodies remain first-class
 * escape hatches for imported, repaired or deliberately non-parametric work.
 */
enum ModellingRole : ubyte
{
    none,
    preferredParametric,
    sketchGeometry,
    directParametric,
    roughCurve,
    dumbBody,
    displayOnly
}

enum FeatureKind : ubyte
{
    none,

    // Preferred profile-driven modelling.
    sketch,
    sketchLine,
    sketchArc,
    sketchCircle,
    sketchRectangle,
    sketchPolygon,
    sketchText,

    // Associative construction geometry.
    datumPlane,
    datumAxis,
    datumCsys,

    extrude,
    revolve,
    sweep,
    loft,

    // NX-style rough/free geometry outside sketches. Valid, but not preferred.
    freePoint,
    freeLine,
    freeArc,
    freeCircle,
    freeSpline,

    // Non-associative or imported bodies.
    dumbBody,
    import2d,
    import3d,
    heightSurface,

    // Direct parametric primitives. Convenient, though profile-driven design
    // is normally preferred for production parts.
    box,
    cylinder,
    sphere,
    coneFrustum,
    torus,
    polyhedron,
    circle2d,
    square2d,
    polygon2d,
    text2d,

    // Feature-tree operations, including the OpenSCAD-equivalent surface.
    translate,
    rotate,
    rotateAxis,
    scale,
    resize,
    mirror,
    multMatrix,
    colour,
    displayModifier,
    offset2d,
    projection,
    hull,
    minkowski,
    booleanUnion,
    booleanSubtract,
    booleanIntersect,
    renderBarrier,
    fillet,
    chamfer,
    shell
}

enum ExactGeometryStatus : ubyte
{
    none,
    exact,
    previewOnly,
    failed
}

enum OperandKind : ubyte
{
    literal,
    parameter,
    feature
}

struct Operand
{
    OperandKind kind;
    EntityId parameterId;
    EntityId featureId;
    double literal;
}

struct Parameter
{
    EntityId id;
    FixedString64 name;
    double value;
    Unit unit;
    FixedString256 expression;
    bool expressionDefined;
    int expressionError;
}

enum SketchConstraintKind : ubyte
{
    coincident,
    horizontal,
    vertical,
    distance,
    equalLength,
    parallel,
    perpendicular,
    angle,
    midpoint,
    concentric,
    equalRadius,
    radius,
    diameter,
    tangent,
    symmetry,
    fixPoint
}

enum SketchConstraintStatus : ubyte
{
    pending,
    satisfied,
    unsatisfied,
    redundant,
    conflicting,
    invalid
}

struct SketchConstraint
{
    EntityId id;
    FixedString64 name;
    SketchConstraintKind kind;
    EntityId sketchId;
    EntityId firstFeatureId;
    EntityId secondFeatureId;
    ubyte firstPoint;
    ubyte secondPoint;
    double value;
    double referenceX;
    double referenceY;
    double residual;
    SketchConstraintStatus status;
    ubyte rankContribution;
    bool rankRedundant;
    bool enabled;
}

struct SketchSolveReport
{
    EntityId sketchId;
    uint initialDegreesOfFreedom;
    uint remainingDegreesOfFreedom;
    uint independentEquationCount;
    uint totalEquationCount;
    uint jacobianRank;
    uint rankDeficiency;
    uint nonlinearIterations;
    uint satisfiedCount;
    uint redundantCount;
    uint conflictingCount;
    uint invalidCount;
    uint unsatisfiedCount;
    uint iterations;
    double maxResidual;
    bool converged;
    bool fullyConstrained;
    bool underConstrained;
    bool overConstrained;
    bool rankAnalysisTruncated;
}

enum WC_MAX_FEATURE_OPERANDS = 24;

struct Feature
{
    EntityId id;
    FixedString64 name;
    FeatureKind kind;
    ModellingRole role;
    Operand[WC_MAX_FEATURE_OPERANDS] operands;
    ubyte operandCount;
    ubyte dependencyDepth;
    bool dirty;
    bool recommendedWorkflow;
    FixedString256 payload;  // file path, text, point-list source or other fixed script payload
    FixedString256 payload2; // second fixed payload, for example polyhedron face indices or font name
    uint meshId;            // non-zero only for a real dumb triangle-mesh body
}

struct BoundingBox
{
    double minX;
    double minY;
    double minZ;
    double maxX;
    double maxY;
    double maxZ;
    bool valid;
}

ModellingRole roleForKind(FeatureKind kind) nothrow @nogc
{
    final switch (kind)
    {
        case FeatureKind.none:
            return ModellingRole.none;

        case FeatureKind.sketch:
        case FeatureKind.sketchLine:
        case FeatureKind.sketchArc:
        case FeatureKind.sketchCircle:
        case FeatureKind.sketchRectangle:
        case FeatureKind.sketchPolygon:
        case FeatureKind.sketchText:
            return ModellingRole.sketchGeometry;

        case FeatureKind.datumPlane:
        case FeatureKind.datumAxis:
        case FeatureKind.datumCsys:
            return ModellingRole.preferredParametric;

        case FeatureKind.extrude:
        case FeatureKind.revolve:
        case FeatureKind.sweep:
        case FeatureKind.loft:
        case FeatureKind.fillet:
        case FeatureKind.chamfer:
        case FeatureKind.shell:
            return ModellingRole.preferredParametric;

        case FeatureKind.freePoint:
        case FeatureKind.freeLine:
        case FeatureKind.freeArc:
        case FeatureKind.freeCircle:
        case FeatureKind.freeSpline:
            return ModellingRole.roughCurve;

        case FeatureKind.dumbBody:
        case FeatureKind.import2d:
        case FeatureKind.import3d:
        case FeatureKind.heightSurface:
        case FeatureKind.polyhedron:
            return ModellingRole.dumbBody;

        case FeatureKind.colour:
        case FeatureKind.displayModifier:
            return ModellingRole.displayOnly;

        case FeatureKind.box:
        case FeatureKind.cylinder:
        case FeatureKind.sphere:
        case FeatureKind.coneFrustum:
        case FeatureKind.torus:
        case FeatureKind.circle2d:
        case FeatureKind.square2d:
        case FeatureKind.polygon2d:
        case FeatureKind.text2d:
        case FeatureKind.translate:
        case FeatureKind.rotate:
        case FeatureKind.rotateAxis:
        case FeatureKind.scale:
        case FeatureKind.resize:
        case FeatureKind.mirror:
        case FeatureKind.multMatrix:
        case FeatureKind.offset2d:
        case FeatureKind.projection:
        case FeatureKind.hull:
        case FeatureKind.minkowski:
        case FeatureKind.booleanUnion:
        case FeatureKind.booleanSubtract:
        case FeatureKind.booleanIntersect:
        case FeatureKind.renderBarrier:
            return ModellingRole.directParametric;
    }
}

bool isRecommendedWorkflowKind(FeatureKind kind) nothrow @nogc
{
    auto role = roleForKind(kind);
    return role == ModellingRole.sketchGeometry || role == ModellingRole.preferredParametric;
}



