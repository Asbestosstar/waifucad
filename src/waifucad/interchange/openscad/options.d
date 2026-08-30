module waifucad.interchange.openscad.options;

import waifucad.core.fixed_string : FixedString64, FixedString256;

enum OpenScadImportEngine : ubyte
{
    autoDetect,
    internalRoundTrip,
    externalCli
}

enum OpenScadBackend : ubyte
{
    automatic,
    manifold,
    cgal
}

enum OpenScadExportFallback : ubyte
{
    rejectUnsupported,
    boundingBox
}

enum OpenScadExportScope : ubyte
{
    namedFeature,
    allDumbBodies,
    allBodies
}

enum WC_SCAD_MAX_DEFINES = 8;

struct OpenScadImportOptions
{
    OpenScadImportEngine engine;
    OpenScadBackend backend;
    FixedString256 executable;
    FixedString256 temporaryDirectory;
    FixedString256 parameterFile;
    FixedString64 parameterSet;
    FixedString256 dependencyFile;
    FixedString256 makeCommand;
    FixedString256 libraryPath;
    FixedString256 fontPath;
    FixedString256[WC_SCAD_MAX_DEFINES] defines;
    ubyte defineCount;

    // OpenSCAD tessellation controls. Zero keeps the OpenSCAD/default value.
    uint fn;
    double fa;
    double fs;
    uint convexity;

    // Dumb-mesh intake policy.
    double unitScale;
    double weldTolerance;
    uint maxVertices;
    uint maxTriangles;
    bool centreOnOrigin;
    bool reverseWinding;
    bool triangulatePolygons;
    bool dropDegenerateTriangles;
    bool requireClosedMesh;

    // External CLI behaviour.
    bool hardWarnings;
    bool quiet;
    bool checkParameters;
    bool checkParameterRanges;
    bool forceRender;
    bool keepTemporaryFiles;
    bool preserveSourcePath;

    void setDefaults() nothrow @nogc
    {
        this = OpenScadImportOptions.init;
        engine = OpenScadImportEngine.autoDetect;
        backend = OpenScadBackend.automatic;
        executable.set("openscad".ptr);
        unitScale = 1.0;
        weldTolerance = 0.0;
        maxVertices = 16384;
        maxTriangles = 32768;
        triangulatePolygons = true;
        dropDegenerateTriangles = true;
        checkParameters = true;
        checkParameterRanges = true;
        convexity = 10;
        preserveSourcePath = true;
    }
}

struct OpenScadExportOptions
{
    OpenScadExportScope exportScope;
    OpenScadExportFallback fallback;
    FixedString64 featureName;

    // Tessellation of exact WaifuBRep bodies before flattening to polyhedron().
    uint fn;
    double fa;
    double fs;
    uint minimumSegments;
    uint maximumSegments;

    // Text/output controls.
    uint precision;
    uint convexity;
    double unitScale;
    bool reverseWinding;
    bool centreEachBody;
    bool emitHeader;
    bool emitStatistics;
    bool emitSourceNames;
    bool emitResolutionVariables;
    bool emitRoundTripMetadata;
    bool oneModulePerBody;
    bool wrapInRender;
    bool sortBodiesByFeatureOrder;

    void setDefaults() nothrow @nogc
    {
        this = OpenScadExportOptions.init;
        exportScope = OpenScadExportScope.namedFeature;
        fallback = OpenScadExportFallback.rejectUnsupported;
        fn = 0;
        fa = 12.0;
        fs = 2.0;
        minimumSegments = 12;
        maximumSegments = 256;
        precision = 9;
        convexity = 10;
        unitScale = 1.0;
        emitHeader = true;
        emitStatistics = true;
        emitSourceNames = true;
        emitRoundTripMetadata = true;
        oneModulePerBody = true;
        sortBodiesByFeatureOrder = true;
    }
}



