# WebAssembly / Memory64

WaifuCAD does not support wasm32. The WebAssembly port is deliberately wasm64
only so the same 64-bit ABI invariant applies to native and WebAssembly builds.

The current build wrapper targets `wasm64-unknown-wasip1` or
`wasm64-unknown-wasip2` and requires an explicit `WASM64_SYSROOT`. This avoids
silently linking against a conventional wasm32 WASI SDK sysroot. The port is
marked `research` until a complete D + libc + linker + runtime combination is
verified end to end.

The BetterC job ABI is preserved. The initial Memory64 build uses the
synchronous thread implementation until a tested Wasm threading environment is
selected. Browser GUI/graphics bindings remain a separate future layer.



