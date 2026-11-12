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
check "enables our services"           "has_line '$L' 'systemctl enable f250-gateway.service f250-recorder.service f250-power-manager.service f250-camera-manager.service f250-navigation.service f250-usb-export.service f250-dashboard.service f250-can-auto.service'"
check "restarts the power and camera managers and navigation" "has_line '$L' 'systemctl restart f250-gateway.service f250-recorder.service f250-power-manager.service f250-camera-manager.service f250-navigation.service f250-usb-export.service'"
check "config.txt keeps the original"  "cmp -s '$T/config.orig' '$R/boot/config.txt.agl-orig'"
check "config.txt has one f250 block"  "[[ \$(count '$R/boot/config.txt' '# >>> f250') == 1 ]]"
check "config.txt enables the DSI panel" "has_line '$R/boot/config.txt' 'dtoverlay=vc4-kms-dsi-7inch,dsi0'"
check "config.txt keeps the image's lines" "has_line '$R/boot/config.txt' 'dtoverlay=vc4-kms-v3d-pi5,cma-256'"
check "DAC8x overlay stays commented"  "! grep -qx 'dtoverlay=hifiberry-dac8x' '$R/boot/config.txt'"
check "default settings installed"     "cmp -s agl/rootfs/etc/default/f250 '$R/etc/default/f250'"
check "default transport is sim"       "has_line '$R/etc/default/f250' 'TRANSPORT=sim'"
check "default transmit is off"        "has_line '$R/etc/default/f250' 'TRANSMIT=0'"
check "helpers are executable"         "[[ -x '$R/opt/f250/libexec/gateway-start' && -x '$R/opt/f250/libexec/dashboard-stopped' ]]"
check "PCIe line on (NVMe HAT fitted)"   "has_line '$R/boot/config.txt' 'dtparam=pciex1' && ! has_line '$R/boot/config.txt' '#dtparam=pciex1'"
check "DATA_DRIVE off by default"      "has_line '$R/etc/default/f250' 'DATA_DRIVE=0'"
check "fstab untouched when off"       "! grep -q f250 '$R/etc/fstab'"
check "no mount when off"              "! grep -q 'var-lib-f250-storage' '$L'"
check "recorder-start installed"       "[[ -x '$R/opt/f250/libexec/recorder-start' ]]"
check "camera-start installed"         "[[ -x '$R/opt/f250/libexec/camera-start' && -f '$R/etc/systemd/system/f250-camera-manager.service' ]]"
check "navigation-start installed"     "[[ -x '$R/opt/f250/libexec/navigation-start' && -f '$R/etc/systemd/system/f250-navigation.service' ]]"
check "power-start and the backlight rule installed" "[[ -x '$R/opt/f250/libexec/power-start' && -f '$R/etc/udev/rules.d/60-f250-backlight.rules' ]]"
check "the backlight rule applied at once" "has_line '$L' 'udevadm trigger --subsystem-match=backlight --action=add'"
check "camera devices empty by default" "has_line '$R/etc/default/f250' 'CAMERA_FRONT=' && has_line '$R/etc/default/f250' 'CAMERA_LEFT=' && has_line '$R/etc/default/f250' 'CAMERA_RIGHT=' && has_line '$R/etc/default/f250' 'CAMERA_REAR='"
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
for b in vehicle-gateway recorder obd-console power-manager camera-manager camera-ctl navigation usb-export f250-can f250-storage; do printf '#!/bin/sh\n' >"$R/opt/f250/bin/$b"; chmod +x "$R/opt/f250/bin/$b"; done
for u in f250-gateway f250-recorder f250-power-manager f250-camera-manager f250-navigation f250-usb-export f250-dashboard f250-can-auto; do echo enabled >"$R/.test/unit-$u.service"; done
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
check "mounted: camera-manager's video directory" "has_line '$R7/.test/sys.log' 'install -d -o agl-driver -g f250 -m 0750 /var/lib/f250/storage/video'"
check "mounted: no second mount"       "! grep -q 'systemctl start var-lib' '$R7/.test/sys.log'"
for b in vehicle-gateway recorder obd-console power-manager camera-manager camera-ctl navigation usb-export f250-can f250-storage; do printf '#!/bin/sh\n' >"$R7/opt/f250/bin/$b"; chmod +x "$R7/opt/f250/bin/$b"; done
for u in kuksa-can-provider can-dev-helper; do echo masked >"$R7/.test/unit-$u.service"; done
for u in f250-gateway f250-recorder f250-power-manager f250-camera-manager f250-navigation f250-usb-export f250-dashboard f250-can-auto; do echo enabled >"$R7/.test/unit-$u.service"; done
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
check "CAN_AUTO_ACTIVE: passive until the interface is active" "[[ \"\$(gw TRANSPORT=can TRANSMIT=1 CAN_AUTO_ACTIVE=1 CAN_IF=f250-test-none)\" == '--listen unix:/run/f250/vehicle.sock --transport can --signals /opt/f250/share/data/signals --warnings /opt/f250/share/data/warning_rules.json --can-if f250-test-none --traffic-log /var/lib/f250/traffic --passive-reason the CAN adapter is absent, waiting to hear the truck'\\''s bus (CAN_AUTO_ACTIVE)' ]]"
# The interface's mode from a fake sysfs and f250-can's mode file: inside the
# unit's sandbox `ip` fails silently (bench-log 2026-11-10).
GS="$T/gw-sys"; mkdir -p "$GS/net/can0" "$GS/run"
gwm() { echo "$1" >"$GS/net/can0/operstate"; echo "$2" >"$GS/run/can0.mode"; shift 2
  env -i PATH="$PATH" F250_GATEWAY_BIN="$STUB" STATE_DIRECTORY=/var/lib/f250 F250_SYS_NET="$GS/net" F250_CAN_RUN="$GS/run" \
    TRANSPORT=can TRANSMIT=1 CAN_IF=can0 "$@" bash "$GW" 2>/dev/null; }
check "auto: transmits once f250-can recorded active" "[[ \"\$(gwm up active CAN_AUTO_ACTIVE=1)\" == *' --transmit'* ]]"
check "auto: passive while listen-only" "[[ \"\$(gwm up listen-only CAN_AUTO_ACTIVE=1)\" != *--transmit* ]]"
check "auto: says why on screen while passive" "[[ \"\$(gwm up listen-only CAN_AUTO_ACTIVE=1)\" == *\"--passive-reason the CAN adapter is listen-only, waiting to hear the truck's bus (CAN_AUTO_ACTIVE)\"* ]]"
check "TRANSMIT=0 by choice: no reason, no advisory" "[[ \"\$(gwm up active TRANSMIT=0)\" != *--passive-reason* ]]"
check "transmitting: no reason" "[[ \"\$(gwm up active CAN_AUTO_ACTIVE=1)\" != *--passive-reason* ]]"
check "auto: passive when down, whatever the file says" "[[ \"\$(gwm down active CAN_AUTO_ACTIVE=1)\" != *--transmit* ]]"
check "auto: passive when the mode is unknown" "[[ \"\$(gwm up '' CAN_AUTO_ACTIVE=1)\" != *--transmit* ]]"
check "by hand: refused while listen-only" "! gwm up listen-only >/dev/null"
check "by hand: transmits when active" "[[ \"\$(gwm up active)\" == *' --transmit'* ]]"
check "f250-can records the mode it set" "grep -q 'record_mode listen-only; else record_mode active' tools/pi/can.sh && grep -q 'record_mode down' tools/pi/can.sh"
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

echo "can-auto"
CA=agl/rootfs/opt/f250/libexec/can-auto
CT="$T/can-auto"; mkdir -p "$CT/net/can0"
# Stand-ins: ip prints the counters from files; f250-can sets the mode file.
cat >"$CT/ip" <<'STUB'
#!/bin/bash
d="$(dirname "$0")"; n=$(( $(cat "$d/packets") ))
[[ -f "$d/grow" ]] && echo $(( n + $(cat "$d/grow") )) >"$d/packets"
lo=""; [[ "$(cat "$d/mode")" == listen ]] && lo="<LISTEN-ONLY> "
printf '3: can0: <UP> mtu 16 state UP\n    can %sstate %s (berr-counter tx 0 rx %s) restart-ms 0\n    RX:  bytes packets errors\n        0 %s 0\n' "$lo" "$(cat "$d/state")" "$(cat "$d/rxerr")" "$n"
STUB
cat >"$CT/f250-can" <<'STUB'
#!/bin/bash
set -u; : "$HOME" "$DATA_DIR"   # as tools/pi/can.sh needs them
d="$(dirname "$0")"; echo "$1" >>"$d/calls"
case "$1" in listen) echo listen >"$d/mode" ;; active) [[ "${YES:-}" == 1 ]] && echo active >"$d/mode" ;; esac
STUB
cat >"$CT/systemctl" <<'STUB'
#!/bin/bash
d="$(dirname "$0")"; echo "$@" >>"$d/systemctl.log"
[[ "$1" == show ]] && echo 4242
true
STUB
mkdir -p "$CT/proc/4242"
gwcmd() { printf '%s\0' /opt/f250/bin/vehicle-gateway --transport can "$@" >"$CT/proc/4242/cmdline"; }
gwcmd --transmit
chmod +x "$CT/ip" "$CT/f250-can" "$CT/systemctl"
ca() { : >"$CT/calls"; : >"$CT/systemctl.log"; echo down >"$CT/mode"
  env -i PATH="$PATH" F250_IP="$CT/ip" F250_CAN_BIN="$CT/f250-can" F250_SYSTEMCTL="$CT/systemctl" \
    F250_SYS_NET="$CT/net" F250_PROC="$CT/proc" F250_SETTLE_S=0 F250_POLL_S=0 CAN_AUTO_ONCE=1 CAN_AUTO_LISTEN_S=0 CAN_AUTO_MIN_FRAMES=100 \
    STATE_DIRECTORY="$CT/state" "$@" bash "$CA" >"$CT/out" 2>&1 && echo 0 >"$CT/rc" || echo $? >"$CT/rc"; }
echo 0 >"$CT/packets"; echo ERROR-ACTIVE >"$CT/state"; echo 0 >"$CT/rxerr"; echo 500 >"$CT/grow"
ca
check "off unless CAN_AUTO_ACTIVE=1: CAN untouched" "[[ \$(cat $CT/rc) == 0 && ! -s $CT/calls && \$(cat $CT/mode) == down ]]"
ca CAN_AUTO_ACTIVE=1
check "a clean listen: listen-only first, then active" "[[ \$(cat $CT/rc) == 0 && \"\$(paste -sd' ' $CT/calls)\" == 'listen active' && \$(cat $CT/mode) == active ]]"
check "then the gateway restarts" "grep -qx 'restart f250-gateway.service' $CT/systemctl.log"
check "and is confirmed polling" "grep -q 'the gateway is polling (--transmit)' $CT/out && [[ \$(grep -c '^restart' $CT/systemctl.log) == 1 ]]"
gwcmd
ca CAN_AUTO_ACTIVE=1
check "a gateway that won't poll: 3 restarts, then an error" "[[ \$(grep -c '^restart' $CT/systemctl.log) == 3 ]] && grep -q '^<3>\[can-auto\] ERROR: can0 is active but the gateway won.t poll' $CT/out"
gwcmd --transmit
echo 0 >"$CT/grow"
ca CAN_AUTO_ACTIVE=1
check "no frames (no bus): stays listen-only" "[[ \$(cat $CT/rc) == 3 && \$(cat $CT/mode) == listen && ! -s $CT/systemctl.log ]] && grep -q 'not clean: 0 frames' $CT/out"
echo 500 >"$CT/grow"; echo 7 >"$CT/rxerr"
ca CAN_AUTO_ACTIVE=1
check "errors (a wrong bitrate): stays listen-only" "[[ \$(cat $CT/rc) == 3 && \$(cat $CT/mode) == listen ]]"
echo 0 >"$CT/rxerr"; echo ERROR-PASSIVE >"$CT/state"
ca CAN_AUTO_ACTIVE=1
check "error-passive: stays listen-only" "[[ \$(cat $CT/rc) == 3 && \$(cat $CT/mode) == listen ]]"
echo ERROR-ACTIVE >"$CT/state"; rmdir "$CT/net/can0"
ca CAN_AUTO_ACTIVE=1
check "no adapter: waits, touches nothing" "[[ \$(cat $CT/rc) == 3 && ! -s $CT/calls ]]"
mkdir -p "$CT/net/can0"
ca CAN_AUTO_ACTIVE=1 CAN_AUTO_CAPTURE=1
check "capture asked for: says where" "grep -q 'capturing every frame to $CT/state/captures/' $CT/out"
check "off by default in /etc/default/f250" "has_line agl/rootfs/etc/default/f250 'CAN_AUTO_ACTIVE=0' && has_line agl/rootfs/etc/default/f250 'CAN_AUTO_CAPTURE=0'"
CU=agl/rootfs/etc/systemd/system/f250-can-auto.service
check "can-auto unit: root, settings file, the script" "grep -qx 'EnvironmentFile=-/etc/default/f250' $CU && grep -qx 'ExecStart=/opt/f250/libexec/can-auto' $CU && ! grep -q '^User=' $CU && [[ -x $CA ]]"

echo "f250-can capture: bounded parts"
SP="$T/split"; mkdir -p "$SP"
awk 'BEGIN { for (i = 0; i < 2000; i++) printf "(%d.%06d) can0 201#00%04X00000080\n", 1000 + int(i / 100), (i % 100) * 10000, i }' >"$T/frames.in"
CAPTURE_PART_MB=0.01 CAPTURE_MAX_MB=0.03 bash tools/pi/can.sh split-frames "$SP" <"$T/frames.in" >/dev/null 2>&1 || fail "split-frames exited non-zero"
check "parts of at most CAPTURE_PART_MB, whole lines" "for f in $SP/candump-part-*.log; do [[ \$(wc -c <\"\$f\") -le 10485 ]] || exit 1; done && ! grep -qv '^([0-9.]*) can0 201#00[0-9A-F]\\{4\\}00000080\$' $SP/candump-part-*.log"
check "the kept parts are the newest frames, in order" "cat $SP/candump-part-*.log | cmp -s - <(tail -n \$(cat $SP/candump-part-*.log | wc -l) $T/frames.in)"
check "all parts together within CAPTURE_MAX_MB" "[[ \$(cat $SP/candump-part-*.log | wc -c) -le 31457 ]]"
check "each deleted part listed in pruned.txt" "[[ \$(wc -l <$SP/pruned.txt) -ge 1 ]] && ! ls $SP/candump-part-00000.log 2>/dev/null && grep -q 'candump-part-00000.log' $SP/pruned.txt"
check "split-frames refuses a missing folder" "! bash tools/pi/can.sh split-frames $T/nowhere </dev/null >/dev/null 2>&1"
check "capture: candump -L through the splitter, a free-space stop" "grep -q 'candump -L \"\$CAN_IF,0:0,#FFFFFFFF\" >.frames' tools/pi/can.sh && grep -q 'split_frames \"\$dir\" <.frames' tools/pi/can.sh && grep -q 'CAPTURE_MIN_FREE_MB' tools/pi/can.sh && ! grep -q 'candump -l ' tools/pi/can.sh"
check "capture bounds documented with their defaults" "grep -q '^CAPTURE_PART_MB=\"\${CAPTURE_PART_MB:-64}\"' tools/pi/can.sh && grep -q '^CAPTURE_MAX_MB=\"\${CAPTURE_MAX_MB:-2048}\"' tools/pi/can.sh && grep -q '^CAPTURE_MIN_FREE_MB=\"\${CAPTURE_MIN_FREE_MB:-1024}\"' tools/pi/can.sh && grep -q '^CAPTURE_MAX_MB=' agl/rootfs/etc/default/f250"

echo "power-start"
PSTUB="$T/power-manager"
printf '#!/bin/sh\necho "$@"\n' >"$PSTUB"; chmod +x "$PSTUB"
pm() { env -i PATH="$PATH" F250_POWER_BIN="$PSTUB" "$@" bash agl/rootfs/opt/f250/libexec/power-start 2>/dev/null; }
PBASE='--display-listen unix:/run/f250-power/power.sock --display-state /var/lib/f250-power/display'
check "nothing set: the boot window default, the display API" "[[ \"\$(pm)\" == \"--boot-key-ignore-s 30 $PBASE\" ]]"
check "empty display settings: none passed" "[[ \"\$(pm BOOT_KEY_IGNORE_S=30 CAMERA_MANAGER=unix:/run/f250-camera/camera.sock DISPLAY_LATITUDE= DISPLAY_LONGITUDE= DISPLAY_FALLBACK= DISPLAY_BACKLIGHT=)\" == \"--boot-key-ignore-s 30 --camera-manager unix:/run/f250-camera/camera.sock $PBASE\" ]]"
check "display settings passed as --name=value (negatives safe)" "[[ \"\$(pm DISPLAY_LATITUDE=39.74 DISPLAY_LONGITUDE=-104.99 DISPLAY_NIGHT_BELOW_DEG=-4 DISPLAY_HYSTERESIS_DEG=1 DISPLAY_FALLBACK=night DISPLAY_TRUST_CLOCK=always DISPLAY_MIN_BRIGHTNESS_PCT=15 DISPLAY_BACKLIGHT=10-0045)\" == \"--boot-key-ignore-s 30 $PBASE --latitude=39.74 --longitude=-104.99 --night-below-deg=-4 --hysteresis-deg=1 --fallback=night --trust-clock=always --min-brightness-pct=15 --backlight=10-0045\" ]]"
check "no camera-manager: moves only logged" "! pm CAMERA_MANAGER= | grep -q -- --camera-manager"
DF=agl/rootfs/etc/default/f250
check "display settings empty by default (no location shipped)" "has_line $DF 'DISPLAY_LATITUDE=' && has_line $DF 'DISPLAY_LONGITUDE=' && has_line $DF 'DISPLAY_TRUST_CLOCK=' && has_line $DF 'DISPLAY_MIN_BRIGHTNESS_PCT='"
check "the wrapper's options exist in power-manager" "for o in latitude longitude night_below_deg hysteresis_deg fallback trust_clock min_brightness_pct backlight display_listen display_state; do grep -q \"^    \$o: Option<\" services/power-manager/src/main.rs || exit 1; done"

echo "navigation-start"
NSTUB="$T/navigation"
printf '#!/bin/sh\necho "$@"\n' >"$NSTUB"; chmod +x "$NSTUB"
nav() { env -i PATH="$PATH" F250_NAV_BIN="$NSTUB" "$@" bash agl/rootfs/opt/f250/libexec/navigation-start 2>/dev/null; }
check "nothing set: gpsd on the loopback" "[[ \"\$(nav)\" == '--listen unix:/run/f250-nav/nav.sock --gpsd 127.0.0.1:2947' ]]"
check "the shipped settings: gpsd, defaults" "[[ \"\$(nav NAV_GPSD= NAV_SIMULATE=0 NAV_STALE_AFTER_MS=)\" == '--listen unix:/run/f250-nav/nav.sock --gpsd 127.0.0.1:2947' ]]"
check "another gpsd, a stale limit" "[[ \"\$(nav NAV_GPSD=127.0.0.1:2948 NAV_STALE_AFTER_MS=5000)\" == '--listen unix:/run/f250-nav/nav.sock --gpsd 127.0.0.1:2948 --stale-after-ms 5000' ]]"
check "simulated: no gpsd" "[[ \"\$(nav NAV_SIMULATE=1 NAV_GPSD=127.0.0.1:2948)\" == '--listen unix:/run/f250-nav/nav.sock --simulate' ]]"
check "routing: data and program elsewhere" "[[ \"\$(nav NAV_VALHALLA=/usr/local/bin/valhalla_service NAV_ROUTING_TILES=/x/t.tar)\" == '--listen unix:/run/f250-nav/nav.sock --gpsd 127.0.0.1:2947 --valhalla /usr/local/bin/valhalla_service --routing-tiles /x/t.tar' ]]"
check "routing: auto ignores truck sizes" "[[ \"\$(nav NAV_COSTING=auto NAV_TRUCK_HEIGHT_M=3)\" == '--listen unix:/run/f250-nav/nav.sock --gpsd 127.0.0.1:2947' ]]"
check "routing: truck with only the sizes set" "[[ \"\$(nav NAV_COSTING=truck NAV_TRUCK_HEIGHT_M=3.1 NAV_TRUCK_WIDTH_M= NAV_TRUCK_WEIGHT_T=4.5)\" == '--listen unix:/run/f250-nav/nav.sock --gpsd 127.0.0.1:2947 --costing truck --truck-height-m 3.1 --truck-weight-t 4.5' ]]"
check "routing: an unknown costing refuses to start" "! nav NAV_COSTING=bus"
check "search: data elsewhere" "[[ \"\$(nav NAV_SEARCH_INDEX=/x/s.sqlite)\" == '--listen unix:/run/f250-nav/nav.sock --gpsd 127.0.0.1:2947 --search-index /x/s.sqlite' ]]"
check "search: shipped empty, navigation's default the Pi's path" "has_line $DF 'NAV_SEARCH_INDEX=' && grep -q 'default_value = \"/var/lib/f250/storage/search/search.sqlite\"' services/navigation/src/main.rs"
check "navigation settings shipped, not simulated" "has_line $DF 'NAV_GPSD=' && has_line $DF 'NAV_SIMULATE=0' && has_line $DF 'NAV_STALE_AFTER_MS='"
check "routing settings shipped: auto, defaults" "has_line $DF 'NAV_COSTING=auto' && for k in VALHALLA ROUTING_TILES TRUCK_HEIGHT_M TRUCK_WIDTH_M TRUCK_LENGTH_M TRUCK_WEIGHT_T TRUCK_AXLE_LOAD_T; do has_line $DF \"NAV_\$k=\" || exit 1; done"
check "the shipped settings: still gpsd, defaults" "[[ \"\$(set -a; . $DF; set +a; F250_NAV_BIN=$NSTUB bash agl/rootfs/opt/f250/libexec/navigation-start 2>/dev/null)\" == '--listen unix:/run/f250-nav/nav.sock --gpsd 127.0.0.1:2947' ]]"
check "the wrapper's options exist in navigation" "for o in listen gpsd simulate stale_after_ms valhalla routing_tiles search_index costing truck_height_m truck_width_m truck_length_m truck_weight_t truck_axle_load_t; do grep -q \"^    \$o: \" services/navigation/src/main.rs || exit 1; done"
check "routing: navigation's defaults are the Pi's paths" "grep -q 'default_value = \"/var/lib/f250/storage/routing/valhalla_tiles.tar\"' services/navigation/src/main.rs && grep -q 'default_value = \"/opt/f250/share/data/valhalla/valhalla-3.9.1.json\"' services/navigation/src/main.rs && grep -q 'default_value = \"/run/f250-nav\"' services/navigation/src/main.rs"
check "routing: Valhalla's config deployed and built into the image" "grep -q 'services/navigation/valhalla/' tools/dev/deploy.sh && grep -q 'services/navigation/valhalla/valhalla-3.9.1.json' agl/meta-f250/recipes-f250/f250-services/f250-services.bb"

echo "camera-start"
CSTUB="$T/camera-manager"
printf '#!/bin/sh\necho "$@"\n' >"$CSTUB"; chmod +x "$CSTUB"
cam() { env -i PATH="$PATH" F250_CAMERA_BIN="$CSTUB" "$@" bash agl/rootfs/opt/f250/libexec/camera-start 2>/dev/null; }
check "no cameras: the socket and the settings file" "[[ \"\$(cam)\" == '--listen unix:/run/f250-camera/camera.sock --settings-file /var/lib/f250-camera/settings' ]]"
check "empty settings: no cameras" "[[ \"\$(cam CAMERA_FRONT= CAMERA_LEFT= CAMERA_RIGHT= CAMERA_REAR= CAMERA_CAPS=)\" == '--listen unix:/run/f250-camera/camera.sock --settings-file /var/lib/f250-camera/settings' ]]"
check "each camera named"   "[[ \"\$(cam CAMERA_REAR=/dev/video0 CAMERA_LEFT=/dev/v4l/by-path/usb-x-video-index0 CAMERA_FRONT=/dev/video2)\" == '--listen unix:/run/f250-camera/camera.sock --settings-file /var/lib/f250-camera/settings --camera front=/dev/video2 --camera left=/dev/v4l/by-path/usb-x-video-index0 --camera rear=/dev/video0' ]]"
check "caps passed as one argument" "[[ \"\$(env -i PATH=\"\$PATH\" F250_CAMERA_BIN=/bin/echo CAMERA_CAPS='video/x-raw,width=640 ! videoscale' bash agl/rootfs/opt/f250/libexec/camera-start 2>/dev/null)\" == '--listen unix:/run/f250-camera/camera.sock --settings-file /var/lib/f250-camera/settings --caps video/x-raw,width=640 ! videoscale' ]]"
check "no recording without the data drive" "[[ \"\$(cam CAMERA_FRONT=/dev/video0 CAMERA_REAR=/dev/video2 RECORD_CAMERAS=front,rear DATA_DRIVE=0)\" == '--listen unix:/run/f250-camera/camera.sock --settings-file /var/lib/f250-camera/settings --camera front=/dev/video0 --camera rear=/dev/video2' ]]"
check "records the cameras that have a device" "[[ \"\$(cam CAMERA_REAR=/dev/video2 RECORD_CAMERAS='front, rear' DATA_DRIVE=1)\" == '--listen unix:/run/f250-camera/camera.sock --settings-file /var/lib/f250-camera/settings --camera rear=/dev/video2 --recording-allowed --record-dir /var/lib/f250/storage/video --record-drive /var/lib/f250/storage --record rear' ]]"
check "records front and rear" "[[ \"\$(cam CAMERA_FRONT=/dev/video0 CAMERA_REAR=/dev/video2 RECORD_CAMERAS=front,rear DATA_DRIVE=1 CAMERA_MEDIA=gstreamer)\" == '--listen unix:/run/f250-camera/camera.sock --settings-file /var/lib/f250-camera/settings --camera front=/dev/video0 --camera rear=/dev/video2 --media gstreamer --recording-allowed --record-dir /var/lib/f250/storage/video --record-drive /var/lib/f250/storage --record front,rear' ]]"
check "left and right are never recorded" "! cam CAMERA_LEFT=/dev/video0 RECORD_CAMERAS=left DATA_DRIVE=1 >/dev/null"
DF=agl/rootfs/etc/default/f250
check "recording on by default for front and rear" "has_line $DF 'RECORD_CAMERAS=front,rear' && has_line $DF 'RECORD_MAX_GB=250' && has_line $DF 'RECORD_SYNC_S=1'"
check "a device with a space refused" "! cam 'CAMERA_REAR=/dev/video 0' >/dev/null"
check "data drive, no RECORD_CAMERAS: the screen may still turn recording on" "[[ \"\$(cam DATA_DRIVE=1 RECORD_CAMERAS=)\" == '--listen unix:/run/f250-camera/camera.sock --settings-file /var/lib/f250-camera/settings --recording-allowed --record-dir /var/lib/f250/storage/video --record-drive /var/lib/f250/storage' ]]"
check "camera-manager: a state directory for the screen's settings (ADR-0029)" "grep -qx 'StateDirectory=f250-camera' agl/rootfs/etc/systemd/system/f250-camera-manager.service && grep -q 'F250_CAMERA_SETTINGS:-/var/lib/f250-camera/settings' agl/rootfs/opt/f250/libexec/camera-start"
check "dashboard: preferences kept in its state directory (ADR-0029)" "grep -qx 'Environment=F250_SETTINGS_FILE=/var/lib/f250-dashboard/settings.json' agl/rootfs/etc/systemd/system/f250-dashboard.service && grep -qx 'StateDirectory=f250-dashboard' agl/rootfs/etc/systemd/system/f250-dashboard.service && grep -q \"F250_SETTINGS_FILE\" apps/infotainment/lib/core/settings_store_io.dart"
check "camera-start's options exist in camera-manager" "grep -q 'pub settings_file: Option<PathBuf>' services/camera-manager/src/config.rs && grep -q 'pub recording_allowed: bool' services/camera-manager/src/config.rs"

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
env -i PATH="$SB:$PATH" EXIT_CODE=exited EXIT_STATUS=0 bash "$STOPPED" >/dev/null
env -i PATH="$SB:$PATH" EXIT_CODE=killed EXIT_STATUS=42 bash "$STOPPED" >/dev/null
check "no power off or reboot on a crash or stop" "[[ ! -e '$T/poweroff.log' ]]"
env -i PATH="$SB:$PATH" EXIT_CODE=exited EXIT_STATUS=42 bash "$STOPPED" >/dev/null
check "power off on exit 42"  "has_line '$T/poweroff.log' 'systemctl poweroff --no-block' && ! grep -q reboot '$T/poweroff.log'"
rm -f "$T/poweroff.log"
env -i PATH="$SB:$PATH" EXIT_CODE=exited EXIT_STATUS=43 bash "$STOPPED" >/dev/null
check "reboot on exit 43"     "has_line '$T/poweroff.log' 'systemctl reboot --no-block' && ! grep -q poweroff '$T/poweroff.log'"

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
check "dashboard treats 42 and 43 as success" "grep -qx 'SuccessExitStatus=42 43' agl/rootfs/etc/systemd/system/f250-dashboard.service"
check "dashboard is bound to the compositor" "grep -qx 'BindsTo=agl-compositor.service' agl/rootfs/etc/systemd/system/f250-dashboard.service && grep -qx 'PartOf=agl-compositor.service' agl/rootfs/etc/systemd/system/f250-dashboard.service"
check "dashboard starts with the compositor" "grep -qx 'WantedBy=graphical.target agl-compositor.service' agl/rootfs/etc/systemd/system/f250-dashboard.service"
check "dashboard never restarts alone" "! grep -q '^Restart=' agl/rootfs/etc/systemd/system/f250-dashboard.service"
check "dashboard failure restarts the compositor" "grep -qx 'OnFailure=f250-dashboard-recover.service' agl/rootfs/etc/systemd/system/f250-dashboard.service && grep -qx 'ExecStart=/usr/bin/systemctl restart agl-compositor.service' agl/rootfs/etc/systemd/system/f250-dashboard-recover.service"
check "connman: ExecStart reset, then without its Bluetooth plugin" "in_order agl/rootfs/etc/systemd/system/connman.service.d/50-f250.conf 'ExecStart=' 'ExecStart=/usr/sbin/connmand -n --noplugin=bluetooth'"
check "compositor restarts after a crash" "grep -qx 'Restart=on-failure' agl/rootfs/etc/systemd/system/agl-compositor.service.d/50-f250.conf"
check "journal mount: SD card to the journal's place" "grep -qx 'What=/var/lib/journal' agl/rootfs/etc/systemd/system/var-volatile-log-journal.mount && grep -qx 'Where=/var/volatile/log/journal' agl/rootfs/etc/systemd/system/var-volatile-log-journal.mount && grep -qx 'Before=systemd-journal-flush.service' agl/rootfs/etc/systemd/system/var-volatile-log-journal.mount"
check "journal mount unit name matches Where=" "[[ \"\$(basename agl/rootfs/etc/systemd/system/var-volatile-log-journal.mount)\" == var-volatile-log-journal.mount ]] && grep -q '^JOURNAL_WHERE=/var/volatile/log/journal$' '$SETUP'"
check "journal is persistent and capped" "grep -qx 'Storage=persistent' agl/rootfs/etc/systemd/journald.conf.d/50-f250.conf && grep -qx 'SystemMaxUse=50M' agl/rootfs/etc/systemd/journald.conf.d/50-f250.conf"
check "power-off code matches the app" "grep -q 'const powerOffExitCode = 42;' apps/infotainment/lib/core/power.dart && grep -qx 'POWER_OFF_EXIT=42' '$STOPPED' && grep -qx 'POWER_OFF_EXIT=42' tools/pi/run.sh"
check "restart code matches the app" "grep -q 'const restartExitCode = 43;' apps/infotainment/lib/core/power.dart && grep -qx 'RESTART_EXIT=43' '$STOPPED' && grep -qx 'RESTART_EXIT=43' tools/pi/run.sh"
check "socket path matches the build"  "grep -q 'SOCK=/run/f250/vehicle.sock' tools/dev/deploy.sh && grep -q 'F250_SOCK:-/run/f250/vehicle.sock' '$REC' && grep -q 'F250_SOCK:-/run/f250/vehicle.sock' '$GW'"
check "recorder starts via its wrapper" "grep -qx 'ExecStart=/opt/f250/libexec/recorder-start' agl/rootfs/etc/systemd/system/f250-recorder.service"
check "services ordered after the drive" "grep -qx 'After=var-lib-f250-storage.mount' agl/rootfs/etc/systemd/system/f250-recorder.service && grep -qx 'After=var-lib-f250-storage.mount' agl/rootfs/etc/systemd/system/f250-gateway.service"
check "mount point agrees everywhere" "grep -q '^STORAGE=/var/lib/f250/storage$' '$SETUP' && grep -q 'F250_STORAGE:-/var/lib/f250/storage' '$GW' && grep -q 'F250_STORAGE:-/var/lib/f250/storage' '$REC' && grep -q '^STORAGE=/var/lib/f250/storage$' '$STORAGE_TOOL'"
check "drive label agrees"     "grep -q '^DRIVE_LABEL=f250-data$' '$SETUP' && grep -q '^LABEL=f250-data$' '$STORAGE_TOOL'"
# Sandbox (ADR-0021): each service has the settings measured on the bench.
U=agl/rootfs/etc/systemd/system
for unit in f250-gateway f250-recorder f250-power-manager f250-dashboard f250-camera-manager f250-navigation; do
  for line in 'NoNewPrivileges=yes' 'MemoryDenyWriteExecute=yes' 'CapabilityBoundingSet=' 'ProtectSystem=strict' 'PrivateTmp=yes' \
              'ProtectKernelModules=yes' 'ProtectKernelLogs=yes' \
              'ProtectControlGroups=yes' 'ProtectClock=yes' 'ProtectHostname=yes' 'ProtectProc=invisible' \
              'RestrictNamespaces=yes' 'RestrictSUIDSGID=yes' 'RestrictRealtime=yes' 'LockPersonality=yes' \
              'SystemCallArchitectures=native' 'SystemCallFilter=@system-service' \
              'SystemCallFilter=~@privileged @resources' 'IPAddressDeny=any'; do
    check "$unit: $line" "grep -qxF '$line' $U/$unit.service"
  done
  # power-manager writes the backlight in /sys (ADR-0028 decision 6).
  if [[ $unit != f250-power-manager ]]; then
    check "$unit: ProtectKernelTunables=yes" "grep -qxF 'ProtectKernelTunables=yes' $U/$unit.service"
  fi
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
check "power-manager: starts via its wrapper" "grep -qx 'ExecStart=/opt/f250/libexec/power-start' $PM && grep -qx 'EnvironmentFile=-/etc/default/f250' $PM"
check "power-manager: only the backlight in /sys (no ProtectKernelTunables, udev grants brightness)" "! grep -q '^ProtectKernelTunables=' $PM && grep -q 'chgrp f250 /sys%p/brightness' agl/rootfs/etc/udev/rules.d/60-f250-backlight.rules && grep -q 'chmod g+w /sys%p/brightness' agl/rootfs/etc/udev/rules.d/60-f250-backlight.rules && grep -q 'SUBSYSTEM==\"backlight\"' agl/rootfs/etc/udev/rules.d/60-f250-backlight.rules"
check "power-manager: display socket and settings directories (group f250)" "grep -qx 'RuntimeDirectory=f250-power' $PM && grep -qx 'StateDirectory=f250-power' $PM && grep -qx 'UMask=0007' $PM && grep -qx 'RuntimeDirectoryMode=0750' $PM && grep -q 'F250_POWER_SOCK:-/run/f250-power/power.sock' agl/rootfs/opt/f250/libexec/power-start && grep -q 'F250_POWER_STATE:-/var/lib/f250-power/display' agl/rootfs/opt/f250/libexec/power-start"
check "dashboard: power-manager's socket in deploy.sh and the image" "grep -q -- '-DPOWER=unix:/run/f250-power/power.sock' agl/meta-f250/recipes-f250/f250-dashboard/f250-dashboard.bb && grep -q -- '--dart-define=POWER=unix:\$POWER_SOCK' tools/dev/deploy.sh && grep -q '^POWER_SOCK=/run/f250-power/power.sock$' tools/dev/deploy.sh"
check "power-manager: switch moves go to camera-manager's socket (ADR-0026)" "grep -qx 'Environment=CAMERA_MANAGER=unix:/run/f250-camera/camera.sock' $PM"
check "power-manager: deployed and built into the image" "grep -q -- '-p power-manager' tools/dev/deploy.sh && grep -q '/target/release/power-manager' tools/dev/deploy.sh && grep -q -- '-p power-manager' agl/meta-f250/recipes-f250/f250-services/f250-services.bb && grep -q 'obd-console power-manager camera-manager camera-ctl navigation usb-export; do' agl/meta-f250/recipes-f250/f250-services/f250-services.bb"
NV=$U/f250-navigation.service
check "navigation: starts via its wrapper" "grep -qx 'ExecStart=/opt/f250/libexec/navigation-start' $NV && grep -qx 'EnvironmentFile=-/etc/default/f250' $NV"
check "navigation: f250, its socket directory (group f250)" "grep -qx 'User=f250' $NV && grep -qx 'Group=f250' $NV && grep -qx 'RuntimeDirectory=f250-nav' $NV && grep -qx 'UMask=0007' $NV && grep -qx 'RuntimeDirectoryMode=0750' $NV && grep -q 'F250_NAV_SOCK:-/run/f250-nav/nav.sock' agl/rootfs/opt/f250/libexec/navigation-start"
check "navigation: no devices; gpsd on the loopback only" "grep -qx 'PrivateDevices=yes' $NV && ! grep -q '^PrivateNetwork=' $NV && grep -qx 'RestrictAddressFamilies=AF_UNIX AF_INET AF_INET6' $NV && grep -qx 'IPAddressAllow=localhost' $NV"
check "navigation: pulls in gpsd's socket" "grep -qx 'Wants=gpsd.socket' $NV && grep -qx 'After=gpsd.socket gpsd.service' $NV"
check "navigation: watchdog" "grep -qx 'Type=notify' $NV && grep -qx 'WatchdogSec=30' $NV"
check "dashboard: navigation's socket, the map and its import status in deploy.sh and the image" "grep -q -- '-DNAV=unix:/run/f250-nav/nav.sock -DMAP_FILE=/var/lib/f250/storage/maps/map.pmtiles -DMAP_STATUS=/run/f250-maps/status.json' agl/meta-f250/recipes-f250/f250-dashboard/f250-dashboard.bb && grep -q -- '--dart-define=NAV=unix:\$NAV_SOCK --dart-define=MAP_FILE=\$MAP_FILE --dart-define=MAP_STATUS=\$MAP_STATUS' tools/dev/deploy.sh && grep -q '^NAV_SOCK=/run/f250-nav/nav.sock$' tools/dev/deploy.sh && grep -q '^MAP_FILE=/var/lib/f250/storage/maps/map.pmtiles$' tools/dev/deploy.sh && grep -q '^MAP_STATUS=/run/f250-maps/status.json$' tools/dev/deploy.sh"
check "navigation: deployed and built into the image" "grep -q -- '-p navigation' tools/dev/deploy.sh && grep -q '/target/release/navigation' tools/dev/deploy.sh && grep -q -- '-p navigation' agl/meta-f250/recipes-f250/f250-services/f250-services.bb && grep -q 'camera-ctl navigation usb-export; do' agl/meta-f250/recipes-f250/f250-services/f250-services.bb"
UX=$U/f250-usb-export.service
UXM=services/usb-export/src/main.rs
check "usb-export: root for mount(2), group f250 for the socket and the recordings (ADR-0037)" "grep -qx 'User=root' $UX && grep -qx 'Group=f250' $UX && grep -qx 'UMask=0007' $UX && grep -qx 'RuntimeDirectory=f250-export' $UX && grep -qx 'RuntimeDirectoryMode=0750' $UX"
check "usb-export: only CAP_SYS_ADMIN, mounts in its own namespace" "grep -qx 'CapabilityBoundingSet=CAP_SYS_ADMIN' $UX && grep -qx 'PrivateMounts=yes' $UX && grep -qx 'NoNewPrivileges=yes' $UX && grep -qx 'SystemCallFilter=@system-service @mount' $UX"
check "usb-export: writes only its runtime directory and the stick" "grep -qx 'ProtectSystem=strict' $UX && ! grep -q '^ReadWritePaths=' $UX && grep -qx 'ProtectHome=yes' $UX && grep -qx 'PrivateTmp=yes' $UX"
check "usb-export: USB sticks only, no network" "grep -qx 'DevicePolicy=closed' $UX && [[ \"\$(grep -c '^DeviceAllow=' $UX)\" == 1 ]] && grep -qx 'DeviceAllow=block-sd rw' $UX && grep -qx 'PrivateNetwork=yes' $UX && grep -qx 'RestrictAddressFamilies=AF_UNIX' $UX && grep -qx 'IPAddressDeny=any' $UX"
for line in 'MemoryDenyWriteExecute=yes' 'ProtectKernelTunables=yes' 'ProtectKernelModules=yes' 'ProtectKernelLogs=yes' 'ProtectControlGroups=yes' \
            'ProtectClock=yes' 'ProtectHostname=yes' 'ProtectProc=invisible' 'RestrictNamespaces=yes' 'RestrictSUIDSGID=yes' \
            'RestrictRealtime=yes' 'LockPersonality=yes' 'SystemCallArchitectures=native'; do
  check "usb-export: $line" "grep -qxF '$line' $UX"
done
check "usb-export: after the data drive, below recording's priority" "grep -q '^After=var-lib-f250-storage.mount' $UX && grep -qx 'Nice=10' $UX && grep -qx 'IOSchedulingPriority=7' $UX && grep -qx 'Type=notify' $UX"
check "usb-export: socket agrees with the dashboard in deploy.sh and the image" "grep -qx 'ExecStart=/opt/f250/bin/usb-export --listen unix:/run/f250-export/export.sock' $UX && grep -q '^EXPORT_SOCK=/run/f250-export/export.sock$' tools/dev/deploy.sh && grep -q -- '--dart-define=EXPORT=unix:\$EXPORT_SOCK' tools/dev/deploy.sh && grep -q -- '-DEXPORT=unix:/run/f250-export/export.sock' agl/meta-f250/recipes-f250/f250-dashboard/f250-dashboard.bb"
check "usb-export: recordings where camera-manager writes them" "grep -q 'default_value = \"/var/lib/f250/storage/video\"' $UXM && grep -q -- '--record-dir \"\$STORAGE/video\"' agl/rootfs/opt/f250/libexec/camera-start && grep -q 'F250_STORAGE:-/var/lib/f250/storage' agl/rootfs/opt/f250/libexec/camera-start"
check "usb-export: waits on the map import's lock, and knows a map stick by its files" "grep -q 'default_value = \"/run/f250-maps/import.lock\"' $UXM && grep -q 'LOCK=\"\$STATUS_DIR/import.lock\"' agl/rootfs/opt/f250/libexec/map-import && grep -q '\\[\"map.pmtiles\", \"routing.tar\", \"search.sqlite\"\\]' services/usb-export/src/exporter.rs && grep -q 'map) SRC_NAME=map.pmtiles' agl/rootfs/opt/f250/libexec/map-import && grep -q 'routing) SRC_NAME=routing.tar' agl/rootfs/opt/f250/libexec/map-import"
check "usb-export: deployed and built into the image" "grep -q -- '-p usb-export' tools/dev/deploy.sh && grep -q '/target/release/usb-export' tools/dev/deploy.sh && grep -q -- '-p usb-export' agl/meta-f250/recipes-f250/f250-services/f250-services.bb && grep -q 'navigation usb-export; do' agl/meta-f250/recipes-f250/f250-services/f250-services.bb"
check "usb-export: stage1 installs, enables and restarts it" "grep -q 'f250-usb-export.service f250-dashboard.service' '$SETUP' && grep -q 'camera-ctl navigation usb-export f250-can' '$SETUP'"
for p in gpsd gpsd-conf gpsd-udev; do
  check "navigation: the image has $p" "grep -qx '    $p \\\\' agl/meta-f250/recipes-platform/images/agl-f250-base.inc"
done
CM=$U/f250-camera-manager.service
check "camera-manager: starts via its wrapper" "grep -qx 'ExecStart=/opt/f250/libexec/camera-start' $CM"
check "camera-manager: power-manager's socket is camera-manager's" "grep -q 'F250_CAMERA_SOCK:-/run/f250-camera/camera.sock' agl/rootfs/opt/f250/libexec/camera-start && grep -qx 'RuntimeDirectory=f250-camera' $CM && grep -qx 'Environment=CAMERA_MANAGER=unix:/run/f250-camera/camera.sock' $PM"
check "camera-manager: agl-driver (Wayland), group f250 (the socket), video" "grep -qx 'User=agl-driver' $CM && grep -qx 'Group=f250' $CM && grep -qx 'SupplementaryGroups=video' $CM && grep -qx 'UMask=0007' $CM && grep -qx 'RuntimeDirectoryMode=0750' $CM"
check "camera-manager: the compositor's Wayland socket" "grep -qx 'Environment=XDG_RUNTIME_DIR=/run/user/1001' $CM && grep -qx 'Environment=WAYLAND_DISPLAY=wayland-0' $CM && grep -qx 'ProtectHome=read-only' $CM && grep -qx 'After=agl-compositor.service' $CM"
check "camera-manager: not bound to the compositor (it retries)" "! grep -q '^BindsTo=' $CM && ! grep -q '^PartOf=' $CM && grep -qx 'Restart=on-failure' $CM"
check "camera-manager: reaches only cameras" "grep -qx 'DevicePolicy=closed' $CM && [[ \"\$(grep -c '^DeviceAllow=' $CM)\" == 1 ]] && grep -qx 'DeviceAllow=char-video4linux rw' $CM"
check "camera-manager: no network" "grep -qx 'PrivateNetwork=yes' $CM && grep -qx 'RestrictAddressFamilies=AF_UNIX' $CM"
check "camera-manager: GStreamer's registry in its cache" "grep -qx 'CacheDirectory=f250-camera' $CM && grep -qx 'Environment=XDG_CACHE_HOME=/var/cache/f250-camera' $CM"
check "camera-manager: writes only the recordings, after the drive mounts" "[[ \"\$(grep '^ReadWritePaths=' $CM)\" == 'ReadWritePaths=-/var/lib/f250/storage/video' ]] && grep -qx 'After=var-lib-f250-storage.mount' $CM"
check "camera-manager: watchdog" "grep -qx 'Type=notify' $CM && grep -qx 'WatchdogSec=30' $CM"
check "camera-manager: stops its own pipeline, never a 90 s hang" "grep -qx 'KillMode=mixed' $CM && grep -qx 'TimeoutStopSec=10' $CM"
check "camera-manager: deploy builds it with GStreamer" "grep -q -- '-p camera-manager --features gstreamer' tools/dev/deploy.sh && grep -q 'libgstreamer1.0-dev' tools/dev/docker/arm64-build.Dockerfile"
check "camera-manager: deployed and built into the image" "grep -q -- '-p camera-manager' tools/dev/deploy.sh && grep -q '/target/release/camera-manager' tools/dev/deploy.sh && grep -q -- '-p camera-manager' agl/meta-f250/recipes-f250/f250-services/f250-services.bb && grep -q 'power-manager camera-manager camera-ctl navigation usb-export; do' agl/meta-f250/recipes-f250/f250-services/f250-services.bb && grep -q '/target/release/camera-ctl' tools/dev/deploy.sh"
check "camera-manager: the image has gst-launch-1.0 (gstreamer1.0)" "grep -qx '    gstreamer1.0 \\\\' agl/meta-f250/recipes-platform/images/agl-f250-base.inc"
check "camera-manager: the image can record (matroska, multifile)" "grep -qx '    gstreamer1.0-plugins-good-matroska \\\\' agl/meta-f250/recipes-platform/images/agl-f250-base.inc && grep -qx '    gstreamer1.0-plugins-good-multifile \\\\' agl/meta-f250/recipes-platform/images/agl-f250-base.inc"
check "camera-manager: the recipe links GStreamer" "grep -q '^DEPENDS += \"gstreamer1.0 glib-2.0\"' agl/meta-f250/recipes-f250/f250-services/f250-services.bb"
# The camera window's area (ADR-0009) must match the dashboard's camera mode:
# right of the button column, below the status bar (where alerts show), and
# one row short of the bottom: the compositor ignores an area that reaches it
# (config.toml says more).
th=apps/infotainment/lib/ui/theme.dart
sb="$(sed -n 's/^const kStatusBarHeight = \([0-9]*\)\.0;$/\1/p' $th)"
cw="$(sed -n 's/^const kCameraControlsWidth = \([0-9]*\)\.0;$/\1/p' $th)"
check "activation area: theme constants read" "[[ -n '$sb' && -n '$cw' ]]"
sed -n '/^\[window_activation_area\]$/,$p' agl/flutter/config.toml | grep -v '^#' >"$T/area.toml"
check "activation area right of the camera buttons, below the status bar" "in_order '$T/area.toml' '[window_activation_area]' 'x = $cw' 'y = $sb' 'width = $((800 - cw))' 'height = $((480 - sb - 1))'"
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
check "units stage1 enables have [Install]" "for u in f250-gateway f250-recorder f250-power-manager f250-camera-manager f250-navigation f250-usb-export f250-dashboard f250-can-auto; do grep -q '^WantedBy=' agl/rootfs/etc/systemd/system/\$u.service || exit 1; done"
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
for p in f250-system f250-services f250-dashboard valhalla weston-ini-conf-flutter bluez5 avahi-daemon rsync \
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
for pair in candump:can-utils lsusb:usbutils mkfs.ext4:e2fsprogs-mke2fs blkid:util-linux-blkid lsblk:util-linux-lsblk findmnt:util-linux-findmnt ip:iproute2 cmp:diffutils sfdisk:util-linux-sfdisk partx:util-linux-partx systemd-growfs:systemd mount:util-linux-mount umount:util-linux-umount modprobe:kmod sha256sum:coreutils exfat:kernel-module-exfat; do
  cmd=${pair%%:*}; pkg=${pair#*:}
  check "f250-system pulls in $pkg ($cmd)" "grep -A4 '^RDEPENDS' '$SYSBB' | grep -qw '$pkg'"
done
check "services: the binaries deploy.sh builds" "grep -q -- '-p vehicle-gateway -p recorder -p obd-console -p power-manager -p camera-manager -p navigation -p usb-export --features vehicle-gateway/rfcomm,camera-manager/gstreamer' $M/recipes-f250/f250-services/f250-services.bb && grep -q -- '-p vehicle-gateway --features rfcomm' tools/dev/deploy.sh"
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

echo "valhalla recipe (ADR-0035)"
VB=$M/recipes-navigation/valhalla/valhalla_3.9.1.bb
check "valhalla: tag 3.9.1's commit, with its submodules" "grep -q '^SRC_URI = \"gitsm://github.com/valhalla/valhalla.git;protocol=https;nobranch=1' $VB && grep -qx 'SRCREV = \"bafb69902220615a48307d5c790fb6c943802ba4\"' $VB"
for o in ENABLE_TOOLS=ON ENABLE_DATA_TOOLS=OFF ENABLE_SERVICES=OFF ENABLE_HTTP=OFF ENABLE_PYTHON_BINDINGS=OFF \
         ENABLE_NODE_BINDINGS=OFF ENABLE_TESTS=OFF ENABLE_GEOTIFF=OFF ENABLE_LZ4=OFF BUILD_SHARED_LIBS=OFF; do
  check "valhalla: -D$o" "grep -qx '    -D$o \\\\' $VB"
done
check "valhalla: protoc from the build host" "grep -q 'protobuf-native' $VB && grep -q 'CMAKE_PROJECT_valhalla_INCLUDE=\${UNPACKDIR}/protoc-native.cmake' $VB && grep -q 'add_executable(protobuf::protoc IMPORTED)' $M/recipes-navigation/valhalla/files/protoc-native.cmake"
check "valhalla: only valhalla_service is packaged" "grep -qx 'FILES:\${PN} = \"\${bindir}/valhalla_service\"' $VB"
check "valhalla: navigation looks for it on PATH" "grep -q 'default_value = \"valhalla_service\"' services/navigation/src/main.rs"
check "valhalla: the config template is 3.9.1's" "[[ -f services/navigation/valhalla/valhalla-3.9.1.json ]] && [[ \"\$(basename $VB)\" == valhalla_3.9.1.bb ]]"

echo "map-import (ADR-0033)"
MI=agl/rootfs/opt/f250/libexec/map-import
FIX=apps/infotainment/test/fixtures/maps/vector-z12-15.pmtiles
OLD=apps/infotainment/test/fixtures/maps/solid-z0-3.pmtiles
mi() {   # mi <test dir> <args...>: map-import against <test dir>/storage and <test dir>/run
  local d="$1"; shift
  F250_STORAGE="$d/storage" F250_MAP_STATUS_DIR="$d/run" F250_MAP_REQUIRE_MOUNT="${MI_REQUIRE:-0}" \
    F250_SYS_LOG="$d/sys.log" bash "$MI" "$@"
}
new_case() {   # new_case <name>: a test dir with an old map installed
  local d="$T/mi-$1"
  mkdir -p "$d/storage/maps" "$d/stick"
  cp "$OLD" "$d/storage/maps/map.pmtiles"
  echo "$d"
}
state_of() { sed -n 's/^{"state":"\([a-z]*\)".*/\1/p' "$1/run/status.json" 2>/dev/null; }
D="$(new_case ok)"
python3 tools/maps/map-stick.py --map "$FIX" --stick "$D/stick" --any-dir >/dev/null 2>&1 || fail "map-stick wrote no stick"
check "map-stick writes the map and its checksum" "cmp -s '$FIX' '$D/stick/f250/map.pmtiles' && grep -qE '^[0-9a-f]{64}  map.pmtiles\$' '$D/stick/f250/map.pmtiles.sha256'"
echo stale >"$D/storage/maps/map.pmtiles.part"
chmod 0755 "$D/stick/f250/map.pmtiles"   # as an exFAT stick shows it on the Pi
rc=0; mi "$D" dir "$D/stick" >"$D/out" 2>&1 || rc=$?
check "a map stick is imported"        "[[ $rc == 0 ]] && cmp -s '$FIX' '$D/storage/maps/map.pmtiles'"
check "status: updated, with an id"    "[[ \"\$(state_of '$D')\" == updated ]] && grep -q '\"id\":\"[0-9TZ-]*\"' '$D/run/status.json'"
check "no copy or lock left behind"    "[[ ! -e '$D/storage/maps/map.pmtiles.part' && ! -e '$D/run/import.lock' ]]"
check "the installed map isn't executable" "[[ \"\$(ls -l '$D/storage/maps/map.pmtiles' | cut -c1-10)\" == -rw-r--r-- ]]"
check "the installed map's checksum is kept" "[[ \"\$(cat '$D/storage/maps/map.pmtiles.sha256')\" == \"\$(cut -c1-64 '$D/stick/f250/map.pmtiles.sha256')\" ]]"
INODE="$(ls -i "$D/storage/maps/map.pmtiles" | awk '{print $1}')"
rc=0; mi "$D" dir "$D/stick" >/dev/null 2>&1 || rc=$?
check "the same stick again: current, nothing copied" "[[ $rc == 0 && \"\$(state_of '$D')\" == current && \"\$(ls -i '$D/storage/maps/map.pmtiles' | awk '{print \$1}')\" == '$INODE' ]] && grep -qF 'already installed' '$D/run/status.json'"
cp "$OLD" "$D/stick/f250/map.pmtiles"
(cd "$D/stick/f250" && (shasum -a 256 map.pmtiles 2>/dev/null || sha256sum map.pmtiles) >map.pmtiles.sha256)
rc=0; mi "$D" dir "$D/stick" >/dev/null 2>&1 || rc=$?
check "a different map on the stick is copied" "[[ $rc == 0 && \"\$(state_of '$D')\" == updated ]] && cmp -s '$OLD' '$D/storage/maps/map.pmtiles'"
check "map-stick refuses a file that isn't a map" "! python3 tools/maps/map-stick.py --map Makefile --stick '$D/stick' --any-dir 2>/dev/null"
check "map-stick refuses a folder that isn't a volume" "! python3 tools/maps/map-stick.py --map '$FIX' --stick '$D/stick' 2>/dev/null"

D="$(new_case other)"; mkdir -p "$D/stick/music"
rc=0; mi "$D" dir "$D/stick" >/dev/null 2>&1 || rc=$?
check "another stick is left alone, silently" "[[ $rc == 0 && ! -e '$D/run/status.json' ]] && cmp -s '$OLD' '$D/storage/maps/map.pmtiles'"

failing_case() {   # failing_case <name> <expected message part> <prepare commands>
  local d; d="$(new_case "$1")"
  mkdir -p "$d/stick/f250"
  ( cd "$d/stick/f250" && eval "$3" ) || true
  mi "$d" dir "$d/stick" >/dev/null 2>&1 && fail "$1: exited 0"
  check "$1: failed, saying so"          "[[ \"\$(state_of '$d')\" == failed ]] && grep -qF -- '$2' '$d/run/status.json'"
  check "$1: the old map is kept"        "cmp -s '$OLD' '$d/storage/maps/map.pmtiles' && [[ ! -e '$d/storage/maps/map.pmtiles.part' ]]"
}
failing_case "no checksum" "no map.pmtiles.sha256" "cp '$PWD/$FIX' map.pmtiles"
failing_case "a malformed checksum" "a SHA-256 checksum" "cp '$PWD/$FIX' map.pmtiles; echo nope >map.pmtiles.sha256"
failing_case "a wrong checksum" "match its checksum" "cp '$PWD/$FIX' map.pmtiles; printf '%064d  map.pmtiles\n' 0 >map.pmtiles.sha256"
failing_case "not a map" "a PMTiles file" "echo hello >map.pmtiles; (shasum -a 256 map.pmtiles 2>/dev/null || sha256sum map.pmtiles) >map.pmtiles.sha256"
D="$(new_case unmounted)"
python3 tools/maps/map-stick.py --map "$FIX" --stick "$D/stick" --any-dir >/dev/null 2>&1 || true
MI_REQUIRE=1 mi "$D" dir "$D/stick" >/dev/null 2>&1 && fail "no data drive: exited 0"
check "no data drive: refused, the old map kept" "grep -qF \"data drive isn't mounted\" '$D/run/status.json' && cmp -s '$OLD' '$D/storage/maps/map.pmtiles'"

D="$(new_case locked)"
python3 tools/maps/map-stick.py --map "$FIX" --stick "$D/stick" --any-dir >/dev/null 2>&1 || true
mkdir -p "$D/run/import.lock"
mi "$D" dir "$D/stick" >/dev/null 2>&1 && fail "a second import at once: exited 0"
check "a second import at once is refused" "cmp -s '$OLD' '$D/storage/maps/map.pmtiles' && [[ -d '$D/run/import.lock' ]]"

D="$(new_case device)"
mkdir -p "$D/run/stick-sda1"
python3 tools/maps/map-stick.py --map "$FIX" --stick "$D/run/stick-sda1" --any-dir >/dev/null 2>&1 || true
mi "$D" device /dev/sda1 >/dev/null 2>&1 || fail "device: exited non-zero"
check "device: mounts the stick read-only, noexec" "in_order '$D/sys.log' 'mount -t exfat,vfat -o ro,nosuid,nodev,noexec /dev/sda1 $D/run/stick-sda1' 'umount $D/run/stick-sda1'"
check "device: imports it, naming the device" "cmp -s '$FIX' '$D/storage/maps/map.pmtiles' && grep -qF '\"device\":\"/dev/sda1\"' '$D/run/status.json'"
check "device: refuses a path that isn't a device" "! mi '$D' device /tmp/x 2>/dev/null"

D="$(new_case pulled)"; mkdir -p "$D/run"
printf '{"state":"copying","percent":40,"message":"","id":"x","device":"/dev/sdb1","at":"2026-11-11T00:00:00Z"}\n' >"$D/run/status.json"
echo partial >"$D/storage/maps/map.pmtiles.part"
mi "$D" stopped /dev/sda1 >/dev/null 2>&1 || true
check "stopped: another stick's import is left alone" "[[ \"\$(state_of '$D')\" == copying && -e '$D/storage/maps/map.pmtiles.part' ]]"
mi "$D" stopped /dev/sdb1 >/dev/null 2>&1 || true
check "stopped: a pulled stick's import fails, the copy goes" "[[ \"\$(state_of '$D')\" == failed && ! -e '$D/storage/maps/map.pmtiles.part' ]] && grep -qF 'stick was removed' '$D/run/status.json' && grep -qF '\"id\":\"x\"' '$D/run/status.json'"
check "stopped: the old map is kept"   "cmp -s '$OLD' '$D/storage/maps/map.pmtiles'"

# Routing data on the stick (ADR-0033 amendment): a small tile extract as
# valhalla_build_extract writes one, index.bin first.
mk_tar() {   # mk_tar <out> <name>...: a ustar file of small members, owned by root
  python3 -I - "$@" <<'PY'
import io, sys, tarfile
with tarfile.open(sys.argv[1], "w", format=tarfile.USTAR_FORMAT) as t:
    for name in sys.argv[2:]:
        data = name.encode()
        info = tarfile.TarInfo(name); info.size = len(data)
        t.addfile(info, io.BytesIO(data))
PY
}
mk_tar "$T/routing.tar" index.bin 0/002/809.gph
mk_tar "$T/not-extract.tar" 0/002/809.gph
mk_tar "$T/routing-old.tar" index.bin 0/002/810.gph
RTS=routing/valhalla_tiles.tar
D="$(new_case routing)"
python3 tools/maps/map-stick.py --map "$FIX" --routing "$T/routing.tar" --stick "$D/stick" --any-dir >/dev/null 2>&1 || fail "map-stick wrote no map and routing stick"
check "map-stick writes routing data and its checksum" "cmp -s '$T/routing.tar' '$D/stick/f250/routing.tar' && grep -qE '^[0-9a-f]{64}  routing.tar\$' '$D/stick/f250/routing.tar.sha256'"
chmod 0755 "$D/stick/f250/routing.tar"
rc=0; mi "$D" dir "$D/stick" >/dev/null 2>&1 || rc=$?
check "map and routing data are imported" "[[ $rc == 0 ]] && cmp -s '$FIX' '$D/storage/maps/map.pmtiles' && cmp -s '$T/routing.tar' '$D/storage/$RTS'"
check "status: both changed, in one import" "[[ \"\$(state_of '$D')\" == updated ]] && grep -qF '\"changed\":[\"map\",\"routing\"]' '$D/run/status.json' && grep -qF 'Map and routing data updated.' '$D/run/status.json'"
check "routing data isn't executable, its checksum kept" "[[ \"\$(ls -l '$D/storage/$RTS' | cut -c1-10)\" == -rw-r--r-- && \"\$(cat '$D/storage/$RTS.sha256')\" == \"\$(cut -c1-64 '$D/stick/f250/routing.tar.sha256')\" && ! -e '$D/storage/$RTS.part' ]]"
rc=0; mi "$D" dir "$D/stick" >/dev/null 2>&1 || rc=$?
check "the same stick again: both current" "[[ $rc == 0 && \"\$(state_of '$D')\" == current ]] && grep -qF 'The map and routing data on this stick are already installed.' '$D/run/status.json' && grep -qF '\"changed\":[]' '$D/run/status.json'"
D="$(new_case routing-only)"
python3 tools/maps/map-stick.py --routing "$T/routing.tar" --stick "$D/stick" --any-dir >/dev/null 2>&1 || fail "map-stick wrote no routing stick"
rc=0; mi "$D" dir "$D/stick" >/dev/null 2>&1 || rc=$?
check "routing data alone: imported, the map untouched" "[[ $rc == 0 ]] && cmp -s '$T/routing.tar' '$D/storage/$RTS' && cmp -s '$OLD' '$D/storage/maps/map.pmtiles'"
check "routing data alone: changed names only routing" "grep -qF '\"changed\":[\"routing\"]' '$D/run/status.json' && grep -qF '\"item\":\"routing\"' '$D/run/status.json' && grep -qF 'Routing data updated.' '$D/run/status.json'"
check "map-stick needs --map, --routing or --search" "! python3 tools/maps/map-stick.py --stick '$D/stick' --any-dir 2>/dev/null"
check "map-stick refuses routing data that isn't a tile extract" "! python3 tools/maps/map-stick.py --routing '$T/not-extract.tar' --stick '$D/stick' --any-dir 2>/dev/null && ! python3 tools/maps/map-stick.py --routing '$FIX' --stick '$D/stick' --any-dir 2>/dev/null"
routing_failing() {   # routing_failing <name> <expected message part> <prepare commands>
  local d; d="$(new_case "r-$1")"
  mkdir -p "$d/stick/f250" "$d/storage/routing"
  cp "$T/routing-old.tar" "$d/storage/$RTS"
  ( cd "$d/stick/f250" && eval "$3" ) || true
  mi "$d" dir "$d/stick" >/dev/null 2>&1 && fail "routing $1: exited 0"
  check "routing $1: failed, saying so" "[[ \"\$(state_of '$d')\" == failed ]] && grep -qF -- '$2' '$d/run/status.json' && grep -qF '\"item\":\"routing\"' '$d/run/status.json'"
  check "routing $1: the old routing data is kept" "cmp -s '$T/routing-old.tar' '$d/storage/$RTS' && [[ ! -e '$d/storage/$RTS.part' ]]"
}
routing_failing "no checksum" "no routing.tar.sha256" "cp '$T/not-extract.tar' routing.tar"
routing_failing "a wrong checksum" "match its checksum" "cp '$T/routing.tar' routing.tar; printf '%064d  routing.tar\n' 0 >routing.tar.sha256"
routing_failing "not an extract" "no index.bin first" "cp '$T/not-extract.tar' routing.tar; (shasum -a 256 routing.tar 2>/dev/null || sha256sum routing.tar) >routing.tar.sha256"
routing_failing "not a tar" "a tar file" "cp '$PWD/$FIX' routing.tar; (shasum -a 256 routing.tar 2>/dev/null || sha256sum routing.tar) >routing.tar.sha256"
D="$(new_case map-then-bad-routing)"; mkdir -p "$D/stick/f250"
python3 tools/maps/map-stick.py --map "$FIX" --stick "$D/stick" --any-dir >/dev/null 2>&1 || true
cp "$T/routing.tar" "$D/stick/f250/routing.tar"; printf '%064d  routing.tar\n' 0 >"$D/stick/f250/routing.tar.sha256"
mi "$D" dir "$D/stick" >/dev/null 2>&1 && fail "map then bad routing data: exited 0"
check "map then bad routing data: the new map stays, and the status says so" "cmp -s '$FIX' '$D/storage/maps/map.pmtiles' && [[ \"\$(state_of '$D')\" == failed ]] && grep -qF '\"changed\":[\"map\"]' '$D/run/status.json' && grep -qF 'The map was updated.' '$D/run/status.json' && [[ ! -e '$D/storage/$RTS' ]]"
D="$(new_case r-pulled)"; mkdir -p "$D/run" "$D/storage/routing"
printf '{"state":"copying","percent":40,"message":"","id":"y","device":"/dev/sdc1","item":"routing","changed":["map"],"at":"2026-11-11T00:00:00Z"}\n' >"$D/run/status.json"
echo partial >"$D/storage/$RTS.part"
mi "$D" stopped /dev/sdc1 >/dev/null 2>&1 || true
check "stopped while copying routing data: failed, that copy goes" "[[ \"\$(state_of '$D')\" == failed && ! -e '$D/storage/$RTS.part' ]] && grep -qF 'before the routing data was copied' '$D/run/status.json'"
echo "map-import: search data (ADR-0038)"
mk_search() {   # mk_search <file> [application id]: a SQLite file as make search-region writes one
  python3 - "$1" "${2:-1177695536}" <<'PY'
import sqlite3, sys
c = sqlite3.connect(sys.argv[1])
c.execute(f"PRAGMA application_id = {int(sys.argv[2])}")
c.execute("CREATE TABLE t(x)")
c.commit()
c.close()
PY
}
mk_search "$T/search.sqlite"
mk_search "$T/search-old.sqlite"; python3 -c "import sqlite3,sys; c=sqlite3.connect(sys.argv[1]); c.execute('CREATE TABLE old(y)'); c.commit()" "$T/search-old.sqlite"
mk_search "$T/not-search.sqlite" 7
SRS=search/search.sqlite
D="$(new_case all-three)"
python3 tools/maps/map-stick.py --map "$FIX" --routing "$T/routing.tar" --search "$T/search.sqlite" --stick "$D/stick" --any-dir >/dev/null 2>&1 || fail "map-stick wrote no three-item stick"
check "map-stick writes search data and its checksum" "cmp -s '$T/search.sqlite' '$D/stick/f250/search.sqlite' && grep -qE '^[0-9a-f]{64}  search.sqlite\$' '$D/stick/f250/search.sqlite.sha256'"
chmod 0755 "$D/stick/f250/search.sqlite"
rc=0; mi "$D" dir "$D/stick" >/dev/null 2>&1 || rc=$?
check "map, routing and search data are imported" "[[ $rc == 0 ]] && cmp -s '$FIX' '$D/storage/maps/map.pmtiles' && cmp -s '$T/routing.tar' '$D/storage/$RTS' && cmp -s '$T/search.sqlite' '$D/storage/$SRS'"
check "status: all three changed" "[[ \"\$(state_of '$D')\" == updated ]] && grep -qF '\"changed\":[\"map\",\"routing\",\"search\"]' '$D/run/status.json' && grep -qF 'Map, routing data and search data updated.' '$D/run/status.json'"
check "search data isn't executable, its checksum kept" "[[ \"\$(ls -l '$D/storage/$SRS' | cut -c1-10)\" == -rw-r--r-- && \"\$(cat '$D/storage/$SRS.sha256')\" == \"\$(cut -c1-64 '$D/stick/f250/search.sqlite.sha256')\" && ! -e '$D/storage/$SRS.part' ]]"
rc=0; mi "$D" dir "$D/stick" >/dev/null 2>&1 || rc=$?
check "the same stick again: all three current" "[[ $rc == 0 && \"\$(state_of '$D')\" == current ]] && grep -qF 'The map, routing data and search data on this stick are already installed.' '$D/run/status.json'"
D="$(new_case search-only)"
python3 tools/maps/map-stick.py --search "$T/search.sqlite" --stick "$D/stick" --any-dir >/dev/null 2>&1 || fail "map-stick wrote no search stick"
rc=0; mi "$D" dir "$D/stick" >/dev/null 2>&1 || rc=$?
check "search data alone: imported, the map untouched" "[[ $rc == 0 ]] && cmp -s '$T/search.sqlite' '$D/storage/$SRS' && cmp -s '$OLD' '$D/storage/maps/map.pmtiles'"
check "search data alone: changed names only search" "grep -qF '\"changed\":[\"search\"]' '$D/run/status.json' && grep -qF '\"item\":\"search\"' '$D/run/status.json' && grep -qF 'Search data updated.' '$D/run/status.json'"
check "map-stick refuses search data that isn't the search index" "! python3 tools/maps/map-stick.py --search '$T/not-search.sqlite' --stick '$D/stick' --any-dir 2>/dev/null && ! python3 tools/maps/map-stick.py --search '$FIX' --stick '$D/stick' --any-dir 2>/dev/null"
D="$(new_case s-bad)"; mkdir -p "$D/stick/f250" "$D/storage/search"
cp "$T/search-old.sqlite" "$D/storage/$SRS"
( cd "$D/stick/f250" && cp "$T/not-search.sqlite" search.sqlite && { shasum -a 256 search.sqlite 2>/dev/null || sha256sum search.sqlite; } >search.sqlite.sha256 )
mi "$D" dir "$D/stick" >/dev/null 2>&1 && fail "bad search data: exited 0"
check "search data that isn't the index: failed, the old kept" "[[ \"\$(state_of '$D')\" == failed ]] && grep -qF \"isn't navigation's search data\" '$D/run/status.json' && cmp -s '$T/search-old.sqlite' '$D/storage/$SRS'"
D="$(new_case map-routing-then-bad-search)"; mkdir -p "$D/stick/f250"
python3 tools/maps/map-stick.py --map "$FIX" --routing "$T/routing.tar" --stick "$D/stick" --any-dir >/dev/null 2>&1 || true
cp "$T/search.sqlite" "$D/stick/f250/search.sqlite"; printf '%064d  search.sqlite\n' 0 >"$D/stick/f250/search.sqlite.sha256"
mi "$D" dir "$D/stick" >/dev/null 2>&1 && fail "map and routing then bad search data: exited 0"
check "map and routing, then bad search data: both stay, and the status says so" "[[ \"\$(state_of '$D')\" == failed ]] && grep -qF 'The map and routing data were updated.' '$D/run/status.json' && cmp -s '$T/routing.tar' '$D/storage/$RTS' && [[ ! -e '$D/storage/$SRS' ]]"
D="$(new_case s-pulled)"; mkdir -p "$D/run" "$D/storage/search"
printf '{"state":"copying","percent":40,"message":"","id":"z","device":"/dev/sdd1","item":"search","changed":[],"at":"2026-11-12T00:00:00Z"}\n' >"$D/run/status.json"
echo partial >"$D/storage/$SRS.part"
mi "$D" stopped /dev/sdd1 >/dev/null 2>&1 || true
check "stopped while copying search data: failed, that copy goes" "[[ \"\$(state_of '$D')\" == failed && ! -e '$D/storage/$SRS.part' ]] && grep -qF 'before the search data was copied' '$D/run/status.json'"

U=agl/rootfs/etc/systemd/system/f250-map-import@.service
RULE=agl/rootfs/etc/udev/rules.d/80-f250-map-stick.rules
check "udev: USB exFAT/FAT filesystems start the import" "grep -qF 'ENV{ID_BUS}==\"usb\"' $RULE && grep -qF 'ENV{ID_FS_TYPE}==\"exfat|vfat\"' $RULE && grep -qF 'ENV{SYSTEMD_WANTS}+=\"f250-map-import@%k.service\"' $RULE"
check "unit: runs map-import on the device, and stopped after" "has_line $U 'ExecStart=/opt/f250/libexec/map-import device /dev/%I' && has_line $U 'ExecStopPost=/opt/f250/libexec/map-import stopped /dev/%I'"
check "unit: bound to the stick, long enough for a big map" "has_line $U 'BindsTo=dev-%i.device' && has_line $U 'TimeoutStartSec=1h'"
check "unit: status kept for the dashboard" "has_line $U 'RuntimeDirectory=f250-maps' && has_line $U 'RuntimeDirectoryPreserve=yes' && has_line $U 'RuntimeDirectoryMode=0755'"
check "unit: writes only the data drive, no network" "has_line $U 'ProtectSystem=strict' && has_line $U 'ReadWritePaths=-/var/lib/f250/storage' && has_line $U 'PrivateNetwork=yes' && has_line $U 'PrivateMounts=yes'"
check "unit: started by udev only (no [Install])" "! grep -q '^\[Install\]' $U"
check "map path agrees: script, image, deploy" "grep -q 'F250_STORAGE:-/var/lib/f250/storage' $MI && grep -q 'DEST_DIR=\"\$STORAGE/maps\"; DEST_NAME=map.pmtiles' $MI && grep -q 'DEST_DIR=\"\$STORAGE/routing\"; DEST_NAME=valhalla_tiles.tar' $MI && grep -q 'default_value = \"/var/lib/f250/storage/routing/valhalla_tiles.tar\"' services/navigation/src/main.rs && grep -q 'STATUS_DIR=\"\${F250_MAP_STATUS_DIR:-/run/f250-maps}\"' $MI && grep -q -- '-DMAP_FILE=/var/lib/f250/storage/maps/map.pmtiles -DMAP_STATUS=/run/f250-maps/status.json' $M/recipes-f250/f250-dashboard/f250-dashboard.bb"

echo
echo "agl-test: $PASS passed, $FAIL failed"
[[ "$FAIL" == 0 ]]
