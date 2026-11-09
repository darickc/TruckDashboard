# ADR 0008 — Libraries in `crates/`, daemons in `services/`

- **Status:** Accepted
- **Date:** 2026-11-01

## Context

The suggested layout has `services/telemetry`. The telemetry model is a library
shared by the gateway, the recorder, the pid-importer and the tests. It is not
a running service.

## Decision

- Rust libraries live in `crates/`: `telemetry`, `elm`, `isotp`,
  `can-decode`, and the generated `proto`.
- Daemons live in `services/`.
- A single Cargo workspace at the repository root includes both, plus the
  `tools/` CLIs.

## Consequences

- This is the one deviation from the suggested layout, documented here.
- The workspace is created in Phase 3, when its first crate exists. Phase 1
  doesn't add an empty workspace that would fail `cargo test`.
