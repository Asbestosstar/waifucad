module waifucad.gui.ribbon_search;

/*
 * Ribbon command search — the single match implementation shared by every
 * native front-end (Cocoa, GTK4, and any future toolkit).
 *
 * Front-ends own only the text field and the results popup; they call
 * ribbonSearch() through the GUI ABI callback and never re-implement
 * matching.  This is the turn-1 rule applied to UI chrome: one change here
 * changes behaviour on all toolkits.
 *
 * Matching is case-insensitive over the command id, its human-readable tail
 * (the part after the last '.'), the localisation key, the group id and the
 * tab id.  Results are ranked: id-tail prefix match first, then
 * localisation-key prefix, then any other substring; ties keep registry
 * order.  Planned commands remain searchable but keep their flag so
 * front-ends can grey them out exactly like the static ribbon.
 */
import core.stdc.ctype : tolower;
import core.stdc.string : strcmp, strlen;
import waifucad.sections.registry : builtInSections, ribbonForSection;
import waifucad.sections.ribbon : SectionRibbonV1;
import waifucad.gui.frontends.common.frontend : WcGuiRibbonCommand;

private char lowerAscii(char value) nothrow @nogc
{
    return cast(char)tolower(cast(int)value);
}

private bool ciContains(const(char)* haystack, const(char)* needle) nothrow @nogc
{
    if (haystack is null || needle is null)
        return false;
    auto needleLength = strlen(needle);
    if (needleLength == 0)
        return true;
    auto haystackLength = strlen(haystack);
    if (needleLength > haystackLength)
        return false;
    for (size_t i = 0; i + needleLength <= haystackLength; ++i)
    {
        size_t j = 0;
        while (j < needleLength &&
               lowerAscii(haystack[i + j]) == lowerAscii(needle[j]))
            ++j;
        if (j == needleLength)
            return true;
    }
    return false;
}

private bool ciStartsWith(const(char)* text, const(char)* prefix) nothrow @nogc
{
    if (text is null || prefix is null)
        return false;
    auto prefixLength = strlen(prefix);
    if (prefixLength == 0)
        return true;
    if (strlen(text) < prefixLength)
        return false;
    foreach (i; 0 .. prefixLength)
        if (lowerAscii(text[i]) != lowerAscii(prefix[i]))
            return false;
    return true;
}

private const(char)* idTail(const(char)* id) nothrow @nogc
{
    if (id is null)
        return "".ptr;
    const(char)* tail = id;
    for (const(char)* cursor = id; *cursor != 0; ++cursor)
        if (*cursor == '.')
            tail = cursor + 1;
    return tail;
}

private enum int WC_RIBBON_SEARCH_MAX_HITS = 64;

struct RibbonSearchHit
{
    WcGuiRibbonCommand command;
    int rank;
    size_t order;
}

/* Collects every command from every built-in Section ribbon, matches them
   against the query, ranks and copies up to `capacity` results into
   `matches`.  Returns the number written (<= capacity).  An empty query
   matches nothing — the front-end shows its "type to search" idle state. */
size_t ribbonSearch(const(char)* query, WcGuiRibbonCommand* matches, size_t capacity) nothrow @nogc
{
    if (query is null || matches is null || capacity == 0 || *query == 0)
        return 0;

    size_t count = 0;
    auto sections = builtInSections(&count);
    RibbonSearchHit[WC_RIBBON_SEARCH_MAX_HITS] hits;
    size_t hitCount = 0;

    foreach (sectionIndex; 0 .. count)
    {
        const(SectionRibbonV1)* ribbon = ribbonForSection(sections[sectionIndex].id);
        if (ribbon is null || ribbon.commands is null)
            continue;
        foreach (commandIndex; 0 .. ribbon.commandCount)
        {
            auto command = &ribbon.commands[commandIndex];
            auto tail = idTail(command.id);
            int rank = -1;
            if (ciStartsWith(tail, query) || ciStartsWith(command.id, query))
                rank = 0;
            else if (ciStartsWith(command.localisationKey, query))
                rank = 1;
            else if (ciContains(tail, query) || ciContains(command.localisationKey, query) ||
                     ciContains(command.groupId, query) || ciContains(command.tabId, query) ||
                     ciContains(command.id, query))
                rank = 2;
            if (rank < 0)
                continue;
            if (hitCount >= hits.length)
                break;
            /* WcGuiRibbonCommand is the ABI layout mirror of the section
               registry's RibbonCommandDescriptorV1 — the same casting
               contract guiActiveRibbon uses for the whole snapshot. */
            hits[hitCount].command = *cast(const(WcGuiRibbonCommand)*)command;
            hits[hitCount].rank = rank;
            hits[hitCount].order = hitCount;
            ++hitCount;
        }
    }

    /* Insertion sort: stable, rank first, then original registry order. */
    foreach (i; 1 .. hitCount)
    {
        auto key = hits[i];
        size_t j = i;
        while (j > 0 && (hits[j - 1].rank > key.rank ||
               (hits[j - 1].rank == key.rank && hits[j - 1].order > key.order)))
        {
            hits[j] = hits[j - 1];
            --j;
        }
        hits[j] = key;
    }

    size_t written = hitCount < capacity ? hitCount : capacity;
    foreach (i; 0 .. written)
        matches[i] = hits[i].command;
    return written;
}
