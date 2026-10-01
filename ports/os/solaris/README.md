# OS port: Solaris

This directory contains Solaris-specific build, ABI and packaging work. See `config/targets.json` for per-architecture status.

## Current WaifuCAD policy

For both declared Solaris x86-64 and SPARC64 targets, the project now allows the user-confirmed GTK4 and Vulkan paths as first preferences when their build/runtime probes succeed. GTK3/Motif/Xlib and OpenGL remain fallbacks; x86-64 additionally retains the Qt5 policy entry.

This policy entry still does not mark either complete application port as verified. A verified target requires a reproducible compiler, native thread shim, GUI and renderer build/run record on the specific Solaris machine.

The BetterC multicore layer uses the portable `wc_threads.h` ABI. The initial Solaris attempt should build `native/threads/wc_threads_posix.c`; if the system compiler needs different pthread switches, set `THREAD_CFLAGS` and `THREAD_LDFLAGS` rather than changing kernel D modules.




## Build notes (gdc, GTK4, start-up crashes)

- `gdc` builds one object per D module and runs several compilers at once (the online processor count, capped at 16). Set `WC_JOBS=N` to override or `WC_GDC_SPLIT=0` for the old single-command build. `ldc2` and `dmd` still use their own single-command path.
- GTK4 is found through `pkg-config` first, then `pkg-config` with the usual `pkgconfig` directories added (`/usr/lib/64/pkgconfig`, `/usr/lib/amd64/pkgconfig`, `/usr/lib/sparcv9/pkgconfig`, `/usr/share/pkgconfig`, ...), then by scanning `<prefix>/include/gtk-4.0` and the 64-bit library directories (`lib/64`, `lib/sparcv9`, `lib/amd64`, `lib`). Use `WC_GTK4_PREFIX=/path`, or set `GTK4_CFLAGS` and `GTK4_LIBS` explicitly. When GTK4 is not found, the build prints why.
- `./build.sh` runs `bin/waifucad-batch --help` after building and warns if it dies on a signal. For a crash such as SIGILL, build with `WC_DEBUG=1 ./build.sh batch` and run `gdb bin/waifucad-batch` or `dbx bin/waifucad-batch`, then report the faulting function (`where`) and instruction (`x/i $pc`).
- If the GTK4 headers are found but linking against GTK4 fails (for example `ld: fatal: library -lgtk-4: not found`), `./build.sh` prints the linker errors and relinks the GUI with the stub frontend instead of failing. The header scan now links versioned-only libraries (`libfoo.so.1`) by path. Use `GTK4_CFLAGS`/`GTK4_LIBS` to override, or `WC_GTK4_REQUIRED=1` to make a GTK4 link failure fatal.
- If `ld` still fails, send the first `ld:` message and the full link command; most failures are a missing `-m64` in `DFLAGS`/`CFLAGS`/`LDFLAGS` (SPARC gcc/gdc default to 32-bit, but the Solaris libraries here are in `lib/64`).
