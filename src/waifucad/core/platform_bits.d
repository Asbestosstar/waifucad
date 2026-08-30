module waifucad.core.platform_bits;


/* WaifuCAD deliberately targets 64-bit address spaces only. Keep this in the
 * common BetterC source list so accidental 32-bit ports fail at compile time
 * rather than producing subtly incompatible ABI objects. */
static assert(size_t.sizeof == 8, "WaifuCAD requires a 64-bit target ABI.");



