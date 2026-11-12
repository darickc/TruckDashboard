#!/bin/sh
# Remakes fixture.osm.pbf from fixture.osm (brew install osmium-tool). The
# replication timestamp in the header is what Geofabrik's extracts carry.
set -eu
cd "$(dirname "$0")"
osmium cat fixture.osm -o fixture.osm.pbf --overwrite \
  --output-header=osmosis_replication_timestamp=2026-11-11T00:00:00Z
