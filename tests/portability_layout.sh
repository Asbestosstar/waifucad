#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT"

# Fast textual guards inspect identifiers rather than explanatory notes, so
# documentation may explicitly say that RV32/wasm32 are unsupported.
if grep -Ei '"(id|arch)"[[:space:]]*:[[:space:]]*"(x86_32|i[3-6]86|rv32|riscv32|arm32|aarch32|wasm32)"' config/targets.json config/architectures.json >/dev/null 2>&1; then
    echo "32-bit architecture/target identifier leaked into the 64-bit-only manifests." >&2
    exit 10
fi

# Every explicit architecture/target bit-width declaration must be 64.
if grep -E '"bits"[[:space:]]*:[[:space:]]*[0-9]+' config/targets.json config/architectures.json |    grep -Ev '"bits"[[:space:]]*:[[:space:]]*64([,[:space:]]|$)' >/dev/null 2>&1; then
    echo "A manifest contains a non-64-bit architecture/target width." >&2
    exit 11
fi

grep -q '"requiredAddressBits"[[:space:]]*:[[:space:]]*64' config/architectures.json
grep -q '"id"[[:space:]]*:[[:space:]]*"riscv64"' config/architectures.json
grep -q '"id"[[:space:]]*:[[:space:]]*"linux-riscv64"' config/targets.json
grep -q '"id"[[:space:]]*:[[:space:]]*"loongarch64"' config/architectures.json
grep -q '"id"[[:space:]]*:[[:space:]]*"linux-loongarch64"' config/targets.json
grep -q '"id"[[:space:]]*:[[:space:]]*"bsd-riscv64"' config/targets.json
[ -f ports/arch/riscv64/README.md ]
[ -x build/arch/riscv64-linux.sh ]
[ -f ports/arch/loongarch64/README.md ]
[ -x build/arch/loongarch64-linux.sh ]

grep -q 'static assert(size_t.sizeof == 8' src/waifucad/core/platform_bits.d
grep -q 'riscv64' src/waifucad/platform/target.d
grep -q 'loongarch64' src/waifucad/platform/target.d
grep -q 'wasm64' src/waifucad/platform/target.d

for directory in ports/arch/*; do
    [ -d "$directory" ] || continue
    case "$(basename "$directory")" in
        *32*|i386|i486|i586|i686|arm|armv6|armv7|riscv32|wasm32)
            echo "32-bit architecture directory is forbidden: $directory" >&2
            exit 12
            ;;
    esac
done

for directory in ports/os/*; do
    [ -d "$directory" ] || continue
    [ -x "$directory/build.sh" ] || {
        echo "Missing executable OS build wrapper: $directory/build.sh" >&2
        exit 13
    }
done

for script in build/os/*.sh build/arch/*.sh; do
    [ -x "$script" ] || {
        echo "Build script is not executable: $script" >&2
        exit 14
    }
done

for script in build/os/*.sh; do
    grep -q 'WC_TARGET_BITS=64' "$script" || {
        echo "OS build wrapper does not explicitly enforce 64 bits: $script" >&2
        exit 15
    }
done

if WC_TARGET_BITS=32 ./build.sh clean >/dev/null 2>&1; then
    echo "Common build accepted a 32-bit target request." >&2
    exit 16
fi

printf '64-bit-only target/build layout test passed, including riscv64 and loongarch64.\n'



