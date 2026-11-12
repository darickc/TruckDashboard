#!/usr/bin/env python3
"""Writes a map, routing data and/or search data onto a USB stick for the
truck (ADR-0033).

  map-stick.py --map build/maps/region.pmtiles --stick /Volumes/MAPS
  map-stick.py --map build/maps/region.pmtiles \
               --routing build/routing/valhalla_tiles.tar \
               --search build/search/search.sqlite --stick /Volumes/MAPS
  map-stick.py --routing build/routing/valhalla_tiles.tar --stick /Volumes/MAPS

The stick gets f250/map.pmtiles, f250/routing.tar and/or f250/search.sqlite,
each with a .sha256 beside it (the SHA-256, computed while copying). In the
truck, the Pi copies each onto its data drive, checks it against the
checksum, and swaps it in (agl/rootfs/opt/f250/libexec/map-import): the map
for the dashboard, the routing data (ADR-0035) and the search data (ADR-0038)
for navigation. A file not given is left on the stick as it is.

The stick must be exFAT for a file over 4 GB (FAT32's file limit): erase it as
ExFAT in Disk Utility. Refuses a map that isn't a PMTiles v3 map of vector,
PNG, JPEG or WebP tiles, routing data that isn't a Valhalla tile extract (a
tar with index.bin first, as `make route-region` writes), search data that
isn't navigation's search index (SQLite with application id "F250", as
`make search-region` writes), a stick without room, and (unless --any-dir, for tests) a folder that isn't a mounted volume.

Python 3 standard library only.
"""
import argparse
import hashlib
import os
import plistlib
import shutil
import subprocess
import sys
import time

CHUNK = 8 * 1024 * 1024
FAT32_LIMIT = 4 * 1024 ** 3 - 1
TILE_TYPES = {1: "vector", 2: "PNG", 3: "JPEG", 4: "WebP"}


def die(msg):
    print(f"map-stick: {msg}", file=sys.stderr)
    sys.exit(1)


def header_problem(path):
    with open(path, "rb") as f:
        h = f.read(127)
    if len(h) < 127 or h[:7] != b"PMTiles":
        return "it isn't a PMTiles file"
    if h[7] != 3:
        return f"it is PMTiles version {h[7]}, not 3"
    if h[99] not in TILE_TYPES:
        return f"its tile type ({h[99]}) isn't vector, PNG, JPEG or WebP"
    return None


def tar_problem(path):
    """As map-import checks it: a ustar file whose first entry is index.bin
    (valhalla_build_extract 3.9.1's layout)."""
    with open(path, "rb") as f:
        h = f.read(512)
    if len(h) < 512 or h[257:262] != b"ustar":
        return "it isn't a tar file"
    if h[:100].rstrip(b"\0") != b"index.bin":
        return "it isn't a Valhalla tile extract (no index.bin first)"
    return None


SQLITE_MAGIC = b"SQLite format 3\0"
SEARCH_APP_ID = b"F250"   # PRAGMA application_id 0x46323530 (crates/geocode)


def search_problem(path):
    """As map-import checks it: a SQLite file whose application id is F250
    (bytes 68-71 of the header)."""
    with open(path, "rb") as f:
        h = f.read(100)
    if len(h) < 100 or h[:16] != SQLITE_MAGIC:
        return "it isn't a SQLite file"
    if h[68:72] != SEARCH_APP_ID:
        return "it isn't navigation's search data (application id isn't F250)"
    return None


# What a stick can carry: (option, name on the stick, check, how to make it).
ITEMS = [
    ("map", "map.pmtiles", header_problem, "make map-region writes build/maps/region.pmtiles"),
    ("routing", "routing.tar", tar_problem, "make route-region writes build/routing/valhalla_tiles.tar"),
    ("search", "search.sqlite", search_problem, "make search-region writes build/search/search.sqlite"),
]
WHAT = {"map.pmtiles": "the map", "routing.tar": "the routing data", "search.sqlite": "the search data"}


def join_and(parts):
    """'a', 'a and b', 'a, b and c'."""
    return parts[0] if len(parts) == 1 else ", ".join(parts[:-1]) + " and " + parts[-1]


def filesystem(stick):
    """The volume's filesystem as macOS names it (e.g. 'exfat', 'msdos'), or None."""
    try:
        out = subprocess.run(["diskutil", "info", "-plist", stick],
                             check=True, capture_output=True).stdout
        info = plistlib.loads(out)
        return (info.get("FilesystemType") or info.get("FilesystemName") or "").lower() or None
    except (OSError, subprocess.CalledProcessError, plistlib.InvalidFileException):
        return None


def human(n):
    for unit in ("B", "kB", "MB", "GB"):
        if n < 1000:
            return f"{n:.0f} {unit}" if unit == "B" else f"{n:.1f} {unit}"
        n /= 1000
    return f"{n:.1f} TB"


def copy(src, dest, size):
    """Copies src to dest through dest.part; returns the SHA-256. The checksum
    file goes only after the copy is complete, so a stick pulled early has no
    checksum and the truck refuses it."""
    part = dest + ".part"
    for stale in (dest + ".sha256", part):
        if os.path.exists(stale):
            os.remove(stale)
    print(f"copying {src} ({human(size)}) to {dest}")
    digest, done, start, shown = hashlib.sha256(), 0, time.time(), 0.0
    with open(src, "rb") as f, open(part, "wb") as out:
        while True:
            chunk = f.read(CHUNK)
            if not chunk:
                break
            digest.update(chunk)
            out.write(chunk)
            done += len(chunk)
            if time.time() - shown > 1:
                shown = time.time()
                rate = done / max(shown - start, 0.001)
                print(f"\r{done * 100 // max(size, 1):3d}%  {human(done)} of {human(size)}, "
                      f"{human(rate)}/s", end="", flush=True)
        out.flush()
        os.fsync(out.fileno())
    os.replace(part, dest)
    with open(dest + ".sha256", "w") as f:
        f.write(f"{digest.hexdigest()}  {os.path.basename(dest)}\n")
        f.flush()
        os.fsync(f.fileno())
    print(f"\r{' ' * 60}\r100%  {human(size)} in {time.time() - start:.0f} s; sha256 {digest.hexdigest()}")
    return digest.hexdigest()


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--map", help="the PMTiles map (make map-region writes one)")
    ap.add_argument("--routing",
                    help="Valhalla routing data (make route-region writes build/routing/valhalla_tiles.tar)")
    ap.add_argument("--search",
                    help="search data (make search-region writes build/search/search.sqlite)")
    ap.add_argument("--stick", required=True, help="the stick's mount point, e.g. /Volumes/MAPS")
    ap.add_argument("--any-dir", action="store_true",
                    help="allow any folder, not only a mounted volume (tests)")
    a = ap.parse_args()

    files = [(name, getattr(a, opt), check, hint)
             for opt, name, check, hint in ITEMS if getattr(a, opt)]
    if not files:
        die("give --map, --routing, --search or several")
    for name, path, check, hint in files:
        if not os.path.isfile(path):
            die(f"{path} not found ({hint})")
        problem = check(path)
        if problem:
            die(f"{path} can't be used: {problem}")
    if not os.path.isdir(a.stick):
        die(f"{a.stick} isn't a folder; plug the stick in (it appears under /Volumes)")
    if not a.any_dir and not os.path.ismount(a.stick):
        die(f"{a.stick} isn't a mounted volume")

    sizes = {name: os.path.getsize(path) for name, path, _, _ in files}
    fs = None if a.any_dir else filesystem(a.stick)
    if fs and fs not in ("exfat", "msdos"):
        die(f"the stick is {fs}; the truck reads exFAT or FAT sticks only. "
            "Erase it as ExFAT in Disk Utility")
    biggest = max(sizes.values())
    if fs == "msdos" and biggest > FAT32_LIMIT:
        die(f"the stick is FAT, which can't hold a file over 4 GB, and one is {human(biggest)}. "
            "Erase it as ExFAT in Disk Utility")
    dest_dir = os.path.join(a.stick, "f250")
    os.makedirs(dest_dir, exist_ok=True)
    old = sum(os.path.getsize(os.path.join(dest_dir, n))
              for n in sizes if os.path.exists(os.path.join(dest_dir, n)))
    free = shutil.disk_usage(a.stick).free + old
    need = sum(sizes.values())
    if free < need:
        die(f"not enough room on the stick: {human(need)} to write, {human(free)} is free")

    for name, path, _, _ in files:
        copy(path, os.path.join(dest_dir, name), sizes[name])
    what = join_and([WHAT[n] for n, _, _, _ in files])
    print(f"Done. Eject the stick, plug it into the truck with the dashboard on, and "
          f"leave it in until the Nav screen says {what} {'is' if len(files) == 1 else 'are'} updated.")


if __name__ == "__main__":
    main()
