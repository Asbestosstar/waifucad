module waifucad.gui.ribbon_host;

import waifucad.sections.api : SectionDescriptorV1;
import waifucad.sections.context : SectionContext;
import waifucad.sections.ribbon : SectionRibbonV1;
import waifucad.sections.registry : builtInSections;

/*
 * The Sections ribbon tab is persistent chrome. Activating one entry swaps only the
 * contextual ribbon supplied by that Section; Mods remains a persistent tab and Scripts remains a Home-ribbon group.
 */
struct RibbonHostState
{
    SectionContext sections;

    void initialise() nothrow @nogc
    {
        sections.initialise();
    }

    bool chooseSection(const(char)* id) nothrow @nogc
    {
        return sections.activate(id);
    }

    const(SectionRibbonV1)* contextualRibbon() const nothrow @nogc
    {
        return sections.activeRibbon();
    }

    SectionDescriptorV1* sectionLauncherEntries(size_t* count) nothrow @nogc
    {
        return builtInSections(count);
    }
}



