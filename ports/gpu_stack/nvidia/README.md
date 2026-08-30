# GPU stack: nvidia

The native P1 GPU probe recognises NVIDIA through Vulkan vendor ID `0x10de`, Vulkan device naming, or the Linux NVIDIA driver marker under `/proc/driver/nvidia`. A Vulkan loader by itself is never treated as proof that NVIDIA Vulkan is usable.

The GTK4 bring-up UI can be launched with `--renderer gl` or `--renderer vulkan`; `auto` is preferred for normal use. The dedicated WaifuCAD Vulkan renderer remains separate P1 work.
