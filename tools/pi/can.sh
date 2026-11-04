#!/usr/bin/env bash
# Bring the direct-CAN interface up or down, and capture the bus (ADR-0012).
# Run it on the Pi. Changing the interface needs sudo; status and capture don't.
#
#   tools/pi/can.sh status            # adapter, driver, mode, bitrate, error counters
#   tools/pi/can.sh listen            # 500 kbit/s, LISTEN-ONLY: the adapter never drives the bus
#   tools/pi/can.sh active            # 500 kbit/s, normal mode: needed for TRANSPORT=can TRANSMIT=1
#   tools/pi/can.sh down
#   tools/pi/can.sh capture [SECONDS] # candump of every frame and error frame, with counters
#
# Options: CAN_IF (default can0), BITRATE (default 500000, the truck's HS-CAN:
# ATDPN 6, VERIFICATION_LOG 2026-08-09), DATA_DIR (default ~/f250-data).
#
# Listen-only is the default and the first step on the truck (ADR-0007): in
# that mode the controller sends no ACKs and no error frames, so a wrong
# bitrate or a wiring mistake can't disturb the bus. `active` is a separate,
# explicit step, and the gateway's --transmit is a second, independent one.
#
# Written for the Jhoinrch RH-02 Pro (a CANable 2.0 design). With candleLight
# firmware it is a gs_usb device and appears as can0 by itself. With the slcan
# firmware it appears as a serial port instead; this script detects that and
# stops, because listen-only over slcan is UNVERIFIED (docs/setup/can.md).
#
# Status: [SIM] only. Not yet run against the adapter (it hasn't arrived).
set -euo pipefail

CAN_IF="${CAN_IF:-can0}"
BITRATE="${BITRATE:-500000}"
DATA_DIR="${DATA_DIR:-$HOME/f250-data}"

say()  { printf '\033[1m==> %s\033[0m\n' "$*"; }
warn() { printf '\033[33mWARN: %s\033[0m\n' "$*"; }
die()  { printf '\033[31m%s\033[0m\n' "$*"; exit 1; }

[[ "$(uname -s)" == Linux ]] || die "can.sh runs on the Pi (Linux)"

details() { ip -details -statistics link show "$CAN_IF"; }

# Serial ports that look like a CANable running slcan firmware.
slcan_ports() {
  ls /dev/serial/by-id/ 2>/dev/null | grep -i -E 'canable|slcan|cantact|usb2can' | sed 's|^|/dev/serial/by-id/|' || true
}

require_interface() {
  if [[ -e "/sys/class/net/$CAN_IF" ]]; then
    return
  fi
  local ports
  ports="$(slcan_ports)"
  if [[ -n "$ports" ]]; then
    echo "No $CAN_IF, but this looks like a CANable with slcan firmware:"
    echo "$ports" | sed 's/^/  /'
    die "Flash candleLight firmware first (docs/setup/can.md): slcan listen-only is unverified."
  fi
  echo "No $CAN_IF and no CANable serial port. USB devices:"
  lsusb 2>/dev/null | sed 's/^/  /' || true
  die "Plug in the CAN adapter (and check the Boot switch is up, not DFU)."
}

driver_of() {
  local d="/sys/class/net/$CAN_IF/device/driver"
  [[ -e "$d" ]] && basename "$(readlink -f "$d")" || echo unknown
}

set_mode() { # listen-only on|off
  require_interface
  local lo="$1"
  sudo ip link set "$CAN_IF" down
  sudo ip link set "$CAN_IF" type can bitrate "$BITRATE" listen-only "$lo"
  sudo ip link set "$CAN_IF" up
  local d
  d="$(details)"
  if [[ "$lo" == on ]] && ! grep -q LISTEN-ONLY <<<"$d"; then
    sudo ip link set "$CAN_IF" down
    die "$CAN_IF came up WITHOUT listen-only; taken down again. The driver or firmware may not support it."
  fi
  if [[ "$lo" == off ]] && grep -q LISTEN-ONLY <<<"$d"; then
    die "$CAN_IF is still listen-only"
  fi
  grep -q "bitrate $BITRATE" <<<"$d" || warn "bitrate is not $BITRATE: $(grep -o 'bitrate [0-9]*' <<<"$d" | head -1)"
  echo "$d"
}

case "${1:-status}" in
  status)
    if [[ -e "/sys/class/net/$CAN_IF" ]]; then
      echo "$CAN_IF: driver $(driver_of), state $(cat "/sys/class/net/$CAN_IF/operstate")"
      details
    else
      echo "No $CAN_IF."
      ports="$(slcan_ports)"
      [[ -n "$ports" ]] && { echo "slcan-looking serial ports:"; echo "$ports" | sed 's/^/  /'; }
      echo "USB devices:"; lsusb 2>/dev/null | sed 's/^/  /' || true
    fi
    ;;
  listen)
    say "$CAN_IF: $BITRATE bit/s, listen-only"
    set_mode on
    ;;
  active)
    say "$CAN_IF: $BITRATE bit/s, NORMAL mode (ACKs frames; the gateway may transmit with --transmit)"
    echo "Only after the listen-only capture looked right and the wiring checklist is signed off"
    echo "(docs/wiring/dlc-can-adapter.md)."
    if [[ "${YES:-0}" != 1 ]]; then
      read -r -p "Type 'active' to continue: " answer
      [[ "$answer" == active ]] || die "Not changed."
    fi
    set_mode off
    ;;
  down)
    require_interface
    sudo ip link set "$CAN_IF" down
    echo "$CAN_IF down"
    ;;
  capture)
    require_interface
    command -v candump >/dev/null || die "candump not found: run 'make pi-setup' (can-utils)"
    [[ "$(cat "/sys/class/net/$CAN_IF/operstate")" == down ]] && die "$CAN_IF is down: run 'tools/pi/can.sh listen' first"
    secs="${2:-0}"
    dir="$DATA_DIR/$(date +%Y%m%d-%H%M%S)-candump"
    mkdir -p "$dir"
    {
      echo "started:   $(date -Iseconds)"
      echo "interface: $CAN_IF, driver $(driver_of)"
      echo "--- before"; details
    } >"$dir/session.txt"
    grep -q LISTEN-ONLY "$dir/session.txt" || warn "$CAN_IF is NOT listen-only (recorded in session.txt)"
    say "Capturing $CAN_IF to $dir $([[ "$secs" -gt 0 ]] && echo "for $secs s" || echo "until Ctrl-C")"
    # 0:0 passes every data frame; #FFFFFFFF passes every error class.
    # candump -l writes candump-<date>.log (timestamps, ID#data) in the cwd.
    finish() {
      { echo "--- after"; details; echo "stopped:   $(date -Iseconds)"; } >>"$dir/session.txt"
      echo "Saved in $dir"
      ls -l "$dir"
    }
    trap finish EXIT
    cd "$dir"
    if [[ "$secs" -gt 0 ]]; then
      timeout --foreground "$secs" candump -l "$CAN_IF,0:0,#FFFFFFFF" || true
    else
      candump -l "$CAN_IF,0:0,#FFFFFFFF" || true
    fi
    ;;
  *)
    sed -n '2,12p' "$0"; exit 1 ;;
esac
