#!/usr/bin/env bash
# `make agl-image`: download the pinned AGL Pi 5 Flutter image
# (agl/configurations/vimba.env) into build/agl/, check its SHA-256, and
# decompress it to a .wic ready to flash. Runs on the Mac or any Linux host.
# It does not flash anything: writing a disk is a manual step
# (docs/setup/agl.md, "Flash").
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
# shellcheck source=../configurations/vimba.env
. agl/configurations/vimba.env

DIR=build/agl
ZST="$DIR/$AGL_IMAGE"
WIC="${ZST%.zst}"
mkdir -p "$DIR"

sha256() { if command -v sha256sum >/dev/null; then sha256sum "$1"; else shasum -a 256 "$1"; fi | cut -d' ' -f1; }

if [[ -f "$ZST" && "$(sha256 "$ZST")" == "$AGL_IMAGE_SHA256" ]]; then
  echo "Have $ZST (SHA-256 matches)"
else
  echo "Downloading AGL $AGL_RELEASE ($((AGL_IMAGE_BYTES / 1000000)) MB) from download.automotivelinux.org"
  curl -fL --retry 3 -C - -o "$ZST" "$AGL_IMAGE_URL"
  got="$(sha256 "$ZST")"
  if [[ "$got" != "$AGL_IMAGE_SHA256" ]]; then
    echo "SHA-256 mismatch: got $got, expected $AGL_IMAGE_SHA256. Deleting the download." >&2
    rm -f "$ZST"; exit 1
  fi
  echo "SHA-256 OK"
fi

command -v zstd >/dev/null || { echo "zstd not found: brew install zstd (or apt install zstd)" >&2; exit 1; }
if [[ ! -f "$WIC" || "$ZST" -nt "$WIC" ]]; then
  zstd -d -f -q "$ZST" -o "$WIC"
fi
echo "Ready to flash: $WIC ($(du -h "$WIC" | cut -f1))"
echo "Next: docs/setup/agl.md, \"Flash\""
