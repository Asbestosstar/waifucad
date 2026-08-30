module waifucad.brep.types;


alias BRepId = uint;
alias BRepPersistentId = ulong;

enum BRepTopologyKind : ubyte
{
    none,
    solidBody,
    face,
    edge,
    vertex
}

enum BRepCurveKind : ubyte
{
    none,
    line,
    circle,
    ellipse,
    bspline
}

enum BRepSurfaceKind : ubyte
{
    none,
    plane,
    cylinder,
    cone,
    sphere,
    torus,
    bspline
}

enum BRepPrimitiveKind : ubyte
{
    generic,
    box,
    cylinder,
    sphere,
    coneFrustum,
    torus,
    boxShell
}

enum BRepPointClassification : ubyte
{
    outside,
    boundary,
    inside
}

struct BRepVec3
{
    double x;
    double y;
    double z;
}

struct BRepBounds
{
    BRepVec3 minimum;
    BRepVec3 maximum;
    bool valid;
}

struct BRepVertex
{
    BRepId id;
    BRepPersistentId persistentId;
    BRepVec3 point;
    double tolerance;
}

/*
 * Analytic curve data lives directly on the topological edge during the
 * bootstrap phase.  For a line, the vertex locations are authoritative.  For
 * circles/ellipses, origin is the centre, axis is the plane normal and
 * referenceDirection defines parameter zero.
 */
struct BRepEdge
{
    BRepId id;
    BRepPersistentId persistentId;
    BRepId startVertex;
    BRepId endVertex;
    BRepCurveKind curveKind;
    BRepId firstCoedge;
    BRepId secondCoedge;
    BRepVec3 origin;
    BRepVec3 axis;
    BRepVec3 referenceDirection;
    double radius;
    double secondaryRadius;
    double parameterStart;
    double parameterEnd;
    BRepId geometryId; // NURBS/extended geometry arena ID when applicable.
}

struct BRepCoedge
{
    BRepId id;
    BRepId edge;
    BRepId loop;
    BRepId next;
    BRepId previous;
    bool reversed;
}

struct BRepLoop
{
    BRepId id;
    BRepId face;
    BRepId firstCoedge;
    uint coedgeCount;
}

/*
 * Analytic surface parameters.  Plane uses origin/normal/referenceDirection.
 * Cylinder uses origin as a point on the axis, axis as the axial direction,
 * referenceDirection as parameter zero and radius as its exact radius.
 */
struct BRepFace
{
    BRepId id;
    BRepPersistentId persistentId;
    BRepId shell;
    BRepId outerLoop; // first exterior loop for compatibility
    BRepId firstLoop;
    uint loopCount;
    BRepSurfaceKind surfaceKind;
    BRepVec3 origin;
    BRepVec3 normal;
    BRepVec3 axis;
    BRepVec3 referenceDirection;
    double radius;
    double secondaryRadius;
    double axialLength;
    bool reversed;
    BRepId geometryId; // NURBS/extended surface arena ID when applicable.
}

struct BRepShell
{
    BRepId id;
    BRepId solid;
    BRepId firstFace;
    uint faceCount;
    bool closed;
}

struct BRepSolid
{
    BRepId id;
    BRepPersistentId persistentId;
    BRepId shell; // primary shell for compatibility
    BRepId firstShell;
    uint shellCount;
    BRepId firstVertex;
    uint vertexCount;
    BRepId firstEdge;
    uint edgeCount;
    BRepId firstFace;
    uint faceCount;
    uint genus; // sum of handle counts across shells
    BRepBounds bounds;
    BRepPrimitiveKind primitiveKind;
    /* Primitive parameters remain useful for exact properties and diagnostic
       validation even after the topology has been built. */
    double primitiveA;
    double primitiveB;
    double primitiveC;
    double primitiveD;
}

struct BRepMassProperties
{
    double volume;
    double surfaceArea;
    BRepVec3 centreOfMass;
    bool valid;
}

enum BRepProfileSegmentKind : ubyte
{
    line,
    circularArc
}

struct BRepProfileSegment
{
    BRepProfileSegmentKind kind;
    BRepVec3 start;
    BRepVec3 finish;
    BRepVec3 centre;
    BRepVec3 axis;
    BRepVec3 referenceDirection;
    double radius;
    double parameterEnd;
}

struct BRepLine
{
    BRepVec3 origin;
    BRepVec3 direction;
}

struct BRepPlane
{
    BRepVec3 origin;
    BRepVec3 normal;
}

enum BRepIntersectionKind : ubyte
{
    none,
    point,
    coincident
}

struct BRepLinePlaneIntersection
{
    BRepIntersectionKind kind;
    BRepVec3 point;
    double lineParameter;
}

enum WC_BREP_MAX_NURBS_CURVE_POINTS = 24;
enum WC_BREP_MAX_NURBS_CURVE_KNOTS = 32;
enum WC_BREP_MAX_NURBS_SURFACE_U = 10;
enum WC_BREP_MAX_NURBS_SURFACE_V = 10;
enum WC_BREP_MAX_NURBS_SURFACE_POINTS = WC_BREP_MAX_NURBS_SURFACE_U * WC_BREP_MAX_NURBS_SURFACE_V;
enum WC_BREP_MAX_NURBS_SURFACE_U_KNOTS = 16;
enum WC_BREP_MAX_NURBS_SURFACE_V_KNOTS = 16;

struct BRepNurbsCurve
{
    BRepId id;
    ubyte degree;
    ubyte controlPointCount;
    ubyte knotCount;
    BRepVec3[WC_BREP_MAX_NURBS_CURVE_POINTS] controlPoints;
    double[WC_BREP_MAX_NURBS_CURVE_POINTS] weights;
    double[WC_BREP_MAX_NURBS_CURVE_KNOTS] knots;
}

struct BRepNurbsSurface
{
    BRepId id;
    ubyte degreeU;
    ubyte degreeV;
    ubyte countU;
    ubyte countV;
    ubyte knotCountU;
    ubyte knotCountV;
    BRepVec3[WC_BREP_MAX_NURBS_SURFACE_POINTS] controlPoints;
    double[WC_BREP_MAX_NURBS_SURFACE_POINTS] weights;
    double[WC_BREP_MAX_NURBS_SURFACE_U_KNOTS] knotsU;
    double[WC_BREP_MAX_NURBS_SURFACE_V_KNOTS] knotsV;
}

enum BRepLineageKind : ubyte
{
    none,
    split,
    merge,
    booleanIntersection,
    booleanUnion,
    booleanSubtract,
    generated
}

struct BRepTopologyLineage
{
    BRepPersistentId result;
    BRepPersistentId parentA;
    BRepPersistentId parentB;
    BRepLineageKind kind;
}

enum WC_BREP_MAX_VERTICES = 512;
enum WC_BREP_MAX_EDGES = 768;
enum WC_BREP_MAX_COEDGES = 1536;
enum WC_BREP_MAX_LOOPS = 384;
enum WC_BREP_MAX_FACES = 384;
enum WC_BREP_MAX_SHELLS = 64;
enum WC_BREP_MAX_SOLIDS = 64;
enum WC_BREP_MAX_NURBS_CURVES = 64;
enum WC_BREP_MAX_NURBS_SURFACES = 32;
enum WC_BREP_MAX_LINEAGE = 2048;

/*
 * Fixed-capacity arena used by the bootstrap kernel. BetterC deliberately
 * avoids hidden heap ownership here. A later allocator ABI can replace the
 * fixed capacities without changing topological identifiers.
 */
struct BRepArena
{
    BRepVertex[WC_BREP_MAX_VERTICES] vertices;
    BRepEdge[WC_BREP_MAX_EDGES] edges;
    BRepCoedge[WC_BREP_MAX_COEDGES] coedges;
    BRepLoop[WC_BREP_MAX_LOOPS] loops;
    BRepFace[WC_BREP_MAX_FACES] faces;
    BRepShell[WC_BREP_MAX_SHELLS] shells;
    BRepSolid[WC_BREP_MAX_SOLIDS] solids;
    BRepNurbsCurve[WC_BREP_MAX_NURBS_CURVES] nurbsCurves;
    BRepNurbsSurface[WC_BREP_MAX_NURBS_SURFACES] nurbsSurfaces;
    BRepTopologyLineage[WC_BREP_MAX_LINEAGE] lineage;
    size_t vertexCount;
    size_t edgeCount;
    size_t coedgeCount;
    size_t loopCount;
    size_t faceCount;
    size_t shellCount;
    size_t solidCount;
    size_t nurbsCurveCount;
    size_t nurbsSurfaceCount;
    size_t lineageCount;

    void clear() nothrow @nogc
    {
        vertexCount = 0;
        edgeCount = 0;
        coedgeCount = 0;
        loopCount = 0;
        faceCount = 0;
        shellCount = 0;
        solidCount = 0;
        nurbsCurveCount = 0;
        nurbsSurfaceCount = 0;
        lineageCount = 0;
    }

    BRepVertex* vertex(BRepId id) nothrow @nogc
    {
        return id == 0 || id > vertexCount ? null : &vertices[id - 1];
    }

    BRepEdge* edge(BRepId id) nothrow @nogc
    {
        return id == 0 || id > edgeCount ? null : &edges[id - 1];
    }

    BRepCoedge* coedge(BRepId id) nothrow @nogc
    {
        return id == 0 || id > coedgeCount ? null : &coedges[id - 1];
    }

    BRepLoop* loop(BRepId id) nothrow @nogc
    {
        return id == 0 || id > loopCount ? null : &loops[id - 1];
    }

    BRepFace* face(BRepId id) nothrow @nogc
    {
        return id == 0 || id > faceCount ? null : &faces[id - 1];
    }

    BRepShell* shell(BRepId id) nothrow @nogc
    {
        return id == 0 || id > shellCount ? null : &shells[id - 1];
    }

    BRepSolid* solid(BRepId id) nothrow @nogc
    {
        return id == 0 || id > solidCount ? null : &solids[id - 1];
    }

    BRepNurbsCurve* nurbsCurve(BRepId id) nothrow @nogc
    {
        return id == 0 || id > nurbsCurveCount ? null : &nurbsCurves[id - 1];
    }

    BRepNurbsSurface* nurbsSurface(BRepId id) nothrow @nogc
    {
        return id == 0 || id > nurbsSurfaceCount ? null : &nurbsSurfaces[id - 1];
    }

    bool addLineage(BRepPersistentId result, BRepPersistentId parentA, BRepPersistentId parentB, BRepLineageKind kind) nothrow @nogc
    {
        if (result == 0 || lineageCount >= lineage.length) return false;
        auto slot=&lineage[lineageCount++];
        slot.result=result; slot.parentA=parentA; slot.parentB=parentB; slot.kind=kind;
        return true;
    }
}



