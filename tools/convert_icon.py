"""Turns art/soapstone.png into the addon's icon textures.

    py tools/convert_icon.py

Writes, into Soapstone/Media/:
  Soapstone.tga     64x64  minimap button, AddOns list
  SoapstonePin.tga  32x32  minimap pins (shown at ~16px; a smaller source
                           avoids shimmer, since addon textures get no mipmaps)

Steps: crop to the art, pad to a square, drop near-invisible stray pixels,
downscale by area-averaging in premultiplied alpha (no dark fringes), then
bleed edge colours into transparent pixels so the game's bilinear filtering
doesn't pull black into the edges.
"""

from pathlib import Path

from pngio import read_png, write_tga

ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / "art" / "soapstone.png"
MEDIA = ROOT / "Soapstone" / "Media"
OUTPUTS = {"Soapstone.tga": 64, "SoapstonePin.tga": 32}

MIN_ALPHA = 12  # source pixels fainter than this are treated as empty
MARGIN = 0.04   # padding around the art, as a fraction of the square


def crop_square(rows):
    h, w = len(rows), len(rows[0])
    pts = [(x, y) for y in range(h) for x in range(w) if rows[y][x][3] >= MIN_ALPHA]
    x0, x1 = min(p[0] for p in pts), max(p[0] for p in pts) + 1
    y0, y1 = min(p[1] for p in pts), max(p[1] for p in pts) + 1
    side = int(max(x1 - x0, y1 - y0) * (1 + 2 * MARGIN)) + 1
    ox = x0 - (side - (x1 - x0)) // 2
    oy = y0 - (side - (y1 - y0)) // 2
    out = []
    for y in range(side):
        row = []
        for x in range(side):
            sx, sy = ox + x, oy + y
            p = rows[sy][sx] if 0 <= sx < w and 0 <= sy < h else (0, 0, 0, 0)
            row.append(p if p[3] >= MIN_ALPHA else (0, 0, 0, 0))
        out.append(row)
    return out


def downscale(rows, size):
    """Area-average resample to size x size in premultiplied alpha."""
    src = len(rows)
    scale = src / size
    out = []
    for oy in range(size):
        y0, y1 = oy * scale, (oy + 1) * scale
        row = []
        for ox in range(size):
            x0, x1 = ox * scale, (ox + 1) * scale
            r = g = b = a = area = 0.0
            for sy in range(int(y0), min(src, int(y1) + 1)):
                wy = min(y1, sy + 1) - max(y0, sy)
                if wy <= 0:
                    continue
                for sx in range(int(x0), min(src, int(x1) + 1)):
                    wx = min(x1, sx + 1) - max(x0, sx)
                    if wx <= 0:
                        continue
                    weight = wx * wy
                    pr, pg, pb, pa = rows[sy][sx]
                    af = pa / 255 * weight
                    r, g, b, a = r + pr * af, g + pg * af, b + pb * af, a + af
                    area += weight
            row.append((r / a, g / a, b / a, a / area * 255) if a > 0 else None)
        out.append(row)
    return out


def bleed(rows):
    """Give every transparent pixel the colour of its nearest visible ones."""
    size = len(rows)
    rows = [list(r) for r in rows]
    while any(p is None for r in rows for p in r):
        filled = [list(r) for r in rows]
        progress = False
        for y in range(size):
            for x in range(size):
                if rows[y][x] is not None:
                    continue
                acc, n = [0.0, 0.0, 0.0], 0
                for dy in (-1, 0, 1):
                    for dx in (-1, 0, 1):
                        yy, xx = y + dy, x + dx
                        if 0 <= yy < size and 0 <= xx < size and rows[yy][xx] is not None:
                            p = rows[yy][xx]
                            acc[0] += p[0]; acc[1] += p[1]; acc[2] += p[2]; n += 1
                if n:
                    filled[y][x] = (acc[0] / n, acc[1] / n, acc[2] / n, 0.0)
                    progress = True
        rows = filled
        if not progress:
            break
    return [[p if p is not None else (0.0, 0.0, 0.0, 0.0) for p in r] for r in rows]


def to_bytes(rows):
    return [[tuple(max(0, min(255, round(c))) for c in p) for p in row] for row in rows]


def main():
    square = crop_square(read_png(SOURCE))
    MEDIA.mkdir(parents=True, exist_ok=True)
    for name, size in OUTPUTS.items():
        write_tga(MEDIA / name, to_bytes(bleed(downscale(square, size))))
        print(f"wrote {MEDIA / name} ({size}x{size}, from a {len(square)}x{len(square)} crop)")


if __name__ == "__main__":
    main()
