# GPU stack: mesa

The native P1 GPU probe records Mesa stack availability and recognises software Mesa Vulkan devices from lavapipe/llvmpipe device names. GTK4 can be launched with `--renderer gl` or `--renderer vulkan` for bring-up, while the status bar reports the Vulkan device that was actually enumerated.

Mesa presence alone is not treated as proof of hardware acceleration.
