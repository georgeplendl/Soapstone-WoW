"""Minimal PNG reader/writer and TGA writer, standard library only.

Reads 8-bit, non-interlaced PNGs (greyscale, RGB, palette, grey+alpha, RGBA)
into rows of (r, g, b, a) tuples in 0-255.
"""

import struct
import zlib

_CHANNELS = {0: 1, 2: 3, 3: 1, 4: 2, 6: 4}


def _paeth(a, b, c):
    p = a + b - c
    pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
    if pa <= pb and pa <= pc:
        return a
    return b if pb <= pc else c


def read_png(path):
    data = open(path, "rb").read()
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        raise ValueError("not a PNG")
    pos, idat, palette, trns = 8, b"", None, None
    while pos < len(data):
        length, kind = struct.unpack(">I4s", data[pos:pos + 8])
        body = data[pos + 8:pos + 8 + length]
        if kind == b"IHDR":
            width, height, depth, ctype, _, _, interlace = struct.unpack(">IIBBBBB", body)
        elif kind == b"PLTE":
            palette = [tuple(body[i:i + 3]) for i in range(0, len(body), 3)]
        elif kind == b"tRNS":
            trns = body
        elif kind == b"IDAT":
            idat += body
        pos += 12 + length
    if depth != 8 or interlace:
        raise ValueError("only 8-bit non-interlaced PNGs are supported")

    bpp = _CHANNELS[ctype]
    stride = width * bpp
    raw = zlib.decompress(idat)
    prev = bytearray(stride)
    rows = []
    for y in range(height):
        ftype = raw[y * (stride + 1)]
        line = bytearray(raw[y * (stride + 1) + 1:(y + 1) * (stride + 1)])
        for i in range(stride):
            left = line[i - bpp] if i >= bpp else 0
            up = prev[i]
            upleft = prev[i - bpp] if i >= bpp else 0
            if ftype == 1:
                line[i] = (line[i] + left) & 255
            elif ftype == 2:
                line[i] = (line[i] + up) & 255
            elif ftype == 3:
                line[i] = (line[i] + (left + up) // 2) & 255
            elif ftype == 4:
                line[i] = (line[i] + _paeth(left, up, upleft)) & 255
        prev = line

        row = []
        for x in range(width):
            px = line[x * bpp:(x + 1) * bpp]
            if ctype == 6:
                row.append(tuple(px))
            elif ctype == 2:
                row.append((*px, 255))
            elif ctype == 0:
                row.append((px[0], px[0], px[0], 255))
            elif ctype == 4:
                row.append((px[0], px[0], px[0], px[1]))
            elif ctype == 3:
                idx = px[0]
                alpha = trns[idx] if trns and idx < len(trns) else 255
                row.append((*palette[idx], alpha))
        rows.append(row)
    return rows


def write_png(path, rows):
    height, width = len(rows), len(rows[0])
    raw = b"".join(b"\x00" + bytes(c for px in row for c in px) for row in rows)

    def chunk(kind, body):
        return struct.pack(">I", len(body)) + kind + body + struct.pack(">I", zlib.crc32(kind + body) & 0xFFFFFFFF)

    open(path, "wb").write(
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0))
        + chunk(b"IDAT", zlib.compress(raw, 9))
        + chunk(b"IEND", b"")
    )


def write_tga(path, rows):
    """Uncompressed 32-bit TGA with 8 alpha bits, bottom-left origin."""
    height, width = len(rows), len(rows[0])
    header = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, width, height, 32, 8)
    body = bytearray()
    for row in reversed(rows):
        for r, g, b, a in row:
            body += bytes((b, g, r, a))
    open(path, "wb").write(header + body)
