#!/usr/bin/env python3
"""Fail if any relative link in a tracked Markdown file points at a missing path.

Usage: python3 tools/dev/check_links.py   (from the repo root; used by `make lint`)

Checks file targets only. Anchors (#section) and external URLs are ignored, and
`file.cpp:123` line suffixes are stripped before the existence check.
"""
import re
import subprocess
import sys
from pathlib import Path

LINK = re.compile(r"\]\(([^)\s]+)\)")
FENCE = re.compile(r"^\s*```")


def markdown_files(root):
    out = subprocess.run(["git", "ls-files", "-co", "--exclude-standard", "*.md"],
                         cwd=root, capture_output=True, text=True, check=True)
    return [root / p for p in out.stdout.split()]


def main():
    root = Path(subprocess.run(["git", "rev-parse", "--show-toplevel"],
                               capture_output=True, text=True, check=True).stdout.strip())
    broken = []
    for md in markdown_files(root):
        in_fence = False
        for n, line in enumerate(md.read_text(encoding="utf-8").splitlines(), 1):
            if FENCE.match(line):
                in_fence = not in_fence
            if in_fence:
                continue
            for target in LINK.findall(line):
                if re.match(r"^[a-z][a-z0-9+.-]*:", target) or target.startswith("#"):
                    continue
                path = re.sub(r":\d+(-\d+)?$", "", target.split("#", 1)[0])
                if path and not (md.parent / path).exists():
                    broken.append(f"{md.relative_to(root)}:{n}: {target}")
    for b in broken:
        print(b)
    print(f"{len(broken)} broken link(s)")
    return 1 if broken else 0


if __name__ == "__main__":
    sys.exit(main())
