#!/bin/bash
# Collect what's needed to tell why the 7" DSI display, its touch or its
# backlight isn't working (Phase 5.2). Runs on the Pi, on AGL or Raspberry Pi
# OS, so the two can be compared (docs/setup/agl.md, "Display fallback").
# Changes nothing. Run as root for the full kernel log.
#
#   diagnose-display.sh            # writes /var/tmp/f250-display-<host>-<time>.tar.gz
#   OUT=/some/dir diagnose-display.sh
#
# Collects: OS and boot config, DRM connectors and modes, the display and
# touch kernel messages and modules, the I2C devices on the display buses
# (i2c-4 and i2c-6 on the Pi 5; the touch controller appears as a separate
# bus, 10-0038 on Raspberry Pi OS), input devices, backlight sysfs, and the
# compositor's and dashboard's logs.
#
# Status: [SIM]. Not run on the Pi yet.
set -uo pipefail

OUT="${OUT:-/var/tmp}"
NAME="f250-display-$(hostname)-$(date +%Y%m%d-%H%M%S)"
DIR="$OUT/$NAME"
mkdir -p "$DIR"

# run <file> <command...>: the command and its output (or why it failed).
run() {
  local file="$1"; shift
  { echo "\$ $*"; "$@" 2>&1 || echo "(exit $?)"; echo; } >>"$DIR/$file"
}
have() { command -v "$1" >/dev/null 2>&1; }
# dump <file> <paths...>: each readable file's name and contents.
dump() {
  local file="$1" p; shift
  for p in "$@"; do
    [[ -r "$p" && -f "$p" ]] || continue
    printf '%s: %s\n' "$p" "$(tr '\0\n' ' ' <"$p" 2>/dev/null)" >>"$DIR/$file"
  done
}

echo "Collecting into $DIR"

# --- system and boot configuration
run system.txt cat /etc/os-release
run system.txt uname -a
run system.txt cat /proc/cmdline
run system.txt uptime
for c in /boot/config.txt /boot/firmware/config.txt; do
  [[ -f "$c" ]] && run boot-config.txt cat "$c"
done
have findmnt && for m in $(findmnt -rn -t vfat -o TARGET); do
  [[ -f "$m/config.txt" ]] && run boot-config.txt grep -nE '^[^#]*(dtoverlay|dtparam|display|lcd|hdmi|ignore_lcd)' "$m/config.txt"
done
have vcgencmd && run system.txt vcgencmd get_throttled

# --- DRM: connectors, status and modes
for c in /sys/class/drm/card*-*; do
  [[ -d "$c" ]] || continue
  {
    echo "== $(basename "$c")"
    for f in status enabled dpms modes; do
      [[ -r "$c/$f" ]] && printf '  %-8s %s\n' "$f" "$(tr '\n' ' ' <"$c/$f")"
    done
  } >>"$DIR/drm-connectors.txt"
done
[[ -f "$DIR/drm-connectors.txt" ]] || echo "no DRM connectors in /sys/class/drm" >"$DIR/drm-connectors.txt"
run drm-connectors.txt ls -l /dev/dri
have modetest && run drm-modetest.txt modetest -c
have kmsprint && run drm-modetest.txt kmsprint

# --- kernel: display, touch, backlight
if dmesg >/dev/null 2>&1; then
  dmesg >"$DIR/dmesg-full.txt" 2>&1
  grep -iE 'drm|dsi|vc4|rp1|panel|tc358762|ft5|edt|touch|backlight|regulator|attiny|i2c|hdmi' \
    "$DIR/dmesg-full.txt" >"$DIR/dmesg-display.txt"
else
  echo "dmesg not readable: run as root" >"$DIR/dmesg-display.txt"
fi
run modules.txt sh -c "lsmod | grep -iE 'drm|vc4|rp1|panel|tc358762|edt|ft5|backlight|attiny|regulator|i2c' || true"

# --- I2C on the display ports: which devices exist and which driver has them
for b in /sys/bus/i2c/devices/i2c-*; do
  [[ -d "$b" ]] || continue
  dump i2c.txt "$b/name"
done
for d in /sys/bus/i2c/devices/[0-9]*-*; do
  [[ -d "$d" ]] || continue
  printf '%s name=%s driver=%s\n' "$(basename "$d")" "$(cat "$d/name" 2>/dev/null)" \
    "$(basename "$(readlink "$d/driver" 2>/dev/null)" 2>/dev/null)" >>"$DIR/i2c.txt"
done
if have i2cdetect; then
  # -r: read-byte probes only, the safer mode. Addresses a driver owns show UU.
  for bus in 4 6; do
    [[ -e "/dev/i2c-$bus" ]] && run i2c.txt i2cdetect -y -r "$bus"
  done
fi

# --- touch and other input devices
run input.txt cat /proc/bus/input/devices
run input.txt ls -l /dev/input/by-path /dev/input/by-id
have libinput && run input.txt libinput list-devices

# --- backlight
for b in /sys/class/backlight/*; do
  [[ -d "$b" ]] || continue
  echo "== $(basename "$b") -> $(readlink -f "$b")" >>"$DIR/backlight.txt"
  dump backlight.txt "$b/brightness" "$b/actual_brightness" "$b/max_brightness" "$b/bl_power" "$b/type"
done
[[ -f "$DIR/backlight.txt" ]] || echo "no /sys/class/backlight devices" >"$DIR/backlight.txt"

# --- compositor and dashboard logs (this boot)
if have journalctl; then
  for u in agl-compositor flutter-ics-homescreen f250-dashboard; do
    run "journal-$u.txt" journalctl -b --no-pager -u "$u"
  done
  run journal-f250-dashboard.txt journalctl -b --no-pager -t f250-dashboard
fi
for f in /run/platform/display/compositor.log /var/log/weston.log; do
  [[ -f "$f" ]] && cp "$f" "$DIR/"
done

tar -czf "$OUT/$NAME.tar.gz" -C "$OUT" "$NAME" && rm -rf "$DIR"
echo "$OUT/$NAME.tar.gz"
