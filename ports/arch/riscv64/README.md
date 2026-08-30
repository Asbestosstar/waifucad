# CPU architecture: riscv64

**64-bit-only project rule:** this directory represents only a 64-bit pointer/address ABI. 32-bit variants of the ISA are outside WaifuCAD scope.

WaifuCAD supports only the 64-bit RISC-V address model: **RV64 / XLEN=64**.
RV32 and every 32-bit RISC-V ABI are outside project scope.

The portable kernel must not assume a particular optional RISC-V extension.
A target/build may select an appropriate RV64 ISA string and ABI for the
actual operating system and toolchain, but the WaifuCAD C ABI must retain
64-bit pointers.

Architecture-specific vectorisation, cache-line tuning, atomics, alignment and
code-generation notes belong here. Generic modelling and WaifuBRep code should
remain architecture-neutral.



