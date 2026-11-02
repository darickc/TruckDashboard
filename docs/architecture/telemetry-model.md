# Telemetry model

Status: **design**. It is implemented in `crates/telemetry` and
`shared/proto/f250/vehicle/v1` in Phase 3. The Flutter app mirrors the model in
Dart in Phase 2.

Everything the UI shows about the vehicle is a **Sample** of a **Signal**. The
model keeps four questions apart, because the field failure this project exists
to fix — EOT/ECT freezing while other gauges keep updating — happens when they
get blurred:

1. What is the value?
2. When was it measured?
3. Is it still current?
4. How much do we trust the definition that produced it?

## Signal definition (registry, `shared/signals/*.yaml`)

| Field | Example | Notes |
|---|---|---|
| `id` | `eot` | Stable, snake_case. This is the API key |
| `name` | `Engine oil temperature` | Display name |
| `quantity` | `temperature` | Selects the unit family for conversion |
| `unit` | `degC` | The canonical unit the formula produces |
| `source` | `diagnostic` \| `broadcast` \| `computed` \| `aux` | |
| `request.protocol` | `iso15765` \| `elm` | |
| `request.tx_id` / `rx_id` | `0x7DF` / `0x7E9` | Request address, and the responder that owns the value |
| `request.payload` | `22 16 74` | Service and DID bytes |
| `response.expect` | `62 16 74` | Positive-response echo; stripped before decoding |
| `response.length` | `2` | Payload bytes required. A shorter payload is a `DECODE_ERROR` |
| `decode.formula` | `((A*256)+B)/8` | Safe grammar (ADR-006), never `eval` |
| `decode.signed` | `false` | |
| `range` | `{min: -40, max: 150}` | Plausibility limits. Values outside become `OUT_OF_RANGE` |
| `poll.priority` | `1` | 0 is highest |
| `poll.interval_ms` | `1000` | A **target**. The budget may stretch it, and the stretch is reported |
| `poll.timeout_ms` | `500` | |
| `stale_after_ms` | `3000` | Default is 3 × the interval |
| `provenance` | `VERIFIED_ON_TRUCK` | See below |
| `evidence` | link into `VERIFICATION_LOG.md` | **Required** for `VERIFIED_ON_TRUCK` |
| `enabled` | `false` | Unverified definitions start disabled |
| `notes` | free text | |

### Provenance

| Value | Meaning | UI treatment |
|---|---|---|
| `SAE` | Published J1979 formula | Normal |
| `VERIFIED_ON_TRUCK` | Confirmed on this truck, with a log entry | Normal |
| `IMPORTED_UNVERIFIED` | From the Torque export or another tool, not yet confirmed | "Unverified" badge |
| `COMPUTED` | Derived from other signals | Normal, but valid only while every input is valid |
| `AUX_SENSOR` | Added hardware (EGT probe, for example) | Normal, with the sensor named |
| `BROADCAST_DECODED` | Decoded from passive CAN traffic | Shows its confidence level. Never presented as validated without corroboration |

A registry loader test fails when:

- a `VERIFIED_ON_TRUCK` row has no `evidence`
- a row is enabled with `IMPORTED_UNVERIFIED` provenance without an explicit
  `allow_unverified: true`

## Sample (what flows to the UI and the recorder)

| Field | Notes |
|---|---|
| `signal_id` | |
| `value` | `double`, in the canonical unit. The UI converts for display |
| `validity` | `VALID`, `STALE`, `NO_DATA`, `OUT_OF_RANGE`, `DECODE_ERROR`, `UNSUPPORTED`, `DISABLED` |
| `measured_at_mono_ns` | Monotonic clock. Used for age and staleness. Immune to RTC or GPS time jumps |
| `measured_at_wall` | Wall clock. Used for logs and export |
| `last_good_value`, `last_good_at` | Kept when the current `validity` is not `VALID` |
| `age_ms` | Computed at publish time |
| `source` | Transport (`simulated` / `socketcan` / `obdlink`), responder CAN ID, request ID |
| `provenance` | Copied from the definition |
| `latency_ms` | From request to response |

### Validity rules

- `VALID` → `STALE` happens when `now − measured_at > stale_after_ms`. This
  check runs on a timer **in the model**, not only when a frame arrives. A PID
  that silently stops answering still goes stale.
- When a request fails, the value is not touched. Only the health counters move,
  and the sample ages into `STALE`.
- `NO_DATA` means the link is healthy but no response ever arrived (since start,
  or since the last reset).
- `UNSUPPORTED` means the ECU answered with a negative response such as
  `7F 22 31`. The PID is then quarantined (see [recovery](diagnostic-recovery.md)).

## Computed signals

```yaml
- id: eot_ect_delta
  source: computed
  inputs: [eot, ect]
  formula: eot - ect
  max_input_skew_ms: 2000    # inputs must be measured within 2 s of each other
```

A computed sample is `VALID` only when all of these hold:

- every input is `VALID`
- the inputs' timestamps are within `max_input_skew_ms` of each other
- the result passes its own range check

Otherwise its validity is the worst input validity, and **no value is shown** —
not even a last-good delta. A delta built from one fresh and one frozen reading
is exactly the misleading number this project must never display.

`boost = map − baro` follows the same rule.

## Units

- Canonical units: SI-ish (`degC`, `kPa`, `V`, `rpm`, `km/h`, `%`).
- Display units are per user preference, metric or imperial, with optional
  per-signal overrides.
- Conversion lives in one place (`crates/telemetry::units`, mirrored in Dart) and
  is unit-tested.
- The ESP32 firmware's `Units.h` stays the reference for the existing
  conversions.

## Warnings

```yaml
- signal: eot_ect_delta
  advisory: {above: 15, clear_below: 12}   # degC — EXAMPLE, verify for this truck
  critical: {above: 25, clear_below: 20}
  require_valid: true
  min_duration_ms: 3000
```

- Hysteresis is configured per level. A warning never fires on a stale or
  invalid signal. Communication loss is its own warning.
- Every threshold in the repository carries the comment **EXAMPLE — verify**.
  The ESP32 `Config.h` rules are the same: they are community numbers, not
  measurements.
- Warnings appear globally in the UI on every screen, ranked critical first.
