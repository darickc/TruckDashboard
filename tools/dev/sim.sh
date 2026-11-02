#!/usr/bin/env bash
# `make sim`: start the vehicle gateway with the simulated transport, then run
# the macOS app against it over gRPC. Stopping the app stops the gateway.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
GATEWAY="${1:-tcp:127.0.0.1:50251}" SCENARIO="${2:-drive_cycle}" START="${3:-0}"

cargo build -q -p vehicle-gateway
./target/debug/vehicle-gateway --listen "$GATEWAY" --scenario "$SCENARIO" --sim-start-s "$START" &
GW=$!
trap 'kill $GW 2>/dev/null || true' EXIT
sleep 1
kill -0 "$GW" 2>/dev/null || { echo "gateway failed to start"; exit 1; }
make --no-print-directory ui SOURCE=gateway GATEWAY="$GATEWAY"
