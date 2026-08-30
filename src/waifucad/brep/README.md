# WaifuBRep

`waifucad.brep` is WaifuCAD's project-owned BetterC boundary-representation kernel.

Current code provides explicit vertex/edge/coedge/multi-loop-face/shell/solid topology; 64-bit persistent semantic topology IDs and lineage; line/circle/rational-NURBS curves; plane/cylinder/cone/sphere/torus/rational-NURBS surfaces; exact analytic primitives and supported profile-derived extrusion/revolution/sweep/loft; selected exact box boolean/shell construction; analytic intersection groundwork; tolerance/healing utilities; topology-preserving edge and planar-face split/merge operations; genus/multi-shell validation; exact mass properties for supported primitive families; and a topology-aware tessellation service kept separate from exact geometry.

This is not a claim that industrial general booleans, trimmed NURBS, filleting/chamfering, tolerant sewing or every arbitrary trim configuration is complete. Unsupported exact domains remain explicit, and tessellation never upgrades an approximation to exact B-rep. See `docs/BREP.md` and `AGENTS.MD`.

