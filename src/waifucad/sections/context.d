module waifucad.sections.context;

import core.stdc.string : strcmp;
import waifucad.sections.api : SectionDescriptorV1;
import waifucad.sections.ribbon : SectionRibbonV1;
import waifucad.sections.registry : findBuiltInSection, ribbonForSection;

struct SectionContext
{
    const(SectionDescriptorV1)* active;

    void initialise() nothrow @nogc
    {
        active = findBuiltInSection("modelling".ptr);
    }

    bool activate(const(char)* id) nothrow @nogc
    {
        auto next = findBuiltInSection(id);
        if (next is null) return false;
        active = next;
        return true;
    }

    const(char)* activeId() const nothrow @nogc
    {
        return active is null ? "modelling".ptr : active.id;
    }

    const(SectionRibbonV1)* activeRibbon() const nothrow @nogc
    {
        return ribbonForSection(activeId());
    }

    bool isActive(const(char)* id) const nothrow @nogc
    {
        return id !is null && strcmp(activeId(), id) == 0;
    }
}



