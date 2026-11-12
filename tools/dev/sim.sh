#!/usr/bin/env bash
# `make sim`: start the vehicle gateway with the simulated transport and
# navigation with a simulated receiver, then run the macOS app against them
# over gRPC. Stopping the app stops both.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
GATEWAY="${1:-tcp:127.0.0.1:50251}" SCENARIO="${2:-drive_cycle}" START="${3:-0}"
NAV="${4:-tcp:127.0.0.1:50253}"

cargo build -q -p vehicle-gateway -p navigation
./target/debug/vehicle-gateway --listen "$GATEWAY" --scenario "$SCENARIO" --sim-start-s "$START" &
GW=$!
# shellcheck disable=SC2086  # NAV_ROUTING is a list of arguments from the Makefile
./target/debug/navigation --listen "$NAV" --simulate ${NAV_ROUTING:-} &
NV=$!
trap 'kill $GW $NV 2>/dev/null || true' EXIT
sleep 1
kill -0 "$GW" 2>/dev/null || { echo "gateway failed to start"; exit 1; }
kill -0 "$NV" 2>/dev/null || { echo "navigation failed to start"; exit 1; }
make --no-print-directory ui SOURCE=gateway GATEWAY="$GATEWAY" NAV="$NAV"
