# WaifuCAD Architecture

WaifuCAD is a BetterC (no druntime, no GC) CAD kernel with provider-neutral
scripting and AI boundaries.

## Layers

- `src/waifucad/core/` — platform bits, fixed strings, job scheduler bridge.
- `src/waifucad/brep/` — the WaifuBRep exact boundary-representation kernel:
  topology arena, Euler operators, analytic primitives, validation, exact
  mass properties and inertia tensors.
- `src/waifucad/kernel/` — modelling history (features, parameters,
  expressions) on top of the exact backend.
- `src/waifucad/scl/` — the SCL/WCS interpreter. Ruby-like `.wcs` and legacy
  `.scl` share one dispatch; read-only `get_*` commands are dispatched before
  journal recording so inspection never enters the semantic journal.
- `src/waifucad/gui/` + `src/waifucad/graphics/` — frontend (Cocoa, GTK4)
  and graphics-backend (Vulkan, Metal) registries. Frontends and backends are
  selected through versioned ABI registries, so adding a new frontend or
  backend does not change shared code.
- `native/` — C bridges with the same registry ABI (threads, temp files, GPU
  probe, GTK4/Cocoa hosts).
- `src/waifucad/ai/` — the provider-neutral AI C ABI.

## AI boundary

AI code does not receive raw model pointers. Providers implement
`AiProviderV1` behind `extern(C)` function pointers and exchange
`AiRequestV1`/`AiResponseV1` structs; inspection happens through read-only
SCL/WCS getters, and mutation proposals arrive as SCL text that is validated
before execution. Raw `Model`, `BRepArena`, `Feature` or `Parameter` pointers
never cross this boundary.

## Dependency policy

No third-party library is required to build or run. PNG screenshots are
written by an in-tree stored-deflate writer; libdl, POSIX threads and GTK4
are probed at build time and replaced by stubs when unavailable; libm is the
only mandatory system library. Optional native accelerators (Vulkan, Metal)
are discovered at runtime through the GPU probe, including versioned Mesa
installations under `/opt`.

## 64-bit-only ABI

All supported targets are 64-bit (`static assert(size_t.sizeof == 8)`).
32-bit architectures are deliberately out of scope; see `config/targets.json`
and `ports/arch/`.
