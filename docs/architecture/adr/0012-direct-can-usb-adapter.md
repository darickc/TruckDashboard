# ADR 0012 — Direct CAN through a USB CANable adapter, with our own single-frame ISO-TP

- **Status:** Accepted
- **Date:** 2026-11-03
- **Amends:** [ADR-0011](0011-mx-plus-trial-first.md) (purchase timing) and
  Phase 4.1/4.5 in [PROJECT_PLAN.md](../../PROJECT_PLAN.md)

## Context

The owner bought a USB CAN adapter on 2026-11-03, before the MX+ trial report
(3.5.7) was written: the **Jhoinrch RH-02 Pro** (Amazon B0FSVNBKQ4). It is a
CANable 2.0 design (STM32G431), with 1.5 kV power and 5.7 kV signal
isolation, TVS/ESD/GDT protection, and a **switch for its 120 Ω terminator**
([compatibility matrix](../../hardware/compatibility-matrix.md#usb-can-adapter-jhoinrch-rh-02-pro)).
It is the "USB candleLight/CANable" row of the
[shopping list](../../hardware/shopping-list.md), and it sidesteps the
CarPiHAT's fixed-terminator question (H1) for the CAN path.

The MX+ trial already showed one limit of an ELM adapter. On 2026-11-03 about
1 window in 100 closed after the TCM's refusal and before the PCM's answer
(adaptive timing), which made EOT drop out
([VERIFICATION_LOG](../../diagnostics/VERIFICATION_LOG.md)). On a raw CAN
socket the gateway decides how long to listen.

The plan said Phase 4.5 would use the kernel's ISO-TP sockets (`can-isotp`).

## Decision

1. **A third gateway transport, `--transport can`**, on a SocketCAN interface
   (`can0`). Same contract as the OBDLink transport: one driver task,
   `DriverEvent`s into the transport-neutral link machine, the same
   scheduler, recovery, validity, recorder and UI.
2. **Our own single-frame ISO-TP over a raw CAN socket, not kernel
   `can-isotp`.** A functional `7DF` request is answered by several modules
   (7E8 and 7E9 on this truck). A kernel ISO-TP socket is bound to one
   tx/rx pair, so it would need one socket per responder and still couldn't
   show the whole census. Every registry request and every registry answer
   fits in one frame, so a single-frame implementation is a few hundred
   lines with tests (`services/vehicle-gateway/src/transport/isotp.rs`).
   Multi-frame answers (e.g. VIN) are reported as Invalid; flow control is
   never sent. TODO if a multi-frame read is ever needed.
3. **Response window: 50 ms**, the commonly cited ISO 15765-4 P2CAN maximum,
   configurable with `--can-window-ms`. Measured 2026-11-07 beside the MX+:
   the slowest of 4408 PCM answers came 40.7 ms after the request, the
   slowest TCM answer 31.8 ms ([CAN_CENSUS](../../diagnostics/CAN_CENSUS.md),
   capture 4), so 50 ms holds on this truck so far. Unpinned requests wait the whole
   window and keep every answer. Pinned requests (`rx_id`) return as soon as
   the owner answers. NRC 0x78 extends the wait to the request timeout.
4. **Requests are 8-byte frames padded with 0x00.** The MX+ pads with 0x00
   too (listen-only capture beside it, 2026-11-07).
5. **Safety stays layered (ADR-0007):**
   - The interface is configured by `tools/pi/can.sh`, as root, and comes up
     **listen-only** by default. The first truck session is listen-only.
   - Normal (ACKing) mode is a separate command, `can.sh active`, which asks
     for confirmation.
   - The gateway opens the socket only with `--transmit`. Every frame goes
     through the same service allow-list. Only the OBD request IDs (`7DF`,
     `7E0`–`7E7`) can be written. The socket's receive filter is `7E8`–`7EF`
     plus error frames.
   - `run.sh` refuses `TRANSMIT=1` while the interface is listen-only, so a
     poll can't silently go nowhere.
6. **Firmware: a `gs_usb` (candleLight-protocol) firmware.** It needs no
   daemon, and listen-only is a standard `ip link` option. *Amended
   2026-11-05:* ours shipped with the CANable 2.0 slcan firmware, which can't
   do listen-only, and mainline candleLight_fw doesn't support the STM32G431
   ([bench-log](../../hardware/bench-log.md)). We use **Candlelight 2.5**
   (Elmue, MIT), flashed by `tools/pi/can.sh flash` from a pinned commit with
   SHA-256 checks. It is a community firmware, not the board maker's, though
   its manual says Jhoinrch now ships it as stock. If it misbehaves, the
   fallback is a candleLight_fw port for the G431 or another adapter; slcan
   stays ruled out for the listen-only sessions.

## Consequences

- The gateway can run on the truck without the MX+. The MX+ path is unchanged
  and stays the fallback. Only one transport runs per gateway process, so the
  two can never transmit together (Phase 4.6).
- A listen-only capture beside the MX+ (Y-splitter) becomes possible. That is
  the dropout experiment (Phase 4.7): did the PCM answer on the bus when the
  MX+ reported nothing?
- K-line modules (RCM, GEM) stay unreachable over CAN. The MX+ can reach them.
- The CarPiHAT decision is still open for power, inputs and audio. Its CAN
  port is no longer needed for diagnostics.
- Tests: the ISO-TP logic and the driver are tested on any OS against an
  in-memory bus replaying the truck's captures (`tests/gateway_can.rs`,
  `[SIM]`). The SocketCAN code is compiled and linted on the Pi 5. **Nothing
  has run against the adapter or the truck yet.**
