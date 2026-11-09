# ADR 0003 — Own versioned vehicle API; KUKSA bridge optional

- **Status:** Accepted
- **Date:** 2026-11-01

## Context

The AGL Vimba image ships `kuksa-databroker` 0.7.1 and `kuksa-can-provider`,
which carry vehicle signals as COVESA VSS. This project's core requirement
needs per-sample fields that VSS datapoints do not model:

- validity
- last-good value and age
- provenance (verified, imported or computed)
- responder ECU
- per-PID communication health
- recovery state

## Decision

The gateway's own API, `f250.vehicle.v1`, is the source of truth for the UI and
the recorder. A one-way **KUKSA bridge** may be added later to publish valid,
current values to the databroker, so AGL demo apps keep working. It never
publishes stale values as current.

## Consequences

- We own the schema, and its versioning discipline.
- AGL's VSS-based apps see nothing until the bridge exists. That is acceptable,
  because our app is the primary UI.
