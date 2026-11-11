#!/bin/bash
# Stage 1 of the AGL bring-up (ADR-0005): turn the prebuilt Vimba Pi 5 Flutter
# image into the head unit, without a custom image build. Runs on the Pi, as
# root. `make deploy PI=<host>` copies everything and runs it; it can also be
# run by hand.
#
#   stage1-setup.sh                 # apply (idempotent), then say what changed
#   stage1-setup.sh --check         # report only; changes nothing
#   stage1-setup.sh --restore-demo  # back to the AGL demo homescreen (fallback)
#
# What "apply" does, in order:
#   1. CAN safety first (ADR-0015): mask the demo's KUKSA CAN provider and its
#      vcan helper, install the networkd override that leaves can* unmanaged,
#      and take can0 down if it is up in normal mode.
#   2. Append agl/boot/config-f250.txt to the boot partition's config.txt
#      (between markers; the original is kept as config.txt.agl-orig).
#   3. The f250 system user; agl-driver joins its group for the gateway socket.
#   4. Install agl/rootfs/ (units, logind drop-in, /etc/default/f250, helpers).
#      /etc/default/f250 is installed only if missing: it holds your settings.
#      Turn on the persistent journal (/var/lib/journal, at most 50 MB).
#   5. The data drive (DATA_DRIVE in /etc/default/f250): with 1, an /etc/fstab
#      entry mounts the ext4 drive labelled f250-data (f250-storage formats
#      it) at /var/lib/f250/storage, with nofail; with 0, the entry is removed.
#   6. Link the dashboard bundle to the image's Flutter engine, after checking
#      the engine version matches the one the bundle was built with.
#   7. Disable the demo homescreen; enable the gateway, recorder, power manager
#      and dashboard.
#      The homescreen app is swapped with the compositor restarted: a second
#      homescreen client makes agl-compositor 0.0.24 abort.
#   8. Bluetooth (ADR-0023): step 4's connman drop-in leaves Bluetooth to
#      BlueZ from connman's next start. Unblock the controller now, while
#      the old connman still runs: systemd-rfkill saves that state, so the
#      block connman left doesn't come back at the next boot.
#
# A reboot applies config.txt, the logind change and the connman drop-in.
# connman isn't restarted here: it may carry this SSH session's Wi-Fi.
#
# Testing: ROOT=<dir> runs against a directory tree, and F250_SYS_LOG=<file>
# records system commands (systemctl, ip, useradd, ...) instead of running
# them (tools/dev/test-agl.sh).
#
# Status: [SIM] (tools/dev/test-agl.sh), and run on AGL 22.0.1 by `make
# deploy` [BENCH] (bench-log 2026-11-06).
set -euo pipefail

MODE=apply
case "${1:-}" in
  "") ;;
  --check) MODE=check ;;
  --restore-demo) MODE=restore ;;
  -h|--help) sed -n '2,36p' "$0"; exit 0 ;;
  *) echo "usage: $0 [--check|--restore-demo]" >&2; exit 2 ;;
esac

ROOT="${ROOT:-}"
HERE="$(cd "$(dirname "$0")/.." && pwd)"   # the agl/ directory
APP_ID=f250_infotainment
CAN_IF="${CAN_IF:-can0}"
DEMO_HOMESCREEN=flutter-ics-homescreen.service
CAN_UNITS=(kuksa-can-provider.service can-dev-helper.service)
F250_UNITS=(f250-gateway.service f250-recorder.service f250-power-manager.service f250-camera-manager.service f250-dashboard.service f250-can-auto.service)
COMPOSITOR=agl-compositor.service
COMPOSITOR_DROPIN=etc/systemd/system/agl-compositor.service.d/50-f250.conf
CONNMAN_DROPIN=etc/systemd/system/connman.service.d/50-f250.conf
RFKILL=/sys/class/rfkill
JOURNAL_DIR=/var/lib/journal
JOURNAL_MOUNT=var-volatile-log-journal.mount
JOURNAL_WHERE=/var/volatile/log/journal
BEGIN='# >>> f250'
STORAGE=/var/lib/f250/storage
DRIVE_LABEL=f250-data
FSTAB_MARK='# f250 data drive: managed by stage1-setup.sh (DATA_DRIVE in /etc/default/f250)'
# nofail: boot and the gateway go on without the drive; the device wait is 10 s.
FSTAB_LINE="LABEL=$DRIVE_LABEL $STORAGE ext4 noatime,nofail,x-systemd.device-timeout=10s 0 2"
END='# <<< f250'

if [[ -t 1 ]]; then B=$'\033[1m'; R=$'\033[31m'; Y=$'\033[33m'; G=$'\033[32m'; N=$'\033[0m'; else B='' R='' Y='' G='' N=''; fi
say()  { printf '%s==> %s%s\n' "$B" "$*" "$N"; }
ok()   { printf '  %sok%s    %s\n' "$G" "$N" "$*"; }
warn() { printf '  %sWARN%s  %s\n' "$Y" "$N" "$*"; WARNINGS=$((WARNINGS + 1)); }
bad()  { printf '  %sFAIL%s  %s\n' "$R" "$N" "$*"; FAILURES=$((FAILURES + 1)); }
die()  { printf '%s%s%s\n' "$R" "$*" "$N" >&2; exit 1; }
WARNINGS=0
FAILURES=0

# System commands: run them, or only record them under test.
sys() {
  if [[ -n "${F250_SYS_LOG:-}" ]]; then
    echo "$*" >>"$F250_SYS_LOG"
    return 0
  fi
  "$@"
}

# Queries that must not run under test answer from files in the test tree.
unit_state() {   # enabled/disabled/masked/... for a unit, or "absent"
  if [[ -n "${F250_SYS_LOG:-}" ]]; then
    cat "$ROOT/.test/unit-$1" 2>/dev/null || echo absent
  else
    local s
    s="$(systemctl is-enabled "$1" 2>/dev/null | head -1)" || true
    case "$s" in
      ""|not-found) echo absent ;;
      *) echo "$s" ;;
    esac
  fi
}
can_details() {  # `ip -details link show $CAN_IF`, or nothing if absent
  if [[ -n "${F250_SYS_LOG:-}" ]]; then
    cat "$ROOT/.test/ip-$CAN_IF" 2>/dev/null || true
  else
    ip -details link show "$CAN_IF" 2>/dev/null || true
  fi
}

storage_mounted() {
  if [[ -n "${F250_SYS_LOG:-}" ]]; then [[ -e "$ROOT/.test/mounted-storage" ]]; return; fi
  mountpoint -q "$STORAGE"
}
drive_present() {  # a filesystem labelled f250-data is attached
  if [[ -n "${F250_SYS_LOG:-}" ]]; then [[ -e "$ROOT/.test/label-$DRIVE_LABEL" ]]; return; fi
  blkid -L "$DRIVE_LABEL" >/dev/null 2>&1
}

can_up() {       # the interface flags (<...,UP,...>) of `ip link` output on stdin include UP
  sed -n 's/^[0-9]*: [^<]*<\([^>]*\)>.*/\1/p' | head -1 | tr ',' '\n' | grep -qx UP
}

journal_mounted() {  # the persistent journal is in place (test: $ROOT/.test/mounted-journal)
  if [[ -n "${F250_SYS_LOG:-}" ]]; then [[ -e "$ROOT/.test/mounted-journal" ]]; else mountpoint -q "$JOURNAL_WHERE"; fi
}

boot_config() {
  local c
  if [[ -n "${BOOT_CONFIG:-}" ]]; then echo "$ROOT$BOOT_CONFIG"; return; fi
  for c in /boot/config.txt /boot/firmware/config.txt; do
    [[ -f "$ROOT$c" ]] && { echo "$ROOT$c"; return; }
  done
  # Any mounted FAT partition holding a config.txt (the image's boot partition).
  if [[ -z "$ROOT" ]] && command -v findmnt >/dev/null; then
    for c in $(findmnt -rn -t vfat -o TARGET); do
      [[ -f "$c/config.txt" ]] && { echo "$c/config.txt"; return; }
    done
  fi
  return 1
}

setting() {      # a value from /etc/default/f250
  sed -n "s/^$1=//p" "$ROOT/etc/default/f250" 2>/dev/null | tail -1
}
fstab_has_entry() {
  awk -v mp="$STORAGE" '$1 !~ /^#/ && $2 == mp { found = 1 } END { exit !found }' "$ROOT/etc/fstab" 2>/dev/null
}

bt_rfkill() {     # the rfkill switches of type bluetooth, one sysfs directory per line
  local d
  for d in "$ROOT$RFKILL"/rfkill*; do
    [[ -f "$d/type" && "$(cat "$d/type")" == bluetooth ]] && echo "$d"
  done
  return 0
}
connmand_cmdline() {  # the running connmand's command line, or nothing (test: $ROOT/.test/connmand-cmdline)
  if [[ -n "${F250_SYS_LOG:-}" ]]; then
    cat "$ROOT/.test/connmand-cmdline" 2>/dev/null || true
    return 0
  fi
  local pid
  pid="$(systemctl show -p MainPID --value connman.service 2>/dev/null)" || true
  [[ -n "$pid" && "$pid" != 0 && -r "/proc/$pid/cmdline" ]] && tr '\0' ' ' <"/proc/$pid/cmdline"
  return 0
}
bt_powered() {   # yes/no from BlueZ, or nothing if it doesn't answer (test: $ROOT/.test/bt-powered)
  if [[ -n "${F250_SYS_LOG:-}" ]]; then
    cat "$ROOT/.test/bt-powered" 2>/dev/null || true
    return 0
  fi
  command -v bluetoothctl >/dev/null || return 0
  timeout 5 bluetoothctl show 2>/dev/null | sed -n 's/^[[:space:]]*Powered: //p' | head -1
  return 0
}
flutter_version() {
  sed -n 's/^FLUTTER_VERSION=//p' "$ROOT/etc/default/flutter" 2>/dev/null | head -1
}

# ---------------------------------------------------------------- check ----

check() {
  local cfg ver bundle d u rf cmdline
  say "Vehicle bus safety (ADR-0015)"
  for u in "${CAN_UNITS[@]}"; do
    case "$(unit_state "$u")" in
      masked*|absent) ok "$u is masked or absent" ;;
      *) bad "$u is not masked: it opens $CAN_IF (run this script without --check)" ;;
    esac
  done
  if cmp -s "$HERE/rootfs/etc/systemd/network/60-canbus-can.network" \
            "$ROOT/etc/systemd/network/60-canbus-can.network"; then
    ok "networkd leaves can* unmanaged (/etc/systemd/network/60-canbus-can.network)"
  else
    bad "the image's networkd config would bring $CAN_IF up in normal mode at 500k"
  fi
  d="$(can_details)"
  if [[ -z "$d" ]]; then
    ok "$CAN_IF absent (adapter unplugged)"
  elif grep -q 'vcan' <<<"$d"; then
    bad "$CAN_IF is a virtual CAN device (can-dev-helper); the adapter would appear under another name"
  elif ! can_up <<<"$d"; then
    ok "$CAN_IF is down"
  elif grep -q LISTEN-ONLY <<<"$d"; then
    ok "$CAN_IF is up, LISTEN-ONLY"
  else
    warn "$CAN_IF is up in NORMAL mode: it ACKs on the bus. Fine only after 'f250-can active' on purpose"
  fi

  say "Boot configuration"
  if cfg="$(boot_config)"; then
    if cmp -s <(sed -n "/^$BEGIN/,/^$END/p" "$cfg") "$HERE/boot/config-f250.txt"; then
      ok "config.txt has the current f250 block ($cfg)"
    elif grep -q "^$BEGIN" "$cfg"; then
      warn "config.txt has an older f250 block: run this script to update it"
    else
      bad "config.txt has no f250 block: the 7\" display stays off"
    fi
  else
    bad "config.txt not found (/boot, /boot/firmware or a mounted FAT partition)"
  fi
  if cmp -s "$HERE/rootfs/etc/systemd/logind.conf.d/50-f250-power-key.conf" \
            "$ROOT/etc/systemd/logind.conf.d/50-f250-power-key.conf"; then
    ok "logind ignores the power key (after a reboot)"
  else
    warn "logind still handles the power key"
  fi

  say "Journal"
  if cmp -s "$HERE/rootfs/etc/systemd/journald.conf.d/50-f250.conf" "$ROOT/etc/systemd/journald.conf.d/50-f250.conf"; then
    ok "journald keeps the journal (Storage=persistent, 50 MB)"
  else
    bad "journald drop-in missing or old: logs vanish at shutdown (run this script)"
  fi
  case "$(unit_state "$JOURNAL_MOUNT")" in
    enabled) ok "$JOURNAL_MOUNT enabled" ;;
    *) bad "$JOURNAL_MOUNT not enabled: the journal would stay on tmpfs" ;;
  esac
  if journal_mounted; then
    ok "$JOURNAL_DIR mounted at $JOURNAL_WHERE"
  else
    bad "$JOURNAL_WHERE is not mounted: the journal is in RAM (systemctl start $JOURNAL_MOUNT)"
  fi

  say "Data drive"
  if [[ "$(setting DATA_DRIVE)" == 1 ]]; then
    if fstab_has_entry; then ok "/etc/fstab mounts LABEL=$DRIVE_LABEL at $STORAGE"
    else bad "DATA_DRIVE=1 but /etc/fstab has no entry: run this script"; fi
    if drive_present; then ok "a drive labelled $DRIVE_LABEL is attached"
    else bad "no drive labelled $DRIVE_LABEL (f250-storage status; f250-storage format <disk>)"; fi
    if storage_mounted; then
      ok "mounted at $STORAGE"
      if [[ -z "$(find "$ROOT$STORAGE" -maxdepth 0 -user f250 2>/dev/null)" ]]; then
        warn "$STORAGE is not owned by f250: run this script"
      fi
    else
      bad "nothing mounted at $STORAGE: the recorder won't run"
    fi
  else
    ok "DATA_DRIVE is off: telemetry is on the SD card"
    if fstab_has_entry; then warn "/etc/fstab still mounts the data drive: run this script to remove it"; fi
  fi

  say "Services"
  ver="$(flutter_version)"
  bundle="$ROOT/usr/share/flutter/$APP_ID/$ver/release"
  if [[ -z "$ver" ]]; then
    bad "/etc/default/flutter has no FLUTTER_VERSION: is this the AGL Flutter image?"
  elif [[ -f "$bundle/lib/libapp.so" && -d "$bundle/data/flutter_assets" ]]; then
    ok "dashboard bundle for Flutter $ver installed"
  else
    bad "no dashboard bundle in $bundle (make deploy)"
  fi
  for d in vehicle-gateway recorder obd-console power-manager camera-manager camera-ctl f250-can f250-storage; do
    [[ -x "$ROOT/opt/f250/bin/$d" ]] && ok "/opt/f250/bin/$d" || bad "/opt/f250/bin/$d missing (make deploy)"
  done
  if [[ -d "$ROOT/opt/f250/share/data/signals" && -f "$ROOT/opt/f250/share/data/warning_rules.json" ]]; then
    ok "gateway data in /opt/f250/share/data"
  else
    bad "/opt/f250/share/data incomplete: the gateway can't load its registry (make deploy)"
  fi
  for u in "${F250_UNITS[@]}"; do
    case "$(unit_state "$u")" in
      enabled) ok "$u enabled" ;;
      *) bad "$u not enabled" ;;
    esac
  done
  case "$(unit_state "$DEMO_HOMESCREEN")" in
    enabled) warn "$DEMO_HOMESCREEN is still enabled: two homescreens would compete" ;;
    absent) ok "$DEMO_HOMESCREEN not installed" ;;
    *) ok "$DEMO_HOMESCREEN disabled" ;;
  esac
  if cmp -s "$HERE/rootfs/$COMPOSITOR_DROPIN" "$ROOT/$COMPOSITOR_DROPIN"; then
    ok "the compositor restarts after a crash (/$COMPOSITOR_DROPIN)"
  else
    bad "/$COMPOSITOR_DROPIN missing or old: a compositor crash leaves the panel on the text console"
  fi

  say "Bluetooth (ADR-0023; the MX+ over RFCOMM)"
  if cmp -s "$HERE/rootfs/$CONNMAN_DROPIN" "$ROOT/$CONNMAN_DROPIN"; then
    ok "connman leaves Bluetooth to BlueZ (/$CONNMAN_DROPIN)"
  else
    bad "/$CONNMAN_DROPIN missing or old: connman keeps the controller rfkill-blocked (run this script)"
  fi
  cmdline="$(connmand_cmdline)"
  if [[ -n "$cmdline" && "$cmdline" != *--noplugin=bluetooth* ]]; then
    warn "connman still runs with its Bluetooth plugin: reboot to apply the drop-in"
  fi
  rf="$(bt_rfkill)"
  if [[ -z "$rf" ]]; then
    warn "no Bluetooth controller (no rfkill switch of type bluetooth): the obdlink transport can't reach the MX+"
  else
    while IFS= read -r d; do
      if [[ "$(cat "$d/hard" 2>/dev/null)" == 1 ]]; then
        bad "Bluetooth ${d##*/} is hard-blocked"
      elif [[ "$(cat "$d/soft" 2>/dev/null)" == 1 ]]; then
        bad "Bluetooth ${d##*/} is soft-blocked (run this script)"
      else
        ok "Bluetooth ${d##*/} is not blocked"
      fi
    done <<<"$rf"
    case "$(bt_powered)" in
      yes) ok "BlueZ: controller powered" ;;
      no) warn "BlueZ: controller not powered (bluetoothctl power on; journalctl -u bluetooth)" ;;
      *) warn "BlueZ didn't answer (systemctl status bluetooth)" ;;
    esac
  fi

  if [[ -z "$ROOT" ]]; then
    if systemctl is-active -q "$COMPOSITOR"; then
      ok "$COMPOSITOR running"
    else
      bad "$COMPOSITOR not running: the panel shows the text console (systemctl restart $COMPOSITOR)"
    fi
  fi

  echo
  if ((FAILURES)); then
    printf '%s%d failed, %d warnings%s\n' "$R" "$FAILURES" "$WARNINGS" "$N"; return 1
  fi
  printf '%sall checks passed%s (%d warnings)\n' "$G" "$N" "$WARNINGS"
}

# ---------------------------------------------------------------- apply ----

install_file() {  # install_file <src> <dest> <mode>: say whether it changed
  local src="$1" dest="$2" mode="$3"
  if cmp -s "$src" "$dest"; then return 1; fi
  mkdir -p "$(dirname "$dest")"
  cp "$src" "$dest.f250-new"
  chmod "$mode" "$dest.f250-new"
  mv "$dest.f250-new" "$dest"
  echo "  installed ${dest#"$ROOT"}"
}

apply() {
  local u d cfg ver bundle engine f rel mode new rf
  [[ -n "$ROOT" || "$(id -u)" == 0 ]] || die "Run as root (on AGL, ssh root@<pi>)"
  [[ -n "$ROOT" || -f /etc/default/flutter ]] || die "/etc/default/flutter missing: this is not the AGL Flutter image"

  say "1. Vehicle bus safety (ADR-0015)"
  for u in "${CAN_UNITS[@]}"; do
    if [[ "$(unit_state "$u")" != masked* ]]; then
      sys systemctl mask --now "$u"
      echo "  masked $u"
    fi
  done
  if install_file "$HERE/rootfs/etc/systemd/network/60-canbus-can.network" \
                  "$ROOT/etc/systemd/network/60-canbus-can.network" 0644; then
    sys networkctl reload
  fi
  d="$(can_details)"
  if grep -q 'vcan' <<<"$d"; then
    sys ip link delete "$CAN_IF"
    echo "  removed the virtual $CAN_IF that can-dev-helper made; replug the adapter"
  elif [[ -n "$d" ]] && can_up <<<"$d" && ! grep -q LISTEN-ONLY <<<"$d"; then
    sys ip link set "$CAN_IF" down
    echo "  took $CAN_IF down: it was up in normal mode (use 'f250-can listen' or 'active')"
  fi

  say "2. Boot configuration"
  cfg="$(boot_config)" || die "config.txt not found. Mount the boot partition, or set BOOT_CONFIG=/path/config.txt"
  [[ -f "$cfg.agl-orig" ]] || cp "$cfg" "$cfg.agl-orig"
  new="$(mktemp)"
  # The image's lines without our block or trailing blank lines, one blank
  # line, then our block: the same result however often this runs.
  sed "/^$BEGIN/,/^$END/d" "$cfg" \
    | awk '{ line[NR] = $0 } END { n = NR; while (n > 0 && line[n] == "") n--; for (i = 1; i <= n; i++) print line[i] }' >"$new"
  echo >>"$new"
  cat "$HERE/boot/config-f250.txt" >>"$new"
  if cmp -s "$new" "$cfg"; then
    rm -f "$new"
  else
    cat "$new" >"$cfg"; rm -f "$new"
    echo "  updated ${cfg#"$ROOT"} (original: config.txt.agl-orig). Reboot to apply"
  fi

  say "3. f250 user"
  if ! grep -q '^f250:' "$ROOT/etc/group" 2>/dev/null; then
    sys groupadd --system f250; echo "  added group f250"
  fi
  if ! grep -q '^f250:' "$ROOT/etc/passwd" 2>/dev/null; then
    sys useradd --system -g f250 -d /var/lib/f250 -s /bin/false -c "F-250 head unit services" f250
    echo "  added user f250"
  fi
  if ! grep -q '^f250:.*agl-driver' "$ROOT/etc/group" 2>/dev/null; then
    sys usermod -aG f250 agl-driver; echo "  agl-driver joined group f250 (the gateway socket)"
  fi

  say "4. Files"
  while IFS= read -r f; do
    rel="${f#"$HERE/rootfs/"}"
    case "$rel" in
      etc/default/f250) [[ -f "$ROOT/etc/default/f250" ]] && continue ;;
    esac
    mode=0644
    [[ "$rel" == opt/f250/libexec/* ]] && mode=0755
    install_file "$f" "$ROOT/$rel" "$mode" || true
  done < <(find "$HERE/rootfs" -type f | sort)
  sys systemctl daemon-reload

  # Persistent journal: /var/log is tmpfs, so the journal lives in
  # $JOURNAL_DIR, bind-mounted at its place ($JOURNAL_MOUNT).
  if [[ ! -d "$ROOT$JOURNAL_DIR" ]]; then
    mkdir -p "$ROOT$JOURNAL_DIR"; chmod 2755 "$ROOT$JOURNAL_DIR"
    sys chgrp systemd-journal "$JOURNAL_DIR"
    echo "  created $JOURNAL_DIR"
  fi
  if [[ "$(unit_state "$JOURNAL_MOUNT")" != enabled ]]; then
    sys systemctl enable "$JOURNAL_MOUNT"; echo "  enabled $JOURNAL_MOUNT"
  fi
  if ! journal_mounted; then
    sys systemctl start "$JOURNAL_MOUNT"
    sys systemctl restart systemd-journald.service
    sys journalctl --flush
    echo "  journal now kept on the SD card ($JOURNAL_DIR)"
  fi

  say "5. Data drive"
  local fstab="$ROOT/etc/fstab" on changed=0
  on="$(setting DATA_DRIVE)"
  new="$(mktemp)"
  if [[ -f "$fstab" ]]; then
    awk -v m="$FSTAB_MARK" -v mp="$STORAGE" '$0 != m && !($1 !~ /^#/ && $2 == mp)' "$fstab" >"$new"
  fi
  [[ "$on" == 1 ]] && printf '%s\n%s\n' "$FSTAB_MARK" "$FSTAB_LINE" >>"$new"
  if [[ ! -f "$fstab" && "$on" != 1 ]] || cmp -s "$new" "$fstab"; then
    rm -f "$new"
  else
    cat "$new" >"$fstab"; rm -f "$new"; changed=1
    sys systemctl daemon-reload   # the fstab generator makes var-lib-f250-storage.mount
  fi
  if [[ "$on" == 1 ]]; then
    ((changed)) && echo "  /etc/fstab: LABEL=$DRIVE_LABEL on $STORAGE"
    if ! storage_mounted; then
      mkdir -p "$ROOT$STORAGE"; chmod 0755 "$ROOT$STORAGE"   # the empty mount point: root's
      if drive_present; then
        sys systemctl start var-lib-f250-storage.mount || warn "the data drive didn't mount (journalctl -u var-lib-f250-storage.mount)"
      else
        warn "no drive labelled $DRIVE_LABEL: format one with 'f250-storage format <disk>'. Until then the recorder won't run"
      fi
    fi
    if storage_mounted; then
      sys chown f250:f250 "$STORAGE"
      sys chmod 0750 "$STORAGE"
      # camera-manager's recordings (ADR-0027): it runs as agl-driver.
      # Group f250 can read them; only camera-manager writes.
      sys install -d -o agl-driver -g f250 -m 0750 "$STORAGE/video"
    fi
  else
    ((changed)) && echo "  /etc/fstab: removed the data drive (DATA_DRIVE is off)"
    if storage_mounted; then echo "  $STORAGE stays mounted until a reboot"; fi
  fi

  say "6. Dashboard bundle"
  ver="$(flutter_version)"
  [[ -n "$ver" ]] || die "/etc/default/flutter has no FLUTTER_VERSION"
  bundle="$ROOT/usr/share/flutter/$APP_ID/$ver/release"
  engine="$ROOT/usr/share/flutter/$ver/release"
  if [[ ! -f "$bundle/lib/libapp.so" ]]; then
    warn "no bundle in ${bundle#"$ROOT"} (make deploy builds it for Flutter $ver)"
  else
    if [[ -f "$bundle/flutter-version" && "$(cat "$bundle/flutter-version")" != "$ver" ]]; then
      die "the bundle was built with Flutter $(cat "$bundle/flutter-version"), the image's engine is $ver: rebuild with that version"
    fi
    install_file "$HERE/flutter/config.toml" "$bundle/config.toml" 0644 || true
    ln -sfn "/usr/share/flutter/$ver/release/data/icudtl.dat" "$bundle/data/icudtl.dat"
    ln -sfn "/usr/share/flutter/$ver/release/lib/libflutter_engine.so" "$bundle/lib/libflutter_engine.so"
    [[ -n "$ROOT" || -f "$engine/lib/libflutter_engine.so" ]] \
      || warn "the image has no release engine at /usr/share/flutter/$ver/release"
  fi

  say "7. Services"
  if [[ "$(unit_state "$DEMO_HOMESCREEN")" == enabled ]]; then
    sys systemctl disable "$DEMO_HOMESCREEN"; echo "  disabled $DEMO_HOMESCREEN"
  fi
  sys systemctl enable "${F250_UNITS[@]}"
  sys systemctl restart f250-gateway.service f250-recorder.service f250-power-manager.service f250-camera-manager.service
  # agl-compositor 0.0.24 takes one homescreen client per run: a second one
  # (a restarted dashboard, or ours after the demo's) makes it abort. Stop
  # the clients (the compositor survives that), then restart it, and the
  # dashboard starts with it.
  if [[ "$(unit_state "$DEMO_HOMESCREEN")" != absent ]]; then sys systemctl stop "$DEMO_HOMESCREEN"; fi
  sys systemctl stop f250-dashboard.service
  sys systemctl reset-failed "$COMPOSITOR" || true
  sys systemctl restart "$COMPOSITOR"
  sys systemctl start f250-dashboard.service

  say "8. Bluetooth (ADR-0023)"
  # The drop-in (step 4) takes effect when connman next starts. Until then
  # the old connman doesn't block the controller again: it only re-blocks
  # when it first sees a switch (technology.c, __connman_technology_add_rfkill).
  rf="$(bt_rfkill)"
  if [[ -z "$rf" ]]; then
    warn "no Bluetooth controller found: nothing to unblock"
  else
    while IFS= read -r d; do
      if [[ "$(cat "$d/soft" 2>/dev/null)" == 1 ]]; then
        echo 0 >"$d/soft"
        echo "  unblocked Bluetooth ${d##*/} (systemd-rfkill keeps it unblocked)"
      fi
    done <<<"$rf"
  fi
  echo
  echo "Done. Reboot if config.txt, logind or the connman drop-in changed, then: $0 --check"
}

restore() {
  [[ -n "$ROOT" || "$(id -u)" == 0 ]] || die "Run as root"
  say "Back to the AGL demo homescreen"
  sys systemctl disable f250-dashboard.service
  sys systemctl enable "$DEMO_HOMESCREEN"
  # One homescreen client per compositor run (see apply, step 7).
  sys systemctl stop f250-dashboard.service
  sys systemctl reset-failed "$COMPOSITOR" || true
  sys systemctl restart "$COMPOSITOR"
  sys systemctl start "$DEMO_HOMESCREEN"
  echo "  The gateway and recorder keep running; the CAN safety settings stay."
  echo "  To undo the boot changes: cp config.txt.agl-orig config.txt on the boot partition."
}

case "$MODE" in
  apply) apply ;;
  check) check ;;
  restore) restore ;;
esac
