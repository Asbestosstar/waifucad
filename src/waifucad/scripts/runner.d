module waifucad.scripts.runner;

import waifucad.journal.backend_api : ScriptContext;
import waifucad.scl.interpreter : executeFile;

// SCL is the bootstrap journal language.  Other language adapters plug in here later.
int runSclScript(ScriptContext* context, const(char)* path) nothrow @nogc
{
    return executeFile(context, path);
}



