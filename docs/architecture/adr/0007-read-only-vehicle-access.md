# ADR 0007 — Read-only vehicle access by default

- **Status:** Accepted
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

1. **At boot, nothing transmits.** CAN comes up in **listen-only** mode, and the
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
