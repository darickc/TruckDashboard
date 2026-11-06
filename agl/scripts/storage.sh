#!/bin/bash
# The data drive on AGL: an NVMe HAT on the Pi 5's PCIe connector, or a USB
# SSD. `make deploy` installs this as /opt/f250/bin/f250-storage.
#
#   f250-storage status          drives, the f250-data filesystem, the mount, health
#   f250-storage format <disk>   ERASE <disk>: one GPT partition, ext4 labelled f250-data
#
# Then set DATA_DRIVE=1 in /etc/default/f250 and run
# /opt/f250/share/agl/scripts/stage1-setup.sh: it adds the /etc/fstab entry
# (by label, nofail) that mounts the drive at /var/lib/f250/storage, where the
# recorder and the gateway's traffic logs go.
#
# `format` refuses a partition, a disk with anything mounted, the disk the
# system runs from, and a second f250-data drive, and wants the disk's name
# typed back. It uses only tools in the AGL Vimba 22.0.1 image (fdisk,
# mkfs.ext4, lsblk, blkid, findmnt; smartctl for health).
#
# Status: [SIM] (a loop device in a Linux container, tools/dev/test-agl.sh
# notes how). Not run on the Pi or with an NVMe drive yet.
set -euo pipefail

LABEL=f250-data
STORAGE=/var/lib/f250/storage

die() { echo "f250-storage: $*" >&2; exit 1; }

status() {
  local dev d on
  echo "== Drives"
  lsblk -e 1,7 -o NAME,SIZE,TYPE,TRAN,MODEL,FSTYPE,LABEL,MOUNTPOINTS
  if command -v lspci >/dev/null && [[ -n "$(lspci 2>/dev/null)" ]]; then
    echo; echo "== PCIe"; lspci
  fi
  echo; echo "== $LABEL"
  if dev="$(blkid -L "$LABEL" 2>/dev/null)"; then
    echo "filesystem: $dev"
  else
    echo "no filesystem labelled $LABEL (f250-storage format <disk>)"
  fi
  if mountpoint -q "$STORAGE"; then
    df -h "$STORAGE"
  else
    echo "nothing mounted at $STORAGE"
  fi
  on="$(sed -n 's/^DATA_DRIVE=//p' /etc/default/f250 2>/dev/null | tail -1)"
  echo "DATA_DRIVE=${on:-0} (/etc/default/f250)"
  for d in /dev/nvme[0-9]; do
    [[ -c "$d" ]] || continue
    echo; echo "== $d health (smartctl)"
    smartctl -H -A "$d" 2>&1 | grep -E 'overall-health|Critical Warning|Temperature:|Percentage Used|Power Cycles|Unsafe Shutdowns|Media and Data Integrity' || true
  done
}

format() {
  local disk="$1" name part other root_disk mounts answer
  [[ "$(id -u)" == 0 ]] || die "run as root"
  [[ -b "$disk" ]] || die "$disk is not a block device"
  name="$(basename "$disk")"
  case "$(lsblk -dno TYPE "$disk")" in
    disk|loop) ;;   # loop: how this script is tested
    *) die "$disk is not a whole disk: give the disk (e.g. /dev/nvme0n1), not a partition" ;;
  esac
  root_disk="$(lsblk -no PKNAME "$(findmnt -no SOURCE /)" 2>/dev/null | head -1)" || true
  [[ "$name" != "$root_disk" ]] || die "$disk holds the running system"
  mounts="$(lsblk -nro MOUNTPOINTS "$disk" | sed '/^$/d')"
  [[ -z "$mounts" ]] || die "$disk has mounted filesystems: $(echo "$mounts" | tr '\n' ' ')"
  if other="$(blkid -L "$LABEL" 2>/dev/null)" && [[ "$(lsblk -no PKNAME "$other" | head -1)" != "$name" ]]; then
    die "$other is already labelled $LABEL: two would mount by chance. Unplug it or reformat it first"
  fi

  echo "This ERASES everything on $disk:"
  lsblk -o NAME,SIZE,TYPE,TRAN,MODEL,FSTYPE,LABEL "$disk"
  read -r -p "Type the disk's name ($name) to erase it: " answer
  [[ "$answer" == "$name" ]] || die "cancelled"

  # g: new GPT; n: partition 1, default first and last sector; w: write.
  # -w/-W always: wipe old signatures without asking.
  printf 'g\nn\n1\n\n\nw\n' | fdisk -w always -W always "$disk" >/dev/null
  udevadm settle 2>/dev/null || sleep 2
  part="$(lsblk -nrpo NAME,TYPE "$disk" | awk '$2 == "part" { print $1; exit }')"
  [[ -n "$part" && -b "$part" ]] || die "the new partition on $disk didn't appear"
  mkfs.ext4 -F -q -L "$LABEL" "$part"
  udevadm settle 2>/dev/null || true
  echo "Formatted $part as ext4, label $LABEL."
  echo "Next: DATA_DRIVE=1 in /etc/default/f250, then /opt/f250/share/agl/scripts/stage1-setup.sh"
}

case "${1:-}" in
  status) status ;;
  format) [[ $# == 2 ]] || die "usage: f250-storage format <disk>"; format "$2" ;;
  -h|--help|"") sed -n '2,19p' "$0" ;;
  *) die "usage: f250-storage status | format <disk>" ;;
esac
