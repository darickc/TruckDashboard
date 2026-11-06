# ADR 0015 — Override the AGL demo image's CAN defaults

- **Status:** Accepted. The override has not run on the image yet; verify it
  with `stage1-setup.sh --check` before the adapter goes near the truck.
- **Date:** 2026-11-06
- **Applies:** [ADR-0007](0007-read-only-vehicle-access.md) (nothing transmits
  at boot) and [ADR-0012](0012-direct-can-usb-adapter.md) (listen-only first)
  to the AGL image

## Context

The prebuilt Vimba 22.0.1 Pi 5 Flutter image is our Stage 1 platform
([ADR-0005](0005-staged-agl-bringup.md)). It is a demo image, and three parts
of it act on CAN interfaces. Read from the AGL layer sources (branch `vimba`)
and the image manifest on 2026-11-06:

| Part | What it does | Source | Status |
|---|---|---|---|
| `systemd-conf-canbus` | Installs `/usr/lib/systemd/network/60-canbus-can.network`: `[Match] Name=can*`, `[CAN] BitRate=500K`, `RestartSec=0.1`. No `ListenOnly`. systemd-networkd brings **every** `can*` interface up at 500 kbit/s in **normal mode** as soon as it appears | `meta-agl/meta-agl-core/recipes-core/systemd/systemd-conf-canbus/`, pulled in by `packagegroup-agl-core-connectivity`; in the manifest | V (source), U (behaviour on the image) |
| `can-dev-helper` | At boot, if the interface named in the KUKSA CAN provider's config (`can0`) doesn't exist, creates it as a **virtual** CAN device | `meta-agl-demo/recipes-connectivity/kuksa-val/can-dev-helper/` | V (source) |
| `kuksa-can-provider` | `dbcfeeder.py`, enabled at boot, reads `can0` with the AGL demo DBC and feeds the KUKSA databroker. Its default arguments leave `--val2dbc` (writing frames) off; other AGL configurations turn it on | `meta-agl/meta-agl-kuksa-val/recipes-connectivity/kuksa-val/kuksa-can-provider*`, `meta-agl-demo/.../kuksa-can-provider-conf-agl/config.ini` | V (source) |

Our USB adapter appears as `can0` under `gs_usb` (ADR-0012). On the stock
image, plugging it in would put it in normal mode, where it **ACKs every frame
on the truck's bus**, before anything of ours runs. That breaks ADR-0007 even
though no software sends a frame. And if the adapter is unplugged at boot,
`can-dev-helper` takes the name `can0` for a virtual device, so the adapter
would come up as `can1` and our tools would watch the wrong interface.

Raspberry Pi OS does neither: the interface stays down until
`tools/pi/can.sh` brings it up, listen-only by default.

## Decision

On the AGL image (Stage 1 now, `meta-f250` later):

1. **systemd-networkd does not manage CAN.** `/etc/systemd/network/60-canbus-can.network`
   has the same name as the image's file, so it replaces it, and says
   `Unmanaged=yes` for `can*`. This is systemd's documented override
   ([systemd.network](https://www.freedesktop.org/software/systemd/man/latest/systemd.network.html):
   `Unmanaged=`, "no attempts are made to bring up or configure matching
   links"). We don't use networkd's `ListenOnly=` instead: `tools/pi/can.sh`
   already owns the interface on Raspberry Pi OS, and one owner is simpler
   than two.
2. **`kuksa-can-provider.service` and `can-dev-helper.service` are masked.**
   Nothing of ours reads the KUKSA databroker (ADR-0003 keeps that bridge
   optional and one-way, from our API outward).
3. **`agl/scripts/stage1-setup.sh` does both before anything else**, takes
   `can0` down if it finds it up in normal mode, and deletes a virtual `can0`.
   `--check` reports all of it, and fails if either unit is unmasked or the
   override is missing.
4. In `meta-f250` (Phase 5.4) the image should not contain
   `kuksa-can-provider` or `can-dev-helper` at all, and installs the same
   networkd file.

## Consequences

- Same CAN behaviour on both OSes: down at boot, `f250-can listen` (the AGL
  name for `tools/pi/can.sh`), then `active` only on purpose.
- The AGL demo's CAN-driven features (the vehicle-signal demo apps fed from
  the DBC) no longer get CAN data. We don't use them.
- **Until `stage1-setup.sh` has run, the AGL image must not be connected to
  the truck with the adapter plugged in.** [docs/setup/agl.md](../../setup/agl.md)
  says so in the flash steps.

## Revisit when

- An AGL release changes these recipes (check on every release bump:
  `60-canbus-can.network`, `can-dev-helper`, the KUKSA provider's arguments).
- We want a KUKSA bridge (ADR-0003). It would read our gateway's API, never
  the bus.
