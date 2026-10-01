module tests.ribbon_search;

/*
 * Unit test for the shared ribbon command search (waifucad.gui.ribbon_search).
 *
 * The searcher is the single match implementation behind every native
 * front-end's ribbon search box, so its ranking contract is pinned here:
 *   - empty query matches nothing,
 *   - id / id-tail prefix matches outrank localisation-key prefixes,
 *   - key prefixes outrank plain substrings (group, tab, id),
 *   - ties keep registry order,
 *   - command flags (e.g. planned) survive into the results,
 *   - results are truncated to the caller's capacity.
 */
import core.stdc.stdio : fprintf, stderr;
import core.stdc.string : strcmp;
import waifucad.gui.ribbon_search : ribbonSearch;
import waifucad.gui.frontends.common.frontend : WcGuiRibbonCommand;
import waifucad.sections.ribbon : RibbonCommandFlags;

private size_t findCommand(WcGuiRibbonCommand* matches, size_t count, const(char)* id) nothrow @nogc
{
    foreach (i; 0 .. count)
        if (strcmp(matches[i].id, id) == 0)
            return i;
    return count;
}

private int fail(const(char)* what, const(char)* detail) nothrow @nogc
{
    fprintf(stderr, "ribbon search check failed: %s (%s)\n", what, detail);
    return 1;
}

extern(C) int main()
{
    WcGuiRibbonCommand[64] matches;

    /* Empty and NULL queries match nothing. */
    if (ribbonSearch("".ptr, matches.ptr, matches.length) != 0)
        return fail("empty query should not match", "".ptr);
    if (ribbonSearch(null, matches.ptr, matches.length) != 0)
        return fail("null query should not match", "".ptr);
    if (ribbonSearch("extrude".ptr, null, matches.length) != 0)
        return fail("null output buffer should yield zero", "".ptr);

    /* Id-tail prefix: "extrude" must surface modelling.extrude first. */
    size_t count = ribbonSearch("extrude".ptr, matches.ptr, matches.length);
    if (count == 0)
        return fail("no results for 'extrude'", "".ptr);
    if (strcmp(matches[0].id, "modelling.extrude") != 0)
        return fail("top hit for 'extrude'", matches[0].id);

    /* Matching is case-insensitive. */
    count = ribbonSearch("EXTRUDE".ptr, matches.ptr, matches.length);
    if (count == 0 || strcmp(matches[0].id, "modelling.extrude") != 0)
        return fail("case-insensitive match failed", count ? matches[0].id : "".ptr);

    /* Full-id prefix: "pmi" finds the PMI section commands in registry order. */
    count = ribbonSearch("pmi".ptr, matches.ptr, matches.length);
    if (count == 0)
        return fail("no results for 'pmi'", "".ptr);
    if (strcmp(matches[0].id, "pmi.quick_dimension") != 0)
        return fail("top hit for 'pmi'", matches[0].id);
    if (findCommand(matches.ptr, count, "pmi.note") == count)
        return fail("pmi.note missing from 'pmi' results", "".ptr);

    /* Rank ordering: "note" ranks pmi.note (tail prefix, rank 0) ahead of the
       commands that only match via the pmi.notes tab id (rank 2). */
    count = ribbonSearch("note".ptr, matches.ptr, matches.length);
    if (count < 2)
        return fail("expected rank-0 and rank-2 hits for 'note'", "".ptr);
    if (strcmp(matches[0].id, "pmi.note") != 0)
        return fail("rank-0 hit must come first for 'note'", matches[0].id);
    bool sawNotesTab = false;
    foreach (i; 1 .. count)
        if (strcmp(matches[i].tabId, "pmi.notes") == 0)
            sawNotesTab = true;
    if (!sawNotesTab)
        return fail("tab substring hit (pmi.notes) missing for 'note'", "".ptr);

    /* Localisation-key prefix: "command.pmi" matches keys, not ids. */
    count = ribbonSearch("command.pmi".ptr, matches.ptr, matches.length);
    if (count == 0 || strcmp(matches[0].id, "pmi.quick_dimension") != 0)
        return fail("localisation-key prefix match failed",
                    count ? matches[0].id : "".ptr);

    /* Flags survive: the planned annotation-plane command keeps its flag. */
    count = ribbonSearch("annotation_plane".ptr, matches.ptr, matches.length);
    if (count == 0)
        return fail("no results for 'annotation_plane'", "".ptr);
    size_t slot = findCommand(matches.ptr, count, "pmi.annotation_plane");
    if (slot == count)
        return fail("pmi.annotation_plane not found", "".ptr);
    if ((matches[slot].flags & cast(uint)RibbonCommandFlags.planned) == 0)
        return fail("planned flag lost in search results", matches[slot].id);

    /* Capacity truncation: "modelling" matches many commands, only one fits. */
    count = ribbonSearch("modelling".ptr, matches.ptr, 1);
    if (count != 1)
        return fail("capacity truncation violated", "".ptr);

    return 0;
}
