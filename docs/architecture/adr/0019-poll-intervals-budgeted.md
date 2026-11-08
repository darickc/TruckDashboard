# ADR 0019 — Poll intervals budgeted from the measured link throughput

- **Status:** Accepted. Tested on the simulator only [SIM]; the budgets are
  truck measurements, but these intervals have not run on the truck yet.
- **Date:** 2026-11-08
- **Closes:** the open half of the
  [poll-interval known issue](../../setup/gateway.md#poll-intervals-and-the-throughput-budget)
  left by [ADR-0018](0018-computed-inputs-read-together.md)

## Context

The registry's `poll.interval_ms` values came from the ESP32 table: RPM, MAP
and ICP every 100 ms, IPR every 150 ms, the temperatures every 500 ms, and so
on. One request is in flight at a time, so the link's throughput is the
budget:

| Transport | Measured | Budget (`config.rs`) |
|---|---|---|
| OBDLink MX+ on `7DF`, two responders | 10–11.7 requests/s [TRUCK] | 10/s |
| USB CAN adapter (ADR-0012), 50 ms window | 15.8–16.8 requests/s [TRUCK] | was 20/s (unmeasured), now **16/s** |
| Simulator (40–80 ms round trip) | 15.8–16.3 requests/s [SIM] | 15/s |

Sources: [VERIFICATION_LOG.md](../../diagnostics/VERIFICATION_LOG.md)
(2026-11-07 CAN sessions; the MX+ trial) and
[bench-log.md](../../hardware/bench-log.md) (2026-11-08).

The old intervals asked for far more than that:

| Enabled set | Asked | Budget |
|---|---|---|
| Simulator (every signal `drive_cycle` models: all 14) | 54.1/s | 15/s |
| Truck as driven on 2026-11-07 (registry defaults + `--enable eot`) | 23.7/s | 10/s MX+, 16/s CAN |

RPM and MAP alone asked 20/s. Everything else was read only when the
scheduler's starvation guard (overdue by 5 intervals) let it in: EOT and ECT
about every 3 s against a 4 s `stale_after_ms`, and load, with a 2 s
`stale_after_ms`, flickering between `VALID` and `STALE`. What the driver saw
depended on the order of the starvation, not on any rate anyone chose.

## Decision

1. **The default enabled set of each transport asks for at most 80 % of its
   budget** (`Scheduler::load`, the same threshold that raises "low
   priorities stretched" in `LinkStatus.detail`). The binding case is the
   simulator, which polls every signal the registry has: 14 signals in
   12 requests/s.
2. **No interval is longer than half its `stale_after_ms`**, so a reading
   that arrives on time never ages into `STALE`. The slow health signals
   (temperatures, voltages, IAT, baro, fuel) also ride out one missed read:
   2 × interval + the 500 ms timeout stays under their `stale_after_ms`.
   RPM, MAP, speed, ICP, IPR and load do not; a miss on one of them shows
   `STALE` until the next answer. That is honest, and such misses are rare on
   the truck (one in 1672 requests in the first CAN session, 2026-11-07).
3. **The rates, and why** (what the driver sees is the interval plus a round
   trip, measured on the simulator over the 600 s `drive_cycle`):

   | Signal | Shown | Was | Now | Delivered [SIM] | Why |
   |---|---|---|---|---|---|
   | RPM | home strip | 100 ms | **500 ms** | every ~580 ms (1.7 Hz) | The factory tachometer is the driver's RPM; this is a cross-check. As fast as the budget allows after the health signals. |
   | MAP (boost) | home strip | 100 ms | **500 ms** | ~575 ms | Read at a glance when towing. Same rate as RPM. |
   | Speed | home strip | 200 ms | **1000 ms** | ~1090 ms | The factory speedometer is primary. Bound by its 2 s `stale_after_ms`. |
   | ICP | gauge pages | 100 ms | **1000 ms** | ~1085 ms | Diagnostic, unverified. Bound by its 2 s `stale_after_ms`. |
   | IPR duty | gauge pages | 150 ms | **1000 ms** | ~1090 ms | Read with ICP, at the same rate. |
   | Load | gauge pages | 500 ms | **1000 ms** | ~1110 ms | Bound by its 2 s `stale_after_ms`. |
   | EOT, ECT | home, large | 500 ms | **1500 ms** | ~1595 ms | Temperatures move slowly; 1.5 s rides out a miss within the 4 s `stale_after_ms`. Twice as often as they were really read before (~3.1 s). Read back to back (ADR-0018). |
   | Trans temp | home, large | 500 ms | **1500 ms** | ~1600 ms | As EOT. |
   | FICM main | home strip | 400 ms | **1500 ms** | ~1595 ms | As EOT. A short sag between reads is not caught at any rate this link allows; that needs the ESP32 or a logged capture. |
   | Battery | home strip | 1000 ms | **3000 ms** | ~3125 ms | Slow; rides out a miss within 8 s. |
   | IAT | gauge pages | 2000 ms | **3000 ms** | ~3160 ms | As battery. |
   | Baro | boost input | 5000 ms | 5000 ms | ~5085 ms | Barely changes; boost allows it 20 s of skew. |
   | Fuel level | home strip | 5000 ms | 5000 ms | ~5130 ms | Slow; within 15 s. |

   Demand: 11.73 requests/s for all 14 (78 % of the simulator's 15/s,
   73 % of the CAN adapter's 16/s); 6.53/s for the truck's set (65 % of the
   MX+'s 10/s, 41 % of CAN).
4. **Priorities are unchanged.** Under 80 % every signal gets its interval, so
   priority only orders reads that fall due together. It still decides who
   stretches when someone enables more than the link carries.
5. **The CAN budget defaults to the measured 16/s**, not the unmeasured 20/s
   ceiling. It is a tightening.
6. **Nothing is loosened.** `stale_after_ms`, `max_input_skew_ms` and the
   timeouts are unchanged.

### Rejected

- **Per-transport intervals in the registry.** Doubles the table to save a
  multiplication, and the registry is meant to describe the signal, not the
  link.
- **Keep the fast targets and let the scheduler stretch.** The previous state:
  the driver gets whatever rates the starvation order produces, and slow
  signals flicker.
- **Faster RPM/MAP, slower temperatures.** The temperatures and EOT − ECT are
  why this head unit exists; RPM and speed duplicate the factory cluster.
- **Raise `stale_after_ms` to fit slower intervals.** Hides staleness.

## Consequences

- [SIM] `tests/poll_budget.rs`: the simulator's set asks 11.73/s of 15 and
  covers the whole registry; the truck's set fits the MX+ and the CAN
  adapter; every signal fits the CAN adapter. With the old intervals all
  three fail (54.1/s of 15; 23.7/s of 10).
- [SIM] `tests/gateway_sim.rs`
  (`every_signal_gets_its_interval_under_the_default_enabled_set`): over the
  600 s `drive_cycle` on a paused clock, all 14 signals stay `VALID` in every
  snapshot after their first reading, each is read at least once per
  interval + 200 ms, and the link never reports oversubscription. With the
  old intervals it fails on the first snapshot. ADR-0018's test still
  passes: EOT − ECT is `VALID` in every snapshot.
- [SIM] The real gateway on the Mac (`vehicle-gateway --listen tcp:…`,
  `drive_cycle`, wall clock): 10.5 requests/s over 98 s; in 157 `obd-console
  pids` samples 0.5 s apart no signal was ever `STALE` and EOT − ECT was
  `VALID` throughout; `stats` showed RPM read 167 times, EOT and ECT 61 times
  each, 0 failures.
- EOT and ECT now share an interval, so after their first pair they fall due
  together and the group reads them back to back without pulling either one
  early.
- **The truck's RPM gets slower.** Over CAN on 2026-11-07 the oversubscribed
  schedule delivered RPM at 5.9 Hz, speed 3.6 Hz and ECT 1.8 Hz. These
  intervals give about 1.8, 0.95 and 0.65 Hz (predicted, not measured), and
  leave about 60 % of the CAN link idle with the truck's current set. The
  intervals are sized for the full set on the slowest default budget; using
  spare capacity when fewer signals are enabled is a scheduler change, not a
  registry one (see Revisit).
- The MX+ cannot carry every signal: all 14 ask 117 % of its 10/s
  (`tests/poll_budget.rs`, `every_signal_oversubscribes_the_mx_plus`).
  Enabling them there is reported as oversubscribed, and fuel, baro, IAT,
  battery and load (priorities 4–6) stretch first. EOT plus MAP on the MX+
  asks 8.53/s, 85 %: reported, with little real stretch.

## Revisit when

- The truck runs these intervals [TRUCK]: compare `stats` per signal with the
  "Delivered" column, and check no signal flickers `STALE` on a drive.
- The scheduler can spend spare budget (for example, priority 0 runs faster
  while the link has room): RPM and MAP could return to several Hz on the
  CAN adapter with the truck's set.
- Multi-DID batching (`raw 2213101446`,
  [TRUCK_SESSION.md](../../diagnostics/TRUCK_SESSION.md)) or physical
  addressing changes what a request costs: re-measure and retune.
- A signal is added to the registry or a scenario: `tests/poll_budget.rs`
  fails if the simulator's set goes over 80 %.
