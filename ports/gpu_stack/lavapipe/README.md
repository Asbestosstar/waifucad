# GPU stack: lavapipe

Lavapipe is treated as a software Vulkan path, never as a hardware GPU. The native P1 probe recognises lavapipe/llvmpipe and emits an explicit software-Vulkan warning when every enumerated Vulkan device is software.

For GTK4 bring-up, `waifucad-gui --native --lavapipe` requests GTK's Vulkan renderer and selects a standard `lvp_icd` file when found. This is useful for correctness/fallback testing, not for performance comparisons with NVIDIA or other hardware Vulkan devices.
