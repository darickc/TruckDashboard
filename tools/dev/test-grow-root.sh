#!/usr/bin/env bash
# grow-root (ADR-0022) on a real, mounted ext4 filesystem: a loop device laid
# out like the Pi wic image (MBR, FAT then ext4, free space after), run under
# f250-grow-root.service's sandbox with systemd-run. Needs Linux, root,
# systemd, losetup, sfdisk, partx, mkfs.ext4/vfat and systemd-growfs. In the
# build VM:
#
#   sudo tools/dev/test-grow-root.sh
#
# (`make agl-test` runs the parts that need none of that: tools/dev/test-agl.sh.)
set -euo pipefail

HERE="$(cd "$(dirname "$0")/../.." && pwd)"
GROW="$HERE/agl/rootfs/opt/f250/libexec/grow-root"
UNIT="$HERE/agl/rootfs/etc/systemd/system/f250-grow-root.service"

[[ "$(uname -s)" == Linux && "$(id -u)" == 0 ]] || { echo "needs Linux and root" >&2; exit 2; }

PASS=0
FAIL=0
ok()   { PASS=$((PASS + 1)); }
fail() { FAIL=$((FAIL + 1)); printf '  FAIL %s\n' "$*"; }
check() { if eval "$2"; then ok; else fail "$1"; fi; }

T="$(mktemp -d)"
MNT=/mnt/f250-grow-root-test   # not under /tmp: the unit has PrivateTmp=yes
LOOP=
cleanup() {
  umount "$MNT" 2>/dev/null || true
  rmdir "$MNT" 2>/dev/null || true
  [[ -n "$LOOP" ]] && losetup -d "$LOOP" 2>/dev/null || true
  rm -rf "$T"
}
trap cleanup EXIT

# The unit's [Service] settings, except ExecStart, as systemd-run properties.
# Not RemainAfterExit= either: --wait waits for the unit to go inactive.
props=()
while IFS= read -r line; do
  case "$line" in ''|'#'*|ExecStart=*|RemainAfterExit=*) continue ;; esac
  props+=(-p "$line")
done < <(sed -n '/^\[Service\]/,/^\[/{/^\[/d;p}' "$UNIT")

run_unit() {   # grow-root under the unit's sandbox; its output in $T/run.out
  systemd-run --quiet --wait --collect --pipe -E F250_GROW_MOUNT="$MNT" "${props[@]}" \
    "$GROW" >"$T/run.out" 2>&1
}

# 96 MiB "card": FAT 1-17 MiB, ext4 17-49 MiB, 47 MiB free.
truncate -s 96M "$T/card.img"
printf 'label: dos\nstart=2048, size=32768, type=c\nstart=34816, size=65536, type=83\n' | sfdisk -q "$T/card.img"
LOOP="$(losetup -fP --show "$T/card.img")"
udevadm settle 2>/dev/null || true
mkfs.vfat "${LOOP}p1" >/dev/null
mkfs.ext4 -q -L root "${LOOP}p2"
mkdir -p "$MNT"
mount "${LOOP}p2" "$MNT"
before="$(df -k --output=size "$MNT" | tail -1)"
echo "before: $(df -h "$MNT" | tail -1)"

echo "grow on first boot"
if run_unit; then ok; else fail "grow-root failed under the sandbox: $(cat "$T/run.out")"; fi
sed 's/^/  | /' "$T/run.out"
after="$(df -k --output=size "$MNT" | tail -1)"
echo "after: $(df -h "$MNT" | tail -1)"
psize="$(cat "/sys/class/block/$(basename "$LOOP")p2/size")"
check "partition reaches the end of the disk" "[[ $((34816 + psize)) == $((96 * 2048)) ]]"
check "kernel sees the new size without a reboot" "[[ '$psize' -gt 65536 ]]"
check "filesystem grew online (from $before KiB to $after KiB)" "[[ '$after' -gt $((before + 40000)) ]]"
check "first partition untouched" "[[ \"\$(sfdisk -d '$LOOP' | grep -c 'start=        2048, size=       32768')\" == 1 ]]"
check "still mounted read-write" "findmnt -no OPTIONS '$MNT' | grep -q '^rw'"
umount "$MNT"
if e2fsck -fn "${LOOP}p2" >"$T/fsck.out" 2>&1; then ok; else fail "e2fsck after the grow: $(tail -3 "$T/fsck.out")"; fi
mount "${LOOP}p2" "$MNT"

echo "second boot: nothing to do"
sfdisk -d "$LOOP" >"$T/table.1"
if run_unit; then ok; else fail "second run failed: $(cat "$T/run.out")"; fi
sfdisk -d "$LOOP" >"$T/table.2"
check "table unchanged" "cmp -s '$T/table.1' '$T/table.2'"
check "says there is no room left" "grep -q ' 0 MiB after it' '$T/run.out'"

echo
echo "test-grow-root: $PASS passed, $FAIL failed"
[[ "$FAIL" == 0 ]]
