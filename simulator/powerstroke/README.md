# Power Stroke scenario simulator

A deterministic simulator that plays scripted 6.0L Power Stroke scenarios as the
stream of per-request outcomes a diagnostic gateway would see: responses,
timeouts, negative responses, undecodable answers and link loss.

- **Dart package `powerstroke_sim`:** used in-process by the Flutter app (Phase 2).
- **The same YAML files** will be read by the Rust gateway's simulated
  transport (Phase 3), so the UI and the backend are tested against the same
  situations.

> Scenario values are **simulated**. They are chosen to look plausible. They are
> not measurements from the truck, and must never be used as reference data or
> threshold sources.

## Scenarios

| File | What it exercises |
|---|---|
| `drive_cycle.yaml` | Baseline: idle, cruise, towing climb, descent. No faults |
| `warm_idle.yaml` | Steady and healthy; layout work |
| `eot_ect_freeze.yaml` | **The field symptom:** EOT and ECT stop answering while everything else works |
| `link_loss.yaml` | The whole link drops for 40 s, then recovers |
| `ficm_sag.yaml` | FICM main power sags under load (low-voltage warning path) |
| `bad_responses.yaml` | Negative response (ICP), undecodable MAP, implausible trans temp, a simulated DTC |

## Format: `f250.scenario.v1`

```yaml
schema: f250.scenario.v1        # required, exact
extends: drive_cycle            # optional: inherit tracks, append faults
name: EOT/ECT freeze
description: …
duration_s: 600                 # scenario length; inherited if extending
loop: true                      # wrap the clock (default true)
seed: 2007                      # deterministic noise

signals:                        # canonical units (telemetry-model.md)
  eot: {unit: degC, interval_ms: 1000, noise: 0.3, min: -40, max: 150,
        keyframes: [[0, 92], [380, 108], [600, 92]]}   # [seconds, value], piecewise linear

faults:                         # active over [start_s, end_s)
  - {kind: no_response,       signals: [eot, ect], start_s: 120, end_s: 260}
  - {kind: negative_response, signals: [icp], nrc: 0x31, start_s: 0, end_s: 600}
  - {kind: invalid_response,  signals: [map], start_s: 100, end_s: 160}
  - {kind: value_override,    signals: [trans_temp], value: 400, start_s: 300, end_s: 330}
  - {kind: link_down,         start_s: 90, end_s: 130}

dtcs:                           # always shown as SIMULATED
  - {code: P0128, description: …, status: stored}
```

Engine guarantees, all of them tested:

- Poll *k* of a signal happens at *k* × `interval_ms` of run time.
- Output depends only on (scenario, time). It does not depend on how the time
  range is split across calls.
- Noise is bounded by `noise` and then clamped to `min`/`max`.
- Fault precedence: link_down, then no_response, then negative_response, then
  invalid_response, then value_override.
- A caller suspended longer than 10 s skips ahead instead of replaying a
  backlog.

```bash
make sim-test    # or: cd simulator/powerstroke && fvm dart test
```
