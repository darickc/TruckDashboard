#!/usr/bin/env python3
"""Builds navigation's offline search index for one or more regions (ADR-0038).

  1. Download each region's OpenStreetMap extract (ODbL) from Geofabrik, the
     same file `make route-region` uses, checked against Geofabrik's MD5 and
     not fetched again for the same date (build-routing.py's download).
     --bbox clips it first, as build-routing.py does, e.g. the lower 48 out of
     Geofabrik's US.
  2. With osmium, export the extract's state boundaries (admin_level=4) as
     GeoJSON beside it, so each result names its state ("Kansas City · KS").
     Without osmium the index is built without states, and says so.
  3. Run tools/search-index (Rust, `cargo run --release`): addresses, named
     streets, towns and named places into one SQLite file,
     build/search/search.sqlite.
  4. Copy it to /tmp/f250/search/ for `make navigation` and `make sim`.

  build-search.py --region north-america/us/kansas
  build-search.py --region north-america/us --bbox=-124.85,24.4,-66.88,49.38 --name "Lower 48 states"
  build-search.py --pbf my-extract.osm.pbf --name "My region"

Needs curl and cargo (and osmium for --bbox). Kansas builds in about 2 s into
35 MB; the lower 48 in about 8 min into 4.9 GB, with 10 GB of memory at its
peak [BENCH, 2026-11-12, M-series Mac].

`make map-stick SEARCH=build/search/search.sqlite` puts it on the map stick.
"""
import argparse
import importlib.util
import os
import re
import shutil
import subprocess
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))


def say(msg):
    print(f"==> {msg}", flush=True)


def die(msg):
    print(f"build-search: {msg}", file=sys.stderr)
    sys.exit(1)


def routing_tools():
    """build-routing.py's download and clip, so both builds use the same
    files from Geofabrik."""
    path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "build-routing.py")
    spec = importlib.util.spec_from_file_location("build_routing", path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def state_boundaries(pbf):
    """The extract's state boundaries as GeoJSON lines beside it (osmium),
    reused while newer than the extract; None without osmium. A boundary
    only partly in the extract can't be assembled and is left out."""
    if shutil.which("osmium") is None:
        say("osmium not found (brew install osmium-tool): results won't name their state")
        return None
    out = re.sub(r"(\.osm)?\.pbf$", "", pbf) + ".states.geojsonseq"
    if os.path.exists(out) and os.path.getmtime(out) > os.path.getmtime(pbf):
        say(f"{os.path.basename(out)}: already exported")
        return out
    say(f"Export the state boundaries of {os.path.basename(pbf)}")
    tmp = out + ".osm.pbf"
    for cmd in (["osmium", "tags-filter", pbf, "r/admin_level=4", "-o", tmp, "--overwrite"],
                ["osmium", "export", tmp, "-f", "geojsonseq", "--geometry-types=polygon",
                 "-o", out + ".part", "--overwrite"]):
        if subprocess.run(cmd).returncode != 0:
            die(f"{' '.join(cmd[:2])} failed")
    os.remove(tmp)
    os.replace(out + ".part", out)
    return out


def region_name(region):
    """north-america/us/kansas -> Kansas; north-america/us -> United States."""
    last = region.rstrip("/").rsplit("/", 1)[-1]
    special = {"us": "United States", "dc": "District of Columbia"}
    return special.get(last, " ".join(w.capitalize() for w in last.split("-")))


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--region", action="append", default=[],
                    help="a Geofabrik region path, e.g. north-america/us/kansas (repeatable)")
    ap.add_argument("--pbf", action="append", default=[], help="a local .osm.pbf instead (repeatable)")
    ap.add_argument("--bbox", metavar="W,S,E,N", help="clip the extracts to this box first (osmium)")
    ap.add_argument("--name", action="append", default=[],
                    help="what the index covers, for the screen (repeatable); "
                         "default: the regions' names")
    ap.add_argument("--out", default=os.path.join(ROOT, "build/search/search.sqlite"))
    ap.add_argument("--dev-copy", default="/tmp/f250/search/search.sqlite",
                    help="also copy the result here for make navigation/sim ('' for none)")
    a = ap.parse_args()
    if not a.region and not a.pbf:
        die("give --region (e.g. north-america/us/kansas) or --pbf")
    cargo = shutil.which("cargo")
    if cargo is None:
        die("cargo not found: run make setup (or put rustup's bin on PATH)")

    br = routing_tools()
    downloads = os.path.join(ROOT, "build/routing/download")
    os.makedirs(downloads, exist_ok=True)
    pbfs = [br.download(r, downloads) for r in a.region]
    for p in a.pbf:
        if not os.path.isfile(p):
            die(f"{p}: no such file")
        pbfs.append(p)
    when = br.data_date(pbfs)
    if a.bbox:
        if not hasattr(br, "clip"):
            die("--bbox needs build-routing.py's clip (not in this checkout): clip with osmium and give --pbf")
        bbox = br.parse_bbox(a.bbox)
        pbfs = [br.clip(p, bbox) for p in pbfs]
    names = a.name or [region_name(r) for r in a.region] or [
        os.path.basename(p).split(".")[0] for p in a.pbf]

    states = [s for s in (state_boundaries(p) for p in pbfs) if s]
    cmd = [cargo, "run", "--release", "-q", "-p", "search-index", "--", "build",
           "--out", os.path.abspath(a.out)]
    if states:
        merged = os.path.join(os.path.dirname(os.path.abspath(a.out)), "states.geojsonseq")
        os.makedirs(os.path.dirname(merged), exist_ok=True)
        with open(merged, "w") as m:
            for f in states:
                with open(f) as one:
                    m.write(one.read())
        cmd += ["--states", merged]
    for p in pbfs:
        cmd += ["--pbf", os.path.abspath(p)]
    for n in names:
        cmd += ["--region", n]
    if when:
        cmd += ["--data-date", when]
    say(f"Build the search index from {', '.join(os.path.basename(p) for p in pbfs)}")
    r = subprocess.run(cmd, cwd=ROOT)
    if r.returncode != 0:
        die(f"search-index failed (exit {r.returncode})")
    say(f"{a.out}: {os.path.getsize(a.out) / 1e6:.0f} MB (© OpenStreetMap contributors, ODbL)")
    if a.dev_copy:
        os.makedirs(os.path.dirname(a.dev_copy), exist_ok=True)
        tmp = a.dev_copy + ".part"
        shutil.copyfile(a.out, tmp)
        os.replace(tmp, a.dev_copy)
        say(f"Copied to {a.dev_copy} for make navigation / make sim")


if __name__ == "__main__":
    main()
