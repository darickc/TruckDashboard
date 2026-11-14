# ADR 0046 — Automatic reverse: the gateway's receive-only reader of `230`, followed by camera-manager

- **Status:** Accepted (owner asked, 2026-11-14: "Build automatic reverse and
  deploy it to the Pi"). [SIM]: the decoder against the truck's values, the
  gateway's stream, and camera-manager end to end against a fake gateway.
  [BENCH] 2026-11-14 on the Pi: the installed services with can0
  listen-only, and the truck's `230` values replayed on a virtual CAN
  interface through the whole path (bench-log). **Not yet seen in the
  truck.**
- **Date:** 2026-11-14
- **Implements:** [ADR-0024](0024-camera-selection-switch-and-can-reverse.md)
  decision 4 (reverse from CAN). **Amends:**
  [ADR-0026](0026-camera-manager-interfaces.md) decision 5 (camera-manager
  now reads the gateway), [ADR-0007](0007-read-only-vehicle-access.md)
  (a receive-only socket opened without `--transmit`; see decision 2).

## Context

Reverse is byte 0 of the truck's broadcast `230`: `10` in R. It was found in
the census, matched at the lever (2026-11-08: P `F0`, R `10`, N `F1`, D
`01`), and held over a real 22-minute drive (2026-11-10: `10` in exactly the
four reverse episodes, never driving forward; values seen `F0`, `10`, `F1`,
`01`, `02`, `03`, `05`, `06`). [VERIFICATION_LOG](../../diagnostics/VERIFICATION_LOG.md)
calls that enough for the decoder's entry; it doesn't cover a cold start in
R or a silent bus, which the decoder must treat as unknown.

The camera policy (`crates/camera-policy`) already handles reverse: debounce,
hold, and unknown never meaning "not in reverse". Nothing fed it. The
gateway had no broadcast signals at all: the registry rejects
`source: broadcast` ("not defined yet"), and the registry's quantities are
numeric gauges the dashboard mirrors.

## Decision

1. **Reverse is not a registry signal.** It is a state, not a gauge; putting
   it in the registry would need a new quantity in the registry, the API and
   the dashboard's catalog for one consumer. It gets its own stream,
   `VehicleService.WatchReverse` (`f250.vehicle.v1`): `UNKNOWN`,
   `NOT_ENGAGED` or `ENGAGED`, the age of the last frame, and why. One
   message at once, then on every change and at least every 100 ms. If
   broadcast gauges come later, they go in the registry as
   `BROADCAST_DECODED`; this doesn't decide that.
2. **The gateway reads `230` receive-only** (`services/vehicle-gateway/src/reverse.rs`),
   with `--transport can`, unless `--no-reverse`:
   - a raw SocketCAN socket with a kernel filter for standard ID `230`;
     its type (`FrameReader`) has no send, and it never changes the
     interface's mode;
   - it doesn't need `--transmit`: listening is ADR-0007's default. It works
     with `can0` listen-only (f250-can-auto's first state) as well as
     active. This is the one socket the gateway opens without
     `--transmit` (ADR-0007 amended here; gateway-start says so);
   - an error (the interface down while f250-can-auto switches modes, or
     missing) makes it reopen after 1 s.
3. **Decoding:** `10` → engaged. `F0`, `F1`, `01`–`06` → not engaged (`04`
   was never seen but sits between the forward gears). Any other value, an
   empty frame, no frame yet, or none for `--reverse-stale-ms` (500, an
   example; the broadcast comes about 31 times a second) → **unknown**,
   never "not engaged" (CLAUDE.md rule 4). With the simulator or the MX+
   alone, reverse is always unknown and says why.
4. **camera-manager follows it** with `--auto-reverse`
   (`src/reverse_link.rs`): engaged/not engaged are policy samples, unknown
   is `ReverseInvalid`; no connection or a stream that ends is unknown and
   retried every 2 s. The policy's own `rev_stale` (500 ms) covers a stream
   that stops without ending. The rules stay camera-policy's: reverse for
   `--reverse-debounce-ms` (300) brings up the rear camera, it stays
   `--reverse-hold-ms` (2000) after, unknown mid-reverse keeps the rear view
   with "unknown" shown until a switch move, unknown never starts it.
   Examples to tune on the truck. The debounce keeps the pass through R into
   P from flashing the rear camera: 0.1 s on 2026-11-10, so it started at
   150 ms; 0.160 s twice on 2026-11-14, which flashed it, so it is 300 ms
   (VERIFICATION_LOG.md, 2026-11-14). Real reverses lasted 15 s or more.
5. **On the Pi:** `CAMERA_AUTO_REVERSE` in `/etc/default/f250`: `1` on, `0`
   off, empty (the default) on with `TRANSPORT=can` and off otherwise.
   `CAMERA_REVERSE_DEBOUNCE_MS` and `CAMERA_REVERSE_HOLD_MS` pass the times.
   camera-manager reaches `/run/f250/vehicle.sock` as group `f250`.
6. The dashboard is unchanged: it already shows camera-manager's reverse
   status (REVERSE on the chip when reverse brought the camera up; the
   Cameras tab's reverse line, unknown included).

## Alternatives considered

- **A registry signal with a new "state" quantity:** the general answer, and
  three times the change (registry, API, the dashboard's catalog and
  formatting) for one consumer. Revisit with the second broadcast state.
- **camera-manager reading CAN itself:** a second process on the vehicle
  bus, against ADR-0024 decision 4 and the gateway owning vehicle I/O.
- **Reverse from the gateway's snapshots:** they are for gauges at 250 ms;
  a separate stream is simpler to keep honest about staleness.

## Consequences

- Reverse needs the CAN adapter; with the MX+ alone it stays unknown, and
  the switch's Back or the dashboard's Rear shows the rear camera.
- One more socket on `can0`, receive-only. It sees only `230` (about 31
  frames a second).
- Checked on the truck 2026-11-14 [TRUCK] (VERIFICATION_LOG.md): the rear
  camera came up 0.89–0.97 s after shifting into R, five times, and went
  about 2.3 s after leaving it. Passing through R into P flashed it twice
  (R for 0.160 s); the debounce is now 300 ms, not yet driven.
- Still to check on the truck: no flash through R into P at 300 ms; a cold
  start already in R; unplugging the adapter shows unknown.
