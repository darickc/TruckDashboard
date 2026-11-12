#!/bin/sh
# A fake valhalla_service for tests/routing_end_to_end.rs: the same arguments
# (CONFIG ACTION REQUEST). It answers with the file the test put in
# answer.json, two folders up from the config, and exits with exit-code.
# Committed rather than written by the test: on Linux, running a script just
# written while other tests fork can fail with "Text file busy".
set -eu
[ "$2" = route ] || { echo "bad action $2" >&2; exit 2; }
grep -q '"tile_extract"' "$1" || { echo "no tile_extract in $1" >&2; exit 2; }
dir=$(dirname "$(dirname "$1")")
printf '%s\n' "$3" > "$dir/last-request.json"
cat "$dir/answer.json"
exit "$(cat "$dir/exit-code")"
