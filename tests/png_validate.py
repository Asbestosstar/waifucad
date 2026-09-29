#!/usr/bin/env python3
"""Strict PNG validator for WaifuCAD's dependency-free PNG writer.

Parses the PNG chunk stream by hand (no Pillow): verifies the signature,
IHDR geometry/colour type, per-chunk CRC32, IDAT zlib framing, Adler32,
and that every scanline uses filter type 0. Optionally checks that two files
are byte-identical (--identical A B) or that a pixel has an expected colour
(--expect-pixel X Y R G B).
"""
import struct
import sys
import zlib


def parse_png(path):
    with open(path, 'rb') as handle:
        data = handle.read()
    if len(data) < 8 or data[:8] != b'\x89PNG\r\n\x1a\n':
        raise SystemExit(f'{path}: bad PNG signature')
    pos = 8
    width = height = None
    idat = bytearray()
    seen_iend = False
    while pos < len(data):
        if pos + 8 > len(data):
            raise SystemExit(f'{path}: truncated chunk header')
        length, ctype = struct.unpack('>I4s', data[pos:pos + 8])
        payload = data[pos + 8:pos + 8 + length]
        crc_stored, = struct.unpack('>I', data[pos + 8 + length:pos + 12 + length])
        if len(payload) != length:
            raise SystemExit(f'{path}: truncated {ctype!r} chunk')
        crc_actual = zlib.crc32(ctype)
        crc_actual = zlib.crc32(payload, crc_actual) & 0xFFFFFFFF
        if crc_actual != crc_stored:
            raise SystemExit(f'{path}: CRC mismatch in {ctype!r} chunk')
        if ctype == b'IHDR':
            width, height, depth, colour, compression, filt, interlace = struct.unpack('>IIBBBBB', payload)
            if depth != 8 or colour != 2 or compression != 0 or filt != 0 or interlace != 0:
                raise SystemExit(f'{path}: expected 8-bit RGB non-interlaced IHDR, got '
                                 f'depth={depth} colour={colour} interlace={interlace}')
            if width == 0 or height == 0:
                raise SystemExit(f'{path}: zero dimension')
        elif ctype == b'IDAT':
            idat += payload
        elif ctype == b'IEND':
            seen_iend = True
        pos += 12 + length
    if not seen_iend:
        raise SystemExit(f'{path}: missing IEND')
    if width is None:
        raise SystemExit(f'{path}: missing IHDR')

    raw = zlib.decompress(bytes(idat))
    stride = width * 3 + 1
    if len(raw) != stride * height:
        raise SystemExit(f'{path}: expected {stride * height} raw bytes, got {len(raw)}')
    rgb = bytearray(width * height * 3)
    for row in range(height):
        base = row * stride
        if raw[base] != 0:
            raise SystemExit(f'{path}: scanline {row} uses filter {raw[base]}, expected 0')
        rgb[row * width * 3:(row + 1) * width * 3] = raw[base + 1:base + stride]
    return width, height, bytes(rgb), data


def main(argv):
    args = argv[1:]
    identical = []
    expect = None
    paths = []
    i = 0
    while i < len(args):
        if args[i] == '--identical':
            identical = [args[i + 1], args[i + 2]]
            i += 3
        elif args[i] == '--expect-pixel':
            expect = tuple(int(v) for v in args[i + 1:i + 6])
            i += 6
        else:
            paths.append(args[i])
            i += 1
    for path in paths:
        width, height, rgb, _ = parse_png(path)
        print(f'{path}: {width}x{height} RGB PNG OK')
    if identical:
        _, _, _, a = parse_png(identical[0])
        _, _, _, b = parse_png(identical[1])
        if a != b:
            raise SystemExit(f'{identical[0]} and {identical[1]} differ')
        print(f'{identical[0]} == {identical[1]} (byte-identical)')
    if expect:
        if not paths:
            raise SystemExit('--expect-pixel needs a PNG path')
        x, y, r, g, b = expect
        width, height, rgb, _ = parse_png(paths[0])
        if not (0 <= x < width and 0 <= y < height):
            raise SystemExit(f'pixel {x},{y} outside {width}x{height}')
        off = (y * width + x) * 3
        actual = (rgb[off], rgb[off + 1], rgb[off + 2])
        if actual != (r, g, b):
            raise SystemExit(f'pixel {x},{y}: expected {(r, g, b)}, got {actual}')
        print(f'{paths[0]}: pixel {x},{y} == {(r, g, b)}')


if __name__ == '__main__':
    main(sys.argv)
