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
  3. For a US region, download the US Census Bureau's TIGER/Line address
     ranges (ADDRFEAT, one zip per county, public domain; ADR-0041) for its
     states into build/search/tiger/, each file once: a run that stops
     carries on where it left off. --no-tiger skips them; --tiger-states
     names the states for --pbf input.
  4. Run tools/search-index (Rust, `cargo run --release`): addresses, named
     streets, towns, named places and the address ranges into one SQLite
     file, build/search/search.sqlite.
  5. Copy it to /tmp/f250/search/ for `make navigation` and `make sim`.

  build-search.py --region north-america/us/kansas
  build-search.py --region north-america/us --bbox=-124.85,24.4,-66.88,49.38 --name "Lower 48 states"
  build-search.py --pbf my-extract.osm.pbf --name "My region"
  build-search.py --pbf my-extract.osm.pbf --tiger-states KS,NE

Needs curl and cargo (and osmium for --bbox). Kansas builds in about 3 s into
63 MB with the Census ranges (37 MB without); the lower 48 in about 7 min into
5.2 GB without them, about 11 min and 7.2 GB with them, with 15-17.5 GB of
memory at its peak either way [SIM, 2026-11-13, M-series Mac, ADR-0041].

`make map-stick SEARCH=build/search/search.sqlite` puts it on the map stick.
"""
import argparse
import concurrent.futures
import importlib.util
import os
import re
import shutil
import subprocess
import sys
import time
import zipfile

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))

# --- US Census address ranges (record changes in ADR-0041) -------------------
# TIGER/Line Shapefiles 2026, Address Range-Feature (ADDRFEAT), released
# 2026-10-06: one zip per county, 3,227 in all, 2.7 GB (2.66 GB for the
# lower 48). Public domain: "not copyrighted ... acknowledgement must be
# given to the U.S. Census Bureau as the source" (the files' own metadata).
TIGER_YEAR = 2026
TIGER_URL = f"https://www2.census.gov/geo/tiger/TIGER{TIGER_YEAR}/ADDRFEAT/"
TIGER_USER_AGENT = "f250-search-build/1"
# Files downloaded at once, and a pause after each. At 4 at once (about 5
# files a second) the Census's server began answering every request with a
# "Request Rejected" page (HTTP 200, HTML) after about 2,600 files
# [2026-11-12]; then the download waits and tries again (TIGER_BACKOFF_S).
# A file refused while the others are served is left out (see fetch).
TIGER_JOBS = 2
TIGER_PAUSE_S = 0.25
TIGER_BACKOFF_S = (60, 120, 300, 600)

# State FIPS codes, postal abbreviations and names, from the Census Bureau's
# https://www2.census.gov/geo/docs/reference/state.txt (read 2026-11-12).
# The 50 states and DC; territories have no Geofabrik "us/" extract.
STATES = [
    ("01", "AL", "Alabama"), ("02", "AK", "Alaska"), ("04", "AZ", "Arizona"),
    ("05", "AR", "Arkansas"), ("06", "CA", "California"), ("08", "CO", "Colorado"),
    ("09", "CT", "Connecticut"), ("10", "DE", "Delaware"),
    ("11", "DC", "District of Columbia"), ("12", "FL", "Florida"),
    ("13", "GA", "Georgia"), ("15", "HI", "Hawaii"), ("16", "ID", "Idaho"),
    ("17", "IL", "Illinois"), ("18", "IN", "Indiana"), ("19", "IA", "Iowa"),
    ("20", "KS", "Kansas"), ("21", "KY", "Kentucky"), ("22", "LA", "Louisiana"),
    ("23", "ME", "Maine"), ("24", "MD", "Maryland"), ("25", "MA", "Massachusetts"),
    ("26", "MI", "Michigan"), ("27", "MN", "Minnesota"), ("28", "MS", "Mississippi"),
    ("29", "MO", "Missouri"), ("30", "MT", "Montana"), ("31", "NE", "Nebraska"),
    ("32", "NV", "Nevada"), ("33", "NH", "New Hampshire"), ("34", "NJ", "New Jersey"),
    ("35", "NM", "New Mexico"), ("36", "NY", "New York"),
    ("37", "NC", "North Carolina"), ("38", "ND", "North Dakota"), ("39", "OH", "Ohio"),
    ("40", "OK", "Oklahoma"), ("41", "OR", "Oregon"), ("42", "PA", "Pennsylvania"),
    ("44", "RI", "Rhode Island"), ("45", "SC", "South Carolina"),
    ("46", "SD", "South Dakota"), ("47", "TN", "Tennessee"), ("48", "TX", "Texas"),
    ("49", "UT", "Utah"), ("50", "VT", "Vermont"), ("51", "VA", "Virginia"),
    ("53", "WA", "Washington"), ("54", "WV", "West Virginia"),
    ("55", "WI", "Wisconsin"), ("56", "WY", "Wyoming"),
]


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


def tiger_states(regions, named):
    """State FIPS codes for the US Census ranges: --tiger-states (postal
    codes or FIPS) if given, else the US regions' states (north-america/us is
    all of them; north-america/us/california/norcal is California)."""
    by_key = {}
    for fips, abbr, name in STATES:
        for k in (fips, abbr.lower(), name.lower().replace(" ", "-")):
            by_key[k] = fips
    if named:
        out = set()
        for k in named.split(","):
            k = k.strip().lower()
            if k not in by_key:
                die(f"--tiger-states: {k!r} isn't a state's postal code or FIPS code")
            out.add(by_key[k])
        return sorted(out)
    out = set()
    for r in regions:
        parts = r.strip("/").split("/")
        if parts[:2] != ["north-america", "us"]:
            continue
        if len(parts) == 2:
            out.update(f for f, _, _ in STATES)
        elif parts[2] in by_key:
            out.add(by_key[parts[2]])
        else:
            say(f"{r}: no US state found in the name, so no Census address ranges for it"
                " (name them with --tiger-states)")
    return sorted(out)


def tiger_download(states, folder):
    """Every ADDRFEAT county zip of these states, in name order. The
    year's file list is kept beside them; a zip already there that opens is
    not fetched again, and each lands under its name only once complete."""
    os.makedirs(folder, exist_ok=True)
    listing = os.path.join(folder, "files.txt")
    if not os.path.exists(listing):
        say(f"List {TIGER_URL}")
        r = subprocess.run(["curl", "-sfL", "--retry", "3", "-A", TIGER_USER_AGENT, TIGER_URL],
                           capture_output=True, text=True)
        if r.returncode != 0:
            die(f"curl {TIGER_URL}: exit {r.returncode}")
        names = sorted(set(re.findall(rf"tl_{TIGER_YEAR}_\d{{5}}_addrfeat\.zip", r.stdout)))
        if len(names) < 3000:
            die(f"{TIGER_URL}: only {len(names)} county files listed; expected about 3,200")
        with open(listing + ".part", "w") as f:
            f.write("\n".join(names) + "\n")
        os.replace(listing + ".part", listing)
    with open(listing) as f:
        names = [n.strip() for n in f if n.strip()]
    wanted = [n for n in names if n[len(f"tl_{TIGER_YEAR}_"):][:2] in set(states)]

    def complete(path):
        try:
            with zipfile.ZipFile(path) as z:
                return any(n.endswith(".shp") for n in z.namelist())
        except (OSError, zipfile.BadZipFile):
            return False

    def rejected(path):
        try:
            with open(path, "rb") as f:
                return b"Request Rejected" in f.read(4096)
        except OSError:
            return False

    def refusing_all():
        """Whether the server refuses every file (its rate limit) rather
        than one: the first four bytes of a file already here."""
        have = next((n for n in wanted if os.path.exists(os.path.join(folder, n))), None)
        if have is None:
            return True
        r = subprocess.run(["curl", "-sL", "-r", "0-3", "-A", TIGER_USER_AGENT, TIGER_URL + have],
                           capture_output=True)
        return r.stdout != b"PK\x03\x04"

    def fetch(name):
        """True if downloaded now, False if already here, None if the server
        refuses this one file while serving the others."""
        dest = os.path.join(folder, name)
        if os.path.exists(dest) and complete(dest):
            return False
        alone = 0
        for wait in (*TIGER_BACKOFF_S, None):
            r = subprocess.run(["curl", "-sfL", "--retry", "5", "--retry-delay", "5", "-A",
                                TIGER_USER_AGENT, "-o", dest + ".part", TIGER_URL + name],
                               capture_output=True, text=True)
            time.sleep(TIGER_PAUSE_S)
            if r.returncode == 0 and complete(dest + ".part"):
                os.replace(dest + ".part", dest)
                return True
            refused = rejected(dest + ".part")
            why = ("the server refused it (\"Request Rejected\": too many requests)" if refused
                   else f"curl exit {r.returncode} {r.stderr.strip()}" if r.returncode
                   else "not a zip with a shapefile")
            # The server has refused a single file for hours while serving
            # every other one (2026-11-12, ADR-0041): after two tries that
            # file is left out rather than holding up the rest.
            if refused and not refusing_all():
                alone += 1
                if alone == 2:
                    os.remove(dest + ".part")
                    return None
            if wait is None:
                raise RuntimeError(f"{TIGER_URL}{name}: {why}")
            say(f"  {name}: {why}; trying again in {wait} s")
            time.sleep(wait)

    say(f"US Census address ranges: {len(wanted)} county files for {len(states)} state(s)"
        f" into {os.path.relpath(folder, ROOT)}")
    fetched, left_out = 0, []
    try:
        with concurrent.futures.ThreadPoolExecutor(TIGER_JOBS) as pool:
            for i, (name, got) in enumerate(zip(wanted, pool.map(fetch, wanted)), 1):
                if got is None:
                    left_out.append(name)
                else:
                    fetched += got
                if i % 250 == 0 or i == len(wanted):
                    say(f"  {i} of {len(wanted)} ({fetched} downloaded now)")
    except RuntimeError as e:
        die(f"{e}. The files downloaded so far are kept: run the same command again later"
            " to carry on, or add --no-tiger to build without the address ranges")
    for name in left_out:
        say(f"warning: left out {name}: the server refuses that file while serving the others;"
            " its county has no address ranges. Run the same command again later to fetch it")
    return [os.path.join(folder, n) for n in wanted if n not in left_out]


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
    ap.add_argument("--no-tiger", action="store_true",
                    help="leave out the US Census address ranges")
    ap.add_argument("--tiger-states", metavar="KS,NE",
                    help="the states whose Census address ranges to add (postal or FIPS"
                         " codes); default: the US regions' states")
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
    tiger = [] if a.no_tiger else tiger_states(a.region, a.tiger_states)
    if tiger:
        folder = os.path.join(ROOT, f"build/search/tiger/TIGER{TIGER_YEAR}/ADDRFEAT")
        files = tiger_download(tiger, folder)
        lst = os.path.join(os.path.dirname(os.path.abspath(a.out)), "tiger-files.txt")
        with open(lst, "w") as f:
            f.write("\n".join(files) + "\n")
        cmd += ["--tiger-list", lst]
        if a.bbox:
            cmd += [f"--tiger-bbox={a.bbox}"]
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
    say(f"{a.out}: {os.path.getsize(a.out) / 1e6:.0f} MB (© OpenStreetMap contributors, ODbL"
        + (f"; address ranges: US Census Bureau TIGER/Line {TIGER_YEAR})" if tiger else ")"))
    if a.dev_copy:
        os.makedirs(os.path.dirname(a.dev_copy), exist_ok=True)
        tmp = a.dev_copy + ".part"
        shutil.copyfile(a.out, tmp)
        os.replace(tmp, a.dev_copy)
        say(f"Copied to {a.dev_copy} for make navigation / make sim")


if __name__ == "__main__":
    main()
