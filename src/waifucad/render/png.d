module waifucad.render.png;

/*
 * Minimal PNG writer using only the C standard library, so screenshots work
 * on hosts without zlib, libpng or any other image dependency. Output is
 * 8-bit RGB (colour type 2), one IDAT chunk holding a zlib stream made of
 * stored (uncompressed) deflate blocks: bigger than compressed output, but
 * every compliant decoder accepts it and there is nothing to install.
 */

import core.stdc.stdio : FILE, fclose, fopen, fwrite;
import core.stdc.stdlib : free, malloc;

enum WC_PNG_OK = 0;
enum WC_PNG_INVALID_ARGUMENT = 1;
enum WC_PNG_TOO_LARGE = 2;
enum WC_PNG_OPEN_FAILED = 3;
enum WC_PNG_WRITE_FAILED = 4;
enum WC_PNG_OUT_OF_MEMORY = 5;

enum uint WC_PNG_MAX_DIMENSION = 4096;

private immutable ubyte[8] pngSignature = [137, 80, 78, 71, 13, 10, 26, 10];

/* Bitwise CRC32 (polynomial 0xEDB88320). Chaining convention matches zlib:
 * the previous output is passed straight back in; the function complements
 * on the way in and out. */
private uint crc32Update(uint crc, const(ubyte)* data, size_t length) nothrow @nogc
{
    crc = ~crc;
    foreach (i; 0 .. length)
    {
        crc ^= data[i];
        foreach (_; 0 .. 8)
            crc = (crc & 1u) ? (crc >> 1) ^ 0xEDB88320u : (crc >> 1);
    }
    return ~crc;
}

/* Adler32 over the filtered scanline stream (filter byte 0 before each row)
 * without materialising it. */
private uint adler32OfRaw(const(ubyte)* rgb, uint width, uint height) nothrow @nogc
{
    uint a = 1, b = 0;
    foreach (row; 0 .. height)
    {
        // The filter byte is 0: a += 0 (no-op), b += a.
        b += a;
        if (b >= 65521u) b -= 65521u;
        immutable size_t base = row * cast(size_t)width * 3u;
        foreach (i; 0 .. cast(size_t)width * 3u)
        {
            a += rgb[base + i];
            if (a >= 65521u) a -= 65521u;
            b += a;
            b %= 65521u; // b + a can reach ~131k, so a single subtract is not enough
        }
    }
    return (b << 16) | a;
}

private bool writeU32BE(FILE* file, uint value) nothrow @nogc
{
    ubyte[4] bytes;
    bytes[0] = cast(ubyte)(value >> 24);
    bytes[1] = cast(ubyte)(value >> 16);
    bytes[2] = cast(ubyte)(value >> 8);
    bytes[3] = cast(ubyte)(value);
    return fwrite(bytes.ptr, 1, 4, file) == 4;
}

private bool writeChunk(FILE* file, const(char)* type, const(ubyte)* data, size_t length) nothrow @nogc
{
    if (!writeU32BE(file, cast(uint)length))
        return false;
    if (fwrite(type, 1, 4, file) != 4)
        return false;
    if (length > 0 && fwrite(data, 1, length, file) != length)
        return false;
    uint crc = crc32Update(0, cast(const(ubyte)*)type, 4);
    if (length > 0)
        crc = crc32Update(crc, data, length);
    return writeU32BE(file, crc);
}

/*
 * Write width*height*3 bytes of RGB pixel data as a PNG. Returns WC_PNG_OK
 * or one of the WC_PNG_* error codes.
 */
int writePngRgb(const(char)* path, const(ubyte)* rgb, uint width, uint height) nothrow @nogc
{
    if (path is null || rgb is null || width == 0 || height == 0)
        return WC_PNG_INVALID_ARGUMENT;
    if (width > WC_PNG_MAX_DIMENSION || height > WC_PNG_MAX_DIMENSION)
        return WC_PNG_TOO_LARGE;

    // zlib stream: 2-byte header, stored deflate blocks (max 65535 each),
    // 4-byte adler32. The raw image has one filter byte per scanline.
    immutable size_t rowBytes = cast(size_t)width * 3u + 1u;
    immutable size_t rawSize = rowBytes * height;
    immutable size_t blockCount = (rawSize + 65534u) / 65535u;
    immutable size_t streamSize = 2u + rawSize + blockCount * 5u + 4u;

    auto stream = cast(ubyte*)malloc(streamSize);
    if (stream is null)
        return WC_PNG_OUT_OF_MEMORY;

    int failure = WC_PNG_OK;
    FILE* file = null;

    stream[0] = 0x78; // zlib CMF: deflate, 32K window
    stream[1] = 0x01; // FLG: check bits, no dictionary, fastest
    size_t wrote = 2;
    size_t offset = 0;
    foreach (block; 0 .. blockCount)
    {
        immutable size_t chunk = rawSize - offset > 65535u ? 65535u : rawSize - offset;
        immutable bool finalBlock = block + 1 == blockCount;
        stream[wrote++] = finalBlock ? 1u : 0u; // BFINAL, BTYPE=00 (stored)
        immutable uint len = cast(uint)chunk;
        stream[wrote++] = cast(ubyte)(len & 0xFFu);
        stream[wrote++] = cast(ubyte)(len >> 8);
        stream[wrote++] = cast(ubyte)(~len & 0xFFu);
        stream[wrote++] = cast(ubyte)((~len >> 8) & 0xFFu);
        foreach (rowByte; 0 .. chunk)
        {
            immutable size_t rawIndex = offset + rowByte;
            immutable size_t column = rawIndex % rowBytes;
            if (column == 0)
                stream[wrote++] = 0; // filter type: none
            else
            {
                immutable size_t pixelBase = (rawIndex / rowBytes) * cast(size_t)width * 3u;
                stream[wrote++] = rgb[pixelBase + column - 1];
            }
        }
        offset += chunk;
    }
    immutable adler = adler32OfRaw(rgb, width, height);
    stream[wrote++] = cast(ubyte)(adler >> 24);
    stream[wrote++] = cast(ubyte)(adler >> 16);
    stream[wrote++] = cast(ubyte)(adler >> 8);
    stream[wrote++] = cast(ubyte)(adler);

    file = fopen(path, "wb");
    if (file is null)
    {
        failure = WC_PNG_OPEN_FAILED;
        goto cleanup;
    }
    if (fwrite(pngSignature.ptr, 1, 8, file) != 8)
    {
        failure = WC_PNG_WRITE_FAILED;
        goto cleanup;
    }
    {
        ubyte[13] ihdr;
        ihdr[0] = cast(ubyte)(width >> 24);
        ihdr[1] = cast(ubyte)(width >> 16);
        ihdr[2] = cast(ubyte)(width >> 8);
        ihdr[3] = cast(ubyte)(width);
        ihdr[4] = cast(ubyte)(height >> 24);
        ihdr[5] = cast(ubyte)(height >> 16);
        ihdr[6] = cast(ubyte)(height >> 8);
        ihdr[7] = cast(ubyte)(height);
        ihdr[8] = 8; // bit depth
        ihdr[9] = 2; // colour type: truecolour RGB
        ihdr[10] = 0; // compression
        ihdr[11] = 0; // filter
        ihdr[12] = 0; // no interlace
        if (!writeChunk(file, "IHDR".ptr, ihdr.ptr, 13) ||
            !writeChunk(file, "IDAT".ptr, stream, wrote) ||
            !writeChunk(file, "IEND".ptr, null, 0))
        {
            failure = WC_PNG_WRITE_FAILED;
            goto cleanup;
        }
    }

cleanup:
    if (file !is null)
        fclose(file);
    free(stream);
    return failure;
}
