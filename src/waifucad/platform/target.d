module waifucad.platform.target;

enum OsFamily : ubyte
{
    unknown, linux, hpux, aix, solaris, illumos, macos, irix, haiku,
    bsdFamily, zos, tru64, openvms, openserver10, webassembly
}

/*
 * Every concrete CPU architecture in this enum is a 64-bit WaifuCAD target.
 * Do not add RV32, x86-32, ARM32, wasm32 or any other 32-bit architecture.
 */
enum CpuArchitecture : ubyte
{
    unknown,
    x86_64,
    aarch64,
    riscv64,
    sparc64,
    ppc64,
    ppc64le,
    s390x,
    ia64,
    parisc64,
    mips64,
    alpha64,
    tilegx,
    wasm64
}

enum PortStatus : ubyte
{
    bootstrap, research, historical, batchOnly, invalidPairing
}

struct TargetIdentity
{
    OsFamily os;
    CpuArchitecture arch;
    PortStatus status;
    bool localGuiExpected;
}

/* Return the project ABI width for a declared architecture. Unknown is not a
 * buildable architecture and therefore returns zero. */
ubyte architectureAddressBits(CpuArchitecture arch) pure nothrow @nogc
{
    final switch (arch)
    {
        case CpuArchitecture.unknown:
            return 0;
        case CpuArchitecture.x86_64:
        case CpuArchitecture.aarch64:
        case CpuArchitecture.riscv64:
        case CpuArchitecture.sparc64:
        case CpuArchitecture.ppc64:
        case CpuArchitecture.ppc64le:
        case CpuArchitecture.s390x:
        case CpuArchitecture.ia64:
        case CpuArchitecture.parisc64:
        case CpuArchitecture.mips64:
        case CpuArchitecture.alpha64:
        case CpuArchitecture.tilegx:
        case CpuArchitecture.wasm64:
            return 64;
    }
}

bool isWaifuCad64BitArchitecture(CpuArchitecture arch) pure nothrow @nogc
{
    return architectureAddressBits(arch) == 64;
}

static assert(architectureAddressBits(CpuArchitecture.riscv64) == 64);
static assert(architectureAddressBits(CpuArchitecture.wasm64) == 64);



