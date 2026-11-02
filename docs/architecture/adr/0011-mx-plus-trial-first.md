# ADR 0011 — MX+ truck trial before buying CAN hardware

- **Status:** Accepted
- **Date:** 2026-11-01
- **Amends:** the Phase 3/4 ordering in [PROJECT_PLAN.md](../../PROJECT_PLAN.md)

## Context

The original plan reached the truck through the CarPiHAT PRO 5's CAN
interface (Phase 4), with the OBDLink MX+ as a later validation or fallback
transport (Stage D). That means buying hardware, and answering its open
questions (the fixed 120 Ω terminator, unpublished input protection), before
the software meets a real vehicle.

The owner already has these, all of which work with each other today:

- a Raspberry Pi 5
- the original 7" display
- the MX+, a commercial adapter already used on this truck
- the ESP32

The owner asked to test with the MX+ before buying anything.

The project's top priority is the intermittent EOT/ECT dropout. Five of its six
hypotheses can be tested from adapter-side logs alone: two-responder desync,
polling overload, misattribution, adapter state, and adapter supply voltage
via `ATRV` (see [PROJECT_PLAN.md](../../PROJECT_PLAN.md#what-the-mx-trial-phase-35-can-already-show)).

## Decision

Insert **Phase 3.5, the MX+ truck trial**, between the backend (Phase 3) and
CAN hardware (Phase 4):

- **Phase 3 builds the MX+ path first**: the `crates/elm` port, the `ObdLink`
  transport (RFCOMM or serial), the scheduler and recovery logic, the
  recorder, the gRPC API, `tools/obd-console`, and a Flutter Linux desktop
  target. The `SocketCan` transport moves to Phase 4.
- **The trial runs on Raspberry Pi OS**, not AGL. That is the fastest path,
  and it is already the plan's stage-0 platform (ADR-0005). It is powered
  temporarily from USB-C, with no wiring changes.
- **Purchases are decided from the trial's data** and recorded in
  `docs/hardware/shopping-list.md`.

## Consequences

- No money is spent until real data exists, and the gateway's recovery logic
  meets a real vehicle months earlier.
- The trial cannot tell "the ECU never answered" from "the adapter dropped the
  answer". That still needs a listen-only CAN capture (Phase 4.7), so it may
  justify the CAN purchase rather than replace it.
- Raspberry Pi OS is not AGL. The BlueZ version and the Flutter embedder
  (GTK desktop instead of flutter-auto) differ, so the AGL behaviour still has
  to be checked in Phase 5.
- **Read-only access still applies (ADR-0007).** Polling through the MX+ is
  diagnostic transmission. It needs `transmit_enabled: true` and the same
  service allow-list. The electrical part of the checklist reduces to
  "commercial adapter in the DLC, no added wiring", recorded in
  `bench-log.md`.
- The MX+ takes one Bluetooth master at a time, so the phone and the ESP32
  must be disconnected during the trial.
