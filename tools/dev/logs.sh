#!/usr/bin/env bash
# `make logs PI=<host>`: run agl/scripts/collect-logs.sh on the AGL Pi and copy
# the archive into build/logs/. The user defaults to root, as for make deploy.
#
# Status: [BENCH] against AGL 22.0.1 (bench-log 2026-11-06).
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

PI="${1:-${PI:-}}"
[[ -n "$PI" ]] || { echo "usage: make logs PI=<host>" >&2; exit 1; }
[[ "$PI" == *@* ]] || PI="root@$PI"

archive="$(ssh "$PI" /opt/f250/share/agl/scripts/collect-logs.sh | tail -1)"
[[ "$archive" == /*.tar.gz ]] || { echo "collect-logs.sh did not report an archive: $archive" >&2; exit 1; }
mkdir -p build/logs
scp -q "$PI:$archive" build/logs/
echo "build/logs/$(basename "$archive")"
