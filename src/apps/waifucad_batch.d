module apps.waifucad_batch;

import core.stdc.stdio : fprintf, fflush, stdout, stderr;
import core.stdc.stdlib : strtoul, strtod;
import core.stdc.string : strcmp;
import waifucad.kernel.model : Model;
import waifucad.kernel.waifubrep_backend : waifuBRepBackend;
import waifucad.brep.dump : dumpBRep;
import waifucad.journal.journal : Journal;
import waifucad.journal.undo : UndoStack;
import waifucad.journal.backend_api : ScriptContext;
import waifucad.sections.pmi.store : PmiStore;
import waifucad.scripts.runner : runSclScript;
import waifucad.scl.interpreter : executeLine;
import waifucad.scl.repl : runSclRepl;
import waifucad.interchange.openscad.options : OpenScadImportOptions, OpenScadImportEngine, OpenScadBackend,
    OpenScadExportOptions, OpenScadExportScope, OpenScadExportFallback, WC_SCAD_MAX_DEFINES;
import waifucad.interchange.openscad.importer : importOpenScad;
import waifucad.interchange.openscad.exporter : exportOpenScad;
import waifucad.core.fixed_string : FixedString256;
import waifucad.render.png : WC_PNG_MAX_DIMENSION;
import waifucad.render.softshot : ScreenshotOptions, renderModelScreenshot, WC_RENDER_FLAT, WC_RENDER_RAY;

private enum uint WC_BATCH_MAX_SHOTS = 8;

/*
 * The document, journal, PMI store and script context are several MiB in
 * total.  They live in static storage rather than in main's stack frame so the
 * frame stays small: a huge frame is reserved by the prologue even for the
 * --help early exit, which is fragile on hosts with small main-thread stacks
 * and non-x86 ABIs (for example SPARC register-window targets).
 */
private __gshared Model gModel;
private __gshared Journal gJournal;
private __gshared PmiStore gPmiStore;
private __gshared ScriptContext gContext;
private __gshared UndoStack gUndoStack;

private void usage() nothrow @nogc
{
    fprintf(stdout,
        "WaifuCAD batch\n" ~
        "Input (choose one):\n" ~
        "  --script FILE | --journal-in FILE | --import-openscad FILE | --command TEXT | --repl\n" ~
        "General: --journal-out FILE --threads N --dump-model --dump-brep\n" ~
        "Undo/redo log: --undo (implied by --repl and --journal-in); scripts may also run undo_enable [DEPTH]\n" ~
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
        "\nHeadless screenshots (repeatable, max 8):\n" ~
        "  --screenshot FILE --rotate YAW[,PITCH[,ROLL]] --size WxH --zoom Z\n" ~
        "  --render flat|ray --ao-samples N --no-axes --no-shadows\n" ~
        "  Modifiers apply to the most recent --screenshot, or to every following\n" ~
        "  --screenshot when given before the first one.\n" ~
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

/* Parses "yaw,pitch[,roll]" in degrees. Missing components keep the current
   option values so partial overrides like "--rotate ,45" work. */
private bool parseShotRotation(const(char)* text, ScreenshotOptions* options) nothrow @nogc
{
    if (text is null || options is null || *text == 0) return false;
    const(char)* cursor = text;
    double[3] values = [options.yawDegrees, options.pitchDegrees, options.rollDegrees];
    foreach (component; 0 .. 3)
    {
        const(char)* end = null;
        auto parsed = strtod(cursor, &end);
        if (end !is cursor) values[component] = parsed;
        if (end is null || *end == 0)
        {
            options.yawDegrees = values[0];
            options.pitchDegrees = values[1];
            options.rollDegrees = values[2];
            return component == 0 ? end !is cursor : true;
        }
        if (*end != ',') return false;
        cursor = end + 1;
    }
    return false; // trailing comma after roll
}

/* Parses "WxH" pixel sizes (both in 16..WC_PNG_MAX_DIMENSION). */
private bool parseShotSize(const(char)* text, ScreenshotOptions* options) nothrow @nogc
{
    if (text is null || options is null) return false;
    const(char)* end = null;
    auto w = strtoul(text, &end, 10);
    if (end is text || *end != 'x') return false;
    const(char)* hEnd = null;
    auto h = strtoul(end + 1, &hEnd, 10);
    if (hEnd is end + 1 || *hEnd != 0) return false;
    if (w < 16 || h < 16 || w > WC_PNG_MAX_DIMENSION || h > WC_PNG_MAX_DIMENSION) return false;
    options.width = cast(uint)w;
    options.height = cast(uint)h;
    return true;
}

extern(C) int main(int argc, char** argv)
{
    // Answer --help before touching any other state.
    foreach (argIndex; 1 .. argc)
    {
        if (strcmp(argv[argIndex], "--help".ptr) == 0 || strcmp(argv[argIndex], "-h".ptr) == 0)
        {
            usage();
            fflush(stdout);
            return 0;
        }
    }

    const(char)* scriptPath = null;
    const(char)* journalInputPath = null;
    const(char)* scadImportPath = null;
    const(char)* scadExportPath = null;
    const(char)* journalPath = null;
    char* commandText = null;
    bool repl = false;
    bool undoLog = false;
    const(char)* importName = "openscad_import".ptr;
    bool dumpModel = false;
    bool dumpExact = false;
    uint workerCount = 0;

    OpenScadImportOptions importOptions; importOptions.setDefaults();
    OpenScadExportOptions exportOptions; exportOptions.setDefaults();

    ScreenshotOptions[WC_BATCH_MAX_SHOTS] shots;
    FixedString256[WC_BATCH_MAX_SHOTS] shotPaths;
    uint shotCount = 0;
    ScreenshotOptions shotDefaults; shotDefaults.setDefaults();
    foreach (ref shot; shots) shot = shotDefaults;

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
        else if (strcmp(arg, "--undo".ptr) == 0) undoLog = true;
        else if (strcmp(arg, "--dump-model".ptr) == 0) dumpModel = true;
        else if (strcmp(arg, "--dump-brep".ptr) == 0) dumpExact = true;

        /* Headless screenshots. Modifier flags (--rotate, --size, --zoom,
           --render, --ao-samples, --no-axes, --no-shadows) apply to the most
           recent --screenshot, or to every following --screenshot when given
           before the first one. */
        else if (strcmp(arg, "--screenshot".ptr) == 0 && i + 1 < argc)
        {
            if (shotCount >= WC_BATCH_MAX_SHOTS) { fprintf(stderr, "Too many --screenshot flags (max %u).\n", WC_BATCH_MAX_SHOTS); return 2; }
            shots[shotCount] = shotDefaults;
            shotPaths[shotCount].set(argv[++i]);
            ++shotCount;
        }
        else if (strcmp(arg, "--rotate".ptr) == 0 && i + 1 < argc)
        {
            auto target = shotCount > 0 ? &shots[shotCount - 1] : &shotDefaults;
            if (!parseShotRotation(argv[++i], target)) { fprintf(stderr, "Invalid --rotate value; expected yaw,pitch[,roll].\n"); return 2; }
        }
        else if (strcmp(arg, "--size".ptr) == 0 && i + 1 < argc)
        {
            auto target = shotCount > 0 ? &shots[shotCount - 1] : &shotDefaults;
            if (!parseShotSize(argv[++i], target)) { fprintf(stderr, "Invalid --size value; expected WxH within 16..%u.\n", WC_PNG_MAX_DIMENSION); return 2; }
        }
        else if (strcmp(arg, "--zoom".ptr) == 0 && i + 1 < argc)
        {
            double zoom = 0.0;
            if (!parseDoubleValue(argv[++i], &zoom) || zoom <= 0.0) { fprintf(stderr, "Invalid --zoom value.\n"); return 2; }
            (shotCount > 0 ? &shots[shotCount - 1] : &shotDefaults).zoom = zoom;
        }
        else if (strcmp(arg, "--no-axes".ptr) == 0)
            (shotCount > 0 ? &shots[shotCount - 1] : &shotDefaults).drawAxes = false;
        else if (strcmp(arg, "--no-shadows".ptr) == 0)
            (shotCount > 0 ? &shots[shotCount - 1] : &shotDefaults).shadows = false;
        else if (strcmp(arg, "--render".ptr) == 0 && i + 1 < argc)
        {
            auto value = argv[++i];
            auto target = shotCount > 0 ? &shots[shotCount - 1] : &shotDefaults;
            if (strcmp(value, "flat".ptr) == 0) target.renderMode = WC_RENDER_FLAT;
            else if (strcmp(value, "ray".ptr) == 0) target.renderMode = WC_RENDER_RAY;
            else { fprintf(stderr, "Unknown --render mode; expected flat or ray.\n"); return 2; }
        }
        else if (strcmp(arg, "--ao-samples".ptr) == 0 && i + 1 < argc)
        {
            uint samples = 0;
            if (!parseUnsigned(argv[++i], &samples, 64u)) { fprintf(stderr, "Invalid --ao-samples value; expected 0..64.\n"); return 2; }
            (shotCount > 0 ? &shots[shotCount - 1] : &shotDefaults).aoSamples = samples;
        }

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

    auto model=&gModel; model.initialise("untitled".ptr); model.workerCount=workerCount;
    auto journal=&gJournal;
    if(journalPath!is null && !journal.start(journalPath)){fprintf(stderr,"Could not create journal: %s\n",journalPath);return 3;}
    auto pmiStore=&gPmiStore; pmiStore.clear();
    auto context=&gContext; context.model=model; context.journal=journal; context.recordCommands=journalPath!is null; context.runtime.initialise(); context.pmi=pmiStore;
    auto undoStack=&gUndoStack; context.undo=undoStack;
    if(undoLog||repl||journalInputPath!is null) undoStack.enable();

    int result=0;
    if(scriptPath!is null) result=runSclScript(context,scriptPath);
    else if(journalInputPath!is null) result=runSclScript(context,journalInputPath);
    else if(commandText!is null) result=executeLine(context,commandText);
    else if(repl) result=runSclRepl(context,true);
    else result=importOpenScad(model,scadImportPath,importName,&importOptions);

    if(result==0){auto backend=waifuBRepBackend();result=backend.recompute(model);}
    if(result==0 && scadExportPath!is null)
    {
        if(exportOptions.exportScope==OpenScadExportScope.namedFeature && exportOptions.featureName.length==0)
        {
            if(scadImportPath!is null) exportOptions.featureName.set(importName);
            else exportOptions.exportScope=OpenScadExportScope.allDumbBodies;
        }
        result=exportOpenScad(model,scadExportPath,&exportOptions);
    }

    if (result == 0 && shotCount > 0)
    {
        foreach (shotIndex; 0 .. shotCount)
        {
            result = renderModelScreenshot(model, shotPaths[shotIndex].ptr(), &shots[shotIndex]);
            if (result != 0)
            {
                fprintf(stderr, "Screenshot failed (%d): %s\n", result, shotPaths[shotIndex].ptr());
                break;
            }
            fprintf(stdout, "Wrote screenshot: %s (%ux%u)\n", shotPaths[shotIndex].ptr(), shots[shotIndex].width, shots[shotIndex].height);
        }
    }

    if(dumpModel) model.dump();
    if(dumpExact) dumpBRep(&model.exactGeometry);
    journal.stop();
    undoStack.disable();
    return result;
}



