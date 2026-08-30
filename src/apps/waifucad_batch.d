module apps.waifucad_batch;

import core.stdc.stdio : fprintf, stdout, stderr;
import core.stdc.stdlib : strtoul, strtod;
import core.stdc.string : strcmp;
import waifucad.kernel.model : Model;
import waifucad.kernel.waifubrep_backend : waifuBRepBackend;
import waifucad.brep.dump : dumpBRep;
import waifucad.journal.journal : Journal;
import waifucad.journal.backend_api : ScriptContext;
import waifucad.sections.pmi.store : PmiStore;
import waifucad.scripts.runner : runSclScript;
import waifucad.scl.interpreter : executeLine;
import waifucad.scl.repl : runSclRepl;
import waifucad.interchange.openscad.options : OpenScadImportOptions, OpenScadImportEngine, OpenScadBackend,
    OpenScadExportOptions, OpenScadExportScope, OpenScadExportFallback, WC_SCAD_MAX_DEFINES;
import waifucad.interchange.openscad.importer : importOpenScad;
import waifucad.interchange.openscad.exporter : exportOpenScad;

private void usage() nothrow @nogc
{
    fprintf(stdout,
        "WaifuCAD batch\n" ~
        "Input (choose one):\n" ~
        "  --script FILE | --journal-in FILE | --import-openscad FILE | --command TEXT | --repl\n" ~
        "General: --journal-out FILE --threads N --dump-model --dump-brep\n" ~
        "Ruby-style SCL can be used with --command or interactively with --repl.\n" ~
        "\nOpenSCAD import (always creates dumb mesh bodies):\n" ~
        "  --import-name NAME\n" ~
        "  --scad-engine auto|internal|external\n" ~
        "  --openscad-bin PATH --scad-backend auto|manifold|cgal\n" ~
        "  --scad-fn N --scad-fa DEG --scad-fs MM --scad-convexity N\n" ~
        "  --scad-scale X --scad-weld TOL --scad-max-vertices N --scad-max-triangles N\n" ~
        "  --scad-centre --scad-reverse-winding --scad-no-triangulate --scad-keep-degenerate\n" ~
        "  --scad-require-closed --scad-hardwarnings --scad-no-check-parameters --scad-no-check-ranges\n" ~
        "  --scad-force-render --scad-keep-temp --scad-temp-dir DIR --scad-strip-source\n" ~
        "  --scad-param-file FILE --scad-param-set NAME --scad-define EXPR (repeatable)\n" ~
        "  --scad-deps FILE --scad-make COMMAND --scad-library-path PATH --scad-font-path PATH --scad-quiet\n" ~
        "\nOpenSCAD export (always flattened to dumb polyhedron bodies):\n" ~
        "  --export-openscad FILE\n" ~
        "  --export-feature NAME | --export-all-dumb | --export-all-bodies\n" ~
        "  --export-scad-fallback reject|bbox\n" ~
        "  --export-scad-fn N --export-scad-fa DEG --export-scad-fs MM\n" ~
        "  --export-scad-min-segments N --export-scad-max-segments N\n" ~
        "  --export-scad-precision N --export-scad-convexity N --export-scad-scale X\n" ~
        "  --export-scad-centre --export-scad-reverse-winding --export-scad-no-header\n" ~
        "  --export-scad-no-stats --export-scad-no-source-names --export-scad-no-roundtrip-metadata\n" ~
        "  --export-scad-resolution-vars\n" ~
        "  --export-scad-flat --export-scad-render\n" ~
        "\n--threads 0 selects the host's online logical processors automatically.\n");
}

private bool parseUnsigned(const(char)* text, uint* result, uint maximum = uint.max) nothrow @nogc
{
    if (text is null || result is null) return false;
    const(char)* end = null;
    auto parsed = strtoul(text, &end, 10);
    if (end is text || *end != 0 || parsed > maximum) return false;
    *result = cast(uint)parsed;
    return true;
}

private bool parseDoubleValue(const(char)* text, double* result) nothrow @nogc
{
    if (text is null || result is null) return false;
    const(char)* end = null;
    auto parsed = strtod(text, &end);
    if (end is text || *end != 0) return false;
    *result = parsed;
    return true;
}

extern(C) int main(int argc, char** argv)
{
    const(char)* scriptPath = null;
    const(char)* journalInputPath = null;
    const(char)* scadImportPath = null;
    const(char)* scadExportPath = null;
    const(char)* journalPath = null;
    char* commandText = null;
    bool repl = false;
    const(char)* importName = "openscad_import".ptr;
    bool dumpModel = false;
    bool dumpExact = false;
    uint workerCount = 0;

    OpenScadImportOptions importOptions; importOptions.setDefaults();
    OpenScadExportOptions exportOptions; exportOptions.setDefaults();

    int i = 1;
    while (i < argc)
    {
        auto arg = argv[i];
        if (strcmp(arg, "--script".ptr) == 0 && i + 1 < argc) scriptPath = argv[++i];
        else if (strcmp(arg, "--command".ptr) == 0 && i + 1 < argc) commandText = argv[++i];
        else if (strcmp(arg, "--repl".ptr) == 0) repl = true;
        else if (strcmp(arg, "--journal-in".ptr) == 0 && i + 1 < argc) journalInputPath = argv[++i];
        else if (strcmp(arg, "--import-openscad".ptr) == 0 && i + 1 < argc) scadImportPath = argv[++i];
        else if (strcmp(arg, "--import-name".ptr) == 0 && i + 1 < argc) importName = argv[++i];
        else if (strcmp(arg, "--export-openscad".ptr) == 0 && i + 1 < argc) scadExportPath = argv[++i];
        else if (strcmp(arg, "--journal-out".ptr) == 0 && i + 1 < argc) journalPath = argv[++i];
        else if (strcmp(arg, "--threads".ptr) == 0 && i + 1 < argc)
        {
            if (!parseUnsigned(argv[++i], &workerCount, 64u)) { fprintf(stderr,"Invalid --threads value; expected 0..64.\n"); return 2; }
        }
        else if (strcmp(arg, "--dump-model".ptr) == 0) dumpModel = true;
        else if (strcmp(arg, "--dump-brep".ptr) == 0) dumpExact = true;

        // Import engine/evaluation options.
        else if (strcmp(arg, "--scad-engine".ptr) == 0 && i + 1 < argc)
        {
            auto value=argv[++i];
            if(strcmp(value,"auto".ptr)==0) importOptions.engine=OpenScadImportEngine.autoDetect;
            else if(strcmp(value,"internal".ptr)==0) importOptions.engine=OpenScadImportEngine.internalRoundTrip;
            else if(strcmp(value,"external".ptr)==0) importOptions.engine=OpenScadImportEngine.externalCli;
            else { fprintf(stderr,"Unknown --scad-engine.\n"); return 2; }
        }
        else if (strcmp(arg,"--openscad-bin".ptr)==0 && i+1<argc) importOptions.executable.set(argv[++i]);
        else if (strcmp(arg,"--scad-backend".ptr)==0 && i+1<argc)
        {
            auto value=argv[++i];
            if(strcmp(value,"auto".ptr)==0) importOptions.backend=OpenScadBackend.automatic;
            else if(strcmp(value,"manifold".ptr)==0) importOptions.backend=OpenScadBackend.manifold;
            else if(strcmp(value,"cgal".ptr)==0) importOptions.backend=OpenScadBackend.cgal;
            else { fprintf(stderr,"Unknown --scad-backend.\n"); return 2; }
        }
        else if (strcmp(arg,"--scad-fn".ptr)==0 && i+1<argc) { if(!parseUnsigned(argv[++i],&importOptions.fn)) return 2; }
        else if (strcmp(arg,"--scad-fa".ptr)==0 && i+1<argc) { if(!parseDoubleValue(argv[++i],&importOptions.fa)) return 2; }
        else if (strcmp(arg,"--scad-fs".ptr)==0 && i+1<argc) { if(!parseDoubleValue(argv[++i],&importOptions.fs)) return 2; }
        else if (strcmp(arg,"--scad-convexity".ptr)==0 && i+1<argc) { if(!parseUnsigned(argv[++i],&importOptions.convexity)) return 2; }
        else if (strcmp(arg,"--scad-scale".ptr)==0 && i+1<argc) { if(!parseDoubleValue(argv[++i],&importOptions.unitScale)) return 2; }
        else if (strcmp(arg,"--scad-weld".ptr)==0 && i+1<argc) { if(!parseDoubleValue(argv[++i],&importOptions.weldTolerance)) return 2; }
        else if (strcmp(arg,"--scad-max-vertices".ptr)==0 && i+1<argc) { if(!parseUnsigned(argv[++i],&importOptions.maxVertices)) return 2; }
        else if (strcmp(arg,"--scad-max-triangles".ptr)==0 && i+1<argc) { if(!parseUnsigned(argv[++i],&importOptions.maxTriangles)) return 2; }
        else if (strcmp(arg,"--scad-centre".ptr)==0) importOptions.centreOnOrigin=true;
        else if (strcmp(arg,"--scad-reverse-winding".ptr)==0) importOptions.reverseWinding=true;
        else if (strcmp(arg,"--scad-no-triangulate".ptr)==0) importOptions.triangulatePolygons=false;
        else if (strcmp(arg,"--scad-keep-degenerate".ptr)==0) importOptions.dropDegenerateTriangles=false;
        else if (strcmp(arg,"--scad-require-closed".ptr)==0) importOptions.requireClosedMesh=true;
        else if (strcmp(arg,"--scad-hardwarnings".ptr)==0) importOptions.hardWarnings=true;
        else if (strcmp(arg,"--scad-quiet".ptr)==0) importOptions.quiet=true;
        else if (strcmp(arg,"--scad-no-check-parameters".ptr)==0) importOptions.checkParameters=false;
        else if (strcmp(arg,"--scad-no-check-ranges".ptr)==0) importOptions.checkParameterRanges=false;
        else if (strcmp(arg,"--scad-force-render".ptr)==0) importOptions.forceRender=true;
        else if (strcmp(arg,"--scad-keep-temp".ptr)==0) importOptions.keepTemporaryFiles=true;
        else if (strcmp(arg,"--scad-temp-dir".ptr)==0 && i+1<argc) importOptions.temporaryDirectory.set(argv[++i]);
        else if (strcmp(arg,"--scad-strip-source".ptr)==0) importOptions.preserveSourcePath=false;
        else if (strcmp(arg,"--scad-param-file".ptr)==0 && i+1<argc) importOptions.parameterFile.set(argv[++i]);
        else if (strcmp(arg,"--scad-deps".ptr)==0 && i+1<argc) importOptions.dependencyFile.set(argv[++i]);
        else if (strcmp(arg,"--scad-make".ptr)==0 && i+1<argc) importOptions.makeCommand.set(argv[++i]);
        else if (strcmp(arg,"--scad-library-path".ptr)==0 && i+1<argc) importOptions.libraryPath.set(argv[++i]);
        else if (strcmp(arg,"--scad-font-path".ptr)==0 && i+1<argc) importOptions.fontPath.set(argv[++i]);
        else if (strcmp(arg,"--scad-param-set".ptr)==0 && i+1<argc) importOptions.parameterSet.set(argv[++i]);
        else if (strcmp(arg,"--scad-define".ptr)==0 && i+1<argc)
        {
            if(importOptions.defineCount>=WC_SCAD_MAX_DEFINES){fprintf(stderr,"Too many --scad-define values (max %u).\n",WC_SCAD_MAX_DEFINES);return 2;}
            importOptions.defines[importOptions.defineCount++].set(argv[++i]);
        }

        // Export flattening/tessellation options.
        else if (strcmp(arg,"--export-feature".ptr)==0 && i+1<argc) { exportOptions.exportScope=OpenScadExportScope.namedFeature; exportOptions.featureName.set(argv[++i]); }
        else if (strcmp(arg,"--export-all-dumb".ptr)==0) exportOptions.exportScope=OpenScadExportScope.allDumbBodies;
        else if (strcmp(arg,"--export-all-bodies".ptr)==0) exportOptions.exportScope=OpenScadExportScope.allBodies;
        else if (strcmp(arg,"--export-scad-fallback".ptr)==0 && i+1<argc)
        {
            auto value=argv[++i];
            if(strcmp(value,"reject".ptr)==0) exportOptions.fallback=OpenScadExportFallback.rejectUnsupported;
            else if(strcmp(value,"bbox".ptr)==0) exportOptions.fallback=OpenScadExportFallback.boundingBox;
            else { fprintf(stderr,"Unknown --export-scad-fallback.\n"); return 2; }
        }
        else if (strcmp(arg,"--export-scad-fn".ptr)==0 && i+1<argc) { if(!parseUnsigned(argv[++i],&exportOptions.fn)) return 2; }
        else if (strcmp(arg,"--export-scad-fa".ptr)==0 && i+1<argc) { if(!parseDoubleValue(argv[++i],&exportOptions.fa)) return 2; }
        else if (strcmp(arg,"--export-scad-fs".ptr)==0 && i+1<argc) { if(!parseDoubleValue(argv[++i],&exportOptions.fs)) return 2; }
        else if (strcmp(arg,"--export-scad-min-segments".ptr)==0 && i+1<argc) { if(!parseUnsigned(argv[++i],&exportOptions.minimumSegments)) return 2; }
        else if (strcmp(arg,"--export-scad-max-segments".ptr)==0 && i+1<argc) { if(!parseUnsigned(argv[++i],&exportOptions.maximumSegments)) return 2; }
        else if (strcmp(arg,"--export-scad-precision".ptr)==0 && i+1<argc) { if(!parseUnsigned(argv[++i],&exportOptions.precision,17u)) return 2; }
        else if (strcmp(arg,"--export-scad-convexity".ptr)==0 && i+1<argc) { if(!parseUnsigned(argv[++i],&exportOptions.convexity)) return 2; }
        else if (strcmp(arg,"--export-scad-scale".ptr)==0 && i+1<argc) { if(!parseDoubleValue(argv[++i],&exportOptions.unitScale)) return 2; }
        else if (strcmp(arg,"--export-scad-centre".ptr)==0) exportOptions.centreEachBody=true;
        else if (strcmp(arg,"--export-scad-reverse-winding".ptr)==0) exportOptions.reverseWinding=true;
        else if (strcmp(arg,"--export-scad-no-header".ptr)==0) exportOptions.emitHeader=false;
        else if (strcmp(arg,"--export-scad-no-stats".ptr)==0) exportOptions.emitStatistics=false;
        else if (strcmp(arg,"--export-scad-no-source-names".ptr)==0) exportOptions.emitSourceNames=false;
        else if (strcmp(arg,"--export-scad-no-roundtrip-metadata".ptr)==0) exportOptions.emitRoundTripMetadata=false;
        else if (strcmp(arg,"--export-scad-resolution-vars".ptr)==0) exportOptions.emitResolutionVariables=true;
        else if (strcmp(arg,"--export-scad-flat".ptr)==0) exportOptions.oneModulePerBody=false;
        else if (strcmp(arg,"--export-scad-render".ptr)==0) exportOptions.wrapInRender=true;

        else if (strcmp(arg, "--help".ptr) == 0 || strcmp(arg, "-h".ptr) == 0) { usage(); return 0; }
        else { fprintf(stderr, "Unknown or incomplete argument: %s\n", arg); usage(); return 2; }
        ++i;
    }

    uint inputCount=(scriptPath!is null?1u:0u)+(journalInputPath!is null?1u:0u)+(scadImportPath!is null?1u:0u)+
        (commandText!is null?1u:0u)+(repl?1u:0u);
    if(inputCount!=1){fprintf(stderr,"Choose exactly one input: --script, --journal-in, --import-openscad, --command, or --repl.\n");usage();return 2;}

    Model model; model.initialise("untitled".ptr); model.workerCount=workerCount;
    Journal journal;
    if(journalPath!is null && !journal.start(journalPath)){fprintf(stderr,"Could not create journal: %s\n",journalPath);return 3;}
    PmiStore pmiStore; pmiStore.clear();
    ScriptContext context; context.model=&model; context.journal=&journal; context.recordCommands=journalPath!is null; context.runtime.initialise(); context.pmi=&pmiStore;

    int result=0;
    if(scriptPath!is null) result=runSclScript(&context,scriptPath);
    else if(journalInputPath!is null) result=runSclScript(&context,journalInputPath);
    else if(commandText!is null) result=executeLine(&context,commandText);
    else if(repl) result=runSclRepl(&context,true);
    else result=importOpenScad(&model,scadImportPath,importName,&importOptions);

    if(result==0){auto backend=waifuBRepBackend();result=backend.recompute(&model);}
    if(result==0 && scadExportPath!is null)
    {
        if(exportOptions.exportScope==OpenScadExportScope.namedFeature && exportOptions.featureName.length==0)
        {
            if(scadImportPath!is null) exportOptions.featureName.set(importName);
            else exportOptions.exportScope=OpenScadExportScope.allDumbBodies;
        }
        result=exportOpenScad(&model,scadExportPath,&exportOptions);
    }

    if(dumpModel) model.dump();
    if(dumpExact) dumpBRep(&model.exactGeometry);
    journal.stop();
    return result;
}



