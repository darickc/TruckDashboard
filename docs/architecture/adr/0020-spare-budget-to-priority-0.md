# ADR 0020 — Priority 0 spends the spare link budget

- **Status:** Accepted. Tested on the simulator only [SIM]; not yet run on
  the MX+ or the CAN adapter.
- **Date:** 2026-11-08
- **Amends:** [ADR-0019](0019-poll-intervals-budgeted.md), "Revisit when"
  (the scheduler can spend spare budget). Keeps
  [ADR-0018](0018-computed-inputs-read-together.md).

## Context

ADR-0019 sized the registry's intervals so the largest default set (all 14
signals the simulator polls) fits 80 % of the slowest default budget. A
smaller set leaves the link idle. The truck's set (registry defaults plus
`--enable eot`) asks 6.53 requests/s: 41 % of the CAN adapter's 16/s, 65 %
of the MX+'s 10/s. The oversubscribed schedule delivered RPM at 5.9 Hz over
CAN on 2026-11-07 [TRUCK]; ADR-0019's 500 ms interval gives about 1.8 Hz,
with about 60 % of the link unused.

The registry describes the signal, not the link (ADR-0019, Rejected), so the
fix belongs in the scheduler. Constraints: never plan more than 80 % of the
budget (`Scheduler::load`, `Load::oversubscribed`); leave `interval_ms`,
`stale_after_ms` and `max_input_skew_ms` alone; keep computed inputs read
back to back.

## Decision

1. **Spare reads go to priority 0 only** (RPM and MAP today). They are the
   fast-moving values on the home strip. Priorities are a ranking already in
   the registry, so no new per-signal setting is needed.
2. **The room** is 80 % of the budget, minus the healthy signals' registry
   demand, minus the probe budget (0.5/s) while anything is backed off or
   quarantined. With no room (demand at or over 80 %) there are no spare
   reads and the scheduler behaves exactly as before.
3. **Each healthy (`Active`) priority-0 signal gets an equal share** of the
   room, added to its registry rate. Its *spare interval* is one over that
   rate. A signal with a recent miss (`Suspect`) gets none, and neither does
   a disabled, backed-off or quarantined one. Shares are water-filled: a
   signal capped by the floor (next item) leaves the rest to the others.
4. **Floor: the core's snapshot period, 250 ms.** A value read more often than
   snapshots are published is never seen by the UI or the recorder, and the
   extra requests would still go on the vehicle bus.
5. **An early read only fills idle time.** It is picked only when nothing is
   due, no group follow-up is pending, and no probe is allowed. It is due
   one spare interval after the signal's last *request*. It can delay a
   signal that falls due during it by at most one round trip, the same as any
   other request in flight.
6. **The registry schedule is untouched.** A spare read is an ordinary
   success: the signal's next regular read is its registry interval after
   it. Staleness, skew and backoff are judged as before. A spare read only
   makes a value fresher.
7. **Groups (ADR-0018).** After an early read, another member follows only if
   it is due, regularly or by its own spare interval. ADR-0018's "same or
   faster interval and half-way to due" rule applies to regular picks only,
   so an early MAP read never drags a same-interval partner along at 4 Hz
   outside the 80 %. Baro still follows MAP only when baro is due, and MAP
   still follows baro.
8. **`Load` reports it.** `spare_rps` is the planned extra rate,
   `planned_rps()` = `demand_rps + spare_rps`, never above 80 % of
   `budget_rps` (with the probe budget reserved while probing).
   `oversubscribed()` still looks at `demand_rps` alone, so
   `LinkStatus.detail` is unchanged. `Scheduler::with_spare_floor(Duration::MAX)`
   turns spare reads off (tests use it for the baseline; there is no CLI flag).

What each set plans (`tests/poll_budget.rs`, `spare_reads_stay_within_80_percent`):

| Set | Budget | Demand | Spare | Planned | RPM spare interval |
|---|---|---|---|---|---|
| Truck set, CAN adapter | 16/s | 6.53/s | 2.00/s | 8.53/s (53 %) | 250 ms (floor) |
| Truck set, MX+ | 10/s | 6.53/s | 1.47/s | 8.00/s (80 %) | 288 ms |
| All 14, simulator | 15/s | 11.73/s | 0.27/s | 12.00/s (80 %) | ~468 ms (RPM and MAP) |
| All signals, MX+ | 10/s | 11.73/s | 0 | oversubscribed, as before | — |

### Rejected

- **Scale every interval down by the spare ratio.** Speeds up baro and fuel
  level, which barely change, and costs bus traffic for nothing the driver
  sees.
- **Shorten the registry intervals per transport.** ADR-0019 already rejected
  per-transport intervals; the registry describes the signal.
- **Change the regular schedule (`PidPoll`'s interval) while there is room.**
  Couples staleness bookkeeping and backoff to a figure that changes whenever
  a signal is enabled or quarantined; and a regular read is picked over lower
  priorities, so it would push them back. Early reads that only fill idle
  time cannot.
- **No floor (spend everything).** RPM alone could go to ~8/s over CAN, but
  only 4 of those reach a snapshot each second.
- **Spare reads for any priority, in priority order.** Speed and ICP are
  bound by their 2 s `stale_after_ms`, which their 1 s interval already
  meets; the temperatures move slowly. Revisit if the UI shows a need.

## Consequences

- [SIM] Scheduler unit test in virtual time
  (`spare_budget_speeds_up_rpm_on_the_truck_can_set`): the truck's set,
  16/s budget, every request 62.5 ms, 300 s. Without spare reads RPM is read
  at 1.77 Hz and the link carries 5.9 requests/s; with them **RPM 3.45 Hz**,
  7.7 requests/s (48 % of 16). Speed and load 0.88 → 0.94 Hz, EOT, ECT and
  trans temp unchanged at 0.63 Hz, baro unchanged, IAT 95 → 94 reads.
  EOT and ECT stay back to back. The plan is 8.53/s, under the 12.8/s line.
- [SIM] Other unit tests: an early read never goes before a due signal; no
  spare when demand is at or over 80 %; shares are equal and capped; probing
  reserves the probe budget; `Suspect` signals are not sped up; early MAP
  reads leave baro at 5 s and a same-interval group partner at its own rate.
- [SIM] `tests/gateway_sim.rs` and the rest of `tests/poll_budget.rs` pass
  unchanged: the simulator's set has only 0.27/s to spare, and every signal
  still gets its interval.
- RPM over CAN with the truck's set is predicted at about 3.5 Hz, not the
  5.9 Hz of the oversubscribed schedule. That schedule starved everything
  else; this one keeps every signal on its interval. On the MX+ the same set
  plans exactly 80 %.
- More requests on the vehicle bus when the link has room: up to 2/s more
  with the truck's set over CAN. They are the same read-only requests as
  the regular reads (`01 0C` for RPM, `22 14 40` for MAP), inside the measured budget
  (ADR-007 unchanged).
- Snapshot ages of RPM and MAP drop: a value is at most a spare interval
  plus a round trip old at publication instead of a registry interval plus
  a round trip.

## Revisit when

- The truck runs it [TRUCK]: compare `stats` per signal against the table
  above, and check the link's requests/s stays under 80 % of its budget.
- The snapshot period changes: the floor follows it (`with_spare_floor`).
- A screen needs another signal faster (spare reads for priority 1).
- Multi-DID batching or physical addressing changes what a request costs
  (ADR-0019 "Revisit when").
