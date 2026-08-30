module waifucad.scl.repl;

import core.stdc.ctype : isspace;
import core.stdc.stdio : fgets, fprintf, fflush, stdin, stdout, stderr;
import core.stdc.string : strcmp;
import waifucad.journal.backend_api : ScriptContext;
import waifucad.kernel.waifubrep_backend : waifuBRepBackend;
import waifucad.scl.interpreter : executeLine;
import waifucad.scl.ruby_syntax : WC_SCL_LINE;

private char* trimCommand(char* line) nothrow @nogc
{
    if (line is null)
        return null;
    while (*line != 0 && isspace(cast(ubyte)*line))
        ++line;
    char* end = line;
    while (*end != 0)
        ++end;
    while (end > line && isspace(cast(ubyte)end[-1]))
        --end;
    *end = 0;
    return line;
}

private void printHelp() nothrow @nogc
{
    fprintf(stdout,
        "Ruby-style SCL examples:\n" ~
        "  param(:width, 80.mm)\n" ~
        "  box(:body, 80.mm, 50.mm, 10.mm)\n" ~
        "  set(:width, 96)\n" ~
        "  puts(\"message\")\n" ~
        "Legacy command-form source belongs in .scl files.\n" ~
        "Type quit or exit to leave the command line.\n");
}

int runSclRepl(ScriptContext* context, bool recomputeAfterCommand = true) nothrow @nogc
{
    if (context is null || context.model is null)
        return 10;

    char[WC_SCL_LINE] line;
    int lastResult = 0;
    fprintf(stdout, "WaifuCAD SCL command line (Ruby-style surface; type help or quit)\n");
    while (true)
    {
        fprintf(stdout, "Command: ");
        fflush(stdout);
        if (fgets(line.ptr, cast(int)line.length, stdin) is null)
            break;
        auto command = trimCommand(line.ptr);
        if (command is null || *command == 0)
            continue;
        if (strcmp(command, "quit".ptr) == 0 || strcmp(command, "exit".ptr) == 0)
            break;
        if (strcmp(command, "help".ptr) == 0)
        {
            printHelp();
            continue;
        }

        lastResult = executeLine(context, command);
        if (lastResult == 0 && recomputeAfterCommand)
        {
            auto backend = waifuBRepBackend();
            lastResult = backend.recompute(context.model);
        }
        if (lastResult != 0)
            fprintf(stderr, "Command failed with SCL error %d.\n", lastResult);
    }
    return lastResult;
}


