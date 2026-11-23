#!/usr/bin/env bash
# Records one real Mapbox Directions answer as a test vector for
# services/navigation (ADR-0052), asked exactly as navigation asks
# (mapbox::directions_url): driving-traffic, polyline6, full overview, steps
# and voice instructions. The token comes from MAPBOX_ACCESS_TOKEN and goes
# to curl on its standard input, never its command line; the answer is
# checked not to contain it.
#
#   MAPBOX_ACCESS_TOKEN=pk.… tools/dev/mapbox-record.sh [FROM TO [OUT]]
#
# FROM and TO are lon,lat (default: two points near Lebanon, Kansas, the
# simulator's area). OUT defaults to
# services/navigation/tests/data/mapbox-directions-recorded.json. Then add a
# test that parses it (mapbox.rs's tests read the hand-written one).
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
: "${MAPBOX_ACCESS_TOKEN:?set MAPBOX_ACCESS_TOKEN to a Mapbox token}"
FROM="${1:--98.600000,39.800000}"
TO="${2:--98.555900,39.810300}"
OUT="${3:-services/navigation/tests/data/mapbox-directions-recorded.json}"
url="https://api.mapbox.com/directions/v5/mapbox/driving-traffic/${FROM};${TO}?access_token=${MAPBOX_ACCESS_TOKEN}&geometries=polyline6&overview=full&steps=true&voice_instructions=true&voice_units=imperial&language=en&alternatives=false"
tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT
printf 'url = "%s"\nsilent\nshow-error\nfail-with-body\n' "$url" | curl --config - -o "$tmp"
python3 -I - "$tmp" "$MAPBOX_ACCESS_TOKEN" <<'PY'
import json, sys
text = open(sys.argv[1]).read()
if sys.argv[2] in text:
    sys.exit("the answer contains the token: not saved")
code = json.loads(text).get("code")
if code != "Ok":
    sys.exit(f"Mapbox answered {code!r}: not saved")
PY
mv "$tmp" "$OUT"
trap - EXIT
echo "recorded $OUT (a real Mapbox answer, $(date -u +%Y-%m-%d))"
