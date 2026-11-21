# Wiring

Status: **design sheets only; nothing installed** (Phase 7). The temporary
DLC hookup is the only sheet signed off.

| Sheet | What |
|---|---|
| [system-overview.md](system-overview.md) | **Start here.** The whole head unit in one diagram, and every connection (W1–W22) with its sheet and what blocks it |
| [dlc-can-adapter.md](dlc-can-adapter.md) | Temporary DLC hookup for the USB CAN adapter |
| [can-permanent.md](can-permanent.md) | The permanent HS-CAN connection: the adapter stays at the DLC on a Y-splitter, USB to the box |
| [power-and-inputs.md](power-and-inputs.md) | DCDC-USB power, ACC, PSW → J2, and the 5-way switch ([ADR-0013](../architecture/adr/0013-dcdc-usb-power-supply.md), [ADR-0024](../architecture/adr/0024-camera-selection-switch-and-can-reverse.md)) |
| [audio.md](audio.md) | DAC8x → new 4-ch amp and the R150-2, speaker and power wiring, amp remote straight on ACC ([ADR-0014](../architecture/adr/0014-multichannel-dac8x.md)) |
| [ground-and-protection.md](ground-and-protection.md) | Ground points G1 and G2, every fuse (F1–F6); no external TVS (owner, 2026-11-16) |
| [usb-and-cameras.md](usb-and-cameras.md) | USB port plan, camera power (USB, no 12 V), cable lengths, the display's 5 V |

Every diagram here must:

- name each fuse rating, wire gauge and connection point
- route vehicle 12 V signals only through protected or opto-isolated inputs,
  never to Pi GPIO
- be reviewed and signed off by a person in
  [bench-log.md](../hardware/bench-log.md) **before** installation (see the
  [safety gates](../safety/assumptions.md#human-verification-gates))

Connecting anything to the DLC also needs the adapter's terminator confirmed
off first ([dlc-can-adapter.md](dlc-can-adapter.md)).
