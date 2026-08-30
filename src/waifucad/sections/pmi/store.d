module waifucad.sections.pmi.store;

import core.stdc.string : strcmp;
import waifucad.sections.pmi.types : PmiAnnotation, PmiAnnotationKind, PmiAssociation;

enum WC_MAX_PMI_ANNOTATIONS = 2048;

struct PmiStore
{
    PmiAnnotation[WC_MAX_PMI_ANNOTATIONS] annotations;
    size_t count;
    uint nextId;

    void clear() nothrow @nogc
    {
        count = 0;
        nextId = 1;
    }

    uint add(PmiAnnotationKind kind, const(char)* name, const(char)* text,
             PmiAssociation association, bool associative = true) nothrow @nogc
    {
        if (count >= annotations.length) return 0;
        auto item = &annotations[count++];
        *item = PmiAnnotation.init;
        item.id = nextId == 0 ? 1 : nextId;
        nextId = item.id + 1;
        item.kind = kind;
        item.name.set(name);
        item.text.set(text);
        item.association = association;
        item.associative = associative;
        item.visible = true;
        return item.id;
    }

    PmiAnnotation* findById(uint id) nothrow @nogc
    {
        if (id == 0) return null;
        foreach (i; 0 .. count)
            if (annotations[i].id == id) return &annotations[i];
        return null;
    }

    PmiAnnotation* findByName(const(char)* name) nothrow @nogc
    {
        if (name is null) return null;
        foreach (i; 0 .. count)
            if (strcmp(annotations[i].name.ptr(), name) == 0) return &annotations[i];
        return null;
    }

    bool setText(const(char)* name, const(char)* text) nothrow @nogc
    {
        auto item = findByName(name);
        if (item is null) return false;
        item.text.set(text);
        return true;
    }

    bool setVisible(const(char)* name, bool visible) nothrow @nogc
    {
        auto item = findByName(name);
        if (item is null) return false;
        item.visible = visible;
        return true;
    }

    bool removeByName(const(char)* name) nothrow @nogc
    {
        if (name is null) return false;
        foreach (i; 0 .. count)
        {
            if (strcmp(annotations[i].name.ptr(), name) != 0) continue;
            foreach (j; i + 1 .. count)
                annotations[j - 1] = annotations[j];
            --count;
            return true;
        }
        return false;
    }
}



