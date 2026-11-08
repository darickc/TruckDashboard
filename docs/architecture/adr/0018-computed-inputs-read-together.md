# ADR 0018 — Read a computed signal's inputs back to back

- **Status:** Accepted. Tested on the simulator only [SIM]; not yet seen on
  the MX+ or the CAN adapter.
- **Date:** 2026-11-08
- **Applies:** the telemetry model's computed-signal rule
  ([telemetry-model.md](../telemetry-model.md#computed-signals)) and CLAUDE.md
  rule 4 to the scheduler ([diagnostic-recovery.md](../diagnostic-recovery.md#scheduler))

## Context

EOT − ECT is `VALID` only while both inputs are `VALID` and were read within
`max_input_skew_ms` (2000 ms) of each other. It is the main 6.0L health number
on the dashboard.

The registry's poll intervals came from the ESP32 table. With every signal the
`drive_cycle` scenario models enabled, they ask for about 54 requests/s. The
simulator delivers about 16/s; the MX+ measured 10–11.7/s and the CAN adapter
about 16/s on the truck ([VERIFICATION_LOG.md](../../diagnostics/VERIFICATION_LOG.md)).
RPM and MAP (priority 0, every 100 ms) alone ask for 20/s, so everything else
is read only when the starvation guard (overdue by 5 intervals) lets it in.
EOT and ECT (priority 3, every 500 ms) were each read about every 3 s, at
times the stretch chose independently. Often they were more than 2 s apart,
so the delta read `STALE` while both inputs were `VALID`:

| Where | What was seen |
|---|---|
| Bench Pi, AGL image, 2026-11-08 ([bench log](../../hardware/bench-log.md)) [SIM transport] | `STALE` in 4 of 5 samples; 15.8 requests/s; EOT and ECT 41 reads each in 128 s |
| Mac, `make gateway` [SIM] | `STALE` in 19 of 80 samples; 16.3 requests/s; EOT and ECT 18 reads each in 57 s |
| `tests/gateway_sim.rs`, before this change [SIM] | `STALE` in 225 of 2131 snapshots over the 600 s scenario |

The `STALE` was honest, but it came from the order of the reads, not from the
data being old.

## Decision

1. **The inputs of each enabled computed signal form a scheduler group.**
   When the scheduler picks a member, the other members are picked next, ahead
   of everything else, so they are read one round trip apart (40–80 ms on the
   simulator).
2. **A member follows only if** it is due, or it is polled at least as often
   as the member picked and half its interval has passed. Following reorders
   reads; it never makes a slow input fast. (MAP follows baro; baro does not
   follow MAP, so baro stays at 5 s.) Backed-off, quarantined and disabled
   members never follow, so a dead input costs nothing extra.
3. **No snapshot is published between the reads of a group.** Otherwise the
   snapshot taken after the first read pairs it with the other input's 3 s
   old reading, and the delta flickers `STALE` once per pair. This delays a
   snapshot by at most one request per extra member (a timeout, 500 ms, in the
   worst case). If the link drops mid-group, polling stops and snapshots go
   out as usual.
4. **Nothing is loosened.** `max_input_skew_ms` stays 2000 ms, the telemetry
   store still checks it, and a delta whose inputs really are apart, stale or
   invalid still shows no value.

### Rejected

- **Raise EOT and ECT's priority.** Priority 0 alone oversubscribes the link,
  so priority 1 or 2 would still live on the starvation guard and drift apart.
  And it would take budget from RPM and MAP to fix an ordering problem.
- **Retune the intervals first.** Needed, but separate: it changes how often
  the driver sees each gauge update, needs the truck's throughput per
  transport, and doesn't by itself keep two inputs together — any later
  oversubscription (an unverified PID enabled, a slow adapter) would bring the
  skew back. It stays the open half of the
  [known issue](../../setup/gateway.md#known-issue-the-poll-intervals-ask-too-much-of-the-mx).
- **Raise `max_input_skew_ms`.** Hides the problem, and would let a 3 s old
  input stand next to a fresh one.

## Consequences

- [SIM] `tests/gateway_sim.rs` runs the real Core on tokio's paused clock for
  the whole `drive_cycle` scenario: EOT − ECT is `VALID` in every snapshot
  after its first reading (0 of ~2130 not `VALID`; grouping without rule 3
  left 33). On `make gateway` it was `VALID` in 119 of 119 samples after the
  first reading, at 15.8 requests/s, with EOT and ECT still read about every
  3.1 s and baro every 5 s.
- The Core's clock is now `tokio::time::Instant` (the same clock unless a test
  pauses it), so the whole loop can be tested in virtual time.
- Boost (`map`, `baro`) is grouped too. With a 20 s skew limit it didn't need
  it, and it costs nothing: MAP is due whenever baro is.
- EOT and ECT are still read only every ~3 s under the default set, which is
  inside their 4 s `stale_after_ms` with little margin. A slower link or more
  enabled signals can still make the inputs, and so the delta, `STALE` —
  correctly. Retuning the intervals is what fixes that.

## Revisit when

- Interval retuning lands: check that the groups still read back to back and
  that nothing else depends on the old order.
- The truck shows the delta `STALE` with both inputs `VALID` [TRUCK]: the
  grouping isn't holding on a real transport (for example, a member that
  times out between the reads).
- A computed signal gets more than two inputs, or inputs with very different
  intervals and a tight skew limit.
