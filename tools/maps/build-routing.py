#!/usr/bin/env python3
"""Builds Valhalla routing data for one or more regions (ADR-0035).

  1. Download each region's OpenStreetMap extract (ODbL) from Geofabrik,
     e.g. north-america/us/kansas, and check it against Geofabrik's MD5. A
     file already downloaded for the same date isn't fetched again.
  2. In Valhalla's pinned Docker image, with no network: build the admin and
     time-zone databases (time zones are downloaded by Valhalla's own tool,
     the one step that needs the network), the routing tiles, and one tile
     extract, `valhalla_tiles.tar`, which is all the Pi needs.
  3. Copy it to /tmp/f250/routing/ for `make navigation` and `make sim`.

  build-routing.py --region north-america/us/kansas
  build-routing.py --region north-america/us/kansas --region north-america/us/nebraska
  build-routing.py --pbf my-extract.osm.pbf

Needs Docker and curl. Kansas (118 MB of OSM data) builds in about 30 s on an M-series
Mac into a 312 MB extract [BENCH, 2026-11-11].
"""
import argparse
import datetime as dt
import hashlib
import os
import re
import shutil
import subprocess
import sys
import tarfile
import urllib.parse

# --- Pins (record changes in ADR-0035) --------------------------------------
# Multi-arch index digest of the 3.9.1 release image.
VALHALLA_IMAGE = (
    "ghcr.io/valhalla/valhalla:3.9.1"
    "@sha256:4fd114eb1d26b8fc2f43bcb3df234c1b63a0bf13c277405e5943d5361dc575de"
)
GEOFABRIK = "https://download.geofabrik.de"
USER_AGENT = "f250-routing-build/1 (+https://github.com/valhalla/valhalla)"

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))


def say(msg):
    print(f"==> {msg}", flush=True)


def die(msg):
    print(f"build-routing: {msg}", file=sys.stderr)
    sys.exit(1)


def curl(*args):
    """curl, as tools/maps/build-map.py uses (Python's own TLS may lack the
    system's certificates on macOS)."""
    r = subprocess.run(["curl", "-sfL", "--retry", "3", "-A", USER_AGENT, *args],
                       capture_output=True, text=True)
    if r.returncode != 0:
        die(f"curl {' '.join(args)}: exit {r.returncode} {r.stderr.strip()}")
    return r.stdout


def resolve(region):
    """The dated file Geofabrik's -latest name points at, e.g. kansas-261111."""
    url = f"{GEOFABRIK}/{region}-latest.osm.pbf"
    r = subprocess.run(["curl", "-sI", "--max-time", "20", "-A", USER_AGENT, url],
                       capture_output=True, text=True)
    status = re.match(r"HTTP/\S+ (\d+)", r.stdout)
    if not status:
        die(f"{url}: no answer ({r.stderr.strip()})")
    code = int(status.group(1))
    if code == 200:
        return url
    location = re.search(r"^location:\s*(\S+)", r.stdout, re.I | re.M)
    if code in (301, 302, 303, 307, 308) and location:
        return urllib.parse.urljoin(url, location.group(1))
    die(f"{url}: HTTP {code} (is '{region}' a Geofabrik region? See {GEOFABRIK})")


def download(region, folder):
    url = resolve(region)
    name = url.rsplit("/", 1)[1]
    dest = os.path.join(folder, name)
    want = curl(url + ".md5").split()[0]
    if os.path.exists(dest) and md5(dest) == want:
        say(f"{name}: already downloaded")
        return dest
    say(f"Download {url}")
    curl("-o", dest + ".part", url)
    os.replace(dest + ".part", dest)
    got = md5(dest)
    if got != want:
        os.remove(dest)
        die(f"{name}: MD5 {got}, Geofabrik says {want}")
    return dest


def md5(path):
    h = hashlib.md5()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def data_date(pbfs):
    """The newest date in Geofabrik's file names (name-YYMMDD.osm.pbf), if any."""
    dates = []
    for p in pbfs:
        m = re.search(r"-(\d{6})\.osm\.pbf$", p)
        if m:
            dates.append(dt.datetime.strptime(m.group(1), "%y%m%d").date())
    return max(dates).isoformat() if dates else None


def docker(work, inputs, script):
    mounts = ["-v", f"{work}:/work"]
    for i, p in enumerate(inputs):
        mounts += ["-v", f"{os.path.abspath(p)}:/input/{i}.osm.pbf:ro"]
    cmd = ["docker", "run", "--rm", *mounts, "-w", "/work", VALHALLA_IMAGE, "bash", "-c",
           "set -euo pipefail\n" + script]
    r = subprocess.run(cmd)
    if r.returncode != 0:
        die(f"Valhalla's build failed (exit {r.returncode}); its log is above")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--region", action="append", default=[],
                    help="a Geofabrik region path, e.g. north-america/us/kansas (repeatable)")
    ap.add_argument("--pbf", action="append", default=[], help="a local .osm.pbf instead (repeatable)")
    ap.add_argument("--out", default=os.path.join(ROOT, "build/routing/valhalla_tiles.tar"))
    ap.add_argument("--work", default=os.path.join(ROOT, "build/routing/work"))
    ap.add_argument("--dev-copy", default="/tmp/f250/routing/valhalla_tiles.tar",
                    help="also copy the result here for make navigation/sim ('' for none)")
    a = ap.parse_args()
    if not a.region and not a.pbf:
        die("give --region (e.g. north-america/us/kansas) or --pbf")
    if shutil.which("docker") is None:
        die("docker not found: install Docker Desktop")
    if subprocess.run(["docker", "info"], capture_output=True).returncode != 0:
        die("Docker isn't running: start Docker Desktop")

    downloads = os.path.join(os.path.dirname(a.work), "download")
    os.makedirs(downloads, exist_ok=True)
    pbfs = [download(r, downloads) for r in a.region]
    for p in a.pbf:
        if not os.path.isfile(p):
            die(f"{p}: no such file")
        pbfs.append(p)

    work = os.path.abspath(a.work)
    if os.path.isdir(work):
        shutil.rmtree(work)  # tiles from an earlier region must not mix in
    os.makedirs(work)
    inputs = " ".join(f"/input/{i}.osm.pbf" for i in range(len(pbfs)))
    say(f"Build routing tiles from {', '.join(os.path.basename(p) for p in pbfs)} in {VALHALLA_IMAGE.split('@')[0]}")
    docker(work, pbfs, f"""
valhalla_build_config --mjolnir-tile-dir /work/tiles --mjolnir-tile-extract /work/valhalla_tiles.tar \\
  --mjolnir-admin /work/admins.sqlite --mjolnir-timezone /work/timezones.sqlite > /work/valhalla.json
valhalla_build_timezones > /work/timezones.sqlite
valhalla_build_admins --config /work/valhalla.json {inputs}
valhalla_build_tiles --config /work/valhalla.json {inputs}
valhalla_build_extract --config /work/valhalla.json
""")
    built = os.path.join(work, "valhalla_tiles.tar")
    with tarfile.open(built) as t:
        tiles = sum(1 for m in t if m.name.endswith(".gph"))
    if tiles == 0:
        die(f"{built} has no tiles")
    os.makedirs(os.path.dirname(os.path.abspath(a.out)), exist_ok=True)
    shutil.copyfile(built, a.out)
    size = os.path.getsize(a.out)
    when = data_date(pbfs)
    say(f"{a.out}: {tiles} tiles, {size / 1e6:.0f} MB, OpenStreetMap data"
        + (f" of {when}" if when else "") + " (© OpenStreetMap contributors, ODbL)")
    if a.dev_copy:
        os.makedirs(os.path.dirname(a.dev_copy), exist_ok=True)
        tmp = a.dev_copy + ".part"
        shutil.copyfile(a.out, tmp)
        os.replace(tmp, a.dev_copy)
        say(f"Copied to {a.dev_copy} for make navigation / make sim")


if __name__ == "__main__":
    main()
