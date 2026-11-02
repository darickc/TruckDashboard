# Infotainment UI (Flutter)

The head unit's touchscreen app for the original Raspberry Pi 7" display
(800×480). On the truck it runs under AGL's flutter-auto embedder (Flutter
**3.38.3**, pinned in the repo's `.fvmrc`). During development it runs as a
macOS desktop app or in a browser.

Status: **Phase 2. Simulated data only.** The status bar shows a
**SIMULATED** badge whenever the data source is the simulator.

## Run

From the repository root:

```bash
make ui-web                                   # browser at http://127.0.0.1:8250 (no Xcode needed)
make ui-web SCENARIO=eot_ect_freeze START=110 # jump straight to a fault window
make ui                                       # macOS window (needs Xcode)
make ui-test                                  # widget + unit tests
make ui-lint                                  # flutter analyze
```

Scenarios live in [`simulator/powerstroke/scenarios/`](../../simulator/powerstroke/scenarios/).
Switch between them in the app under **Diagnostics → Developer**.

## Structure

| Path | Role |
|---|---|
| `lib/model/` | Signal definitions, the catalog (mirrors `docs/diagnostics/FORD_6_0_PIDS.md`), unit conversion |
| `lib/telemetry/` | `TelemetryStore`: validity, staleness, computed signals, link state, warnings with hysteresis, event log |
| `lib/data/` | `VehicleDataSource` interface; the simulated source and scenario controller. The gRPC gateway source arrives in Phase 3 |
| `lib/config/` | Loads `assets/config/` (warning rules, gauge profiles) and checks it against the catalog |
| `lib/ui/` | Shell (status bar, global alert banner, nav bar), gauge widgets, screens |
| `test/unit/`, `test/widget/` | Logic tests and 800×480 widget tests |

## Rules this app enforces

- **The UI never touches vehicle hardware.** It reads a `VehicleDataSource`.
- **Validity is decided in one place.** `TelemetryStore` decides it, on a
  monotonic clock, and re-checks every refresh even if the data source stops.
- **Stale data is never current.** `SignalState.value` is non-null only while
  the signal is valid. A stale gauge shows the last good value dimmed, with
  its age and a hatch. Computed values (EOT−ECT, boost) disappear when any
  input is invalid.
- **Alerts are global.** The banner sits above every screen and can't be
  dismissed. It clears when the condition clears.
- **Touch targets are at least 60×60 px.** Everything tappable goes through
  `TapTarget`, and a test checks every tap handler on every screen.
- **Thresholds are configuration** (`assets/config/warning_rules.json`),
  labelled as examples.
- **Display assumption:** logical px = physical px (devicePixelRatio 1.0) on
  the target. To be confirmed with flutter-auto in Phase 5.
