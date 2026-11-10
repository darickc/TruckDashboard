#!/usr/bin/env bash
# `make agl-test`: tests for the AGL Stage 1 scripts (Phase 5), run against a
# directory tree with system commands recorded, not run. Needs no Pi and no
# root; works with macOS's bash 3.2.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

PASS=0
FAIL=0
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT

ok()   { PASS=$((PASS + 1)); }
fail() { FAIL=$((FAIL + 1)); printf '  FAIL %s\n' "$*"; }
check() { if eval "$2"; then ok; else fail "$1"; fi; }   # check <name> <shell test>
has_line() { grep -qxF -- "$2" "$1"; }                     # exact line in file
count() { grep -cF -- "$2" "$1" || true; }
in_order() {   # in_order <file> <line>...: each exact line present, in this order
  local f="$1" prev=0 n; shift
  for l in "$@"; do
    n="$(grep -nxF -- "$l" "$f" | head -1 | cut -d: -f1)"
    [[ -n "$n" && "$n" -gt "$prev" ]] || return 1
    prev="$n"
  done
}

SETUP=agl/scripts/stage1-setup.sh
GW=agl/rootfs/opt/f250/libexec/gateway-start
STOPPED=agl/rootfs/opt/f250/libexec/dashboard-stopped
REC=agl/rootfs/opt/f250/libexec/recorder-start
GROW=agl/rootfs/opt/f250/libexec/grow-root
STORAGE_TOOL=agl/scripts/storage.sh
FSTAB_LINE='LABEL=f250-data /var/lib/f250/storage ext4 noatime,nofail,x-systemd.device-timeout=10s 0 2'

echo "syntax"
for f in agl/scripts/*.sh agl/rootfs/opt/f250/libexec/* agl/rootfs/etc/profile.d/f250.sh tools/dev/deploy.sh tools/dev/logs.sh tools/dev/build-vm.sh tools/pi/*.sh; do
  check "bash -n $f" "bash -n '$f'"
done
for f in agl/scripts/*.sh agl/rootfs/opt/f250/libexec/*; do
  check "$f is executable" "[[ -x '$f' ]]"
done

# A fake AGL root: the image's Flutter env, the end of its config.txt, the
# agl-driver user, a deployed bundle, and the state the queries report.
make_root() {
  local r="$1"
  mkdir -p "$r/etc/default" "$r/boot" "$r/.test" "$r/opt/f250/bin" \
           "$r/usr/share/flutter/f250_infotainment/3.38.3/release/lib" \
           "$r/usr/share/flutter/f250_infotainment/3.38.3/release/data/flutter_assets"
  printf 'FLUTTER_VERSION=3.38.3\nFLUTTER_RUNTIME=release\n' >"$r/etc/default/flutter"
  printf '# Enable VC4 Graphics\ndtoverlay=vc4-kms-v3d-pi5,cma-256\n\n# Seeed CAN FD HATs\n#dtoverlay=seeed-can-fd-hat-v2\n\n' >"$r/boot/config.txt"
  printf 'root:x:0:0:root:/home/root:/bin/sh\nagl-driver:x:1001:1001::/home/agl-driver:/bin/sh\n' >"$r/etc/passwd"
  printf 'root:x:0:\nagl-driver:x:1001:\n' >"$r/etc/group"
  printf '/dev/root            /                    auto       defaults              1  1\nproc                 /proc                proc       defaults              0  0\n' >"$r/etc/fstab"
  echo elf >"$r/usr/share/flutter/f250_infotainment/3.38.3/release/lib/libapp.so"
  echo 3.38.3 >"$r/usr/share/flutter/f250_infotainment/3.38.3/release/flutter-version"
  for u in kuksa-can-provider can-dev-helper flutter-ics-homescreen; do
    echo enabled >"$r/.test/unit-$u.service"
  done
  # can0 up in NORMAL mode, as the image's networkd config would leave it.
  printf '3: can0: <NOARP,UP,LOWER_UP,ECHO> mtu 16 qdisc pfifo_fast state UP mode DEFAULT group default qlen 1000\n    link/can  promiscuity 0\n    can state ERROR-ACTIVE restart-ms 100\n\t  bitrate 500000 sample-point 0.875\n' >"$r/.test/ip-can0"
}
setup() { ROOT="$1" F250_SYS_LOG="$1/.test/sys.log" bash "$SETUP" "${@:2}"; }

echo "stage1-setup: apply"
R="$T/root"
make_root "$R"
cp "$R/boot/config.txt" "$T/config.orig"
setup "$R" >"$T/apply1.out" 2>&1 || { fail "apply exited non-zero"; cat "$T/apply1.out"; }
L="$R/.test/sys.log"
check "masks the KUKSA CAN provider"   "has_line '$L' 'systemctl mask --now kuksa-can-provider.service'"
check "masks the vcan helper"          "has_line '$L' 'systemctl mask --now can-dev-helper.service'"
check "takes can0 down (normal mode)"  "has_line '$L' 'ip link set can0 down'"
check "reloads networkd"               "has_line '$L' 'networkctl reload'"
check "networkd override installed"    "cmp -s agl/rootfs/etc/systemd/network/60-canbus-can.network '$R/etc/systemd/network/60-canbus-can.network'"
check "override leaves can* unmanaged" "grep -qx 'Unmanaged=yes' '$R/etc/systemd/network/60-canbus-can.network'"
check "CAN safety runs first"          "[[ \"\$(head -1 '$L')\" == 'systemctl mask --now kuksa-can-provider.service' ]]"
check "adds group f250"                "has_line '$L' 'groupadd --system f250'"
check "adds user f250"                 "grep -q '^useradd --system -g f250 ' '$L'"
check "agl-driver joins f250"          "has_line '$L' 'usermod -aG f250 agl-driver'"
check "disables the demo homescreen"   "has_line '$L' 'systemctl disable flutter-ics-homescreen.service'"
# agl-compositor aborts on a second homescreen client: stop the clients, then
# restart the compositor, then start the dashboard (bench-log 2026-11-06).
check "stops the demo homescreen"      "has_line '$L' 'systemctl stop flutter-ics-homescreen.service'"
check "swaps clients around a compositor restart" "in_order '$L' 'systemctl stop f250-dashboard.service' 'systemctl restart agl-compositor.service' 'systemctl start f250-dashboard.service'"
check "never restarts the dashboard alone" "! grep -q '^systemctl restart.*f250-dashboard' '$L'"
check "journald drop-in installed"     "cmp -s agl/rootfs/etc/systemd/journald.conf.d/50-f250.conf '$R/etc/systemd/journald.conf.d/50-f250.conf'"
check "journal directory created"      "[[ -d '$R/var/lib/journal' && -g '$R/var/lib/journal' ]]"
check "journal mount enabled, then started" "in_order '$L' 'systemctl enable var-volatile-log-journal.mount' 'systemctl start var-volatile-log-journal.mount' 'systemctl restart systemd-journald.service' 'journalctl --flush'"
check "compositor drop-in installed"   "cmp -s agl/rootfs/etc/systemd/system/agl-compositor.service.d/50-f250.conf '$R/etc/systemd/system/agl-compositor.service.d/50-f250.conf'"
check "enables our services"           "has_line '$L' 'systemctl enable f250-gateway.service f250-recorder.service f250-power-manager.service f250-camera-manager.service f250-dashboard.service'"
check "restarts the power and camera managers" "has_line '$L' 'systemctl restart f250-gateway.service f250-recorder.service f250-power-manager.service f250-camera-manager.service'"
check "config.txt keeps the original"  "cmp -s '$T/config.orig' '$R/boot/config.txt.agl-orig'"
check "config.txt has one f250 block"  "[[ \$(count '$R/boot/config.txt' '# >>> f250') == 1 ]]"
check "config.txt enables the DSI panel" "has_line '$R/boot/config.txt' 'dtoverlay=vc4-kms-dsi-7inch,dsi0'"
check "config.txt keeps the image's lines" "has_line '$R/boot/config.txt' 'dtoverlay=vc4-kms-v3d-pi5,cma-256'"
check "DAC8x overlay stays commented"  "! grep -qx 'dtoverlay=hifiberry-dac8x' '$R/boot/config.txt'"
check "default settings installed"     "cmp -s agl/rootfs/etc/default/f250 '$R/etc/default/f250'"
check "default transport is sim"       "has_line '$R/etc/default/f250' 'TRANSPORT=sim'"
check "default transmit is off"        "has_line '$R/etc/default/f250' 'TRANSMIT=0'"
check "helpers are executable"         "[[ -x '$R/opt/f250/libexec/gateway-start' && -x '$R/opt/f250/libexec/dashboard-stopped' ]]"
check "PCIe line stays commented"      "has_line '$R/boot/config.txt' '#dtparam=pciex1' && ! has_line '$R/boot/config.txt' 'dtparam=pciex1'"
check "DATA_DRIVE off by default"      "has_line '$R/etc/default/f250' 'DATA_DRIVE=0'"
check "fstab untouched when off"       "! grep -q f250 '$R/etc/fstab'"
check "no mount when off"              "! grep -q 'var-lib-f250-storage' '$L'"
check "recorder-start installed"       "[[ -x '$R/opt/f250/libexec/recorder-start' ]]"
check "camera-start installed"         "[[ -x '$R/opt/f250/libexec/camera-start' && -f '$R/etc/systemd/system/f250-camera-manager.service' ]]"
check "camera devices empty by default" "has_line '$R/etc/default/f250' 'CAMERA_LEFT=' && has_line '$R/etc/default/f250' 'CAMERA_RIGHT=' && has_line '$R/etc/default/f250' 'CAMERA_REAR='"
check "grow-root installed, never enabled by Stage 1" "[[ -x '$R/opt/f250/libexec/grow-root' ]] && ! grep -q 'f250-grow-root' '$L'"
check "units installed"                "[[ -f '$R/etc/systemd/system/f250-gateway.service' && -f '$R/etc/systemd/system/f250-dashboard.service' ]]"
check "logind drop-in installed"       "[[ -f '$R/etc/systemd/logind.conf.d/50-f250-power-key.conf' ]]"
B="$R/usr/share/flutter/f250_infotainment/3.38.3/release"
check "bundle config.toml"             "cmp -s agl/flutter/config.toml '$B/config.toml'"
check "bundle links the engine"        "[[ \"\$(readlink '$B/lib/libflutter_engine.so')\" == /usr/share/flutter/3.38.3/release/lib/libflutter_engine.so ]]"
check "bundle links icudtl.dat"        "[[ \"\$(readlink '$B/data/icudtl.dat')\" == /usr/share/flutter/3.38.3/release/data/icudtl.dat ]]"

echo "stage1-setup: apply again (idempotent)"
cp "$R/boot/config.txt" "$T/config.after1"
echo 'TRANSPORT=can' >"$R/etc/default/f250"           # the owner's settings
echo masked >"$R/.test/unit-kuksa-can-provider.service"
echo masked >"$R/.test/unit-can-dev-helper.service"
echo disabled >"$R/.test/unit-flutter-ics-homescreen.service"
rm "$R/.test/ip-can0"
: >"$L"
setup "$R" >"$T/apply2.out" 2>&1 || { fail "second apply exited non-zero"; cat "$T/apply2.out"; }
check "config.txt unchanged"           "cmp -s '$T/config.after1' '$R/boot/config.txt'"
check "original copy unchanged"        "cmp -s '$T/config.orig' '$R/boot/config.txt.agl-orig'"
check "owner's settings kept"          "[[ \"\$(cat '$R/etc/default/f250')\" == TRANSPORT=can ]]"
check "no second mask"                 "! grep -q 'systemctl mask' '$L'"
check "no networkd reload"             "! grep -q 'networkctl' '$L'"
check "no can0 change when absent"     "! grep -q '^ip ' '$L'"

echo "stage1-setup: an older f250 block is replaced"
sed -i.bak 's/^dtoverlay=vc4-kms-dsi-7inch,dsi0$/dtoverlay=vc4-kms-dsi-7inch/' "$R/boot/config.txt"
setup "$R" >/dev/null 2>&1 || fail "apply over an old block exited non-zero"
check "old block replaced"             "cmp -s '$T/config.after1' '$R/boot/config.txt'"

echo "stage1-setup: can0 states"
R2="$T/root2"; make_root "$R2"
printf '3: can0: <NOARP,UP,LOWER_UP,ECHO> mtu 16 state UP\n    link/can  promiscuity 0\n    can <LISTEN-ONLY> state ERROR-ACTIVE\n' >"$R2/.test/ip-can0"
setup "$R2" >/dev/null 2>&1 || fail "apply (listen-only can0) exited non-zero"
check "listen-only can0 left up"       "! grep -q '^ip ' '$R2/.test/sys.log'"
R3="$T/root3"; make_root "$R3"
printf '3: can0: <NOARP,UP,LOWER_UP> mtu 72 state UNKNOWN\n    link/can  promiscuity 0\n    vcan numtxqueues 1\n' >"$R3/.test/ip-can0"
setup "$R3" >/dev/null 2>&1 || fail "apply (vcan can0) exited non-zero"
check "virtual can0 removed"           "has_line '$R3/.test/sys.log' 'ip link delete can0'"
R4="$T/root4"; make_root "$R4"
printf '3: can0: <NOARP,ECHO> mtu 16 state DOWN\n    link/can  promiscuity 0\n' >"$R4/.test/ip-can0"
setup "$R4" >/dev/null 2>&1 || fail "apply (can0 down) exited non-zero"
check "down can0 left alone"           "! grep -q '^ip ' '$R4/.test/sys.log'"

echo "stage1-setup: engine version mismatch"
R5="$T/root5"; make_root "$R5"
echo 3.41.0 >"$R5/usr/share/flutter/f250_infotainment/3.38.3/release/flutter-version"
if setup "$R5" >"$T/mismatch.out" 2>&1; then fail "a bundle for another engine was accepted"; else ok; fi
check "mismatch is explained"          "grep -q 'built with Flutter 3.41.0' '$T/mismatch.out'"

echo "stage1-setup: --check"
R6="$T/root6"; make_root "$R6"
if setup "$R6" --check >"$T/check-before.out" 2>&1; then fail "--check passed before setup"; else ok; fi
check "--check flags the CAN provider" "grep -q 'kuksa-can-provider.service is not masked' '$T/check-before.out'"
check "--check flags normal-mode can0" "grep -q 'NORMAL mode' '$T/check-before.out'"
check "--check changes nothing"        "[[ ! -s '$R6/.test/sys.log' && ! -e '$R6/etc/systemd/network/60-canbus-can.network' ]]"
for b in vehicle-gateway recorder obd-console power-manager camera-manager camera-ctl f250-can f250-storage; do printf '#!/bin/sh\n' >"$R/opt/f250/bin/$b"; chmod +x "$R/opt/f250/bin/$b"; done
for u in f250-gateway f250-recorder f250-power-manager f250-camera-manager f250-dashboard; do echo enabled >"$R/.test/unit-$u.service"; done
echo enabled >"$R/.test/unit-var-volatile-log-journal.mount"; : >"$R/.test/mounted-journal"
mkdir -p "$R/opt/f250/share/data/signals"; echo '{}' >"$R/opt/f250/share/data/warning_rules.json"
if setup "$R" --check >"$T/check-after.out" 2>&1; then ok; else fail "--check after setup: $(grep FAIL "$T/check-after.out")"; fi

echo "stage1-setup: --restore-demo"
: >"$L"
setup "$R" --restore-demo >/dev/null 2>&1 || fail "--restore-demo exited non-zero"
check "restores the demo homescreen"   "has_line '$L' 'systemctl enable flutter-ics-homescreen.service'"
check "restore swaps around a compositor restart" "in_order '$L' 'systemctl stop f250-dashboard.service' 'systemctl restart agl-compositor.service' 'systemctl start flutter-ics-homescreen.service'"
check "disables our dashboard"         "has_line '$L' 'systemctl disable f250-dashboard.service'"

echo "stage1-setup: data drive"
R7="$T/root7"; make_root "$R7"
cp "$R7/etc/fstab" "$T/fstab.orig"
setup "$R7" >/dev/null 2>&1 || fail "apply (data drive, first) exited non-zero"
echo DATA_DRIVE=1 >>"$R7/etc/default/f250"
: >"$R7/.test/sys.log"
setup "$R7" >"$T/drive-none.out" 2>&1 || fail "apply (DATA_DRIVE=1, no drive) exited non-zero"
check "fstab entry added"              "has_line '$R7/etc/fstab' '$FSTAB_LINE'"
check "fstab keeps the image's lines"  "grep -q '^/dev/root ' '$R7/etc/fstab' && grep -q '^proc ' '$R7/etc/fstab'"
check "fstab change reloads systemd"   "grep -q 'systemctl daemon-reload' '$R7/.test/sys.log'"
check "mount point created"            "[[ -d '$R7/var/lib/f250/storage' ]]"
check "no drive: warned, not mounted"  "grep -q 'no drive labelled f250-data' '$T/drive-none.out' && ! grep -q 'systemctl start var-lib' '$R7/.test/sys.log'"
touch "$R7/.test/label-f250-data"
: >"$R7/.test/sys.log"
cp "$R7/etc/fstab" "$T/fstab.on"
setup "$R7" >/dev/null 2>&1 || fail "apply (DATA_DRIVE=1, drive attached) exited non-zero"
check "drive attached: mounts it"      "has_line '$R7/.test/sys.log' 'systemctl start var-lib-f250-storage.mount'"
check "fstab entry not duplicated"     "cmp -s '$T/fstab.on' '$R7/etc/fstab'"
touch "$R7/.test/mounted-storage"
: >"$R7/.test/sys.log"
setup "$R7" >/dev/null 2>&1 || fail "apply (DATA_DRIVE=1, mounted) exited non-zero"
check "mounted: owned by f250"         "has_line '$R7/.test/sys.log' 'chown f250:f250 /var/lib/f250/storage' && has_line '$R7/.test/sys.log' 'chmod 0750 /var/lib/f250/storage'"
check "mounted: no second mount"       "! grep -q 'systemctl start var-lib' '$R7/.test/sys.log'"
for b in vehicle-gateway recorder obd-console power-manager camera-manager camera-ctl f250-can f250-storage; do printf '#!/bin/sh\n' >"$R7/opt/f250/bin/$b"; chmod +x "$R7/opt/f250/bin/$b"; done
for u in kuksa-can-provider can-dev-helper; do echo masked >"$R7/.test/unit-$u.service"; done
for u in f250-gateway f250-recorder f250-power-manager f250-camera-manager f250-dashboard; do echo enabled >"$R7/.test/unit-$u.service"; done
echo enabled >"$R7/.test/unit-var-volatile-log-journal.mount"; : >"$R7/.test/mounted-journal"
echo disabled >"$R7/.test/unit-flutter-ics-homescreen.service"; rm -f "$R7/.test/ip-can0"
mkdir -p "$R7/opt/f250/share/data/signals"; echo '{}' >"$R7/opt/f250/share/data/warning_rules.json"
if setup "$R7" --check >"$T/check-drive.out" 2>&1; then ok; else fail "--check with the drive mounted: $(grep FAIL "$T/check-drive.out")"; fi
check "--check sees the mount"         "grep -q 'mounted at /var/lib/f250/storage' '$T/check-drive.out'"
# The trimmed image has none of the demo's units (ADR-0021).
rm -f "$R7/.test/unit-flutter-ics-homescreen.service" "$R7/.test/unit-kuksa-can-provider.service" "$R7/.test/unit-can-dev-helper.service"
if setup "$R7" --check >"$T/check-trimmed.out" 2>&1; then ok; else fail "--check without the demo's units: $(grep FAIL "$T/check-trimmed.out")"; fi
check "--check: homescreen not installed" "grep -q 'flutter-ics-homescreen.service not installed' '$T/check-trimmed.out'"
rm "$R7/.test/mounted-storage"
if setup "$R7" --check >"$T/check-nodrive.out" 2>&1; then fail "--check passed with DATA_DRIVE=1 and nothing mounted"; else ok; fi
check "--check says the recorder stops" "grep -q \"the recorder won't run\" '$T/check-nodrive.out'"
sed -i.bak 's/^DATA_DRIVE=1$/DATA_DRIVE=0/' "$R7/etc/default/f250"
setup "$R7" >/dev/null 2>&1 || fail "apply (DATA_DRIVE back to 0) exited non-zero"
check "off again: fstab as before"     "cmp -s '$T/fstab.orig' '$R7/etc/fstab'"

echo "stage1-setup: Bluetooth (ADR-0023)"
# rfkill switches as sysfs shows them: connman left both blocked.
rfkill() {   # rfkill <root> <n> <type> <soft> <hard>
  mkdir -p "$1/sys/class/rfkill/rfkill$2"
  echo "$3" >"$1/sys/class/rfkill/rfkill$2/type"
  echo "$4" >"$1/sys/class/rfkill/rfkill$2/soft"
  echo "$5" >"$1/sys/class/rfkill/rfkill$2/hard"
}
R8="$T/root8"; make_root "$R8"
rfkill "$R8" 0 bluetooth 1 0
rfkill "$R8" 1 wlan 1 0
setup "$R8" >"$T/bt-apply.out" 2>&1 || { fail "apply (Bluetooth blocked) exited non-zero"; cat "$T/bt-apply.out"; }
check "connman drop-in installed"      "cmp -s agl/rootfs/etc/systemd/system/connman.service.d/50-f250.conf '$R8/etc/systemd/system/connman.service.d/50-f250.conf'"
check "unblocks Bluetooth"             "[[ \"\$(cat '$R8/sys/class/rfkill/rfkill0/soft')\" == 0 ]] && grep -q 'unblocked Bluetooth rfkill0' '$T/bt-apply.out'"
check "leaves other radios alone"      "[[ \"\$(cat '$R8/sys/class/rfkill/rfkill1/soft')\" == 1 ]]"
check "never restarts connman (SSH may be on its Wi-Fi)" "! grep -q 'connman' '$R8/.test/sys.log'"
check "says a reboot applies the drop-in" "grep -q 'connman drop-in changed' '$T/bt-apply.out'"
: >"$T/bt-apply2.out"
setup "$R8" >"$T/bt-apply2.out" 2>&1 || fail "second apply (Bluetooth) exited non-zero"
check "unblocked: nothing to do again" "! grep -q 'unblocked Bluetooth' '$T/bt-apply2.out'"
R9="$T/root9"; make_root "$R9"
setup "$R9" >"$T/bt-none.out" 2>&1 || fail "apply without a Bluetooth controller exited non-zero"
check "no controller: warned, apply goes on" "grep -q 'no Bluetooth controller found' '$T/bt-none.out'"
# --check reads the switch, connmand's command line and BlueZ's Powered.
echo 'yes' >"$R8/.test/bt-powered"
echo '/usr/sbin/connmand -n --noplugin=bluetooth ' >"$R8/.test/connmand-cmdline"
setup "$R8" --check >"$T/bt-check.out" 2>&1 || true
check "--check: drop-in ok"            "grep -q 'ok.*connman leaves Bluetooth to BlueZ' '$T/bt-check.out'"
check "--check: switch not blocked"    "grep -q 'ok.*Bluetooth rfkill0 is not blocked' '$T/bt-check.out'"
check "--check: powered"               "grep -q 'ok.*BlueZ: controller powered' '$T/bt-check.out'"
check "--check: connman without the plugin, no warning" "! grep -q 'still runs with its Bluetooth plugin' '$T/bt-check.out'"
check "--check: ignores other radios"  "! grep -q 'rfkill1' '$T/bt-check.out'"
echo '/usr/sbin/connmand -n ' >"$R8/.test/connmand-cmdline"
echo 'no' >"$R8/.test/bt-powered"
setup "$R8" --check >"$T/bt-check2.out" 2>&1 || true
check "--check: old connman needs a reboot" "grep -q 'WARN.*still runs with its Bluetooth plugin: reboot' '$T/bt-check2.out'"
check "--check: not powered is a warning" "grep -q 'WARN.*controller not powered' '$T/bt-check2.out'"
echo 1 >"$R8/sys/class/rfkill/rfkill0/soft"
setup "$R8" --check >"$T/bt-check3.out" 2>&1 || true
check "--check: soft-blocked fails"    "grep -q 'FAIL.*Bluetooth rfkill0 is soft-blocked' '$T/bt-check3.out'"
echo 0 >"$R8/sys/class/rfkill/rfkill0/soft"; echo 1 >"$R8/sys/class/rfkill/rfkill0/hard"
setup "$R8" --check >"$T/bt-check4.out" 2>&1 || true
check "--check: hard-blocked fails"    "grep -q 'FAIL.*Bluetooth rfkill0 is hard-blocked' '$T/bt-check4.out'"
rm "$R8/etc/systemd/system/connman.service.d/50-f250.conf"
setup "$R8" --check >"$T/bt-check5.out" 2>&1 || true
check "--check: missing drop-in fails" "grep -q 'FAIL.*connman.service.d/50-f250.conf missing' '$T/bt-check5.out'"

echo "gateway-start"
STUB="$T/vehicle-gateway"
printf '#!/bin/sh\necho "$@"\n' >"$STUB"; chmod +x "$STUB"
gw() { env -i PATH="$PATH" F250_GATEWAY_BIN="$STUB" STATE_DIRECTORY=/var/lib/f250 "$@" bash "$GW" 2>/dev/null; }
check "sim"                 "[[ \"\$(gw TRANSPORT=sim)\" == '--listen unix:/run/f250/vehicle.sock --transport sim --signals /opt/f250/share/data/signals --warnings /opt/f250/share/data/warning_rules.json --scenario-dir /opt/f250/share/data/scenarios --scenario drive_cycle --sim-start-s 0' ]]"
check "obdlink passive"     "[[ \"\$(gw TRANSPORT=obdlink)\" == '--listen unix:/run/f250/vehicle.sock --transport obdlink --signals /opt/f250/share/data/signals --warnings /opt/f250/share/data/warning_rules.json --adapter rfcomm:00:04:3E:85:EA:FC --traffic-log /var/lib/f250/traffic' ]]"
check "obdlink transmit"    "[[ \"\$(gw TRANSPORT=obdlink TRANSMIT=1)\" == *' --transmit' ]]"
check "can passive"         "[[ \"\$(gw TRANSPORT=can CAN_IF=can0)\" == '--listen unix:/run/f250/vehicle.sock --transport can --signals /opt/f250/share/data/signals --warnings /opt/f250/share/data/warning_rules.json --can-if can0 --traffic-log /var/lib/f250/traffic' ]]"
check "pinned: physical by default" "[[ \"\$(gw TRANSPORT=can PINNED=)\" != *--can-pinned* ]]"
check "pinned on 7DF"       "[[ \"\$(gw TRANSPORT=can PINNED=functional)\" == *' --can-pinned functional'* ]]"
check "TRANSMIT=0 never transmits" "[[ \"\$(gw TRANSPORT=can TRANSMIT=0)\" != *--transmit* ]]"
check "can transmit refused without the interface" "! gw TRANSPORT=can TRANSMIT=1 CAN_IF=f250-test-none >/dev/null"
check "enable and budget"   "[[ \"\$(gw TRANSPORT=sim ENABLE=rpm,trans_temp BUDGET_RPS=8)\" == *'--enable rpm,trans_temp --budget-rps 8' ]]"
check "unknown transport refused" "! gw TRANSPORT=bogus >/dev/null"
check "traffic on the data drive"  "[[ \"\$(gw TRANSPORT=can DATA_DRIVE=1 F250_TEST_MOUNTED=1)\" == *'--traffic-log /var/lib/f250/storage/traffic' ]]"
check "no drive: traffic on the SD, gateway runs" "[[ \"\$(gw TRANSPORT=can DATA_DRIVE=1 F250_TEST_MOUNTED=0)\" == *'--traffic-log /var/lib/f250/traffic' ]]"

echo "recorder-start"
RSTUB="$T/recorder"
printf '#!/bin/sh\necho "$@"\n' >"$RSTUB"; chmod +x "$RSTUB"
rec() { env -i PATH="$PATH" F250_RECORDER_BIN="$RSTUB" STATE_DIRECTORY=/var/lib/f250 "$@" bash "$REC" 2>/dev/null; }
check "SD card by default"   "[[ \"\$(rec)\" == 'run --gateway unix:/run/f250/vehicle.sock --db /var/lib/f250/telemetry.sqlite' ]]"
check "data drive"           "[[ \"\$(rec DATA_DRIVE=1 F250_TEST_MOUNTED=1)\" == 'run --gateway unix:/run/f250/vehicle.sock --db /var/lib/f250/storage/telemetry.sqlite' ]]"
check "no drive: refuses, never the SD" "! rec DATA_DRIVE=1 F250_TEST_MOUNTED=0 >'$T/rec.out' && [[ ! -s '$T/rec.out' ]]"

echo "camera-start"
CSTUB="$T/camera-manager"
printf '#!/bin/sh\necho "$@"\n' >"$CSTUB"; chmod +x "$CSTUB"
cam() { env -i PATH="$PATH" F250_CAMERA_BIN="$CSTUB" "$@" bash agl/rootfs/opt/f250/libexec/camera-start 2>/dev/null; }
check "no cameras: only the socket" "[[ \"\$(cam)\" == '--listen unix:/run/f250-camera/camera.sock' ]]"
check "empty settings: no cameras" "[[ \"\$(cam CAMERA_LEFT= CAMERA_RIGHT= CAMERA_REAR= CAMERA_CAPS=)\" == '--listen unix:/run/f250-camera/camera.sock' ]]"
check "each camera named"   "[[ \"\$(cam CAMERA_REAR=/dev/video0 CAMERA_LEFT=/dev/v4l/by-id/usb-x-video-index0)\" == '--listen unix:/run/f250-camera/camera.sock --camera left=/dev/v4l/by-id/usb-x-video-index0 --camera rear=/dev/video0' ]]"
check "caps passed as one argument" "[[ \"\$(env -i PATH=\"\$PATH\" F250_CAMERA_BIN=/bin/echo CAMERA_CAPS='video/x-raw,width=640 ! videoscale' bash agl/rootfs/opt/f250/libexec/camera-start 2>/dev/null)\" == '--listen unix:/run/f250-camera/camera.sock --caps video/x-raw,width=640 ! videoscale' ]]"
check "a device with a space refused" "! cam 'CAMERA_REAR=/dev/video 0' >/dev/null"

echo "grow-root"
# A fake sysfs for the card: <disk sectors> then partitions as <n>:<start>:<size>
# (512-byte sectors, as sysfs counts). Root is partition 2 (179:2).
fake_card() {
  local d="$1" disk="$2"; shift 2
  rm -rf "$d"; mkdir -p "$d/block/mmcblk0" "$d/dev/block"
  echo "$disk" >"$d/block/mmcblk0/size"
  for p in "$@"; do
    IFS=: read -r n start size <<<"$p"
    mkdir -p "$d/block/mmcblk0/mmcblk0p$n"
    echo "$n" >"$d/block/mmcblk0/mmcblk0p$n/partition"
    echo "$start" >"$d/block/mmcblk0/mmcblk0p$n/start"
    echo "$size" >"$d/block/mmcblk0/mmcblk0p$n/size"
    ln -s "../../block/mmcblk0/mmcblk0p$n" "$d/dev/block/179:$n"
  done
}
grow() {   # grow <pttype>: run grow-root on $T/sys, commands to $T/grow.log
  : >"$T/grow.log"
  env -i PATH="$PATH" F250_SYSFS="$T/sys" F250_TEST_MAJMIN='179:2  ' F250_TEST_PTTYPE="$1" \
    F250_SYS_LOG="$T/grow.log" bash "$GROW" >"$T/grow.out" 2>&1
}
# The release image on a card of about 7.3 GiB: boot 8192+266240, root 278528+1842380 (its MBR).
CARD=15269888
fake_card "$T/sys" $CARD 1:8192:266240 2:278528:1842380
if grow dos; then ok; else fail "grow-root exited non-zero: $(cat "$T/grow.out")"; fi
check "grows partition 2 to the end"   "has_line '$T/grow.log' 'sfdisk --no-reread -N 2 /dev/mmcblk0'"
check "tells the kernel the new size"  "in_order '$T/grow.log' 'sfdisk --no-reread -N 2 /dev/mmcblk0' 'partx -u --nr 2 /dev/mmcblk0'"
check "then grows the filesystem"      "[[ \"\$(tail -1 '$T/grow.log')\" == '/usr/lib/systemd/systemd-growfs /' ]]"
check "says how much room"             "grep -q 'partition 2 of /dev/mmcblk0: 899 MiB, 6420 MiB after it' '$T/grow.out'"
fake_card "$T/sys" $CARD 1:8192:266240 "2:278528:$((CARD - 278528))"
grow dos || fail "grow-root (already grown) exited non-zero"
check "already full: no table write"   "! grep -q sfdisk '$T/grow.log' && has_line '$T/grow.log' '/usr/lib/systemd/systemd-growfs /'"
fake_card "$T/sys" $CARD 1:8192:266240 "2:278528:$((CARD - 278528 - 30000))"
grow dos || fail "grow-root (15 MiB left) exited non-zero"
check "under 16 MiB left: no table write" "! grep -q sfdisk '$T/grow.log'"
fake_card "$T/sys" $CARD 1:8192:266240 2:278528:1842380 3:4194304:2097152
grow dos || fail "grow-root (partition after root) exited non-zero"
check "a partition after root: left alone" "! grep -q sfdisk '$T/grow.log' && grep -q 'mmcblk0p3 comes after it' '$T/grow.out'"
fake_card "$T/sys" $CARD 1:8192:266240 2:278528:1842380
grow gpt || fail "grow-root (GPT) exited non-zero"
check "GPT: left alone"                "! grep -q sfdisk '$T/grow.log' && grep -q \"'gpt' partition table\" '$T/grow.out'"
rm -rf "$T/sys"; mkdir -p "$T/sys/dev/block/0:25"
grow dos || fail "grow-root (not a partition) exited non-zero"
check "root not on a partition: nothing written" "! grep -q sfdisk '$T/grow.log'"
check "grow unit: enabled after local-fs, before the data writers" "grep -qx 'After=local-fs.target' agl/rootfs/etc/systemd/system/f250-grow-root.service && grep -qx 'Before=f250-gateway.service f250-recorder.service' agl/rootfs/etc/systemd/system/f250-grow-root.service && grep -qx 'WantedBy=multi-user.target' agl/rootfs/etc/systemd/system/f250-grow-root.service"
# A device allow-list (DeviceAllow=, or ProtectClock= and PrivateDevices=, which
# imply one) would shut it out of the disk; / must stay writable for the resize.
check "grow unit: the disk and / stay writable" "! grep -qE '^(DeviceAllow|DevicePolicy|ProtectClock|PrivateDevices)=' agl/rootfs/etc/systemd/system/f250-grow-root.service && grep -qx 'ProtectSystem=full' agl/rootfs/etc/systemd/system/f250-grow-root.service"
check "grow unit: only the capabilities it needs" "grep -qx 'CapabilityBoundingSet=CAP_SYS_ADMIN CAP_SYS_RESOURCE' agl/rootfs/etc/systemd/system/f250-grow-root.service"

echo "f250-storage"
check "unknown command refused" "! bash '$STORAGE_TOOL' bogus 2>/dev/null"
check "format needs a disk"     "! bash '$STORAGE_TOOL' format 2>/dev/null"
if [[ "$(id -u)" != 0 ]]; then
  bash "$STORAGE_TOOL" format /dev/null >"$T/storage.out" 2>&1 || true
  check "format needs root"     "grep -q 'run as root' '$T/storage.out'"
fi

echo "dashboard-stopped"
SB="$T/sbin"; mkdir -p "$SB"
printf '#!/bin/sh\necho "systemctl $*" >>"%s/poweroff.log"\n' "$T" >"$SB/systemctl"; chmod +x "$SB/systemctl"
env -i PATH="$SB:$PATH" EXIT_CODE=exited EXIT_STATUS=1 bash "$STOPPED" >/dev/null
env -i PATH="$SB:$PATH" EXIT_CODE=killed EXIT_STATUS=TERM bash "$STOPPED" >/dev/null
check "no power off on a crash or stop" "[[ ! -e '$T/poweroff.log' ]]"
env -i PATH="$SB:$PATH" EXIT_CODE=exited EXIT_STATUS=42 bash "$STOPPED" >/dev/null
check "power off on exit 42"  "has_line '$T/poweroff.log' 'systemctl poweroff --no-block'"

echo "power-manager-stopped"
PMSTOPPED=agl/rootfs/opt/f250/libexec/power-manager-stopped
rm -f "$T/poweroff.log"
env -i PATH="$SB:$PATH" EXIT_CODE=exited EXIT_STATUS=1 bash "$PMSTOPPED" >/dev/null
env -i PATH="$SB:$PATH" EXIT_CODE=exited EXIT_STATUS=0 bash "$PMSTOPPED" >/dev/null
env -i PATH="$SB:$PATH" EXIT_CODE=killed EXIT_STATUS=TERM bash "$PMSTOPPED" >/dev/null
env -i PATH="$SB:$PATH" EXIT_CODE=dumped EXIT_STATUS=ABRT bash "$PMSTOPPED" >/dev/null
check "power-manager: no power off on a crash, stop or watchdog kill" "[[ ! -e '$T/poweroff.log' ]]"
env -i PATH="$SB:$PATH" EXIT_CODE=exited EXIT_STATUS=42 bash "$PMSTOPPED" >/dev/null
check "power-manager: power off on exit 42" "has_line '$T/poweroff.log' 'systemctl poweroff --no-block'"
check "power-manager: exit code matches the service" "grep -q 'pub const POWER_OFF_EXIT: u8 = 42;' services/power-manager/src/lib.rs"

echo "units"
check "dashboard treats 42 as success" "grep -qx 'SuccessExitStatus=42' agl/rootfs/etc/systemd/system/f250-dashboard.service"
check "dashboard is bound to the compositor" "grep -qx 'BindsTo=agl-compositor.service' agl/rootfs/etc/systemd/system/f250-dashboard.service && grep -qx 'PartOf=agl-compositor.service' agl/rootfs/etc/systemd/system/f250-dashboard.service"
check "dashboard starts with the compositor" "grep -qx 'WantedBy=graphical.target agl-compositor.service' agl/rootfs/etc/systemd/system/f250-dashboard.service"
check "dashboard never restarts alone" "! grep -q '^Restart=' agl/rootfs/etc/systemd/system/f250-dashboard.service"
check "dashboard failure restarts the compositor" "grep -qx 'OnFailure=f250-dashboard-recover.service' agl/rootfs/etc/systemd/system/f250-dashboard.service && grep -qx 'ExecStart=/usr/bin/systemctl restart agl-compositor.service' agl/rootfs/etc/systemd/system/f250-dashboard-recover.service"
check "connman: ExecStart reset, then without its Bluetooth plugin" "in_order agl/rootfs/etc/systemd/system/connman.service.d/50-f250.conf 'ExecStart=' 'ExecStart=/usr/sbin/connmand -n --noplugin=bluetooth'"
check "compositor restarts after a crash" "grep -qx 'Restart=on-failure' agl/rootfs/etc/systemd/system/agl-compositor.service.d/50-f250.conf"
check "journal mount: SD card to the journal's place" "grep -qx 'What=/var/lib/journal' agl/rootfs/etc/systemd/system/var-volatile-log-journal.mount && grep -qx 'Where=/var/volatile/log/journal' agl/rootfs/etc/systemd/system/var-volatile-log-journal.mount && grep -qx 'Before=systemd-journal-flush.service' agl/rootfs/etc/systemd/system/var-volatile-log-journal.mount"
check "journal mount unit name matches Where=" "[[ \"\$(basename agl/rootfs/etc/systemd/system/var-volatile-log-journal.mount)\" == var-volatile-log-journal.mount ]] && grep -q '^JOURNAL_WHERE=/var/volatile/log/journal$' '$SETUP'"
check "journal is persistent and capped" "grep -qx 'Storage=persistent' agl/rootfs/etc/systemd/journald.conf.d/50-f250.conf && grep -qx 'SystemMaxUse=50M' agl/rootfs/etc/systemd/journald.conf.d/50-f250.conf"
check "power-off code matches the app" "grep -q 'const powerOffExitCode = 42;' apps/infotainment/lib/core/power.dart"
check "socket path matches the build"  "grep -q 'SOCK=/run/f250/vehicle.sock' tools/dev/deploy.sh && grep -q 'F250_SOCK:-/run/f250/vehicle.sock' '$REC' && grep -q 'F250_SOCK:-/run/f250/vehicle.sock' '$GW'"
check "recorder starts via its wrapper" "grep -qx 'ExecStart=/opt/f250/libexec/recorder-start' agl/rootfs/etc/systemd/system/f250-recorder.service"
check "services ordered after the drive" "grep -qx 'After=var-lib-f250-storage.mount' agl/rootfs/etc/systemd/system/f250-recorder.service && grep -qx 'After=var-lib-f250-storage.mount' agl/rootfs/etc/systemd/system/f250-gateway.service"
check "mount point agrees everywhere" "grep -q '^STORAGE=/var/lib/f250/storage$' '$SETUP' && grep -q 'F250_STORAGE:-/var/lib/f250/storage' '$GW' && grep -q 'F250_STORAGE:-/var/lib/f250/storage' '$REC' && grep -q '^STORAGE=/var/lib/f250/storage$' '$STORAGE_TOOL'"
check "drive label agrees"     "grep -q '^DRIVE_LABEL=f250-data$' '$SETUP' && grep -q '^LABEL=f250-data$' '$STORAGE_TOOL'"
# Sandbox (ADR-0021): each service has the settings measured on the bench.
U=agl/rootfs/etc/systemd/system
for unit in f250-gateway f250-recorder f250-power-manager f250-dashboard f250-camera-manager; do
  for line in 'NoNewPrivileges=yes' 'CapabilityBoundingSet=' 'ProtectSystem=strict' 'PrivateTmp=yes' \
              'ProtectKernelTunables=yes' 'ProtectKernelModules=yes' 'ProtectKernelLogs=yes' \
              'ProtectControlGroups=yes' 'ProtectClock=yes' 'ProtectHostname=yes' 'ProtectProc=invisible' \
              'RestrictNamespaces=yes' 'RestrictSUIDSGID=yes' 'RestrictRealtime=yes' 'LockPersonality=yes' \
              'SystemCallArchitectures=native' 'SystemCallFilter=@system-service' \
              'SystemCallFilter=~@privileged @resources' 'IPAddressDeny=any'; do
    check "$unit: $line" "grep -qxF '$line' $U/$unit.service"
  done
done
# Every service but camera-manager: GStreamer's orc writes code at run time
# (f250-camera-manager.service says why; UNVERIFIED that it needs to).
for unit in f250-gateway f250-recorder f250-power-manager f250-dashboard; do
  check "$unit: MemoryDenyWriteExecute=yes" "grep -qxF 'MemoryDenyWriteExecute=yes' $U/$unit.service"
done
check "gateway reaches only USB serial devices" "grep -qx 'DevicePolicy=closed' $U/f250-gateway.service && [[ \"\$(grep -c '^DeviceAllow=' $U/f250-gateway.service)\" == 1 ]] && grep -qx 'DeviceAllow=char-ttyUSB rw' $U/f250-gateway.service"
check "gateway keeps its adapter families" "grep -qx 'RestrictAddressFamilies=AF_UNIX AF_CAN AF_BLUETOOTH AF_INET AF_INET6 AF_NETLINK' $U/f250-gateway.service"
check "gateway reaches the local network only" "grep -qx 'IPAddressAllow=localhost link-local 10.0.0.0/8 172.16.0.0/12 192.168.0.0/16' $U/f250-gateway.service"
PM=$U/f250-power-manager.service
check "power-manager: ExecStopPost as root powers off" "grep -qx 'ExecStopPost=+/opt/f250/libexec/power-manager-stopped' $PM && grep -qx 'SuccessExitStatus=42' $PM"
check "power-manager: reads input devices only" "grep -qx 'DevicePolicy=closed' $PM && [[ \"\$(grep -c '^DeviceAllow=' $PM)\" == 1 ]] && grep -qx 'DeviceAllow=char-input r' $PM && grep -qx 'SupplementaryGroups=input' $PM"
check "power-manager: /proc/uptime visible (no ProcSubset=pid)" "! grep -q '^ProcSubset=' $PM"
check "power-manager: input group mapped (no PrivateUsers)" "! grep -q '^PrivateUsers=' $PM && ! grep -q '^PrivateDevices=' $PM"
check "power-manager: no network" "grep -qx 'PrivateNetwork=yes' $PM && grep -qx 'RestrictAddressFamilies=AF_UNIX' $PM"
check "power-manager: boot window default and setting agree" "grep -qx 'Environment=BOOT_KEY_IGNORE_S=30' $PM && grep -qx 'BOOT_KEY_IGNORE_S=30' agl/rootfs/etc/default/f250 && grep -q 'default_value_t = 30' services/power-manager/src/main.rs"
check "power-manager: the settings reach the binary" "grep -qx 'ExecStart=/opt/f250/bin/power-manager --boot-key-ignore-s \${BOOT_KEY_IGNORE_S} --camera-manager \${CAMERA_MANAGER}' $PM"
check "power-manager: switch moves go to camera-manager's socket (ADR-0026)" "grep -qx 'Environment=CAMERA_MANAGER=unix:/run/f250-camera/camera.sock' $PM"
check "power-manager: deployed and built into the image" "grep -q -- '-p power-manager' tools/dev/deploy.sh && grep -q '/target/release/power-manager' tools/dev/deploy.sh && grep -q -- '-p power-manager' agl/meta-f250/recipes-f250/f250-services/f250-services.bb && grep -q 'obd-console power-manager camera-manager camera-ctl; do' agl/meta-f250/recipes-f250/f250-services/f250-services.bb"
CM=$U/f250-camera-manager.service
check "camera-manager: starts via its wrapper" "grep -qx 'ExecStart=/opt/f250/libexec/camera-start' $CM"
check "camera-manager: power-manager's socket is camera-manager's" "grep -q 'F250_CAMERA_SOCK:-/run/f250-camera/camera.sock' agl/rootfs/opt/f250/libexec/camera-start && grep -qx 'RuntimeDirectory=f250-camera' $CM && grep -qx 'Environment=CAMERA_MANAGER=unix:/run/f250-camera/camera.sock' $PM"
check "camera-manager: agl-driver (Wayland), group f250 (the socket), video" "grep -qx 'User=agl-driver' $CM && grep -qx 'Group=f250' $CM && grep -qx 'SupplementaryGroups=video' $CM && grep -qx 'UMask=0007' $CM && grep -qx 'RuntimeDirectoryMode=0750' $CM"
check "camera-manager: the compositor's Wayland socket" "grep -qx 'Environment=XDG_RUNTIME_DIR=/run/user/1001' $CM && grep -qx 'Environment=WAYLAND_DISPLAY=wayland-0' $CM && grep -qx 'ProtectHome=read-only' $CM && grep -qx 'After=agl-compositor.service' $CM"
check "camera-manager: not bound to the compositor (it retries)" "! grep -q '^BindsTo=' $CM && ! grep -q '^PartOf=' $CM && grep -qx 'Restart=on-failure' $CM"
check "camera-manager: reaches only cameras" "grep -qx 'DevicePolicy=closed' $CM && [[ \"\$(grep -c '^DeviceAllow=' $CM)\" == 1 ]] && grep -qx 'DeviceAllow=char-video4linux rw' $CM"
check "camera-manager: no network" "grep -qx 'PrivateNetwork=yes' $CM && grep -qx 'RestrictAddressFamilies=AF_UNIX' $CM"
check "camera-manager: GStreamer's registry in its cache" "grep -qx 'CacheDirectory=f250-camera' $CM && grep -qx 'Environment=XDG_CACHE_HOME=/var/cache/f250-camera' $CM && ! grep -q '^ReadWritePaths=' $CM"
check "camera-manager: watchdog" "grep -qx 'Type=notify' $CM && grep -qx 'WatchdogSec=30' $CM"
check "camera-manager: deployed and built into the image" "grep -q -- '-p camera-manager' tools/dev/deploy.sh && grep -q '/target/release/camera-manager' tools/dev/deploy.sh && grep -q -- '-p camera-manager' agl/meta-f250/recipes-f250/f250-services/f250-services.bb && grep -q 'power-manager camera-manager camera-ctl; do' agl/meta-f250/recipes-f250/f250-services/f250-services.bb && grep -q '/target/release/camera-ctl' tools/dev/deploy.sh"
check "camera-manager: the image has gst-launch-1.0 (gstreamer1.0)" "grep -qx '    gstreamer1.0 \\\\' agl/meta-f250/recipes-platform/images/agl-f250-base.inc"
# The camera window's area (ADR-0009) must match the dashboard's layout: below
# the status bar and alert banner, above the nav bar.
th=apps/infotainment/lib/ui/theme.dart
sb="$(sed -n 's/^const kStatusBarHeight = \([0-9]*\)\.0;$/\1/p' $th)"
ab="$(sed -n 's/^const kAlertBannerHeight = \([0-9]*\)\.0;$/\1/p' $th)"
nb="$(sed -n 's/^const kNavBarHeight = \([0-9]*\)\.0;$/\1/p' $th)"
check "activation area: theme constants read" "[[ -n '$sb' && -n '$ab' && -n '$nb' ]]"
sed -n '/^\[window_activation_area\]$/,$p' agl/flutter/config.toml | grep -v '^#' >"$T/area.toml"
check "activation area below the alert banner, above the nav bar" "in_order '$T/area.toml' '[window_activation_area]' 'x = 0' 'y = $((sb + ab))' 'width = 800' 'height = $((480 - sb - ab - nb))'"
check "recorder has no network or devices" "grep -qx 'PrivateNetwork=yes' $U/f250-recorder.service && grep -qx 'PrivateDevices=yes' $U/f250-recorder.service && grep -qx 'RestrictAddressFamilies=AF_UNIX' $U/f250-recorder.service"
check "dashboard reaches only the GPU" "grep -qx 'DevicePolicy=closed' $U/f250-dashboard.service && [[ \"\$(grep -c '^DeviceAllow=' $U/f250-dashboard.service)\" == 1 ]] && grep -qx 'DeviceAllow=char-drm rw' $U/f250-dashboard.service"
check "dashboard has no network" "grep -qx 'PrivateNetwork=yes' $U/f250-dashboard.service && grep -qx 'RestrictAddressFamilies=AF_UNIX' $U/f250-dashboard.service"
check "dashboard's home is read-only, /run/user visible" "grep -qx 'ProtectHome=read-only' $U/f250-dashboard.service"
check "dashboard writes only directories systemd creates" "! grep -q '^ReadWritePaths=' $U/f250-dashboard.service && grep -qx 'StateDirectory=f250-dashboard' $U/f250-dashboard.service && grep -qx 'CacheDirectory=f250-dashboard' $U/f250-dashboard.service"
check "flutter-auto's HOME is the state directory" "grep -qx 'Environment=HOME=/var/lib/f250-dashboard' $U/f250-dashboard.service && grep -qx 'Environment=XDG_CACHE_HOME=/var/cache/f250-dashboard' $U/f250-dashboard.service"
check "dashboard leaves the compositor's IPC alone" "! grep -q '^RemoveIPC=' $U/f250-dashboard.service"
check "power off runs outside the sandbox" "grep -qx 'ExecStopPost=+/opt/f250/libexec/dashboard-stopped' $U/f250-dashboard.service"
check "config block is marked"         "[[ \"\$(head -1 agl/boot/config-f250.txt)\" == '# >>> f250'* && \"\$(tail -1 agl/boot/config-f250.txt)\" == '# <<< f250' ]]"
# Camera switch (ADR-0025): the gpio-key overlay's default key is KEY_POWER, so
# every line must name its own; the five keys are power-manager's F13-F17, on
# the wiring doc's pins, none of them the DAC8x's (BCM5, BCM18-27).
GK="$(grep '^dtoverlay=gpio-key' agl/boot/config-f250.txt)"
check "camera switch: five gpio-key lines" "[[ \"\$(grep -c . <<<\"\$GK\")\" == 5 ]]"
check "camera switch: every line sets keycode" "! grep -v ',keycode=' <<<\"\$GK\" | grep -q . && ! grep -q 'keycode=116' <<<\"\$GK\""
check "camera switch: keys match power-manager" "[[ \"\$(sed -n 's/.*keycode=\\([0-9]*\\).*/\\1/p' <<<\"\$GK\" | sort | tr '\\n' ' ')\" == '183 184 185 186 187 ' ]] && grep -q 'Direction::Left => 183' services/power-manager/src/camera_switch.rs && grep -q 'Direction::Press => 187' services/power-manager/src/camera_switch.rs"
check "camera switch: pins as wired" "[[ \"\$(sed -n 's/.*gpio=\\([0-9]*\\),.*/\\1/p' <<<\"\$GK\" | sort -n | tr '\\n' ' ')\" == '6 12 13 16 17 ' ]]"
check "camera switch: pull-ups on" "! grep -v ',gpio_pull=2' <<<\"\$GK\" | grep -q ."
check "engine pin matches .fvmrc"      "grep -q \"AGL_FLUTTER_VERSION=\$(sed -n 's/.*\"flutter\": *\"\\([^\"]*\\)\".*/\\1/p' .fvmrc)\" agl/configurations/vimba.env"

# Build host (Phase 5.4): the build scripts only run on Linux, and the
# manifest they ask repo for is named from the release pin.
if [[ "$(uname -s)" != Linux ]]; then
  check "agl-build.sh refuses to run off Linux"   "! agl/scripts/agl-build.sh fetch >/dev/null 2>&1"
  check "setup-build-host.sh refuses off Linux"   "! agl/scripts/setup-build-host.sh >/dev/null 2>&1"
fi
check "build uses the release's pinned manifest" "grep -q -- '-m \"\${AGL_BRANCH}_\${AGL_RELEASE}.xml\"' agl/scripts/agl-build.sh && grep -q -- '-b \"refs/tags/\$AGL_BRANCH/\$AGL_RELEASE\"' agl/scripts/agl-build.sh"

# meta-f250 (Phase 5.4): the layer must give the image what stage1-setup.sh
# gives the prebuilt one, so --check means the same on both.
echo "meta-f250"
M=agl/meta-f250
SYSBB=$M/recipes-f250/f250-system/f250-system.bb
check "crate list matches Cargo.lock"  "python3 tools/dev/gen-crates-inc.py --check"
# The bbappend's config.txt step, run on the fake image's config.txt, writes
# what stage1-setup.sh's apply wrote ($R from the first apply above).
mkdir -p "$T/deploy/bootfiles" "$T/unpack"
cp "$T/config.orig" "$T/deploy/bootfiles/config.txt"
cp agl/boot/config-f250.txt "$T/unpack/"
sed -n '/^f250_config_txt() {/,/^}/p' $M/recipes-bsp/bootfiles/rpi-config_git.bbappend >"$T/cfgfn.sh"
( DEPLOYDIR="$T/deploy" BOOTFILES_DIR_NAME=bootfiles UNPACKDIR="$T/unpack"
  . "$T/cfgfn.sh"; f250_config_txt; f250_config_txt ) 2>/dev/null
check "config.txt: same as stage1-setup.sh" "cmp -s '$T/deploy/bootfiles/config.txt' '$R/boot/config.txt'"
for u in kuksa-can-provider.service can-dev-helper.service; do
  check "image masks $u" "grep -q 'for u in kuksa-can-provider.service can-dev-helper.service' '$SYSBB' && grep -q '$u' '$SETUP'"
done
# Every [Install] WantedBy= of every unit in agl/rootfs is an f250_wants line.
for unit in agl/rootfs/etc/systemd/system/*.service agl/rootfs/etc/systemd/system/*.mount; do
  [[ -f "$unit" ]] || continue
  name="$(basename "$unit")"
  for tgt in $(sed -n 's/^WantedBy=//p' "$unit"); do
    check "image enables $name for $tgt" "grep -qx '    f250_wants $tgt $name' '$SYSBB'"
  done
done
check "units stage1 enables have [Install]" "for u in f250-gateway f250-recorder f250-power-manager f250-camera-manager f250-dashboard; do grep -q '^WantedBy=' agl/rootfs/etc/systemd/system/\$u.service || exit 1; done"
check "static IDs for f250"            "grep -qx 'f250::950:950:F-250 head unit services:/var/lib/f250:/bin/false' $M/files/f250-passwd && grep -qx 'f250::950:' $M/files/f250-group"
check "agl-driver joins f250"          "grep -qx 'GROUPMEMS_PARAM:\${PN} = \"-a agl-driver -g f250\"' $M/recipes-config/agl-users/agl-users_%.bbappend"
CM=$M/recipes-connectivity/connman
check "connman patch is in SRC_URI"    "grep -qx 'SRC_URI += \"file://0001-rtnl-receive-whole-netlink-messages.patch\"' $CM/connman_%.bbappend && test -f $CM/connman/0001-rtnl-receive-whole-netlink-messages.patch"
check "connman reads 32 KiB from netlink" "grep -qxF -e '-	unsigned char buf[4096];' $CM/connman/0001-rtnl-receive-whole-netlink-messages.patch && grep -qxF -e '+	unsigned char buf[32768];' $CM/connman/0001-rtnl-receive-whole-netlink-messages.patch"
IMG=$M/recipes-platform/images
check "images start from the compositor image, not the demo" "grep -qx 'require recipes-platform/images/agl-image-compositor.bb' $IMG/agl-f250-base.inc && ! grep -rq 'agl-ivi-demo\\|agl-ivi-image' $IMG"
for i in agl-f250 agl-f250-release; do
  check "$i uses the shared base" "grep -qx 'require agl-f250-base.inc' $IMG/$i.bb"
done
for p in f250-system f250-services f250-dashboard weston-ini-conf-flutter bluez5 avahi-daemon rsync \
         gstreamer1.0-plugins-good-video4linux2 gstreamer1.0-plugins-good-jpeg \
         gstreamer1.0-plugins-base-videoconvertscale \
         gstreamer1.0-plugins-bad-waylandsink; do
  check "base installs $p" "grep -qx '    $p \\\\' $IMG/agl-f250-base.inc"
done
check "camera bench tools only in the dev image" "grep -qx '    v4l-utils \\\\' $IMG/agl-f250.bb && ! grep -q 'v4l-utils\\|videotestsrc\\|debugutilsbad' $IMG/agl-f250-base.inc $IMG/agl-f250-release.bb"
for feat in allow-empty-password empty-root-password allow-root-login tools-debug tools-profile package-management; do
  check "release drops $feat" "sed -n '/^IMAGE_FEATURES:remove/,/^\"/p' $IMG/agl-f250-release.bb | grep -qx '    $feat \\\\'"
done
check "release drops agl-devel's packages" "grep -qx 'IMAGE_INSTALL:remove = \"packagegroup-agl-core-devel libdrm-tests weston-examples screen mc\"' $IMG/agl-f250-release.bb && grep -qx 'FEATURE_PACKAGES_selinux = \"packagegroup-agl-core-selinux\"' $IMG/agl-f250-release.bb"
check "release needs a root key"       "grep -q 'SkipRecipe(\"F250_AUTHORIZED_KEYS is not set' $IMG/agl-f250-release.bb"
check "key installed for root, in the rootfs signature" "grep -q 'ROOT_HOME}/.ssh/authorized_keys' $IMG/agl-f250-base.inc && grep -q 'do_rootfs\\[file-checksums\\]' $IMG/agl-f250-base.inc"
check "agl-build.sh hands the key to BitBake" "grep -q 'F250_AUTHORIZED_KEYS = ' agl/scripts/agl-build.sh && grep -q 'f250-authorized_keys' tools/dev/build-vm.sh"
# Every command the on-Pi scripts call comes from a package f250-system pulls in.
for pair in candump:can-utils lsusb:usbutils mkfs.ext4:e2fsprogs-mke2fs blkid:util-linux-blkid lsblk:util-linux-lsblk findmnt:util-linux-findmnt ip:iproute2 cmp:diffutils sfdisk:util-linux-sfdisk partx:util-linux-partx systemd-growfs:systemd; do
  cmd=${pair%%:*}; pkg=${pair#*:}
  check "f250-system pulls in $pkg ($cmd)" "grep -A2 '^RDEPENDS' '$SYSBB' | grep -qw '$pkg'"
done
check "services: the binaries deploy.sh builds" "grep -q -- '-p vehicle-gateway -p recorder -p obd-console -p power-manager -p camera-manager --features vehicle-gateway/rfcomm' $M/recipes-f250/f250-services/f250-services.bb && grep -q -- '-p vehicle-gateway --features rfcomm' tools/dev/deploy.sh"
check "dashboard: deploy.sh's defines"  "grep -q -- '-DVEHICLE_SOURCE=gateway -DGATEWAY=unix:/run/f250/vehicle.sock -DCAMERAS=unix:/run/f250-camera/camera.sock' $M/recipes-f250/f250-dashboard/f250-dashboard.bb && grep -q -- '--dart-define=VEHICLE_SOURCE=gateway --dart-define=GATEWAY=unix:\$SOCK' tools/dev/deploy.sh && grep -q -- '--dart-define=CAMERAS=unix:\$CAMERA_SOCK' tools/dev/deploy.sh && grep -q '^CAMERA_SOCK=/run/f250-camera/camera.sock$' tools/dev/deploy.sh"
check "dashboard: bundle name is the app's" "grep -qx 'PUBSPEC_APPNAME = \"f250_infotainment\"' $M/recipes-f250/f250-dashboard/f250-dashboard.bb && grep -qx 'name: f250_infotainment' apps/infotainment/pubspec.yaml && grep -q '^APP_ID=f250_infotainment$' '$SETUP'"
check "layer builds a commit, not the tree" "grep -q 'F250_ALLOW_DIRTY' agl/scripts/agl-build.sh && grep -q 'F250_SRCREV = \"\$rev\"' agl/scripts/agl-build.sh"
check "recipes fail without the commit pin" "grep -q 'SkipRecipe' $M/conf/include/f250-source.inc"
check "recipes never run the repository's Makefile clean" "grep -q '^CLEANBROKEN = \"1\"' $M/conf/include/f250-source.inc"
check "f250-services links the image's SQLite (the cargo class unbundles rusqlite)" "grep -q '^DEPENDS += \"sqlite3\"' $M/recipes-f250/f250-services/f250-services.bb"
for u in kuksa-can-provider.service can-dev-helper.service; do
  check "preset disables masked $u (preset-all fails on a masked enable)" "grep -qx 'disable $u' agl/rootfs/etc/systemd/system-preset/00-f250.preset && grep -q '$u' '$SETUP'"
done
check "oFono disabled in the image and by preset" "grep -qx 'disable ofono.service' agl/rootfs/etc/systemd/system-preset/00-f250.preset && grep -q 'disable ofono.service' agl/meta-f250/recipes-platform/images/agl-f250-base.inc"
check "f250-system skips configure and compile" "grep -q '^do_compile\[noexec\] = \"1\"' $M/recipes-f250/f250-system/f250-system.bb && grep -q '^do_configure\[noexec\] = \"1\"' $M/recipes-f250/f250-system/f250-system.bb"

echo
echo "agl-test: $PASS passed, $FAIL failed"
[[ "$FAIL" == 0 ]]
