#!/usr/bin/env bash
# `make pi-run`: start the vehicle gateway, the recorder and the dashboard on
# the Pi (Raspberry Pi OS, Phase 3.5). Closing the app or Ctrl-C stops all three.
#
#   make pi-run                                   # simulator (bench: display, touch, full stack)
#   make pi-run TRANSPORT=obdlink                 # MX+, PASSIVE_ONLY: the adapter is never opened
#   make pi-run TRANSPORT=obdlink TRANSMIT=1      # MX+, read-only polling (ADR-0007 opt-in)
#   make pi-run TRANSPORT=can                     # direct CAN (can0), PASSIVE_ONLY: never opened
#   make pi-run TRANSPORT=can TRANSMIT=1          # direct CAN polling; can0 must be up in active
#                                                 # mode first (tools/pi/can.sh active, ADR-0012)
#   make pi-run TRANSPORT=obdlink TRANSMIT=1 CAPTURE=1
#                                                 # also candump can0 into the session (candump/):
#                                                 # the MX+'s requests and answers next to the
#                                                 # broadcasts, for can-monitor correlate. can0
#                                                 # must be up first (tools/pi/can.sh listen)
#   make pi-run ... UI=0                          # gateway + recorder only, no app
#   make pi-run ... UI=headless                   # app under cage on a virtual display (no screen needed)
#
# Each run gets its own directory under $DATA_DIR (default ~/f250-data) with
# the recorder database, the adapter traffic log and every process's log.
#
# In the kiosk (cage on the Pi's screen) the dashboard's Settings screen has
# Power and Restart. The app then exits with POWER_OFF_EXIT or RESTART_EXIT;
# this script stops the recorder and the gateway as usual, then powers the Pi
# off or reboots it. They are offered only when logind says
# this session may power off without a password (CanPowerOff = yes: polkit's
# default for the active session on a seat, i.e. the user at the screen).
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

TRANSPORT="${TRANSPORT:-sim}"
ADAPTER="${ADAPTER:-rfcomm:00:04:3E:85:EA:FC}"
CAN_IF="${CAN_IF:-can0}"
TRANSMIT="${TRANSMIT:-0}"
CAPTURE="${CAPTURE:-0}"
ENABLE="${ENABLE:-}"
BUDGET_RPS="${BUDGET_RPS:-}"
PINNED="${PINNED:-}"   # can: physical (default) | functional; see /etc/default/f250 on AGL
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
# apps/infotainment/lib/core/power.dart: powerOffExitCode, restartExitCode.
POWER_OFF_EXIT=42
RESTART_EXIT=43
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
  can)
    gw_args+=(--can-if "$CAN_IF")
    [[ -n "$PINNED" ]] && gw_args+=(--can-pinned "$PINNED")
    if [[ "$TRANSMIT" == 1 ]]; then
      gw_args+=(--transmit)
      # The gateway can't change the interface mode (that needs root), so say
      # now if its polls can't reach the bus, rather than after 5 s of silence.
      if [[ ! -e "/sys/class/net/$CAN_IF" ]]; then
        echo "$CAN_IF does not exist: plug in the CAN adapter and run 'tools/pi/can.sh active'"; exit 1
      fi
      if ip -details link show "$CAN_IF" | grep -q LISTEN-ONLY; then
        echo "$CAN_IF is in listen-only mode: polls would never reach the bus."
        echo "Switch it with 'tools/pi/can.sh active' (ADR-0012), or drop TRANSMIT=1."; exit 1
      fi
    else
      echo "PASSIVE_ONLY: $CAN_IF will not be opened and nothing reaches the vehicle."
      echo "To poll (read-only services only), opt in with TRANSMIT=1 (ADR-0007)."
    fi ;;
  *)
    echo "TRANSPORT must be sim, obdlink or can, got '$TRANSPORT'"; exit 1 ;;
esac
case "$CAPTURE" in
  0) ;;
  1)
    # Bringing the interface up needs root, and pi-start can't ask for a
    # password, so it must already be up: listen-only for a capture beside the
    # MX+, or active for TRANSPORT=can TRANSMIT=1.
    if [[ ! -e "/sys/class/net/$CAN_IF" ]]; then
      echo "CAPTURE=1: $CAN_IF does not exist. Plug in the CAN adapter, then: tools/pi/can.sh listen"; exit 1
    fi
    if [[ "$(cat "/sys/class/net/$CAN_IF/operstate")" == down ]]; then
      echo "CAPTURE=1: $CAN_IF is down. Bring it up first: tools/pi/can.sh listen"; exit 1
    fi ;;
  *)
    echo "CAPTURE must be 0 or 1, got '$CAPTURE'"; exit 1 ;;
esac
[[ -n "$ENABLE" ]] && gw_args+=(--enable "$ENABLE")
[[ -n "$BUDGET_RPS" ]] && gw_args+=(--budget-rps "$BUDGET_RPS")

# Where the app draws:
#   - a desktop session (this shell's, or the one on the Pi's screen): run in it
#   - none (Raspberry Pi OS Lite): fullscreen under the cage kiosk compositor
#   - UI=headless: cage on a virtual display, to test without a screen
APP_CMD=()
KIOSK=0
POWER_OFF=0
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
      else
        # cage needs a login that owns the screen (a seat). An SSH login has
        # none, and cage would only time out after 10 s.
        if [[ -z "$(loginctl show-session "${XDG_SESSION_ID:-}" -p Seat --value 2>/dev/null)" ]]; then
          echo "This login has no seat (SSH?), so cage can't take the Pi's screen."
          echo "Over SSH use 'make pi-start' (same options); or run this on the Pi's console."
          exit 1
        fi
        KIOSK=1
      fi
      unset WAYLAND_DISPLAY DISPLAY
      APP_CMD=(cage -- "$APP_BIN")
    fi ;;
  *)
    echo "UI must be 1, 0 or headless, got '$UI'"; exit 1 ;;
esac

SESSION="$DATA_DIR/$(date +%Y%m%d-%H%M%S)-$TRANSPORT"
mkdir -p "$SESSION"
[[ "$TRANSPORT" == obdlink || "$TRANSPORT" == can ]] && gw_args+=(--traffic-log "$SESSION/traffic")
{
  echo "started:   $(date -Iseconds)"
  echo "commit:    $(git rev-parse --short HEAD)$(git diff --quiet || echo ' (uncommitted changes)')"
  echo "host:      $(hostname) $(uname -srm)"
  echo "transport: $TRANSPORT"
  echo "transmit:  $([[ "$TRANSPORT" != sim && "$TRANSMIT" == 1 ]] && echo enabled || echo off)"
  echo "capture:   $([[ "$CAPTURE" == 1 ]] && echo "$CAN_IF -> $SESSION/candump" || echo off)"
  echo "gateway:   $GW_BIN ${gw_args[*]}"
  if [[ "$TRANSPORT" == can ]]; then
    echo "interface:"
    ip -details -statistics link show "$CAN_IF" 2>&1 | sed 's/^/  /'
  fi
} >"$SESSION/session.txt"

# A pi-start session is active only once its VT is in front, so wait for that
# (cage waits too) before asking logind.
can_power_off() {
  if [[ -n "${XDG_SESSION_ID:-}" ]]; then
    for _ in $(seq 20); do
      [[ "$(loginctl show-session "$XDG_SESSION_ID" -p Active --value 2>/dev/null)" == yes ]] && break
      sleep 0.5
    done
  fi
  [[ "$(busctl call org.freedesktop.login1 /org/freedesktop/login1 \
        org.freedesktop.login1.Manager CanPowerOff 2>/dev/null)" == 's "yes"' ]]
}

PIDS=()
CAP_PID=
cleanup() {
  # Stop the recorder before the gateway so it records the shutdown cleanly.
  for ((i=${#PIDS[@]}-1; i>=0; i--)); do kill "${PIDS[i]}" 2>/dev/null || true; done
  # The capture stops last, so it holds the gateway's final requests.
  if [[ -n "$CAP_PID" ]]; then
    wait "${PIDS[@]}" 2>/dev/null || true
    kill "$CAP_PID" 2>/dev/null || true
  fi
  wait 2>/dev/null || true
  if [[ "$TRANSPORT" == can ]]; then
    { echo "interface at stop:"; ip -details -statistics link show "$CAN_IF" 2>&1 | sed 's/^/  /'; } \
      >>"$SESSION/session.txt"
  fi
  echo "stopped:   $(date -Iseconds)" >>"$SESSION/session.txt"
  echo "Session saved in $SESSION"
}
trap cleanup EXIT
trap 'exit 130' INT TERM

if [[ "$CAPTURE" == 1 ]]; then
  # Before the gateway, so its first requests are in the capture.
  CAN_IF="$CAN_IF" CAPTURE_DIR="$SESSION/candump" tools/pi/can.sh capture >"$SESSION/capture.log" 2>&1 &
  CAP_PID=$!
fi

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
  if [[ "$KIOSK" == 1 ]]; then
    if can_power_off; then
      POWER_OFF=1
    else
      echo "No Power button: logind does not let this session power off without a password."
    fi
  fi
  echo "app:       ${APP_CMD[*]}" >>"$SESSION/session.txt"
  echo "power btn: $([[ "$POWER_OFF" == 1 ]] && echo offered || echo not offered)" >>"$SESSION/session.txt"
  # In the background, because bash runs the TERM trap only after a
  # foreground command returns; `wait` returns as soon as a signal arrives.
  F250_FULLSCREEN="${F250_FULLSCREEN:-1}" F250_POWER_OFF="$POWER_OFF" \
    "${APP_CMD[@]}" > >(tee "$SESSION/app.log") 2>&1 &
  APP_PID=$!
  PIDS+=("$APP_PID")
  app_status=0
  wait "$APP_PID" || app_status=$?
  # cage returns its client's exit status (cage.c, return_app_code, v0.3.1).
  if [[ "$POWER_OFF" == 1 && "$app_status" == "$POWER_OFF_EXIT" ]]; then
    echo "power off: requested from the dashboard" | tee -a "$SESSION/session.txt"
    trap - EXIT
    cleanup
    sync
    exec systemctl poweroff
  fi
  if [[ "$POWER_OFF" == 1 && "$app_status" == "$RESTART_EXIT" ]]; then
    echo "restart: requested from the dashboard" | tee -a "$SESSION/session.txt"
    trap - EXIT
    cleanup
    sync
    exec systemctl reboot
  fi
  exit "$app_status"
else
  echo "Headless (UI=0). Ctrl-C to stop."
  wait "${PIDS[0]}"
fi
