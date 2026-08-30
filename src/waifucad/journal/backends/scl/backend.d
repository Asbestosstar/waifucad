module waifucad.journal.backends.scl.backend;

import waifucad.journal.backend_api : JournalBackendV1, ScriptContext, WC_JOURNAL_BACKEND_ABI_V1;
import waifucad.scl.interpreter : executeFile, executeLine;

extern(C) private int executeSclFile(ScriptContext* context, const(char)* path) nothrow @nogc
{
    return executeFile(context, path);
}

extern(C) private int executeSclText(ScriptContext* context, char* text) nothrow @nogc
{
    // Bootstrap contract: mutable text contains one command.  Multi-line buffers
    // will be added when the streaming parser owns an explicit input span.
    return executeLine(context, text);
}

JournalBackendV1 sclBackend() nothrow @nogc
{
    JournalBackendV1 backend;
    backend.abiVersion = WC_JOURNAL_BACKEND_ABI_V1;
    backend.name = "scl".ptr;
    backend.extension = ".wcs".ptr;
    backend.executeFile = &executeSclFile;
    backend.executeMutableText = &executeSclText;
    return backend;
}



