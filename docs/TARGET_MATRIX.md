# Target matrix

WaifuCAD is **64-bit-only**. This table is generated from `config/targets.json` for human review. Presence is not a verified support claim.

Every row must have `Bits = 64`; `tests/portability_layout.sh` rejects any other value.

| Target | Bits | Status | GUI policy | Graphics policy |
|---|---:|---|---|---|
| `linux-x86_64` | 64 | bootstrap | gtk4, qt6, gtk3, xlib | vulkan, opengl |
| `linux-aarch64` | 64 | bootstrap | gtk4, qt6, gtk3, xlib | vulkan, opengl |
| `linux-riscv64` | 64 | research | gtk4, qt6, gtk3, xlib | vulkan, opengl |
| `linux-sparc64` | 64 | research | gtk4, qt6, gtk3, xlib | vulkan, opengl |
| `linux-ppc64` | 64 | research | gtk4, qt6, gtk3, xlib | vulkan, opengl |
| `linux-ppc64le` | 64 | research | gtk4, qt6, gtk3, xlib | vulkan, opengl |
| `linux-s390x` | 64 | research | none | none |
| `linux-ia64` | 64 | research | gtk4, qt6, gtk3, xlib | vulkan, opengl |
| `linux-alpha64` | 64 | research | gtk4, qt6, gtk3, xlib | vulkan, opengl |
| `linux-tilegx` | 64 | research | gtk4, qt6, gtk3, xlib | vulkan, opengl |
| `hpux-ia64` | 64 | research | motif, gtk2, xlib | opengl |
| `hpux-parisc64` | 64 | historical | motif, gtk2, xlib | opengl |
| `aix-ppc64` | 64 | research | motif, gtk3, gtk2, xlib | opengl |
| `aix-ppc64le-requested` | 64 | research | none | none |
| `solaris-x86_64` | 64 | research | gtk4, gtk3, qt5, motif, xlib | vulkan, opengl |
| `solaris-sparc64` | 64 | research | gtk4, gtk3, motif, xlib | vulkan, opengl |
| `illumos-x86_64` | 64 | research | gtk3, qt5, motif, xlib | vulkan, opengl |
| `illumos-sparc64` | 64 | research | gtk3, motif, xlib | opengl |
| `illumos-aarch64` | 64 | research | gtk3, xlib | vulkan, opengl |
| `macos-ppc64` | 64 | historical | qt4, qt3, xlib | opengl |
| `macos-x86_64` | 64 | bootstrap | qt6, gtk4 | metal, vulkan, opengl |
| `macos-aarch64` | 64 | bootstrap | qt6, gtk4 | metal, vulkan |
| `irix-mips64` | 64 | historical | motif, xlib | opengl |
| `haiku-x86_64` | 64 | research | qt6, qt5 | vulkan, opengl |
| `haiku-aarch64` | 64 | research | qt6, qt5 | vulkan, opengl |
| `bsd-x86_64` | 64 | research | gtk4, qt6, gtk3, qt5, xlib | vulkan, opengl |
| `bsd-aarch64` | 64 | research | gtk4, qt6, gtk3, qt5, xlib | vulkan, opengl |
| `bsd-riscv64` | 64 | research | gtk4, qt6, gtk3, qt5, xlib | vulkan, opengl |
| `bsd-sparc64` | 64 | research | gtk4, qt6, gtk3, qt5, xlib | vulkan, opengl |
| `bsd-ia64` | 64 | research | gtk4, qt6, gtk3, qt5, xlib | vulkan, opengl |
| `bsd-ppc64` | 64 | research | gtk4, qt6, gtk3, qt5, xlib | vulkan, opengl |
| `bsd-ppc64le` | 64 | research | gtk4, qt6, gtk3, qt5, xlib | vulkan, opengl |
| `zos-s390x` | 64 | batch_only | none | none |
| `tru64-alpha64` | 64 | historical | motif, xlib | opengl |
| `openvms-ia64` | 64 | historical | none | none |
| `openvms-x86_64` | 64 | research | none | none |
| `openvms-alpha64` | 64 | historical | none | none |
| `openvms-parisc64-requested` | 64 | invalid_pairing | none | none |
| `openserver10-x86_64` | 64 | historical | xlib, motif | opengl |
| `webassembly-wasm64-wasip1` | 64 | research | none | none |
| `webassembly-wasm64-wasip2` | 64 | research | none | none |



