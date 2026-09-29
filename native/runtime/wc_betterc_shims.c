/*
 * DMD -betterC runtime shims.
 *
 * DMD's -betterC code generator lowers array/struct fills that repeat a
 * non-zero scalar value to druntime helpers (_memsetDouble, _memset32, ...),
 * but -betterC links no druntime. LDC and GDC emit their own inline fills and
 * never reference these symbols. The implementations below follow the
 * druntime rt/memset.d contract: fill `count` copies of the given value
 * starting at `p`, returning `p`.
 *
 * Compiled and linked only for DMD builds (see betterc_shim_objects in
 * build/compiler.sh); harmless dead objects everywhere else.
 */

#include <stddef.h>
#include <stdint.h>
#include <string.h>

void* _memsetn(void* p, int value, size_t count)
{
    memset(p, value, count);
    return p;
}

void* _memset16(void* p, uint16_t value, size_t count)
{
    uint16_t* d = (uint16_t*)p;
    for (size_t i = 0; i < count; ++i)
        d[i] = value;
    return p;
}

void* _memset32(void* p, uint32_t value, size_t count)
{
    uint32_t* d = (uint32_t*)p;
    for (size_t i = 0; i < count; ++i)
        d[i] = value;
    return p;
}

void* _memset64(void* p, uint64_t value, size_t count)
{
    uint64_t* d = (uint64_t*)p;
    for (size_t i = 0; i < count; ++i)
        d[i] = value;
    return p;
}

void* _memset128(void* p, uint64_t valueLo, uint64_t valueHi, size_t count)
{
    /* D ucent fill; druntime passes the 128-bit pattern by value. We take it
     * as two 64-bit halves, which is ABI-compatible on x86_64 SysV where a
     * ucent argument arrives in a register pair. */
    unsigned char* d = (unsigned char*)p;
    for (size_t i = 0; i < count; ++i)
    {
        memcpy(d + i * 16, &valueLo, 8);
        memcpy(d + i * 16 + 8, &valueHi, 8);
    }
    return p;
}

void* _memsetFloat(void* p, float value, size_t count)
{
    float* d = (float*)p;
    for (size_t i = 0; i < count; ++i)
        d[i] = value;
    return p;
}

void* _memsetDouble(void* p, double value, size_t count)
{
    double* d = (double*)p;
    for (size_t i = 0; i < count; ++i)
        d[i] = value;
    return p;
}

void* _memsetReal(void* p, long double value, size_t count)
{
    long double* d = (long double*)p;
    for (size_t i = 0; i < count; ++i)
        d[i] = value;
    return p;
}

/* 80-bit x87 reals occupy 16 bytes of storage on x86_64 SysV. */
void* _memset80(void* p, long double value, size_t count)
{
    long double* d = (long double*)p;
    for (size_t i = 0; i < count; ++i)
        d[i] = value;
    return p;
}
