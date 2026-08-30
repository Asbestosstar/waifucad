# Porting model

WaifuCAD is **64-bit-only**. Every common BetterC build includes `src/waifucad/core/platform_bits.d`, which compile-time asserts an eight-byte `size_t`. `config/architectures.json` and every record in `config/targets.json` also declare 64-bit width explicitly. A target with 32-bit pointers is outside the project scope rather than a degraded compatibility mode.

WaifuCAD uses three target labels:

- **bootstrap** — intended first-class development target for the base project.
- **research/historical** — directory and policy exist, but there is no claim that the current source has been built there.
- **invalid_pairing** — a requested OS/CPU combination that does not correspond to the documented operating-system architecture set.

A graphics policy is a preference list, not proof that an API exists on a platform. Runtime and build-time probes must win over the preference list.

## Compiler policy

- LDC is preferred where a suitable LLVM target, C runtime, linker and D front-end bootstrap are available.
- GDC is useful for targets where GCC has a mature native back-end and a GDC package/port can be built.
- BetterC removes the dependency on DRuntime, but it does not make every LLVM/GCC code-generation target a complete operating-system port. System headers, CRT, linker, object format and ABI details still have to work.
- A port must preserve 64-bit pointers and the common C ABI.

## GUI policy

Newer target: GTK4 or Qt6 where available and selected by target policy.
Solaris project policy permits GTK4 first, with GTK3/Qt5/Motif/Xlib fallbacks according to the target record.
Conservative UNIX elsewhere: GTK3/Qt5/Qt4 as available.
Legacy UNIX: GTK2/GTK1, Qt3/Qt2, Motif or Xlib as the machine actually supports.
Batch-only remains valid for systems with no useful local graphics path.

## Graphics policy

1. Native Vulkan with a real hardware device, when present and accepted by the target/runtime probe. Solaris target policy includes Vulkan before OpenGL.
2. Metal on modern macOS.
3. Hardware OpenGL when Vulkan is absent or software Vulkan would be a regression.
4. Software Vulkan only when explicitly selected or when it is the best available renderer.
5. Legacy OpenGL for older UNIX ports.

Do not equate “NVIDIA driver exists” with “Vulkan driver exists”. Those are separate capabilities.

## Multicore port layer

The first job-system bridge is POSIX pthread based. `THREAD_CFLAGS` and `THREAD_LDFLAGS` may be overridden by a port without editing BetterC source. A target whose native threading API is not pthread-compatible should provide another implementation of the small `wc_threads.h` ABI rather than importing an operating-system thread API directly into D.

## Per-OS build entry points

Every OS family under `ports/os/` has a `build.sh` wrapper. The implementations live under `build/os/` so target-specific compiler flags and thread shims do not leak into the common build.

Examples:

```sh
./build/os/linux.sh all
./build/os/solaris.sh batch
WASI_SDK_PATH=/opt/wasi-sdk \
WASM64_SYSROOT=/opt/wasm64-wasi-sysroot \
WASM_ABI=wasip1 \
./build/os/webassembly.sh batch
```

### RISC-V / RV64

WaifuCAD's RISC-V architecture identifier is `riscv64` and means RV64 with
XLEN=64. RV32 is deliberately unsupported.

Linux has a `linux-riscv64` research target. The cross-build helper
`build/arch/riscv64-linux.sh` accepts an RV64-capable LDC or GDC toolchain and
keeps the exact ISA extension string/toolchain ABI configurable instead of
hard-coding optional extensions into the CAD kernel.

The BSD-family matrix also has a `bsd-riscv64` research record. As with the
other BSD entries, each concrete BSD must be built and tested independently.

### WebAssembly / Memory64

WaifuCAD does not build `wasm32`. Its WebAssembly target is the 64-bit Memory64 address model and is intentionally marked `research`.

`WASM_ABI=wasip1` selects `wasm64-unknown-wasip1`; `WASM_ABI=wasip2` selects `wasm64-unknown-wasip2`. The wrapper requires an explicit `WASM64_SYSROOT` so a normal 32-bit WASI sysroot cannot be used accidentally. `wc_threads_single.c` is selected for the initial port until a specific, tested WebAssembly threading configuration is adopted.



