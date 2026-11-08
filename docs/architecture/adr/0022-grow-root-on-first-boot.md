# ADR 0022 — Root fills the SD card on the first boot

- **Status:** Proposed ([SIM]: `tools/dev/test-agl.sh`, and a mounted loop
  device in the build VM under the unit's sandbox; not run on the Pi yet)
- **Date:** 2026-11-08
- **Refines:** [ADR-0021](0021-trimmed-dev-and-release-images.md)

## Context

The wic image's root partition is only as large as the image needs. Flashed
to a 7.3 GB card, the release image (e82719f) has an 851 MB root
(`mmcblk0p2`, 899.6 MB) with about 250 MB free; the development image's root
is about 1.4 GB. The other 6 GB of the card is unused.

What writes to root:

- `f250-can capture` writes a candump to `/root/f250-data`, about 120 MB an
  hour on the truck. This is the immediate limit: a drive for the CAN test
  could be captured for about two hours.
- The gateway's traffic logs (up to 50 MB), the recorder's database (its own
  retention), and the journal (at most 50 MB) go to `/var/lib`.

Facts about the 22.0.1 build, read in the build VM on 2026-11-08:

- The Pi wic image has an **MBR** (`dos`) partition table: FAT boot at
  4 MiB, ext4 root after it, nothing after root.
- systemd is 259.5. `systemd-growfs` is in the `systemd` package, so both
  images already have it. `systemd-repart` isn't built (no `repart` in the
  recipe's configuration), and it only handles GPT anyway.
- The images have `fdisk`, `mkfs.ext4` and `e2fsck`, but no `resize2fs`,
  `growpart` or `parted`. util-linux's `sfdisk` and `partx` are built and
  packaged (`util-linux-sfdisk`, `util-linux-partx`), just not installed.
- SELinux is disabled on the image (bench-log).

## Options

1. **Grow root on the first boot.** A oneshot unit moves the root
   partition's end to the end of the disk (`sfdisk -N 2`, start unchanged),
   makes the kernel use the new size (`partx -u`), and grows the mounted
   ext4 filesystem (`systemd-growfs`). This is the usual approach on SD-card
   images (Raspberry Pi OS does it too).
2. **Make a data partition from the free space**, ext4 labelled
   `f250-data`, and use the existing `DATA_DRIVE` mechanism. The recorder and
   traffic logs already move there with `DATA_DRIVE=1`; `f250-can capture`
   would need to as well.
3. **Make root bigger at build time** (wic `--extra-space`, or
   `IMAGE_ROOTFS_SIZE`) for a fixed card size.

## Decision

**Option 1.** `f250-system` installs and enables `f250-grow-root.service`,
which runs `/opt/f250/libexec/grow-root` at every boot:

- It grows the partition only when root is the disk's last partition, the
  table is `dos`, and at least 16 MiB follow it. Otherwise it logs why and
  leaves the table alone. On a card that has already grown it writes nothing.
- `systemd-growfs /` then grows the filesystem online. If the kernel kept the
  old partition size, the next boot reads the new table and grows it then.
- It is ordered after `local-fs.target` and before the gateway and recorder.
  It touches no network and no vehicle bus (ADR-0007).
- Sandbox: only `CAP_SYS_ADMIN` (the kernel's partition update) and
  `CAP_SYS_RESOURCE` (ext4's online resize). `ProtectSystem=full` (so `/`
  stays writable for the resize), no network, no namespaces. There's no device
  allow-list, because the disk must be writable. So there's no `ProtectClock=`
  either, since it implies an allow-list. The loop test found that
  `ProtectClock=` alone would lock the disk out.
- `stage1-setup.sh` installs the files on the prebuilt image (it installs all
  of `agl/rootfs`) but doesn't enable the unit there.
- New runtime packages: `util-linux-sfdisk` and `util-linux-partx`.

Why not the others:

- **Data partition.** `DATA_DRIVE` and the `f250-data` label mean an external
  drive (NVMe HAT or USB SSD). Partition 3 on the card would take that label.
  An NVMe drive later would then be a second `f250-data`, which
  `f250-storage format` refuses ("two would mount by chance"). Option 2 would
  also have to set `DATA_DRIVE=1` in `/etc/default/f250` at first boot, which
  is the owner's settings file and a conffile, and teach `f250-can` a second
  location. Its real advantage is isolation: a runaway capture would fill the
  data partition, not root. That's noted below as a consequence of option 1.
  An external data drive is still how long-term telemetry gets off the card.
- **Build-time size.** The image would be tied to one card size: too big to
  flash to a smaller card, and space left unused on a larger one. Every
  image would also grow by gigabytes on the Mac and in flashing time.

## Consequences

- After the first boot, root is about the size of the card (about 7 GB on the
  bench card). `f250-can capture` writes to `/root/f250-data` with no changes,
  and the services see the space with no changes.
- Root can now fill up. A capture is the only unbounded writer: about 50
  hours fill the bench card. A full root stops the recorder and the journal.
  Captures are started by hand, so stop them, and copy them off, after a
  drive.
- The first boot of a newly flashed card writes the MBR while root is mounted
  from it. A power cut during that write could leave the card unbootable
  until it is flashed again. The write is one sector and happens once.
- A card flashed again starts small and grows again on its first boot.
- `DATA_DRIVE` is unchanged: an external drive still takes the recorder and
  traffic logs off the card.
- A GPT image, or one with a partition after root, would need this revisited:
  the script refuses both and logs why.
