module waifucad.journal.backend_api;

import waifucad.kernel.model : Model;
import waifucad.journal.journal : Journal;
import waifucad.journal.script_runtime : ScriptRuntime;
import waifucad.sections.pmi.store : PmiStore;

enum WC_JOURNAL_BACKEND_ABI_V1 = 1u;

struct ScriptContext
{
    Model* model;
    Journal* journal;
    bool recordCommands;
    ScriptRuntime runtime;
    // Optional document-level PMI store. Kept outside modelling history.
    PmiStore* pmi;
}

extern(C) alias JournalExecuteFileFn = int function(ScriptContext*, const(char)*) nothrow @nogc;
extern(C) alias JournalExecuteTextFn = int function(ScriptContext*, char*) nothrow @nogc;

struct JournalBackendV1
{
    uint abiVersion;
    const(char)* name;
    const(char)* extension;
    JournalExecuteFileFn executeFile;
    JournalExecuteTextFn executeMutableText;
}



