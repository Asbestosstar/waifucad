# wasm64

**64-bit-only project rule:** this directory represents only a 64-bit pointer/address ABI. 32-bit variants of the ISA are outside WaifuCAD scope.

WaifuCAD is 64-bit-only, so WebAssembly support targets the Memory64/`wasm64`
address model rather than `wasm32`. This is a research port: the compiler,
libc/WASI sysroot, linker and runtime must all agree on 64-bit pointers.

Presence of this directory is not a verified support claim.



