#!/usr/bin/env bash
# `make pi-start` / `make pi-stop` / `make pi-status`: run `tools/pi/run.sh`
# (gateway, recorder, fullscreen app) as a transient systemd service on its own
# virtual terminal, so it can be started and stopped over SSH.
#
#   make pi-start                                 # same options as pi-run: TRANSPORT=, TRANSMIT=1, ...
#   make pi-stop                                  # clean stop: app, recorder, then gateway
#   make pi-status                                # state and the last log lines
#
# Why: an SSH login has no seat, so cage started from it can't take the screen
# ("Timeout waiting session to become active", bench-log 2026-11-02). Started
# by systemd with a TTY and a PAM session, run.sh gets a logind session on
# seat0, the way the cage wiki starts cage at boot
# (https://github.com/cage-kiosk/cage/wiki/Starting-Cage-on-boot-with-systemd).
# The unit is transient: nothing is installed, and it is gone after a reboot.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

UNIT=f250-dashboard
# PAMName= moves the processes into the login session's scope, so the journal
# files their output under the session, not the unit: find it by this tag.
LOGS=(journalctl -t "$UNIT")
VT="${VT:-7}"
# The options run.sh reads; the ones set here are passed to the service.
PASS=(TRANSPORT ADAPTER CAN_IF TRANSMIT CAPTURE ENABLE BUDGET_RPS SCENARIO START DATA_DIR F250_FULLSCREEN)

case "${1:-}" in
  start)
    if systemctl is-active --quiet "$UNIT"; then
      echo "$UNIT is already running. Stop it first: make pi-stop"; exit 1
    fi
    sudo systemctl reset-failed "$UNIT" 2>/dev/null || true
    env_args=()
    for v in "${PASS[@]}"; do
      [[ -n "${!v:-}" ]] && env_args+=("--setenv=$v=${!v}")
    done
    # KillMode=mixed: `stop` signals run.sh only, so it stops the app, then the
    # recorder, then the gateway (the order it records cleanly in). run.sh
    # exits 130 on SIGTERM, which is that clean stop, not a failure.
    sudo systemd-run --unit="$UNIT" --description="F-250 dashboard (tools/pi/run.sh)" \
      --uid="$(id -un)" --working-directory="$PWD" "${env_args[@]}" \
      -p PAMName=login -p TTYPath="/dev/tty$VT" -p TTYReset=yes -p TTYVHangup=yes \
      -p TTYVTDisallocate=yes -p StandardInput=tty-fail \
      -p StandardOutput=journal -p StandardError=journal -p SyslogIdentifier="$UNIT" \
      -p UtmpIdentifier="tty$VT" -p UtmpMode=user \
      -p KillMode=mixed -p TimeoutStopSec=15 -p SuccessExitStatus=130 \
      tools/pi/run.sh
    # The session only becomes active, and cage only gets the screen, once its
    # VT is in front.
    sudo chvt "$VT"
    echo "Started on tty$VT. Logs: ${LOGS[*]} -f    Stop: make pi-stop"
    ;;
  stop)
    if ! systemctl is-active --quiet "$UNIT"; then
      echo "$UNIT is not running"; exit 0
    fi
    sudo systemctl stop "$UNIT"
    sudo chvt 1
    "${LOGS[@]}" -n 2 --no-pager -o cat
    ;;
  status)
    systemctl status "$UNIT" --no-pager -n 0 || true
    "${LOGS[@]}" -n 15 --no-pager
    ;;
  *)
    echo "usage: $0 start|stop|status"; exit 2 ;;
esac
