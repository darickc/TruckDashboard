# Signal registry

Status: **imports only.** The registry YAML, its JSON Schema and the loader
arrive in Phase 3. See [ADR-0006](../../docs/architecture/adr/0006-signal-registry-formula.md)
and the [telemetry model](../../docs/architecture/telemetry-model.md).

| Path | Contents |
|---|---|
| [`imports/torque/exportedPIDs.csv`](imports/torque/exportedPIDs.csv) | The owner's Torque Pro custom-PID export. **Untrusted input.** Every row imports as `IMPORTED_UNVERIFIED` and disabled |

Rules:

- Nothing here is invented.
- A definition is `VERIFIED_ON_TRUCK` only with an entry in
  [docs/diagnostics/VERIFICATION_LOG.md](../../docs/diagnostics/VERIFICATION_LOG.md).
- The ESP32 table (`firmware/esp32/lib/ObdCore/src/PidDefs.cpp`) is the current
  reference for which definitions are verified.
