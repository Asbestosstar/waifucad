module waifucad.gui.command_console;

import core.stdc.stdio : fgets, fprintf, fflush, stdin, stdout, stderr;
import core.stdc.string : strcmp;
import waifucad.core.fixed_string : FixedString64, FixedString256;
import waifucad.journal.backend_api : ScriptContext;
import waifucad.kernel.waifubrep_backend : waifuBRepBackend;
import waifucad.scl.interpreter : executeLine;
import waifucad.scl.ruby_syntax : WC_SCL_LINE;

enum WC_COMMAND_CONSOLE_HISTORY = 24;

struct CommandConsoleLayout
{
    int x;
    int y;
    int width;
    int height;
    int inputHeight;
    uint visibleHistoryRows;
    bool overlayViewport;
}

struct CommandConsoleState
{
    FixedString64 prompt;
    FixedString256[WC_COMMAND_CONSOLE_HISTORY] history;
    size_t historyCount;
    size_t historyWriteIndex;
    int lastStatus;
    bool focused;
    bool autoRecompute;
    CommandConsoleLayout layout;

    void initialise(int windowWidth, int windowHeight) nothrow @nogc
    {
        prompt.set("Command:".ptr);
        historyCount = 0;
        historyWriteIndex = 0;
        lastStatus = 0;
        focused = false;
        autoRecompute = true;
        foreach (ref entry; history)
            entry.clear();

        layout.width = windowWidth > 800 ? 720 : windowWidth - 80;
        if (layout.width < 320)
            layout.width = 320;
        layout.height = 104;
        layout.inputHeight = 32;
        layout.visibleHistoryRows = 3;
        layout.x = (windowWidth - layout.width) / 2;
        layout.y = (windowHeight - layout.height) / 2;
        layout.overlayViewport = true;
    }

    private void remember(const(char)* command) nothrow @nogc
    {
        if (command is null || *command == 0)
            return;
        auto capacity = cast(size_t)WC_COMMAND_CONSOLE_HISTORY;
        history[historyWriteIndex].set(command);
        historyWriteIndex = (historyWriteIndex + 1) % capacity;
        if (historyCount < capacity)
            ++historyCount;
    }


    const(char)* historyFromNewest(size_t offset) const nothrow @nogc
    {
        if (offset >= historyCount)
            return null;
        auto capacity = cast(size_t)WC_COMMAND_CONSOLE_HISTORY;
        auto newest = (historyWriteIndex + capacity - 1) % capacity;
        auto index = (newest + capacity - offset) % capacity;
        return history[index].ptr();
    }

    int submit(ScriptContext* context, char* command) nothrow @nogc
    {
        if (context is null || context.model is null || command is null)
            return 10;
        remember(command);
        lastStatus = executeLine(context, command);
        if (lastStatus != 0)
        {
            fprintf(stderr, "SCL command failed (%d): %s\n", lastStatus, command);
            return lastStatus;
        }
        if (autoRecompute)
        {
            auto backend = waifuBRepBackend();
            lastStatus = backend.recompute(context.model);
            if (lastStatus != 0)
                fprintf(stderr, "Model recompute failed after command (%d): %s\n", lastStatus, command);
        }
        return lastStatus;
    }

    int runTerminalPrototype(ScriptContext* context) nothrow @nogc
    {
        char[WC_SCL_LINE] line;
        focused = true;
        while (true)
        {
            fprintf(stdout, "%s ", prompt.ptr());
            fflush(stdout);
            if (fgets(line.ptr, cast(int)line.length, stdin) is null)
                break;
            size_t length = 0;
            while (line[length] != 0)
                ++length;
            while (length != 0 && (line[length - 1] == '\n' || line[length - 1] == '\r'))
                line[--length] = 0;
            if (strcmp(line.ptr, "quit".ptr) == 0 || strcmp(line.ptr, "exit".ptr) == 0)
                break;
            if (strcmp(line.ptr, "help".ptr) == 0)
            {
                fprintf(stdout, "Enter Ruby-style SCL such as box(:body, 80.mm, 50.mm, 10.mm); quit exits.\n");
                continue;
            }
            if (line[0] == 0)
                continue;
            auto result = submit(context, line.ptr);
            if (result != 0)
                fprintf(stderr, "GUI command line SCL error %d.\n", result);
        }
        focused = false;
        return lastStatus;
    }
}



