# ADR 0050 — Range bars and this drive's peak on digital gauges

- **Status:** Accepted (owner, 2026-11-18, from the design review's Gauges
  mockup: "Gauges range bars"). `[SIM]` only; not yet on the Pi's panel.
- **Date:** 2026-11-18
- **Refines:** the Gauges screen (Phase 2.6), CLAUDE.md rules 4 and 10.

## Context

A digital gauge tile shows a number. Whether 214 °F of EOT is fine or close
to a warning depends on thresholds the driver can't see. The warning rules
(`assets/config/warning_rules.json`) already hold example limits, and the
circular gauges already had display ranges in code. The highest EOT or
lowest FICM voltage during a tow is also worth keeping in view, and nothing
showed it.

Constraints: a value that isn't current is never shown as current (rule 4);
thresholds are examples from configuration, never universal (rule 10); the
tile is about 190 × 170 px with no room for another line.

## Options considered

1. **A bar on every digital tile.** Signals without a rule (ICP, speed,
   fuel) would get a bar with no zones, which means nothing.
2. **A bar only where a warning rule exists, its zones from that rule.**
   Chosen.
3. **Peaks in the UI**, from the values it happens to render. Lost when the
   Gauges screen isn't showing; rejected.
4. **Peaks in the telemetry store**, sampled from valid values. Chosen.

## Decision

1. **A range bar under the number** on a digital tile whose signal has a
   warning rule and a display range (`gaugeRanges` in
   `lib/ui/widgets/range_bar.dart`, now shared with the circular gauge).
   Its advisory and critical stretches start at the rule's triggers
   (`rangeZones`), so changing `warning_rules.json` moves them; they are the
   same example limits the alerts use. Hysteresis and minimum durations stay
   the warning engine's.
2. **The marker shows only a current value.** Without one the bar has no
   marker and dims; the number and its stale status show as before.
3. **This drive's peak on the status line**: "max 214 °F", or "min 47.6 V"
   for a rule that watches the low side. The status (STALE, out of range…)
   always takes the line when there is one. Signals without a rule show no
   peak.
4. **Peaks live in the telemetry store** (`SignalState.peakHigh`,
   `peakLow`): every refresh, and every gateway snapshot, folds each valid
   value in. A rejected or stale value never counts. Where every rule on a
   signal is gated (the EOT–ECT delta only on a warm engine), its peaks
   count only while the gate holds, so a cold start doesn't leave a scary
   peak no alert would have raised. They start over when the dashboard
   starts, when the simulator's scenario changes, and when the signal's
   calibration changes (old and new factors don't mix).

Display ranges (canonical units, UI configuration): EOT, ECT and trans
temperature 40–130 °C (104–266 °F); EOT − ECT 0–20 °C (0–36 °F); FICM 40–52
V; battery 10–15 V; RPM, boost, speed and load as before.

## Consequences

- The bar takes 12 px from the number, which scales down to fit (it already
  did under an alert).
- "This drive" means since the dashboard started: there is no key-on signal
  in the app yet. A restart mid-drive starts the peaks over.
- Peaks are sampled at the refresh rate (250 ms) or the gateway's snapshot
  rate, the rate the screen shows values at; a spike between samples isn't
  kept.
- Circular gauges keep their arc and show no peak; the mockup's peak on
  them, the profile selector as one segmented control, a health summary
  in the Gauges header and a smaller UNVERIFIED badge are not part of this.

`[SIM]`: `test/unit/peaks_test.dart` (the store: highs, lows, rejected and
stale values, the gate, calibration, reset) and
`test/widget/gauge_range_test.dart` (zones for above, below and
advisory-only rules, clamping, the marker, max and min, no rule, a frozen
value); checked in the browser at 800×480.
