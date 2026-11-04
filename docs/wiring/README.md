# Wiring

Status: **design sheets only; nothing installed** (Phase 7).

| Sheet | What |
|---|---|
| [dlc-can-adapter.md](dlc-can-adapter.md) | Temporary DLC hookup for the USB CAN adapter |
| [power-and-inputs.md](power-and-inputs.md) | DCDC-USB power, ACC, PSW → J2, and the reverse input ([ADR-0013](../architecture/adr/0013-dcdc-usb-power-supply.md)) |

Every diagram here must:

- name each fuse rating, wire gauge and connection point
- route vehicle 12 V signals only through protected or opto-isolated inputs,
  never to Pi GPIO
- be reviewed and signed off by a person in
  [bench-log.md](../hardware/bench-log.md) **before** installation (see the
  [safety gates](../safety/assumptions.md#human-verification-gates))

Connecting anything to the DLC also needs the adapter's terminator confirmed
off first ([dlc-can-adapter.md](dlc-can-adapter.md)).
