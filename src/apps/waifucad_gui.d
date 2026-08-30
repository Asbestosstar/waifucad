module apps.waifucad_gui;

import core.stdc.stdio : fprintf, stdout, stderr;
import core.stdc.string : strcmp;
import waifucad.gui.theme : nightcore2008Defaults;
import waifucad.gui.ribbon_host : RibbonHostState;
import waifucad.gui.command_console : CommandConsoleState, WC_COMMAND_CONSOLE_HISTORY;
import waifucad.core.jobs : hardwareThreadCount;
import waifucad.kernel.model : Model;
import waifucad.journal.backend_api : ScriptContext;
import waifucad.journal.journal : Journal;
import waifucad.sections.pmi.store : PmiStore;
import waifucad.gui.frontends.gtk4.frontend : gtk4NativeAvailable, runGtk4Native;

enum WC_GUI_STARTUP_COMMANDS = 16;

extern(C) int main(int argc, char** argv)
{
    auto theme = nightcore2008Defaults();
    RibbonHostState ribbonHost;
    ribbonHost.initialise();

    char*[WC_GUI_STARTUP_COMMANDS] startupCommands;
    size_t startupCommandCount = 0;
    bool terminalConsole = false;
    bool nativeGui = true;
    bool bootstrapInfo = false;
    const(char)* gtkRenderer = "auto".ptr;
    bool forceLavapipe = false;

    for (int i = 1; i < argc; ++i)
    {
        if (strcmp(argv[i], "--section".ptr) == 0 && i + 1 < argc)
        {
            ++i;
            if (!ribbonHost.chooseSection(argv[i]))
            {
                fprintf(stderr, "Unknown Section: %s\n", argv[i]);
                return 2;
            }
        }
        else if (strcmp(argv[i], "--command".ptr) == 0 && i + 1 < argc)
        {
            if (startupCommandCount >= startupCommands.length)
            {
                fprintf(stderr, "Too many --command values (max %u).\n", cast(uint)startupCommands.length);
                return 2;
            }
            startupCommands[startupCommandCount++] = argv[++i];
        }
        else if (strcmp(argv[i], "--console".ptr) == 0)
        {
            terminalConsole = true;
            nativeGui = false;
        }
        else if (strcmp(argv[i], "--bootstrap-info".ptr) == 0)
        {
            bootstrapInfo = true;
            nativeGui = false;
        }
        else if (strcmp(argv[i], "--native".ptr) == 0 || strcmp(argv[i], "--gtk4".ptr) == 0)
        {
            nativeGui = true;
            terminalConsole = false;
            bootstrapInfo = false;
        }
        else if (strcmp(argv[i], "--renderer".ptr) == 0 && i + 1 < argc)
        {
            gtkRenderer = argv[++i];
            if (strcmp(gtkRenderer, "auto".ptr) != 0 &&
                strcmp(gtkRenderer, "vulkan".ptr) != 0 &&
                strcmp(gtkRenderer, "gl".ptr) != 0 &&
                strcmp(gtkRenderer, "cairo".ptr) != 0)
            {
                fprintf(stderr, "Unknown GTK renderer '%s' (use auto, vulkan, gl or cairo).\n", gtkRenderer);
                return 2;
            }
        }
        else if (strcmp(argv[i], "--lavapipe".ptr) == 0)
        {
            forceLavapipe = true;
            gtkRenderer = "vulkan".ptr;
        }
        else
        {
            fprintf(stderr, "Unknown or incomplete GUI argument: %s\n", argv[i]);
            return 2;
        }
    }

    Model model;
    model.initialise("untitled".ptr);
    PmiStore pmiStore;
    pmiStore.clear();
    Journal journal;
    ScriptContext context;
    context.model = &model;
    context.journal = &journal;
    context.recordCommands = false;
    context.runtime.initialise();
    context.pmi = &pmiStore;

    CommandConsoleState commandConsole;
    commandConsole.initialise(theme.width, theme.height);
    foreach (i; 0 .. startupCommandCount)
    {
        auto result = commandConsole.submit(&context, startupCommands[i]);
        if (result != 0)
        {
            fprintf(stderr, "GUI startup command %u failed with SCL error %d.\n", cast(uint)i + 1u, result);
            return result;
        }
    }

    size_t sectionCount = 0;
    auto sections = ribbonHost.sectionLauncherEntries(&sectionCount);
    auto activeRibbon = ribbonHost.contextualRibbon();

    fprintf(stdout, "WaifuCAD GUI host bootstrap\n");
    fprintf(stdout, "Detected logical processors: %u\n", hardwareThreadCount());
    fprintf(stdout, "Theme: %s %dx%d\n", theme.id, theme.width, theme.height);
    fprintf(stdout, "Persistent ribbon tabs: Sections | Mods; Scripts is a Home-ribbon group\n");
    fprintf(stdout, "Sections launcher entries: %u\n", cast(uint)sectionCount);
    foreach (i; 0 .. sectionCount)
        fprintf(stdout, "  %s%s\n", sections[i].id,
                ribbonHost.sections.isActive(sections[i].id) ? " [active]".ptr : "".ptr);

    fprintf(stdout, "Active Section: %s\n", ribbonHost.sections.activeId());
    if (activeRibbon !is null)
    {
        fprintf(stdout, "Contextual ribbon tabs: %u commands: %u\n",
                cast(uint)activeRibbon.tabCount, cast(uint)activeRibbon.commandCount);
        foreach (i; 0 .. activeRibbon.tabCount)
            fprintf(stdout, "  tab %s\n", activeRibbon.tabs[i].id);
    }
    else
        fprintf(stdout, "Contextual ribbon: bootstrap placeholder for this Section\n");

    fprintf(stdout, "Command line overlay: %s at x=%d y=%d width=%d height=%d\n",
            commandConsole.prompt.ptr(), commandConsole.layout.x, commandConsole.layout.y,
            commandConsole.layout.width, commandConsole.layout.height);
    fprintf(stdout, "Command syntax: Ruby-like .wcs SCL; legacy command files use .scl; history capacity: %u\n",
            cast(uint)WC_COMMAND_CONSOLE_HISTORY);
    fprintf(stdout, "GTK4 native bridge: %s\n", gtk4NativeAvailable() ? "available".ptr : "not built (install GTK4 development files)".ptr);

    if (bootstrapInfo)
        return 0;

    if (nativeGui)
    {
        if (!gtk4NativeAvailable())
        {
            fprintf(stderr, "GTK4 native frontend was not built. Install gtk4 development files and rebuild the GUI target.\n");
            return 78;
        }
        auto result = runGtk4Native(&model, &context, &ribbonHost, &commandConsole,
                                    theme.width, theme.height, "WaifuCAD".ptr, theme.id,
                                    theme.navigatorBackground, theme.navigatorRailBackground,
                                    gtkRenderer, forceLavapipe);
        context.recordCommands = false;
        journal.stop();
        return result;
    }

    if (terminalConsole)
    {
        auto result = commandConsole.runTerminalPrototype(&context);
        context.recordCommands = false;
        journal.stop();
        return result;
    }
    journal.stop();
    return 0;
}



