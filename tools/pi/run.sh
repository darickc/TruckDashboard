#!/usr/bin/env bash
# `make pi-run`: start the vehicle gateway, the recorder and the dashboard on
# the Pi (Raspberry Pi OS, Phase 3.5). Closing the app or Ctrl-C stops all three.
#
#   make pi-run                                   # simulator (bench: display, touch, full stack)
#   make pi-run TRANSPORT=obdlink                 # MX+, PASSIVE_ONLY: the adapter is never opened
#   make pi-run TRANSPORT=obdlink TRANSMIT=1      # MX+, read-only polling (ADR-0007 opt-in)
#   make pi-run ... UI=0                          # gateway + recorder only, e.g. over SSH
#
# Each run gets its own directory under $DATA_DIR (default ~/f250-data) with
# the recorder database, the adapter traffic log and every process's log.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

TRANSPORT="${TRANSPORT:-sim}"
ADAPTER="${ADAPTER:-rfcomm:00:04:3E:85:EA:FC}"
TRANSMIT="${TRANSMIT:-0}"
ENABLE="${ENABLE:-}"
BUDGET_RPS="${BUDGET_RPS:-}"
SCENARIO="${SCENARIO:-drive_cycle}"
START="${START:-0}"
UI="${UI:-1}"
DATA_DIR="${DATA_DIR:-$HOME/f250-data}"
# The app is built against this endpoint (make pi-build), so it is fixed here.
SOCK=/tmp/f250/vehicle.sock

GW_BIN=target/release/vehicle-gateway
REC_BIN=target/release/recorder
APP_BIN="$(ls apps/infotainment/build/linux/*/release/bundle/f250_infotainment 2>/dev/null | head -1 || true)"
for bin in "$GW_BIN" "$REC_BIN"; do
  [[ -x "$bin" ]] || { echo "$bin not found: run 'make pi-build' first"; exit 1; }
done
[[ "$UI" != 1 || -x "$APP_BIN" ]] || { echo "app bundle not found: run 'make pi-build' first"; exit 1; }
# The gateway replaces a stale socket, which would cut off one still running.
if pgrep -x vehicle-gateway >/dev/null; then
  echo "A vehicle-gateway is already running (pid $(pgrep -x vehicle-gateway | tr '\n' ' ')). Stop it first."
  exit 1
fi

gw_args=(--listen "unix:$SOCK" --transport "$TRANSPORT")
case "$TRANSPORT" in
  sim)
    gw_args+=(--scenario "$SCENARIO" --sim-start-s "$START") ;;
  obdlink)
    gw_args+=(--adapter "$ADAPTER")
    if [[ "$TRANSMIT" == 1 ]]; then
      gw_args+=(--transmit)
    else
      echo "PASSIVE_ONLY: the adapter will not be opened and nothing reaches the vehicle."
      echo "To poll (read-only services only), opt in with TRANSMIT=1 (ADR-0007)."
    fi ;;
  *)
    echo "TRANSPORT must be sim or obdlink, got '$TRANSPORT'"; exit 1 ;;
esac
[[ -n "$ENABLE" ]] && gw_args+=(--enable "$ENABLE")
[[ -n "$BUDGET_RPS" ]] && gw_args+=(--budget-rps "$BUDGET_RPS")

# The app needs the desktop session on the Pi's screen. Over SSH this shell has
# none, so look for the logged-in user's Wayland or X11 session.
if [[ "$UI" == 1 && -z "${WAYLAND_DISPLAY:-}${DISPLAY:-}" ]]; then
  export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
  if [[ -S "$XDG_RUNTIME_DIR/wayland-0" ]]; then
    export WAYLAND_DISPLAY=wayland-0
  elif [[ -S /tmp/.X11-unix/X0 ]]; then
    export DISPLAY=:0
  else
    echo "No desktop session found. Log in on the Pi's screen, or run headless with UI=0."
    exit 1
  fi
fi

SESSION="$DATA_DIR/$(date +%Y%m%d-%H%M%S)-$TRANSPORT"
mkdir -p "$SESSION"
[[ "$TRANSPORT" == obdlink ]] && gw_args+=(--traffic-log "$SESSION/traffic")
{
  echo "started:   $(date -Iseconds)"
  echo "commit:    $(git rev-parse --short HEAD)$(git diff --quiet || echo ' (uncommitted changes)')"
  echo "host:      $(hostname) $(uname -srm)"
  echo "transport: $TRANSPORT"
  echo "transmit:  $([[ "$TRANSPORT" == obdlink && "$TRANSMIT" == 1 ]] && echo enabled || echo off)"
  echo "gateway:   $GW_BIN ${gw_args[*]}"
} >"$SESSION/session.txt"

PIDS=()
cleanup() {
  # Stop the recorder before the gateway so it records the shutdown cleanly.
  for ((i=${#PIDS[@]}-1; i>=0; i--)); do kill "${PIDS[i]}" 2>/dev/null || true; done
  wait 2>/dev/null || true
  echo "stopped:   $(date -Iseconds)" >>"$SESSION/session.txt"
  echo "Session saved in $SESSION"
}
trap cleanup EXIT
trap 'exit 130' INT TERM

"$GW_BIN" "${gw_args[@]}" >"$SESSION/gateway.log" 2>&1 &
PIDS+=($!)
for _ in $(seq 50); do
  [[ -S "$SOCK" ]] && break
  kill -0 "${PIDS[0]}" 2>/dev/null || { echo "gateway exited:"; tail -20 "$SESSION/gateway.log"; exit 1; }
  sleep 0.2
done
[[ -S "$SOCK" ]] || { echo "gateway did not open $SOCK within 10 s"; exit 1; }

"$REC_BIN" run --gateway "unix:$SOCK" --db "$SESSION/telemetry.sqlite" >"$SESSION/recorder.log" 2>&1 &
PIDS+=($!)

echo "Recording to $SESSION"
if [[ "$UI" == 1 ]]; then
  F250_FULLSCREEN="${F250_FULLSCREEN:-1}" "$APP_BIN" 2>&1 | tee "$SESSION/app.log"
else
  echo "Headless (UI=0). Ctrl-C to stop."
  wait "${PIDS[0]}"
fi
