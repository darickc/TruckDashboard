#!/usr/bin/env bash
# Bring the direct-CAN interface up or down, and capture the bus (ADR-0012).
# Run it on the Pi. Changing the interface needs sudo; status and capture don't.
#
#   tools/pi/can.sh status            # adapter, driver, mode, bitrate, error counters
#   tools/pi/can.sh listen            # 500 kbit/s, LISTEN-ONLY: the adapter never drives the bus
#   tools/pi/can.sh active            # 500 kbit/s, normal mode: needed for TRANSPORT=can TRANSMIT=1
#   tools/pi/can.sh down
#   tools/pi/can.sh capture [SECONDS] # candump of every frame and error frame, with counters
#   tools/pi/can.sh flash             # put Candlelight 2.5 (gs_usb) firmware on the adapter
#
# Options: CAN_IF (default can0), BITRATE (default 500000, the truck's HS-CAN:
# ATDPN 6, VERIFICATION_LOG 2026-08-09), DATA_DIR (default ~/f250-data),
# BOARD (flash only: multiboard, the default, or jhoinrch).
#
# Listen-only is the default and the first step on the truck (ADR-0007): in
# that mode the controller sends no ACKs and no error frames, so a wrong
# bitrate or a wiring mistake can't disturb the bus. `active` is a separate,
# explicit step, and the gateway's --transmit is a second, independent one.
#
# Written for the Jhoinrch RH-02 Pro (a CANable 2.0 design). With candleLight
# firmware it is a gs_usb device and appears as can0 by itself. Ours came with
# the CANable 2.0 slcan firmware (normaldotcom canable2-fw b158aa7), which
# appears as a serial port and can't do listen-only: its `O` (open) resets the
# mode that `M1` (silent) set, and it has no `L`, the command the kernel's
# slcan driver sends for listen-only (source read 2026-11-05,
# docs/hardware/bench-log.md). This script detects it and stops; `flash`
# replaces it.
#
# Status: `status` run against the adapter [BENCH 2026-11-05]; the rest [SIM].
set -euo pipefail

CAN_IF="${CAN_IF:-can0}"
BITRATE="${BITRATE:-500000}"
DATA_DIR="${DATA_DIR:-$HOME/f250-data}"
BOARD="${BOARD:-multiboard}"

# Candlelight 2.5 (Elmue/CANable-2.5-firmware-Slcan-and-Candlelight, MIT),
# pinned to one commit and checked by SHA-256 (taken 2026-11-05). It
# enumerates as 1d50:606f, which mainline gs_usb binds, and maps gs_usb's
# listen-only flag to the FDCAN's bus-monitoring mode (no ACKs).
#   multiboard: internal RC oscillator, like the factory firmware. Runs on any
#               STM32G431 CANable 2.0. The default.
#   jhoinrch:   for RH-02 boards with a 25 MHz crystal (fitted "since 2026",
#               per the firmware's manual). Only if you can see the crystal.
FW_COMMIT=12aa9fa1210757923507f6d390f7f909049f4e84
FW_URL="https://raw.githubusercontent.com/Elmue/CANable-2.5-firmware-Slcan-and-Candlelight/$FW_COMMIT/Binary%20Files"

say()  { printf '\033[1m==> %s\033[0m\n' "$*"; }
warn() { printf '\033[33mWARN: %s\033[0m\n' "$*"; }
die()  { printf '\033[31m%s\033[0m\n' "$*"; exit 1; }

[[ "$(uname -s)" == Linux ]] || die "can.sh runs on the Pi (Linux)"

details() { ip -details -statistics link show "$CAN_IF"; }

# The STM32's ROM bootloader (Boot switch down).
in_dfu() { lsusb -d 0483:df11 >/dev/null 2>&1; }

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
    die "That firmware can't do listen-only. Flash Candlelight first: tools/pi/can.sh flash (docs/setup/can.md)."
  fi
  in_dfu && die "The adapter is in DFU mode (Boot switch down). Switch it up and replug it."
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
      if [[ -n "$ports" ]]; then
        echo "slcan-looking serial ports:"; echo "$ports" | sed 's/^/  /'
        echo "  -> slcan firmware: no listen-only. Run 'tools/pi/can.sh flash'."
      fi
      in_dfu && echo "The adapter is in DFU mode (Boot switch down): ready for 'tools/pi/can.sh flash'."
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
  flash)
    case "$BOARD" in
      multiboard) fw="Candlelight2.5 - Multiboard - STM32G431.dfu"
                  sum=19eb458d2c495d67e71e86ac598665308a11a271c3c11cd349045eb9b4c9055d ;;
      jhoinrch)   fw="Candlelight2.5 - Jhoinrch - STM32G431.dfu"
                  sum=693626c442a1125ff21fb33e299a2491df58616c73e021d382a55bb008177bac ;;
      *) die "BOARD must be multiboard or jhoinrch, got '$BOARD'" ;;
    esac
    command -v dfu-util >/dev/null || die "dfu-util not found: run 'make pi-setup' (or: sudo apt install dfu-util)"
    file="$DATA_DIR/firmware/${fw// /_}"
    mkdir -p "$DATA_DIR/firmware"
    if [[ ! -f "$file" ]]; then
      say "Downloading $fw (commit ${FW_COMMIT:0:7})"
      curl -fsSL -o "$file.part" "$FW_URL/${fw// /%20}"
      mv "$file.part" "$file"
    fi
    echo "$sum  $file" | sha256sum -c --quiet - || { rm -f "$file"; die "Checksum mismatch: deleted $file. Not flashed."; }
    echo "Firmware: $file (SHA-256 OK)"
    if ! in_dfu; then
      echo "The adapter is not in DFU mode. Unplug it, set the Boot switch DOWN, plug it back"
      echo "in, then run this again. (lsusb should list 0483:df11 STMicroelectronics ... DFU.)"
      exit 1
    fi
    say "Flashing Candlelight 2.5 ($BOARD) into the adapter over DFU"
    echo "This replaces the adapter's firmware. The STM32's ROM bootloader stays, so the"
    echo "Boot switch can always bring it back to DFU to be flashed again."
    if [[ "${YES:-0}" != 1 ]]; then
      read -r -p "Type 'flash' to continue: " answer
      [[ "$answer" == flash ]] || die "Not flashed."
    fi
    sudo dfu-util -w -c 1 -i 0 -a 0 -D "$file"
    echo
    echo "Done. Unplug the adapter, set the Boot switch UP, plug it back in, then:"
    echo "  tools/pi/can.sh status      # expect: $CAN_IF: driver gs_usb"
    ;;
  *)
    sed -n '2,14p' "$0"; exit 1 ;;
esac
