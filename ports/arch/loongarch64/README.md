# CPU architecture: loongarch64

**64-bit-only project rule:** this directory represents only a 64-bit pointer/address ABI. 32-bit variants of the ISA are outside WaifuCAD scope.

WaifuCAD supports only the 64-bit LoongArch address model: **LA64 / loongarch64**.
LA32 and every 32-bit LoongArch ABI are outside project scope.

Mainstream Linux distributions for Loongson hardware use the **new-world**
ABI/toolchain stack; old-world binaries are a legacy compatibility concern and
are not a WaifuCAD target. A target/build must record which world ABI it
selects. The portable kernel must not assume the optional LSX/LASX vector
extensions: LoongArch vector code, where it is later added for tessellation or
solver hot paths, must be runtime- or build-gated with a scalar fallback.
Atomics may use either the AM* instruction family or LL/SC sequences; the
WaifuCAD C ABI and the native thread shim must remain correct on both.

Architecture-specific vectorisation, cache-line tuning, atomics, alignment and
code-generation notes belong here. Generic modelling and WaifuBRep code should
remain architecture-neutral.

Toolchain status (research, not a verified-port claim): LLVM provides a
LoongArch backend from release 17 onwards and GCC from release 12/13
onwards; a loongarch64-capable LDC or GDC build must be confirmed before this
target is upgraded from `research` in `config/targets.json`.
