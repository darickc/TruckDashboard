#!/usr/bin/env bash
# `make pi-run`: start the vehicle gateway, the recorder and the dashboard on
# the Pi (Raspberry Pi OS, Phase 3.5). Closing the app or Ctrl-C stops all three.
#
#   make pi-run                                   # simulator (bench: display, touch, full stack)
#   make pi-run TRANSPORT=obdlink                 # MX+, PASSIVE_ONLY: the adapter is never opened
#   make pi-run TRANSPORT=obdlink TRANSMIT=1      # MX+, read-only polling (ADR-0007 opt-in)
#   make pi-run ... UI=0                          # gateway + recorder only, no app
#   make pi-run ... UI=headless                   # app under cage on a virtual display (no screen needed)
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
[[ "$UI" == 0 || -x "$APP_BIN" ]] || { echo "app bundle not found: run 'make pi-build' first"; exit 1; }
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

# Where the app draws:
#   - a desktop session (this shell's, or the one on the Pi's screen): run in it
#   - none (Raspberry Pi OS Lite): fullscreen under the cage kiosk compositor
#   - UI=headless: cage on a virtual display, to test without a screen
APP_CMD=()
case "$UI" in
  0) ;;
  1|headless)
    export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
    if [[ "$UI" == 1 && -n "${WAYLAND_DISPLAY:-}${DISPLAY:-}" ]]; then
      APP_CMD=("$APP_BIN")
    elif [[ "$UI" == 1 && -S "$XDG_RUNTIME_DIR/wayland-0" ]]; then
      export WAYLAND_DISPLAY=wayland-0
      APP_CMD=("$APP_BIN")
    elif [[ "$UI" == 1 && -S /tmp/.X11-unix/X0 ]]; then
      export DISPLAY=:0
      APP_CMD=("$APP_BIN")
    else
      command -v cage >/dev/null || { echo "No desktop session and no cage kiosk: run 'make pi-setup'"; exit 1; }
      if [[ "$UI" == headless ]]; then
        export WLR_BACKENDS=headless WLR_LIBINPUT_NO_DEVICES=1
      fi
      unset WAYLAND_DISPLAY DISPLAY
      APP_CMD=(cage -- "$APP_BIN")
    fi ;;
  *)
    echo "UI must be 1, 0 or headless, got '$UI'"; exit 1 ;;
esac

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
if [[ ${#APP_CMD[@]} -gt 0 ]]; then
  echo "app:       ${APP_CMD[*]}" >>"$SESSION/session.txt"
  # In the background, because bash runs the TERM trap only after a
  # foreground command returns; `wait` returns as soon as a signal arrives.
  F250_FULLSCREEN="${F250_FULLSCREEN:-1}" "${APP_CMD[@]}" > >(tee "$SESSION/app.log") 2>&1 &
  APP_PID=$!
  PIDS+=("$APP_PID")
  wait "$APP_PID"
else
  echo "Headless (UI=0). Ctrl-C to stop."
  wait "${PIDS[0]}"
fi
