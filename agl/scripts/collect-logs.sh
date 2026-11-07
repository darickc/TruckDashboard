#!/bin/bash
# Collect the head unit's logs and state into one archive (Phase 5.5). Runs on
# the Pi under AGL; `make logs PI=<host>` runs it over SSH and copies the
# archive back. Changes nothing.
#
#   collect-logs.sh                # writes /var/tmp/f250-logs-<host>-<time>.tar.gz
#   BOOTS=3 collect-logs.sh        # the journal of the last 3 boots (default 2)
#
# The archive has: the journals of our services, the compositor, the demo's
# CAN units, networkd and logind; the stage1-setup check; the CAN interface
# state and counters; /etc/default/f250; the gateway's traffic logs; the
# recorder database's size (not the database: copy it with scp when needed);
# the kernel log.
#
# Status: [BENCH] on AGL 22.0.1 through `make logs` (bench-log 2026-11-06).
set -uo pipefail

OUT="${OUT:-/var/tmp}"
BOOTS="${BOOTS:-2}"
CAN_IF="${CAN_IF:-can0}"
NAME="f250-logs-$(hostname)-$(date +%Y%m%d-%H%M%S)"
DIR="$OUT/$NAME"
HERE="$(cd "$(dirname "$0")" && pwd)"
mkdir -p "$DIR"

run() {
  local file="$1"; shift
  { echo "\$ $*"; "$@" 2>&1 || echo "(exit $?)"; echo; } >>"$DIR/$file"
}

run system.txt cat /etc/os-release
run system.txt uname -a
run system.txt uptime
run system.txt df -h / /var
run system.txt journalctl --list-boots --no-pager
run system.txt timedatectl
[[ -e /sys/class/rtc/rtc0 ]] && run system.txt sh -c 'cat /sys/class/rtc/rtc0/name; hwclock -r'

# Journals, newest boot last.
for ((b = BOOTS - 1; b >= 0; b--)); do
  journalctl -b "-$b" --no-pager >/dev/null 2>&1 || continue
  for u in f250-gateway f250-recorder f250-dashboard agl-compositor flutter-ics-homescreen \
           kuksa-can-provider can-dev-helper systemd-networkd systemd-logind var-lib-f250-storage.mount; do
    run "journal-$u.txt" journalctl -b "-$b" --no-pager -o short-iso -u "$u"
  done
  run "kernel-boot-$b.txt" journalctl -b "-$b" --no-pager -k -o short-iso
done

run setup-check.txt "$HERE/stage1-setup.sh" --check
run can.txt ip -details -statistics link show "$CAN_IF"
run can.txt networkctl status "$CAN_IF" --no-pager
run services.txt systemctl --no-pager status f250-gateway f250-recorder f250-dashboard agl-compositor
run services.txt systemctl --no-pager --failed
[[ -f /etc/default/f250 ]] && cp /etc/default/f250 "$DIR/etc-default-f250"
[[ -d /var/lib/f250/traffic ]] && cp -r /var/lib/f250/traffic "$DIR/traffic"
run recorder.txt ls -la /var/lib/f250
run storage.txt /opt/f250/bin/f250-storage status
run storage.txt grep -n f250 /etc/fstab

tar -czf "$OUT/$NAME.tar.gz" -C "$OUT" "$NAME" && rm -rf "$DIR"
echo "$OUT/$NAME.tar.gz"
