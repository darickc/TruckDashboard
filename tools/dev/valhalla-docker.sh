#!/bin/sh
# valhalla_service for development on the Mac (ADR-0035): takes the same
# arguments (CONFIG ACTION REQUEST) and runs them in Valhalla's pinned Docker
# image, which has no network. services/navigation runs it once per route
# (`make navigation`, `make sim`). The Pi runs valhalla_service itself.
#
# The config and the routing data must be under /tmp/f250, which is mounted
# read-only at the same path, so the paths in the config stay valid.
set -eu
IMAGE="${VALHALLA_IMAGE:-ghcr.io/valhalla/valhalla:3.9.1@sha256:4fd114eb1d26b8fc2f43bcb3df234c1b63a0bf13c277405e5943d5361dc575de}"
command -v docker >/dev/null || { echo "docker not found: install Docker Desktop" >&2; exit 127; }
# /tmp is a symlink to /private/tmp on macOS; Docker needs the real path.
data=$(cd /tmp/f250 && pwd -P)
exec docker run --rm --network none -v "$data:/tmp/f250:ro" "$IMAGE" valhalla_service "$@"
