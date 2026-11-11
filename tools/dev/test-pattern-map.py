#!/usr/bin/env python3
"""Writes a raster MBTiles that is plainly NOT a map, for developing and
testing the Navigation screen (ADR-0030). Convert it with the official tool:

    python3 tools/dev/test-pattern-map.py --out build/maps/test-pattern.mbtiles
    pmtiles convert build/maps/test-pattern.mbtiles build/maps/test-pattern.pmtiles

Styles:
  pattern  256 px PNGs: a grid, "TEST PATTERN - NOT A MAP" and z/x/y (needs Pillow)
  solid    256 px PNGs of five flat colours (no Pillow), for small fixtures
  id       three bytes per tile, [z, x % 256, y % 256]: not images, for reader tests

The default area is the simulated receiver's loop near Lebanon, Kansas
(services/navigation/src/sim.rs), zooms 0-16.
"""
import argparse
import math
import os
import sqlite3
import struct
import zlib


def tile_range(z, west, south, east, north):
    n = 1 << z

    def x_of(lon):
        return min(n - 1, max(0, int((lon + 180.0) / 360.0 * n)))

    def y_of(lat):
        r = math.radians(max(-85.0511, min(85.0511, lat)))
        return min(n - 1, max(0, int((1.0 - math.asinh(math.tan(r)) / math.pi) / 2.0 * n)))

    return range(x_of(west), x_of(east) + 1), range(y_of(north), y_of(south) + 1)


def png_solid(rgb):
    """A valid 256x256 PNG of one colour, without Pillow."""
    w = h = 256
    raw = b"".join(b"\x00" + bytes(rgb) * w for _ in range(h))

    def chunk(kind, data):
        body = kind + data
        return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body) & 0xFFFFFFFF)

    return (b"\x89PNG\r\n\x1a\n"
            + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(raw, 9))
            + chunk(b"IEND", b""))


SOLID = [(222, 226, 230), (206, 212, 218), (233, 236, 239), (214, 219, 224), (199, 205, 211)]


def png_pattern(z, x, y):
    from io import BytesIO

    from PIL import Image, ImageDraw

    hue = [(236, 240, 245), (240, 236, 245), (236, 245, 238), (245, 241, 233)][z % 4]
    im = Image.new("RGB", (256, 256), hue)
    d = ImageDraw.Draw(im)
    for i in range(0, 256, 32):
        d.line([(i, 0), (i, 255)], fill=(205, 210, 218))
        d.line([(0, i), (255, i)], fill=(205, 210, 218))
    d.rectangle([0, 0, 255, 255], outline=(150, 156, 166))
    d.text((10, 10), "TEST PATTERN", fill=(120, 60, 160))
    d.text((10, 24), "NOT A MAP", fill=(120, 60, 160))
    d.text((10, 230), f"{z}/{x}/{y}", fill=(60, 66, 76))
    out = BytesIO()
    im.save(out, "PNG", optimize=True)
    return out.getvalue()


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--out", required=True)
    ap.add_argument("--style", choices=["pattern", "solid", "id"], default="pattern")
    ap.add_argument("--bbox", default="-98.60,39.78,-98.47,39.88", help="west,south,east,north")
    ap.add_argument("--minzoom", type=int, default=0)
    ap.add_argument("--maxzoom", type=int, default=16)
    ap.add_argument("--world-below", type=int, default=0,
                    help="zooms below this cover the whole world, not just the bbox")
    a = ap.parse_args()
    west, south, east, north = (float(v) for v in a.bbox.split(","))
    os.makedirs(os.path.dirname(os.path.abspath(a.out)), exist_ok=True)
    if os.path.exists(a.out):
        os.remove(a.out)
    db = sqlite3.connect(a.out)
    db.execute("CREATE TABLE metadata (name TEXT, value TEXT)")
    db.execute("CREATE TABLE tiles (zoom_level INTEGER, tile_column INTEGER, tile_row INTEGER, tile_data BLOB)")
    db.execute("CREATE UNIQUE INDEX tile_index ON tiles (zoom_level, tile_column, tile_row)")
    meta = {
        "name": f"F-250 test pattern ({a.style})",
        "format": "png",
        "type": "baselayer",
        "bounds": f"{west},{south},{east},{north}",
        "center": f"{(west + east) / 2},{(south + north) / 2},{min(13, a.maxzoom)}",
        "minzoom": str(a.minzoom),
        "maxzoom": str(a.maxzoom),
        "attribution": "Test pattern, not map data",
    }
    db.executemany("INSERT INTO metadata VALUES (?, ?)", meta.items())
    count = 0
    for z in range(a.minzoom, a.maxzoom + 1):
        if z < a.world_below:
            xs, ys = range(1 << z), range(1 << z)
        else:
            xs, ys = tile_range(z, west, south, east, north)
        for x in xs:
            for y in ys:
                if a.style == "id":
                    data = bytes([z, x % 256, y % 256])
                elif a.style == "solid":
                    data = png_solid(SOLID[(x * 7 + y * 3 + z) % len(SOLID)])
                else:
                    data = png_pattern(z, x, y)
                tms_row = (1 << z) - 1 - y
                db.execute("INSERT INTO tiles VALUES (?, ?, ?, ?)", (z, x, tms_row, data))
                count += 1
    db.commit()
    db.close()
    print(f"{a.out}: {count} tiles, zooms {a.minzoom}-{a.maxzoom}")


if __name__ == "__main__":
    main()
