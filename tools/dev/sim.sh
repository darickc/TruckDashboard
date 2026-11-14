#!/usr/bin/env bash
# `make sim`: start the vehicle gateway with the simulated transport,
# navigation with a simulated receiver and audio-manager with a simulated
# phone, then run the macOS app against them over gRPC. Stopping the app
# stops all three.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
GATEWAY="${1:-tcp:127.0.0.1:50251}" SCENARIO="${2:-drive_cycle}" START="${3:-0}"
NAV="${4:-tcp:127.0.0.1:50253}" AUDIO="${5:-tcp:127.0.0.1:50254}"

cargo build -q -p vehicle-gateway -p navigation -p audio-manager
./target/debug/vehicle-gateway --listen "$GATEWAY" --scenario "$SCENARIO" --sim-start-s "$START" &
GW=$!
# shellcheck disable=SC2086  # NAV_ROUTING is a list of arguments from the Makefile
# Prompts go to audio-manager, which pauses the simulated music (ADR-0040).
./target/debug/navigation --listen "$NAV" --simulate ${NAV_ROUTING:-} --audio-manager "$AUDIO" &
NV=$!
mkdir -p /tmp/f250/audio
# Its voice is silent unless VOICE names a program (VOICE=say); a made-up
# call rings every SIM_CALL seconds if set (ADR-0045).
./target/debug/audio-manager --listen "$AUDIO" --simulate --settings-file /tmp/f250/audio/speakers.json \
  ${VOICE:+--voice-command "$VOICE"} ${SIM_CALL:+--sim-call-every-s "$SIM_CALL"} &
AU=$!
trap 'kill $GW $NV $AU 2>/dev/null || true' EXIT
sleep 1
kill -0 "$GW" 2>/dev/null || { echo "gateway failed to start"; exit 1; }
kill -0 "$NV" 2>/dev/null || { echo "navigation failed to start"; exit 1; }
kill -0 "$AU" 2>/dev/null || { echo "audio-manager failed to start"; exit 1; }
make --no-print-directory ui SOURCE=gateway GATEWAY="$GATEWAY" NAV="$NAV" AUDIO="$AUDIO"
