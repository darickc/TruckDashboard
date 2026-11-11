#!/usr/bin/env python3
"""Builds a raster PMTiles map of one region for the dashboard (ADR-0031).

  1. `pmtiles extract` the region's vector tiles from a Protomaps daily build
     (OpenStreetMap data, ODbL). Only the region's tiles are fetched.
  2. Write a MapLibre style with @protomaps/basemaps, and fetch its fonts and
     sprites (protomaps/basemaps-assets). All pinned below.
  3. Render it on this machine with tileserver-gl in Docker (pinned by digest),
     listening on 127.0.0.1 only, and crawl the region into an MBTiles file.
  4. `pmtiles convert` it to the PMTiles v3 file the Navigation tab reads.

Nothing is downloaded from tile.openstreetmap.org; its policy forbids bulk
downloads. The tileset's attribution metadata carries the OpenStreetMap
attribution, which the screen shows.

  build-raster-map.py --bbox=W,S,E,N --maxzoom Z --estimate   # counts and sizes, no network
  build-raster-map.py --bbox=W,S,E,N --maxzoom Z --out map.pmtiles

Needs: pmtiles (brew install pmtiles), Docker, Node.js 18+ with npm. A render
can be stopped and run again with the same arguments; finished tiles are kept.
"""
import argparse
import concurrent.futures
import datetime as dt
import hashlib
import json
import math
import os
import shutil
import sqlite3
import subprocess
import sys
import tarfile
import time
import urllib.error
import urllib.request

# --- Pins (record changes in ADR-0031) --------------------------------------
TILESERVER_IMAGE = (
    "maptiler/tileserver-gl:v5.7.0"
    "@sha256:24d0364e1d40da0ae3fb3269f617c26e36a883ad4b7454e5c4064a8795bfc807"
)
BASEMAPS_NPM = "@protomaps/basemaps@5.7.2"
ASSETS_COMMIT = "028c18f713baecad011301ff7a69acc39bcc2ae7"
ASSETS_URL = f"https://codeload.github.com/protomaps/basemaps-assets/tar.gz/{ASSETS_COMMIT}"
BUILD_URL = "https://build.protomaps.com/{date}.pmtiles"
# Protomaps builds stop at zoom 15; higher raster zooms overzoom its tiles.
VECTOR_MAXZOOM = 15

ATTRIBUTION = "© OpenStreetMap contributors · Protomaps"
CONTAINER = "f250-map-render"
FORMATS = {"png": "png", "webp": "webp", "jpg": "jpg"}  # file suffix -> MBTiles "format" (pmtiles convert wants "jpg")

# Average bytes per 256 px tile, measured [BENCH] on 2026-11-11 with this
# pipeline at the default settings (light flavor; WebP and PNG quality 90,
# JPEG 85) from build 20261110, on two samples: rural Kansas (section-line
# roads, a village) and central Kansas City. Real regions fall in between.
# Zooms below 8 use the zoom-8 figure; zooms above 16 the zoom-16 figure
# (per-tile size falls with zoom, so that errs high). {format: {zoom: (rural, urban)}}
BYTES_PER_TILE = {
    "webp": {8: (4800, 11900), 9: (2000, 16500), 10: (1600, 18700), 11: (1500, 17600),
             12: (1000, 15400), 13: (900, 13500), 14: (700, 11400), 15: (530, 9700),
             16: (580, 8500)},
    "png": {8: (14300, 37800), 9: (7100, 58900), 10: (6000, 69700), 11: (6000, 75500),
            12: (3600, 62800), 13: (4300, 59500), 14: (3900, 55300), 15: (2700, 49700),
            16: (2600, 39200)},
    "jpg": {8: (6200, 11900), 9: (3100, 15700), 10: (2800, 16700), 11: (2300, 16300),
            12: (1700, 14900), 13: (1800, 13600), 14: (1400, 11900), 15: (1140, 10400),
            16: (1180, 9300)},
}

TILE_LIMIT_WITHOUT_YES = 100_000  # bigger builds need --yes


def log(msg):
    print(msg, flush=True)


def die(msg):
    print(f"error: {msg}", file=sys.stderr)
    sys.exit(1)


# --- Tile maths --------------------------------------------------------------

def tile_range(z, west, south, east, north):
    n = 1 << z

    def x_of(lon):
        return min(n - 1, max(0, int((lon + 180.0) / 360.0 * n)))

    def y_of(lat):
        r = math.radians(max(-85.0511, min(85.0511, lat)))
        return min(n - 1, max(0, int((1.0 - math.asinh(math.tan(r)) / math.pi) / 2.0 * n)))

    return range(x_of(west), x_of(east) + 1), range(y_of(north), y_of(south) + 1)


def count_tiles(bbox, minzoom, maxzoom):
    out = {}
    for z in range(minzoom, maxzoom + 1):
        xs, ys = tile_range(z, *bbox)
        out[z] = len(xs) * len(ys)
    return out


def human(n):
    for unit in ("B", "kB", "MB", "GB"):
        if n < 1000:
            return f"{n:.0f} {unit}" if unit == "B" else f"{n:.1f} {unit}"
        n /= 1000
    return f"{n:.1f} TB"


def bbox_area_km2(west, south, east, north):
    r = 6371.0
    return (math.radians(east - west) * r * r
            * abs(math.sin(math.radians(north)) - math.sin(math.radians(south))))


def estimate(bbox, minzoom, maxzoom, fmt):
    counts = count_tiles(bbox, minzoom, maxzoom)
    rows, lo_total, hi_total = [], 0, 0
    for z, n in counts.items():
        table = BYTES_PER_TILE[fmt]
        rural, urban = table[max(min(table), min(z, max(table)))]
        rows.append((z, n, n * rural, n * urban))
        lo_total += n * rural
        hi_total += n * urban
    return rows, sum(counts.values()), lo_total, hi_total


def print_estimate(a, bbox):
    rows, total, lo, hi = estimate(bbox, a.minzoom, a.maxzoom, a.format)
    log(f"Region {','.join(f'{v:g}' for v in bbox)} "
        f"(about {bbox_area_km2(*bbox):,.0f} km²), zooms {a.minzoom}-{a.maxzoom}, {a.format}")
    log(f"{'zoom':>4}  {'tiles':>10}  {'size if rural':>14}  {'size if urban':>14}")
    for z, n, zlo, zhi in rows:
        log(f"{z:>4}  {n:>10,}  {human(zlo):>14}  {human(zhi):>14}")
    log(f"{'all':>4}  {total:>10,}  {human(lo):>14}  {human(hi):>14}")
    log("Rough: averages from two samples (BYTES_PER_TILE in this script). Identical "
        "tiles (empty land, water) are stored once, so sparse areas come out smaller.")
    return total


# --- Steps -------------------------------------------------------------------

def run(cmd, **kw):
    log("$ " + " ".join(cmd))
    return subprocess.run(cmd, check=True, **kw)


def need(tool, hint):
    if shutil.which(tool) is None:
        die(f"{tool} not found ({hint})")


def pick_build(date):
    """The Protomaps daily build to use: the date given, or the newest of the
    last week that exists."""
    if date:
        return date
    today = dt.datetime.now(dt.timezone.utc).date()
    for back in range(0, 8):
        d = (today - dt.timedelta(days=back)).strftime("%Y%m%d")
        head = subprocess.run(["curl", "-sfI", "--max-time", "20", BUILD_URL.format(date=d)],
                              capture_output=True)
        if head.returncode == 0:
            return d
    die("no Protomaps build found in the last week; pass --build YYYYMMDD")


def extract_vector(build, bbox, maxzoom, dest):
    if os.path.exists(dest):
        log(f"vector tiles: {dest} (kept)")
        return
    tmp = dest + ".part"
    if os.path.exists(tmp):
        os.remove(tmp)
    run(["pmtiles", "extract", BUILD_URL.format(date=build), tmp,
         "--bbox=" + ",".join(f"{v:g}" for v in bbox),
         f"--maxzoom={min(maxzoom, VECTOR_MAXZOOM)}"])
    os.replace(tmp, dest)


def fetch_assets(work, server, flavor):
    """basemaps-assets at the pinned commit: three Noto Sans fonts and the
    flavor's sprites."""
    archive = os.path.join(work, f"basemaps-assets-{ASSETS_COMMIT[:12]}.tar.gz")
    if not os.path.exists(archive):
        log(f"fetching {ASSETS_URL}")
        run(["curl", "-sfL", "--retry", "3", "-o", archive + ".part", ASSETS_URL])
        os.replace(archive + ".part", archive)
    fonts, sprites = os.path.join(server, "fonts"), os.path.join(server, "sprites")
    if os.path.isdir(fonts) and os.path.exists(os.path.join(sprites, flavor + ".json")):
        return
    os.makedirs(fonts, exist_ok=True)
    os.makedirs(sprites, exist_ok=True)
    with tarfile.open(archive) as tar:
        for m in tar.getmembers():
            parts = m.name.split("/")[1:]  # drop "basemaps-assets-<sha>/"
            if not m.isfile() or not parts or any(p in ("", ".", "..") for p in parts):
                continue
            if parts[0] == "fonts" and len(parts) == 3 and parts[2].endswith(".pbf"):
                to = os.path.join(fonts, parts[1], parts[2])
            elif parts[:2] == ["sprites", "v4"] and len(parts) == 3 \
                    and parts[2].split(".")[0].split("@")[0] == flavor:
                to = os.path.join(sprites, parts[2])
            elif parts == ["fonts", "OFL.txt"]:
                to = os.path.join(fonts, "OFL.txt")
            else:
                continue
            os.makedirs(os.path.dirname(to), exist_ok=True)
            with tar.extractfile(m) as src, open(to, "wb") as dst:
                shutil.copyfileobj(src, dst)
    if not os.path.exists(os.path.join(sprites, flavor + ".json")):
        die(f"basemaps-assets has no v4 sprites for flavor {flavor!r}")


def write_style(work, server, flavor, lang):
    node_dir = os.path.join(work, "style")
    os.makedirs(node_dir, exist_ok=True)
    pkg = os.path.join(node_dir, "node_modules", "@protomaps", "basemaps", "package.json")
    want = BASEMAPS_NPM.rsplit("@", 1)[1]
    have = json.load(open(pkg)).get("version") if os.path.exists(pkg) else None
    if have != want:
        run(["npm", "install", "--prefix", node_dir, "--no-audit", "--no-fund",
             "--ignore-scripts", "--save-exact", BASEMAPS_NPM], stdout=subprocess.DEVNULL)
    script = os.path.join(node_dir, "style.mjs")
    shutil.copyfile(os.path.join(os.path.dirname(os.path.abspath(__file__)), "style.mjs"), script)
    run(["node", script, os.path.join(server, "style.json"), flavor, lang])


def write_config(server, fmt, quality, margin):
    config = {
        "options": {
            "paths": {"root": "/data", "fonts": "fonts", "sprites": "sprites",
                      "styles": ".", "pmtiles": "data"},
            "formatOptions": {"webp": {"quality": quality},
                              "jpeg": {"quality": quality},
                              "png": {"compressionLevel": 9}},
            # Renders a margin around each tile and crops it, so labels near
            # an edge are placed the same way in both neighbours.
            "tileMargin": margin,
            "serveStaticMaps": False,
        },
        "styles": {"f250": {"style": "style.json", "serve_data": False}},
        "data": {"protomaps": {"pmtiles": "vector.pmtiles"}},
    }
    with open(os.path.join(server, "config.json"), "w") as f:
        json.dump(config, f, indent=2)


def start_server(server, port):
    subprocess.run(["docker", "rm", "-f", CONTAINER], capture_output=True)
    run(["docker", "run", "--rm", "-d", "--name", CONTAINER,
         "-p", f"127.0.0.1:{port}:8080", "-v", f"{os.path.abspath(server)}:/data:ro",
         TILESERVER_IMAGE, "--config", "/data/config.json"], stdout=subprocess.DEVNULL)
    url = f"http://127.0.0.1:{port}/styles/f250.json"
    for _ in range(120):
        try:
            with urllib.request.urlopen(url, timeout=5) as r:
                if r.status == 200:
                    return
        except (urllib.error.URLError, ConnectionError, OSError):
            pass
        time.sleep(1)
    logs = subprocess.run(["docker", "logs", CONTAINER], capture_output=True, text=True)
    stop_server()
    die("tileserver-gl didn't start:\n" + logs.stdout + logs.stderr)


def stop_server():
    subprocess.run(["docker", "rm", "-f", CONTAINER], capture_output=True)


def open_mbtiles(path, params):
    """The MBTiles being filled. Kept between runs with the same parameters,
    so a stopped render resumes; started again if anything changed."""
    key = json.dumps(params, sort_keys=True)
    if os.path.exists(path):
        db = sqlite3.connect(path)
        row = db.execute("SELECT value FROM metadata WHERE name='f250:params'").fetchone()
        if row and row[0] == key:
            return db
        db.close()
        os.remove(path)
    db = sqlite3.connect(path)
    db.execute("CREATE TABLE metadata (name TEXT, value TEXT)")
    db.execute("CREATE TABLE tiles (zoom_level INTEGER, tile_column INTEGER, "
               "tile_row INTEGER, tile_data BLOB)")
    db.execute("CREATE UNIQUE INDEX tile_index ON tiles (zoom_level, tile_column, tile_row)")
    db.execute("INSERT INTO metadata VALUES ('f250:params', ?)", (key,))
    db.commit()
    return db


def fetch_tile(port, fmt, z, x, y):
    url = f"http://127.0.0.1:{port}/styles/f250/{z}/{x}/{y}.{fmt}"
    for attempt in range(4):
        try:
            with urllib.request.urlopen(url, timeout=120) as r:
                data = r.read()
                if r.status == 200 and data:
                    return z, x, y, data
                err = f"HTTP {r.status}, {len(data)} bytes"
        except (urllib.error.URLError, ConnectionError, OSError) as e:
            err = str(e)
        time.sleep(1 + attempt * 2)
    raise RuntimeError(f"tile {z}/{x}/{y}: {err}")


def render(db, port, fmt, bbox, minzoom, maxzoom, jobs):
    have = {(z, x, (1 << z) - 1 - r)
            for z, x, r in db.execute("SELECT zoom_level, tile_column, tile_row FROM tiles")}
    for z in range(minzoom, maxzoom + 1):
        xs, ys = tile_range(z, *bbox)
        todo = [(z, x, y) for x in xs for y in ys if (z, x, y) not in have]
        total = len(xs) * len(ys)
        if not todo:
            log(f"zoom {z:>2}: {total:,} tiles (kept)")
            continue
        start, done, size = time.time(), total - len(todo), 0
        with concurrent.futures.ThreadPoolExecutor(jobs) as pool:
            futures = [pool.submit(fetch_tile, port, fmt, *t) for t in todo]
            for f in concurrent.futures.as_completed(futures):
                tz, tx, ty, data = f.result()
                db.execute("INSERT OR REPLACE INTO tiles VALUES (?, ?, ?, ?)",
                           (tz, tx, (1 << tz) - 1 - ty, data))
                done += 1
                size += len(data)
                if done % 500 == 0:
                    db.commit()
                    print(f"\rzoom {z:>2}: {done:,}/{total:,}", end="", flush=True)
        db.commit()
        secs = time.time() - start
        log(f"\rzoom {z:>2}: {total:,} tiles, {human(size)} new, "
            f"{secs:.0f} s ({len(todo) / max(secs, 0.001):.0f} tiles/s)")


def write_metadata(db, a, bbox, build):
    west, south, east, north = bbox
    meta = {
        "name": a.name,
        "description": (f"Raster render of the Protomaps basemap build {build} "
                        f"(OpenStreetMap data), {a.flavor} flavor, made by "
                        f"tools/maps/build-raster-map.py"),
        "format": FORMATS[a.format],
        "type": "baselayer",
        "version": "1",
        "bounds": f"{west:g},{south:g},{east:g},{north:g}",
        "center": f"{(west + east) / 2:.5f},{(south + north) / 2:.5f},{min(12, a.maxzoom)}",
        "minzoom": str(a.minzoom),
        "maxzoom": str(a.maxzoom),
        "attribution": ATTRIBUTION,
        "f250:protomaps_build": build,
        "f250:style": f"{BASEMAPS_NPM} {a.flavor} {a.lang}",
        "f250:assets": f"protomaps/basemaps-assets@{ASSETS_COMMIT}",
        "f250:renderer": TILESERVER_IMAGE,
        "f250:license": "Map data: OpenStreetMap contributors, ODbL "
                        "(https://www.openstreetmap.org/copyright)",
    }
    db.execute("DELETE FROM metadata WHERE name != 'f250:params'")
    db.executemany("INSERT INTO metadata VALUES (?, ?)", meta.items())
    db.commit()


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--bbox", required=True, help="west,south,east,north in degrees")
    ap.add_argument("--minzoom", type=int, default=0)
    ap.add_argument("--maxzoom", type=int, required=True)
    ap.add_argument("--format", choices=sorted(FORMATS), default="webp")
    ap.add_argument("--quality", type=int, default=90, help="WebP/JPEG quality (default 90)")
    ap.add_argument("--flavor", default="light",
                    choices=["light", "dark", "white", "grayscale", "black"])
    ap.add_argument("--lang", default="en")
    ap.add_argument("--margin", type=int, default=128,
                    help="tileserver-gl tileMargin in px (default 128)")
    ap.add_argument("--build", help="Protomaps build date YYYYMMDD (default: newest)")
    ap.add_argument("--name", default="F-250 offline map")
    ap.add_argument("--out", default="build/maps/region.pmtiles")
    ap.add_argument("--work", help="work directory (default: next to --out)")
    ap.add_argument("--jobs", type=int, default=os.cpu_count() or 4)
    ap.add_argument("--port", type=int, default=8281)
    ap.add_argument("--estimate", action="store_true",
                    help="print tile counts and sizes per zoom, then stop (no network)")
    ap.add_argument("--yes", action="store_true",
                    help=f"build even above {TILE_LIMIT_WITHOUT_YES:,} tiles")
    ap.add_argument("--keep-server", action="store_true",
                    help="leave tileserver-gl running to look at http://127.0.0.1:PORT")
    a = ap.parse_args()

    try:
        bbox = tuple(float(v) for v in a.bbox.split(","))
        assert len(bbox) == 4
    except (ValueError, AssertionError):
        die("--bbox is west,south,east,north")
    west, south, east, north = bbox
    if not (-180 <= west < east <= 180 and -85.06 <= south < north <= 85.06):
        die("--bbox must be west<east and south<north, in degrees")
    if not 0 <= a.minzoom <= a.maxzoom <= 18:
        die("zooms must satisfy 0 <= minzoom <= maxzoom <= 18")

    total = print_estimate(a, bbox)
    if a.estimate:
        return
    if total > TILE_LIMIT_WITHOUT_YES and not a.yes:
        die(f"{total:,} tiles; check the estimate above and pass --yes to build it")

    for tool, hint in [("pmtiles", "brew install pmtiles"), ("docker", "Docker Desktop"),
                       ("curl", "curl"),
                       ("node", "Node.js 18+"), ("npm", "Node.js 18+")]:
        need(tool, hint)
    if subprocess.run(["docker", "info"], capture_output=True).returncode != 0:
        die("Docker isn't running")

    work = a.work or os.path.splitext(a.out)[0] + ".work"
    server = os.path.join(work, "server")
    os.makedirs(os.path.join(server, "data"), exist_ok=True)

    build = pick_build(a.build)
    log(f"Protomaps build {build}")
    region = hashlib.sha1(f"{build} {bbox} {min(a.maxzoom, VECTOR_MAXZOOM)}".encode()).hexdigest()[:10]
    vector = os.path.join(work, f"vector-{region}.pmtiles")
    extract_vector(build, bbox, a.maxzoom, vector)
    shutil.copyfile(vector, os.path.join(server, "data", "vector.pmtiles"))
    fetch_assets(work, server, a.flavor)
    write_style(work, server, a.flavor, a.lang)
    write_config(server, a.format, a.quality, a.margin)

    params = {"build": build, "bbox": bbox, "minzoom": a.minzoom, "maxzoom": a.maxzoom,
              "format": a.format, "quality": a.quality, "flavor": a.flavor, "lang": a.lang,
              "margin": a.margin, "image": TILESERVER_IMAGE, "style": BASEMAPS_NPM,
              "assets": ASSETS_COMMIT}
    mbtiles = os.path.join(work, "raster.mbtiles")
    db = open_mbtiles(mbtiles, params)
    start_server(server, a.port)
    try:
        t0 = time.time()
        render(db, a.port, a.format, bbox, a.minzoom, a.maxzoom, a.jobs)
        log(f"rendered in {time.time() - t0:.0f} s")
    except KeyboardInterrupt:
        db.commit()
        die("stopped; run the same command again to carry on")
    finally:
        if a.keep_server:
            log(f"tileserver-gl left running: http://127.0.0.1:{a.port} "
                f"(docker rm -f {CONTAINER})")
        else:
            stop_server()
    write_metadata(db, a, bbox, build)
    db.close()

    os.makedirs(os.path.dirname(os.path.abspath(a.out)), exist_ok=True)
    run(["pmtiles", "convert", "--force", mbtiles, a.out])
    run(["pmtiles", "verify", a.out])
    log(f"{a.out}: {human(os.path.getsize(a.out))}")


if __name__ == "__main__":
    main()
