# Signal registry

Every signal the head unit knows about is defined here as data. The Rust
loader and validator is `crates/telemetry` (`f250_telemetry::registry`). See
[ADR-0006](../../docs/architecture/adr/0006-signal-registry-formula.md) and the
[telemetry model](../../docs/architecture/telemetry-model.md).

| Path | Contents |
|---|---|
| [`sae.yaml`](sae.yaml) | Generic SAE J1979 Mode 01 signals (`SAE`) |
| [`ford_enhanced.yaml`](ford_enhanced.yaml) | Ford service-22 rows from the Torque export (`IMPORTED_UNVERIFIED`, all disabled) |
| [`ford_tcm.yaml`](ford_tcm.yaml) | Transmission fluid temp, the one `VERIFIED_ON_TRUCK` signal |
| [`computed.yaml`](computed.yaml) | Signals derived from others (`eot_ect_delta`, `boost`) |
| [`aux.yaml`](aux.yaml) | Added hardware (EGT, disabled: no probe installed) |
| [`imports/torque/exportedPIDs.csv`](imports/torque/exportedPIDs.csv) | The owner's Torque Pro custom-PID export. **Untrusted input.** Every row imports as `IMPORTED_UNVERIFIED` and disabled |

Rules:

- Nothing here is invented. Ford formulas are copied verbatim from the Torque
  export; SAE formulas are the published J1979 ones listed in
  [FORD_6_0_PIDS.md](../../docs/diagnostics/FORD_6_0_PIDS.md).
- A definition is `VERIFIED_ON_TRUCK` only with an entry in
  [docs/diagnostics/VERIFICATION_LOG.md](../../docs/diagnostics/VERIFICATION_LOG.md),
  cited in its `evidence` field.
- The registry mirrors `apps/infotainment/lib/model/signal_catalog.dart`
  (same ids, provenance, ranges and stale times). A test in
  `crates/telemetry/tests/seed_registry.rs` fails when they drift.

## Format

Every `*.yaml` file directly in this directory is loaded (subdirectories are
not), in file-name order. Each file is a YAML sequence of signal definitions.
Unknown fields are errors.

```yaml
- id: trans_temp                  # snake_case, unique; the API key
  name: Transmission fluid temp
  short_name: Trans               # compact tile label
  quantity: temperature           # temperature | temperature_delta | pressure | voltage | speed | rotation | percent
  unit: degC                      # canonical unit of the quantity: degC | kPa | V | km/h | rpm | "%"
  source: diagnostic              # diagnostic | computed | aux  (broadcast: not defined yet)
  request:
    protocol: iso15765            # iso15765 | elm
    tx_id: "0x7DF"                # quoted 0x-hex CAN id
    rx_id: "0x7E9"                # optional: the responder that owns the value, once established
    payload: "22 16 74"           # service + DID/PID bytes; service must be 01, 03, 07, 09 or 22 (ADR-0007)
  response:
    expect: "62 16 74"            # positive-response echo (service + 0x40), stripped before decoding
    length: 2                     # payload bytes required after the echo; fewer is a DECODE_ERROR
  decode:
    formula: "((A*256)+B)/8"      # ADR-0006 grammar, see below
    unit: degF                    # the formula's native unit, converted to `unit`: degC degF kPa psi V km/h mph rpm "%"
    signed: false                 # optional; only false is supported, use signed(x) in the formula
  range: {min: -40, max: 150}     # plausibility limits, canonical unit; outside → OUT_OF_RANGE
  poll: {priority: 3, interval_ms: 500, timeout_ms: 500}   # priority 0 is highest; interval is a target
  stale_after_ms: 4000            # default 3 × poll.interval_ms
  provenance: VERIFIED_ON_TRUCK   # SAE | VERIFIED_ON_TRUCK | IMPORTED_UNVERIFIED | COMPUTED | AUX_SENSOR
  evidence: "docs/diagnostics/VERIFICATION_LOG.md, 2026-08-09 …"   # required for VERIFIED_ON_TRUCK
  enabled: true
  allow_unverified: false         # must be true to enable an IMPORTED_UNVERIFIED signal
  calibration: {scale: 1.0, offset: 0, note: "…"}   # optional; displayed = raw × scale + offset, scale 0.5–2.0
  notes: free text
```

Computed signals have no `request`, `response`, `decode`, `poll`,
`stale_after_ms` or `calibration`. They follow their inputs:

```yaml
- id: boost
  source: computed
  provenance: COMPUTED
  inputs: [map, baro]             # existing, non-computed signals
  compute: "map - baro"           # must reference exactly the inputs, no payload bytes
  max_input_skew_ms: 20000        # inputs must be measured this close together (default 2000)
  # plus id, name, short_name, quantity, unit, range, enabled
```

Aux signals (`source: aux`, `provenance: AUX_SENSOR`) have no request or
decode and need an explicit `stale_after_ms`.

### Formula grammar (ADR-0006)

- Numbers: decimal (`0.03625`, `.5`) and hex (`0x7F`). No exponents.
- `A`…`Z`: payload bytes after the echo, unsigned 0–255 (`A` is the first).
- `+ - * /`, parentheses, unary minus. Usual precedence, left-associative.
- `signed(x)`: an 8-bit value read as two's complement (as Torque does).
  `bit(x, n)`: bit `n` (0 = least significant). `min(a, b)`, `max(a, b)`.
- Other signals by snake_case id (`baro`), in their canonical unit.
- No `eval`, loops or user functions. Division by zero, a missing byte or a
  missing reference makes the reading a `DECODE_ERROR`.

`formula::from_torque` translates Torque equations (`BARO()` → `baro`,
`Signed(A)` → `signed(A)`) and rejects anything else with a reason.

### Validation

Loading fails, listing every problem, when: an id is duplicated or not
snake_case; `unit` isn't the quantity's canonical unit; `source` and
`provenance` disagree; a `VERIFIED_ON_TRUCK` row has no `evidence`; an
`IMPORTED_UNVERIFIED` row is enabled without `allow_unverified: true`; a
request uses a service outside the allow-list or `expect` isn't its echo; a
formula doesn't parse, its unit doesn't fit the quantity, or `response.length`
is shorter than the bytes it uses; a computed input is missing or computed; a
calibration scale is outside 0.5–2.0; or a CAN id isn't valid hex.
