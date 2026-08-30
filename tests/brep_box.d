module tests.brep_box;

import core.stdc.stdio : fprintf, stderr;
import waifucad.brep.types : BRepArena;
import waifucad.brep.euler : splitLineEdge;
import waifucad.brep.kernel : makeBox;
import waifucad.brep.validate : validateClosedSolid;

extern(C) int main()
{
    BRepArena arena;
    arena.clear();
    auto solid = makeBox(&arena, 80.0, 50.0, 10.0);
    if (solid == 0)
        return 10;
    if (arena.vertexCount != 8 || arena.edgeCount != 12 || arena.coedgeCount != 24 ||
        arena.loopCount != 6 || arena.faceCount != 6 || arena.shellCount != 1 || arena.solidCount != 1)
    {
        fprintf(stderr, "Unexpected WaifuBRep box topology counts.\n");
        return 11;
    }
    auto validation = validateClosedSolid(&arena, solid);
    if (validation != 0)
    {
        fprintf(stderr, "WaifuBRep box validation failed: %d\n", validation);
        return 12;
    }

    auto split = splitLineEdge(&arena, 1, 0.5);
    if (!split.valid || arena.vertexCount != 9 || arena.edgeCount != 13 || arena.coedgeCount != 26)
    {
        fprintf(stderr, "WaifuBRep line-edge split failed.\n");
        return 13;
    }
    validation = validateClosedSolid(&arena, solid);
    if (validation != 0)
    {
        fprintf(stderr, "WaifuBRep split box validation failed: %d\n", validation);
        return 14;
    }
    return 0;
}



