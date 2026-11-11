# ADR 0007 — Read-only vehicle access by default

- **Status:** Accepted. Decision 1 amended 2026-11-10 (owner): see
  "Amendment: active after a clean listen"
- **Date:** 2026-11-01

## Context

The Pi shares the HS-CAN bus with the PCM, TCM, ABS and instrument cluster. A
wrongly configured node can disturb the bus:

- a wrong bitrate
- an extra terminator
- unsolicited frames

So can a stray diagnostic service: a session change, a DTC clear, or an
actuator test. The owner requires initial communication to be read-only.

## Decision

1. **At boot, nothing transmits.** *(Amended 2026-11-10: with the owner's
   `CAN_AUTO_ACTIVE=1`, CAN may go active by itself, but only after a clean
   listen-only check; see the amendment below.)* CAN comes up in **listen-only** mode, and the
   gateway starts in `PASSIVE_ONLY`.
2. Diagnostic transmit needs **both**:
   - `diagnostics.transmit_enabled: true` in the config
   - a recorded electrical-verification checklist:
     - termination measured
     - bitrate confirmed in listen-only mode
     - wiring reviewed by a person
3. A **service allow-list** is enforced in code before any frame is sent. Only
   read services are allowed. Every other service is refused and logged.
4. **One transmitting transport at a time.** There is a kill switch.
5. Never implemented:
   - ECU programming
   - immobilizer or security-access bypass
   - actuator control
   - module configuration writes
   - safety-module interaction

## Amendment: active after a clean listen (owner, 2026-11-10)

The owner wants to drive without a laptop. Until now, `f250-can active` was
typed over SSH on every drive. Options put to the owner: CAN active straight
at boot; keep it manual; or active after a clean listen. He chose the last:

- **An explicit opt-in:** `CAN_AUTO_ACTIVE=1` in `/etc/default/f250`, off
  by default. Without it nothing changes: CAN stays down at boot.
- **Listen first, every boot.** `f250-can-auto.service`
  (`/opt/f250/libexec/can-auto`) puts `can0` in **listen-only** mode, where
  the adapter sends neither ACKs nor error frames. It switches to active
  only after a window (`CAN_AUTO_LISTEN_S`, 3 s; 30 s until the owner shortened
  it, 2026-11-10: the Pi is up in ~9 s, and 30 s held polling back to ~38 s)
  in which it received at
  least `CAN_AUTO_MIN_FRAMES` frames (1000; the truck sends ~712/s), stayed
  ERROR-ACTIVE, and kept both error counters at 0. That is decision 2's
  "bitrate confirmed in listen-only mode", repeated each time. No bus (the
  bench, ignition off), errors (a wrong bitrate) or error-passive: it stays
  listen-only and keeps listening. It never goes active without the
  truck's own traffic first.
- Then it restarts the gateway, which polls only with **`TRANSMIT=1`**.
  Decision 2's other conditions, the checklist and the allow-list, are
  unchanged.

So decision 1 now reads: at boot, nothing transmits until the bus has
been heard cleanly, and only with the owner's opt-in. Optional:
`CAN_AUTO_CAPTURE=1` also records every frame until shutdown, on the SD
card.

## Consequences

- **The MX+ trial (ADR-0011)** is diagnostic transmission through a
  commercial adapter. It still needs the config opt-in and is still limited to
  the service allow-list. The checklist's electrical items reduce to
  "commercial adapter in the DLC, no added wiring", recorded like any other
  entry.

- Stage A (passive monitoring) can run on the truck before any transmit risk is
  taken.
- The allow-list is unit-tested over the whole table: a test fails if any
  enabled signal uses a service that isn't allowed.
