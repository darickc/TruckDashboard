#!/usr/bin/env python3
"""Write the BitBake crate list for the Rust services from Cargo.lock.

BitBake builds offline, so every crate the workspace locks has to be in the
recipe's SRC_URI with its checksum. `bitbake -c update_crates` would write the
same list into the layer, but the layer is read-only inside the build VM, so
it is generated here instead, from the same Cargo.lock:

    tools/dev/gen-crates-inc.py           # rewrite the .inc
    tools/dev/gen-crates-inc.py --check   # exit 1 if it is out of date (make agl-test)

Only crates.io packages are allowed: a git or path dependency outside the
workspace would need its own SRC_URI entry, so it is an error here.
"""

import sys
import tomllib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
LOCK = ROOT / "Cargo.lock"
OUT = ROOT / "agl/meta-f250/recipes-f250/f250-services/f250-services-crates.inc"
CRATES_IO = "registry+https://github.com/rust-lang/crates.io-index"


def render() -> str:
    lock = tomllib.loads(LOCK.read_text())
    crates = []
    for p in lock["package"]:
        src = p.get("source")
        if src is None:
            continue  # a workspace member
        if src != CRATES_IO:
            sys.exit(f"{p['name']} {p['version']}: source {src} is not crates.io; add it to the recipe by hand")
        if "checksum" not in p:
            sys.exit(f"{p['name']} {p['version']}: no checksum in Cargo.lock")
        crates.append((p["name"], p["version"], p["checksum"]))
    crates.sort()
    lines = [
        "# Generated from Cargo.lock by tools/dev/gen-crates-inc.py. Do not edit:",
        "# run that script after changing Cargo.lock (make agl-test checks it).",
        "",
        'SRC_URI += " \\',
    ]
    lines += [f"    crate://crates.io/{n}/{v} \\" for n, v, _ in crates]
    lines += ['"', ""]
    lines += [f'SRC_URI[{n}-{v}.sha256sum] = "{c}"' for n, v, c in crates]
    return "\n".join(lines) + "\n"


def main() -> int:
    text = render()
    if sys.argv[1:] == ["--check"]:
        if not OUT.exists() or OUT.read_text() != text:
            print(f"{OUT.relative_to(ROOT)} is out of date: run tools/dev/gen-crates-inc.py", file=sys.stderr)
            return 1
        return 0
    if sys.argv[1:]:
        print(__doc__, file=sys.stderr)
        return 2
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(text)
    print(f"wrote {OUT.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
