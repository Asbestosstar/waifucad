module waifucad.interchange.openscad.importer;

import core.stdc.stdio : snprintf, remove;
import core.stdc.stdlib : system;
import core.stdc.string : strlen;
import waifucad.kernel.model : Model;
import waifucad.mesh.types : MeshId;
import waifucad.mesh.off_io : readOffMesh;
import waifucad.interchange.openscad.options : OpenScadImportOptions, OpenScadImportEngine, OpenScadBackend;
import waifucad.interchange.openscad.roundtrip : isWaifuCadDumbScad, importWaifuCadDumbScad;
import waifucad.platform.temp_files : makeSecureTemporaryFile;

private bool appendRaw(char* output, size_t capacity, size_t* used, const(char)* text) nothrow @nogc
{
    if (output is null || used is null || text is null) return false;
    auto length = strlen(text);
    if (*used + length + 1 > capacity) return false;
    foreach (i; 0 .. length) output[*used + i] = text[i];
    *used += length;
    output[*used] = 0;
    return true;
}

/* POSIX-shell quoting for the external evaluator bootstrap. */
private bool appendQuoted(char* output, size_t capacity, size_t* used, const(char)* text) nothrow @nogc
{
    if (!appendRaw(output,capacity,used,"'".ptr)) return false;
    if (text !is null)
    {
        for (auto p = text; *p != 0; ++p)
        {
            if (*p == '\'')
            {
                if (!appendRaw(output,capacity,used,"'\\''".ptr)) return false;
            }
            else
            {
                if (*used + 2 > capacity) return false;
                output[(*used)++] = *p;
                output[*used] = 0;
            }
        }
    }
    return appendRaw(output,capacity,used,"'".ptr);
}

private bool appendNumberDefine(char* command, size_t capacity, size_t* used, const(char)* name, double value) nothrow @nogc
{
    char[128] expression;
    snprintf(expression.ptr, expression.length, "%s=%.17g", name, value);
    return appendRaw(command,capacity,used," -D ".ptr) && appendQuoted(command,capacity,used,expression.ptr);
}

private int runExternalOpenScad(const(char)* sourcePath, const(char)* offPath,
                                const OpenScadImportOptions* options) nothrow @nogc
{
    char[8192] command;
    size_t used = 0;
    command[0] = 0;
    if (options.libraryPath.length != 0)
    {
        if (!appendRaw(command.ptr,command.length,&used,"OPENSCADPATH=".ptr) ||
            !appendQuoted(command.ptr,command.length,&used,options.libraryPath.ptr()) ||
            !appendRaw(command.ptr,command.length,&used," ".ptr)) return 39;
    }
    if (options.fontPath.length != 0)
    {
        if (!appendRaw(command.ptr,command.length,&used,"OPENSCAD_FONT_PATH=".ptr) ||
            !appendQuoted(command.ptr,command.length,&used,options.fontPath.ptr()) ||
            !appendRaw(command.ptr,command.length,&used," ".ptr)) return 39;
    }
    if (!appendQuoted(command.ptr,command.length,&used,options.executable.ptr())) return 40;

    final switch (options.backend)
    {
        case OpenScadBackend.automatic: break;
        case OpenScadBackend.manifold:
            if (!appendRaw(command.ptr,command.length,&used," --backend=manifold".ptr)) return 41;
            break;
        case OpenScadBackend.cgal:
            if (!appendRaw(command.ptr,command.length,&used," --backend=cgal".ptr)) return 42;
            break;
    }
    if (options.hardWarnings && !appendRaw(command.ptr,command.length,&used," --hardwarnings".ptr)) return 43;
    if (options.quiet && !appendRaw(command.ptr,command.length,&used," -q".ptr)) return 43;
    if (options.checkParameters && !appendRaw(command.ptr,command.length,&used," --check-parameters=true".ptr)) return 44;
    if (options.checkParameterRanges && !appendRaw(command.ptr,command.length,&used," --check-parameter-ranges=true".ptr)) return 45;
    if (options.forceRender && !appendRaw(command.ptr,command.length,&used," --render".ptr)) return 46;
    if (options.fn != 0 && !appendNumberDefine(command.ptr,command.length,&used,"$fn".ptr,cast(double)options.fn)) return 47;
    if (options.fa > 0.0 && !appendNumberDefine(command.ptr,command.length,&used,"$fa".ptr,options.fa)) return 48;
    if (options.fs > 0.0 && !appendNumberDefine(command.ptr,command.length,&used,"$fs".ptr,options.fs)) return 49;
    foreach (i; 0 .. options.defineCount)
    {
        if (!appendRaw(command.ptr,command.length,&used," -D ".ptr) ||
            !appendQuoted(command.ptr,command.length,&used,options.defines[i].ptr())) return 50;
    }
    if (options.dependencyFile.length != 0)
    {
        if (!appendRaw(command.ptr,command.length,&used," -d ".ptr) || !appendQuoted(command.ptr,command.length,&used,options.dependencyFile.ptr())) return 51;
    }
    if (options.makeCommand.length != 0)
    {
        if (!appendRaw(command.ptr,command.length,&used," -m ".ptr) || !appendQuoted(command.ptr,command.length,&used,options.makeCommand.ptr())) return 51;
    }
    if (options.parameterFile.length != 0)
    {
        if (!appendRaw(command.ptr,command.length,&used," -p ".ptr) || !appendQuoted(command.ptr,command.length,&used,options.parameterFile.ptr())) return 51;
    }
    if (options.parameterSet.length != 0)
    {
        if (!appendRaw(command.ptr,command.length,&used," -P ".ptr) || !appendQuoted(command.ptr,command.length,&used,options.parameterSet.ptr())) return 52;
    }
    if (!appendRaw(command.ptr,command.length,&used," --export-format=off -o ".ptr) ||
        !appendQuoted(command.ptr,command.length,&used,offPath) ||
        !appendRaw(command.ptr,command.length,&used," ".ptr) ||
        !appendQuoted(command.ptr,command.length,&used,sourcePath)) return 53;

    auto rc = system(command.ptr);
    return rc == 0 ? 0 : 54;
}

private int importExternal(Model* model, const(char)* path, const(char)* featureName,
                           const OpenScadImportOptions* options) nothrow @nogc
{
    char[1024] temporary;
    const(char)* requestedDirectory = options.temporaryDirectory.length != 0 ? options.temporaryDirectory.ptr() : null;
    if (makeSecureTemporaryFile(requestedDirectory, temporary.ptr, temporary.length) != 0) return 60;
    auto runResult = runExternalOpenScad(path,temporary.ptr,options);
    if (runResult != 0)
    {
        if (!options.keepTemporaryFiles) remove(temporary.ptr);
        return runResult;
    }

    MeshId meshId = 0;
    auto readResult = readOffMesh(&model.dumbMeshes,temporary.ptr,options,&meshId);
    if (!options.keepTemporaryFiles) remove(temporary.ptr);
    if (readResult != 0) return 70 + readResult;
    auto mesh = model.dumbMeshes.mesh(meshId);
    if (mesh !is null)
    {
        mesh.sourcePath.set(options.preserveSourcePath ? path : null);
        mesh.sourceFormat.set("OpenSCAD/OFF".ptr);
        mesh.convexityHint = options.convexity;
    }
    auto id = model.addDumbMeshFeature(featureName,meshId,options.preserveSourcePath ? path : "OpenSCAD dumb body".ptr);
    return id == 0 ? 90 : 0;
}

int importOpenScad(Model* model, const(char)* path, const(char)* featureName,
                   const OpenScadImportOptions* suppliedOptions) nothrow @nogc
{
    if (model is null || path is null || featureName is null) return 1;
    OpenScadImportOptions defaults;
    defaults.setDefaults();
    auto options = suppliedOptions is null ? &defaults : suppliedOptions;

    if (options.engine == OpenScadImportEngine.internalRoundTrip)
    {
        uint imported = 0;
        return importWaifuCadDumbScad(model,path,featureName,options,&imported);
    }
    if (options.engine == OpenScadImportEngine.externalCli)
        return importExternal(model,path,featureName,options);

    // Auto mode keeps WaifuCAD-generated dumb SCAD files dependency-free.
    if (isWaifuCadDumbScad(path))
    {
        uint imported = 0;
        auto internalResult = importWaifuCadDumbScad(model,path,featureName,options,&imported);
        if (internalResult == 0) return 0;
    }
    return importExternal(model,path,featureName,options);
}



