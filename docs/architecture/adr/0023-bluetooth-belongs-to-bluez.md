# ADR 0023 — Bluetooth belongs to BlueZ, not connman

- **Status:** Accepted. [BENCH] 2026-11-09 on image 288d091: connmand runs
  without its Bluetooth plugin, the controller is unblocked, powered, not
  discoverable and not pairable, and Wi-Fi still joins and rejoins the
  hotspot (bench-log). Not yet: pairing the MX+
- **Date:** 2026-11-09
- **Refines:** [ADR-0021](0021-trimmed-dev-and-release-images.md)

## Context

On the trimmed development image (33d8324), Bluetooth never comes up:
`hci0` is present but not powered, connman's settings have
`[Bluetooth] Enable=false`, and the controller is rfkill soft-blocked
(bthelper: "Failed to set power on"; bench-log 2026-11-08). The OBDLink MX+
over RFCOMM needs Bluetooth, so the `obdlink` transport has never run on
AGL. It is the fallback transport, and 4.6 (transport switching with the MX+
and the CAN adapter both present) needs it. Phase 6.1's audio manager needs
Bluetooth too.

What the sources say (read in the build VM on 2026-11-09):

- **connman 2.0** keeps an `Enable` state for each technology it has a
  driver for. With no settings file, a technology is enabled only if
  `DefaultEnabledTechnologies` in `main.conf` names it; AGL's `main.conf`
  doesn't. The first time connman sees an rfkill switch of a type it
  manages, it blocks it to match a disabled technology
  (`__connman_technology_add_rfkill`). For a type with no driver it returns
  early: "If there is no driver for this type, ignore it." Later rfkill
  changes don't make it block again (`__connman_technology_update_rfkill`).
- connman's Bluetooth driver is the builtin `bluetooth` plugin
  (`CONNMAN_PLUGIN_DEFINE(bluetooth, ...)`). It gives Bluetooth PAN
  networking and tethering. `--noplugin=bluetooth` keeps it from loading.
- The image's `connman.service` runs `/usr/sbin/connmand -n` (unit read
  from the built `connman-2.0-r0` package).
- **BlueZ 5.86** powers every controller it finds when `[Policy] AutoEnable`
  is true, and true is the default (`plugins/policy.c`). The image's
  `/etc/bluetooth/main.conf` sets nothing. BlueZ keeps the controller
  non-discoverable unless asked.
- **systemd 259**'s `systemd-rfkill` is in the image (built `systemd`
  package). Its manual page, systemd-rfkill.service(8), says it restores each
  switch's saved state at boot and saves the state on each change; the
  source wasn't read. A card that has booted with connman's block has that
  block saved.

Earlier ADRs left this open: ADR-0021 recorded that nothing in AGL's layers
turns Bluetooth on, and that the demo's settings app did that at run time.

## Options

1. **connman drops Bluetooth.** A drop-in runs connmand with
   `--noplugin=bluetooth`. connman then leaves the Bluetooth rfkill switch
   alone, and BlueZ powers the controller. One owner for Bluetooth.
2. **connman enables Bluetooth.** Ship `DefaultEnabledTechnologies=bluetooth`
   in `main.conf`, or a `[Bluetooth] Enable=true` settings file. This only
   helps a card without a settings file (connman wrote `Enable=false` on the
   first boot, so existing cards keep it), and connman and BlueZ both keep
   switching the controller.
3. **A boot unit runs `connmanctl enable bluetooth`.** It works on every
   card, but it starts connman's Bluetooth handling and then corrects it.

## Decision

**Option 1.** `agl/rootfs/etc/systemd/system/connman.service.d/50-f250.conf`
replaces `ExecStart` with `/usr/sbin/connmand -n --noplugin=bluetooth`.
connman keeps Wi-Fi and Ethernet. Bluetooth, and pairing in Phase 6.1, belong
to BlueZ. Because the drop-in is in `agl/rootfs`, Stage 1 installs it on the
prebuilt image and `f250-system` builds it into both meta-f250 images.

On a new card, nothing blocks the controller: connman never touches the
switch and systemd-rfkill has no saved state. On a card that has already
booted (Stage 1 on the prebuilt image), connman's block is saved, and
systemd-rfkill would restore it at the next boot. So `stage1-setup.sh` step 8
clears the soft block through sysfs while the old connman still runs. The
old connman doesn't block it again, and systemd-rfkill saves the cleared
state. connman isn't restarted, because it may carry the SSH session's Wi-Fi.
The drop-in takes effect at the next reboot.

`stage1-setup.sh --check` gained a Bluetooth section:

- FAIL: the drop-in is missing or old, or a Bluetooth switch is blocked.
- WARN: the running connmand still has its plugin (reboot), the controller
  isn't powered, or there is no controller.

## Consequences

- `connmanctl technologies` no longer lists Bluetooth. Turn Bluetooth on or
  off with `bluetoothctl power on|off`.
- Bluetooth is powered but not discoverable. With no agent registered,
  `bluetoothctl show` reports `Pairable: no` ([BENCH] 2026-11-09); whether
  that refuses an incoming pairing attempt is still **UNVERIFIED**. Phase 6.1's controlled pairing window decides that policy.
  Until then, pair the MX+ from the Pi (`bluetoothctl`, outgoing), as on
  Raspberry Pi OS.
- When connman is upgraded, check its `ExecStart` again: the drop-in
  replaces it.
- The `obdlink` transports have still not run inside the gateway's sandbox
  (ADR-0021 §10). That is checked the first time the MX+ connects on AGL.

## To verify on the Pi

1. Flash an image built with this change (or `make deploy` to a Stage 1
   card, then reboot). `stage1-setup.sh --check` passes with no Bluetooth
   warnings.
2. `bluetoothctl show` says `Powered: yes` and `Discoverable: no`.
   `cat /sys/class/rfkill/*/soft` is 0 for the bluetooth switch.
3. `connmanctl technologies` lists Wi-Fi, and the hotspot still rejoins after
   a reboot.
4. Pair the MX+ (`bluetoothctl`) and keep the transcript. Then run
   `TRANSPORT=obdlink` with the gateway sandboxed. Record all of this in the
   bench log.
