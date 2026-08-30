# OS port: Solaris

This directory contains Solaris-specific build, ABI and packaging work. See `config/targets.json` for per-architecture status.

## Current WaifuCAD policy

For both declared Solaris x86-64 and SPARC64 targets, the project now allows the user-confirmed GTK4 and Vulkan paths as first preferences when their build/runtime probes succeed. GTK3/Motif/Xlib and OpenGL remain fallbacks; x86-64 additionally retains the Qt5 policy entry.

This policy entry still does not mark either complete application port as verified. A verified target requires a reproducible compiler, native thread shim, GUI and renderer build/run record on the specific Solaris machine.

The BetterC multicore layer uses the portable `wc_threads.h` ABI. The initial Solaris attempt should build `native/threads/wc_threads_posix.c`; if the system compiler needs different pthread switches, set `THREAD_CFLAGS` and `THREAD_LDFLAGS` rather than changing kernel D modules.



