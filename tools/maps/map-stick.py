#!/usr/bin/env python3
"""Writes a map onto a USB stick for the truck (ADR-0033).

  map-stick.py --map build/maps/region.pmtiles --stick /Volumes/MAPS

The stick gets f250/map.pmtiles and f250/map.pmtiles.sha256 (the SHA-256 of
the map, computed while copying). In the truck, the Pi copies the map onto its
data drive, checks it against the checksum, and swaps it in
(agl/rootfs/opt/f250/libexec/map-import).

The stick must be exFAT for a map over 4 GB (FAT32's file limit): erase it as
ExFAT in Disk Utility. Refuses a file that isn't a PMTiles v3 map of vector,
PNG, JPEG or WebP tiles, a stick without room, and (unless --any-dir, for
tests) a folder that isn't a mounted volume.

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


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--map", required=True, help="the PMTiles map (make map-region writes one)")
    ap.add_argument("--stick", required=True, help="the stick's mount point, e.g. /Volumes/MAPS")
    ap.add_argument("--any-dir", action="store_true",
                    help="allow any folder, not only a mounted volume (tests)")
    a = ap.parse_args()

    if not os.path.isfile(a.map):
        die(f"{a.map} not found (make map-region writes build/maps/region.pmtiles)")
    problem = header_problem(a.map)
    if problem:
        die(f"{a.map} can't be used: {problem}")
    if not os.path.isdir(a.stick):
        die(f"{a.stick} isn't a folder; plug the stick in (it appears under /Volumes)")
    if not a.any_dir and not os.path.ismount(a.stick):
        die(f"{a.stick} isn't a mounted volume")

    size = os.path.getsize(a.map)
    fs = None if a.any_dir else filesystem(a.stick)
    if fs and fs not in ("exfat", "msdos"):
        die(f"the stick is {fs}; the truck reads exFAT or FAT sticks only. "
            "Erase it as ExFAT in Disk Utility")
    if fs == "msdos" and size > FAT32_LIMIT:
        die(f"the stick is FAT, which can't hold a file over 4 GB, and the map is {human(size)}. "
            "Erase it as ExFAT in Disk Utility")
    dest_dir = os.path.join(a.stick, "f250")
    os.makedirs(dest_dir, exist_ok=True)
    dest = os.path.join(dest_dir, "map.pmtiles")
    part = dest + ".part"
    old = os.path.getsize(dest) if os.path.exists(dest) else 0
    free = shutil.disk_usage(a.stick).free + old
    if free < size:
        die(f"not enough room on the stick: the map is {human(size)}, {human(free)} is free")

    # The checksum file goes only after the map is complete, so a stick
    # pulled early has no checksum and the truck refuses it.
    for stale in (dest + ".sha256", part):
        if os.path.exists(stale):
            os.remove(stale)
    print(f"copying {a.map} ({human(size)}) to {dest}")
    digest, done, start, shown = hashlib.sha256(), 0, time.time(), 0.0
    with open(a.map, "rb") as src, open(part, "wb") as out:
        while True:
            chunk = src.read(CHUNK)
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
        f.write(f"{digest.hexdigest()}  map.pmtiles\n")
        f.flush()
        os.fsync(f.fileno())
    print(f"\r{' ' * 60}\r100%  {human(size)} in {time.time() - start:.0f} s; sha256 {digest.hexdigest()}")
    print(f"Done. Eject the stick, plug it into the truck with the dashboard on, and "
          f"leave it in until the Nav screen says the map is updated.")


if __name__ == "__main__":
    main()
