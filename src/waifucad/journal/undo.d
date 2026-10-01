module waifucad.journal.undo;

import core.stdc.stdlib : malloc, free;
import core.stdc.string : memcpy, memcmp;
import waifucad.kernel.model : Model;
import waifucad.sections.pmi.store : PmiStore;

/*
 * Undo/redo transaction log.
 *
 * One transaction is one top-level SCL line executed through the interpreter
 * (GUI ribbon/dialogue/menu actions, command-line entries, or each line of a
 * script/journal replay).  Every transaction that changes the document stores
 * the complete document state as it was *before* the line ran, so undo and redo
 * are exact state swaps.  They never re-execute commands, therefore file
 * imports/exports, expression evaluation or future non-deterministic services
 * cannot make an undo diverge from the state the user actually saw.
 *
 * The document state is the modelling Model (history, parameters, sketch
 * constraints, exact WaifuBRep arena, dumb meshes, persistent-ID counters) and
 * the optional PMI store.  Script-runtime variables and callable macros are
 * interpreter state, not document state, and are deliberately not rolled back;
 * host settings (worker count, cancellation token) are preserved.
 *
 * Snapshots are heap blocks allocated on demand, never per-model GC memory.
 * They are large (several MiB each), so the log is bounded and opt-in:
 * WC_UNDO_MAX_DEPTH caps the number of retained transactions and
 * `enable(depth)` clamps to it.  A transaction whose state is byte-identical
 * after execution (read-only commands, rejected commands with no partial
 * effect) is discarded and never consumes an undo level.
 */
enum WC_UNDO_MAX_DEPTH = 64;
enum WC_UNDO_DEFAULT_DEPTH = 32;

struct UndoSnapshot
{
    Model model;
    PmiStore pmi;
    bool hasPmi;
}

enum UndoStatus : int
{
    ok = 0,
    disabled = 1,
    nothingToDo = 2,
    inTransaction = 3,
    outOfMemory = 4
}

struct UndoStack
{
    UndoSnapshot*[WC_UNDO_MAX_DEPTH] undoSlots;
    UndoSnapshot*[WC_UNDO_MAX_DEPTH] redoSlots;
    size_t undoCount;
    size_t redoCount;
    UndoSnapshot* pending;
    UndoSnapshot* spare;
    uint limit;
    uint nesting;
    bool enabled;

    bool isEnabled() const nothrow @nogc { return enabled; }
    size_t undoDepth() const nothrow @nogc { return undoCount; }
    size_t redoDepth() const nothrow @nogc { return redoCount; }
    bool inTransactionNow() const nothrow @nogc { return nesting != 0; }
    bool canUndo() const nothrow @nogc { return enabled && undoCount != 0 && nesting == 0; }
    bool canRedo() const nothrow @nogc { return enabled && redoCount != 0 && nesting == 0; }

    /* Turn recording on. depth 0 selects the default; larger values clamp. */
    void enable(uint depth = 0) nothrow @nogc
    {
        if (depth == 0)
            depth = WC_UNDO_DEFAULT_DEPTH;
        if (depth > WC_UNDO_MAX_DEPTH)
            depth = WC_UNDO_MAX_DEPTH;
        limit = depth;
        enabled = true;
        // A smaller limit than the retained history discards the oldest entries.
        while (undoCount > limit)
            dropOldestUndo();
        while (undoCount + redoCount > limit && redoCount != 0)
            dropOldestRedo();
    }

    /* Stop recording and release every retained snapshot. */
    void disable() nothrow @nogc
    {
        clear();
        enabled = false;
    }

    /* Forget all undo/redo history but keep the current enabled state. */
    void clear() nothrow @nogc
    {
        foreach (i; 0 .. undoCount)
            releaseSlot(undoSlots[i]);
        foreach (i; 0 .. redoCount)
            releaseSlot(redoSlots[i]);
        undoCount = 0;
        redoCount = 0;
        if (pending !is null)
            releaseSlot(pending);
        pending = null;
        nesting = 0;
        if (spare !is null)
            free(spare);
        spare = null;
    }

    /*
     * Start a tracked transaction.  Only the outermost call captures the
     * pre-state; nested calls only track depth so that undo/redo cannot run
     * from inside a transaction.  Every begin() must be matched by end().
     */
    void begin(const(Model)* model, const(PmiStore)* pmi) nothrow @nogc
    {
        if (!enabled || model is null)
            return;
        if (nesting++ != 0)
            return;
        pending = acquire();
        if (pending !is null)
            capture(pending, model, pmi);
    }

    /* Finish a tracked transaction started by begin(). */
    void end(const(Model)* model, const(PmiStore)* pmi) nothrow @nogc
    {
        if (nesting == 0)
            return;
        if (--nesting != 0)
            return;
        auto snapshot = pending;
        pending = null;
        if (snapshot is null || model is null)
        {
            if (snapshot !is null)
                releaseSlot(snapshot);
            return;
        }
        if (!enabled || statesEqual(snapshot, model, pmi))
        {
            recycle(snapshot);
            return;
        }
        // A genuinely new edit invalidates the redo branch.
        foreach (i; 0 .. redoCount)
            releaseSlot(redoSlots[i]);
        redoCount = 0;
        if (undoCount >= limit)
            dropOldestUndo();
        undoSlots[undoCount++] = snapshot;
    }

    UndoStatus undo(Model* model, PmiStore* pmi) nothrow @nogc
    {
        return swapState(model, pmi, undoSlots.ptr, &undoCount, redoSlots.ptr, &redoCount);
    }

    UndoStatus redo(Model* model, PmiStore* pmi) nothrow @nogc
    {
        return swapState(model, pmi, redoSlots.ptr, &redoCount, undoSlots.ptr, &undoCount);
    }

private:
    UndoStatus swapState(Model* model, PmiStore* pmi,
                         UndoSnapshot** fromSlots, size_t* fromCount,
                         UndoSnapshot** toSlots, size_t* toCount) nothrow @nogc
    {
        if (!enabled)
            return UndoStatus.disabled;
        if (nesting != 0)
            return UndoStatus.inTransaction;
        if (*fromCount == 0 || model is null)
            return UndoStatus.nothingToDo;
        auto current = acquire();
        if (current is null)
            return UndoStatus.outOfMemory;
        capture(current, model, pmi);
        auto target = fromSlots[*fromCount - 1];
        --*fromCount;
        fromSlots[*fromCount] = null;
        restore(model, pmi, target);
        recycle(target);
        toSlots[(*toCount)++] = current;
        return UndoStatus.ok;
    }

    UndoSnapshot* acquire() nothrow @nogc
    {
        if (spare !is null)
        {
            auto result = spare;
            spare = null;
            return result;
        }
        return cast(UndoSnapshot*)malloc(UndoSnapshot.sizeof);
    }

    void recycle(UndoSnapshot* snapshot) nothrow @nogc
    {
        if (snapshot is null)
            return;
        if (spare is null)
            spare = snapshot;
        else
            free(snapshot);
    }

    static void releaseSlot(UndoSnapshot* snapshot) nothrow @nogc
    {
        if (snapshot !is null)
            free(snapshot);
    }

    void dropOldestUndo() nothrow @nogc
    {
        if (undoCount == 0)
            return;
        releaseSlot(undoSlots[0]);
        foreach (i; 1 .. undoCount)
            undoSlots[i - 1] = undoSlots[i];
        --undoCount;
        undoSlots[undoCount] = null;
    }

    void dropOldestRedo() nothrow @nogc
    {
        if (redoCount == 0)
            return;
        // The oldest redo entry is the one furthest from the present.
        releaseSlot(redoSlots[0]);
        foreach (i; 1 .. redoCount)
            redoSlots[i - 1] = redoSlots[i];
        --redoCount;
        redoSlots[redoCount] = null;
    }

    static void capture(UndoSnapshot* snapshot, const(Model)* model, const(PmiStore)* pmi) nothrow @nogc
    {
        memcpy(&snapshot.model, model, Model.sizeof);
        snapshot.hasPmi = pmi !is null;
        if (pmi !is null)
            memcpy(&snapshot.pmi, pmi, PmiStore.sizeof);
    }

    static void restore(Model* model, PmiStore* pmi, const(UndoSnapshot)* snapshot) nothrow @nogc
    {
        // Host settings are not document state and survive undo/redo.
        immutable workers = model.workerCount;
        immutable token = model.recomputeCancellation;
        memcpy(model, &snapshot.model, Model.sizeof);
        model.workerCount = workers;
        model.recomputeCancellation = token;
        if (pmi !is null && snapshot.hasPmi)
            memcpy(pmi, &snapshot.pmi, PmiStore.sizeof);
    }

    static bool statesEqual(UndoSnapshot* snapshot, const(Model)* model, const(PmiStore)* pmi) nothrow @nogc
    {
        // Ignore host settings that can change without touching the document.
        snapshot.model.workerCount = model.workerCount;
        snapshot.model.recomputeCancellation = model.recomputeCancellation;
        if (memcmp(&snapshot.model, model, Model.sizeof) != 0)
            return false;
        if (pmi !is null && snapshot.hasPmi && memcmp(&snapshot.pmi, pmi, PmiStore.sizeof) != 0)
            return false;
        return true;
    }
}
