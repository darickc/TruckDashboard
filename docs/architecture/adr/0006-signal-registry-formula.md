# ADR 0006 — YAML signal registry with a safe formula grammar

- **Status:** Accepted
- **Date:** 2026-11-01

## Context

PID definitions come from many places:

- the SAE standard
- the owner's Torque Pro export
- future captures

Torque formulas are expressions such as `(((A*256)+B)*0.03625)-BARO()`. The
ESP32 firmware reduced them to `raw·scale + bias` in hand-reviewed C++, which
does not scale to an importer or to user-supplied CSVs.

## Decision

- Signal definitions are **data**: YAML in `shared/signals/`, validated against
  a JSON Schema, with the fields listed in
  [telemetry-model.md](../telemetry-model.md).
- Formulas use a **small grammar** parsed in Rust:
  - numbers
  - byte variables `A`…`Z` (payload offset)
  - `+ - * /`, parentheses, unary minus
  - `signed(x)`, `bit(x,n)`, `min`, `max`
  - references to other signals (for example `baro`)

  There is no `eval`, no loops and no user functions. Division by zero produces
  `DECODE_ERROR`.
- The **Torque importer** translates what it can into this grammar. It rejects
  anything else with a reason. Every imported row is marked
  `IMPORTED_UNVERIFIED` and `enabled: false`.

## Consequences

- An untrusted CSV can't execute code or crash the gateway.
- The grammar needs its own tests: precedence, signedness, malformed input.
- The test vectors come from the ESP32 decoder tests and from verified captures.
