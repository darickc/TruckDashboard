# ADR 0024 — Cameras: a 5-way switch picks the view, reverse comes from CAN; no opto board

- **Status:** Accepted (decided by the owner, 2026-11-09). [SIM] nothing yet:
  the reverse decoder still needs its own truck check, and the switch isn't
  chosen
- **Date:** 2026-11-09
- **Supersedes:** the "Reverse input" and "Turn signals" rows of
  [ADR-0013](0013-dcdc-usb-power-supply.md) decision 4, and the GPIO plan in
  [ADR-0014](0014-multichannel-dac8x.md) decision 7
- **Amends:** [camera-policy.md](../camera-policy.md),
  [power-states.md](../power-states.md),
  [wiring/power-and-inputs.md](../../wiring/power-and-inputs.md)

## Context

The camera plan switched views automatically: reverse showed the rear camera,
and a turn signal showed that side's camera. Neither signal had a source yet:

- **Turn signals aren't on HS-CAN.** They are an analogue flasher-relay
  circuit under the dash (owner, 2026-11-07; no flasher-rate bit in the
  census). They needed two channels of an opto-isolated input board, two taps
  into the flasher wiring, and blink-debounce and hazard-detection logic.
- **Reverse needed a third opto channel** and a tap on the reverse-lamp feed.
- **Reverse is on HS-CAN.** Broadcast `230` byte 0 reads `10` in R: at both
  P→R→P cycles in the census (2026-11-07,
  [CAN_CENSUS](../../diagnostics/CAN_CENSUS.md#reverse-found-event-matched-candidates)),
  and at the lever with P `F0`, R `10`, N `F1`, D `01`
  ([VERIFICATION_LOG](../../diagnostics/VERIFICATION_LOG.md), 2026-11-08). It
  arrives about 31 times a second. It is still a **candidate**, not a decoder.

The owner wants any camera viewable at any point in a drive, not only when a
turn signal is on.

## Options

1. **Keep the plan:** opto board, three vehicle taps, automatic turn-signal
   switching.
2. **Manual selection with a 5-way switch, reverse from CAN.** The switch picks
   left, right or rear, or goes back to the previous screen. Reverse still
   shows the rear camera automatically, from the broadcast the gateway already
   receives listen-only.
3. **Detect reverse from the rear camera's video**, with the camera powered
   from the reverse lamps. Rejected: the rear view couldn't be picked while
   driving, and a dead camera would look exactly like "not in reverse", with
   no warning.

## Decision

**Option 2.**

1. **A 5-way switch** (four directions and a press: a navigation switch, a
   microswitch joystick or five buttons; part TBD, H32) picks the camera:

   | Switch | Default action (configuration) |
   |---|---|
   | Left | Left camera |
   | Right | Right camera |
   | Back | Rear camera |
   | Forward | No camera: back to the previous screen. **Amended 2026-11-10 (owner): the front camera** |
   | Press | No camera: back to the previous screen |

   The choice is latched until the next move. Forward has its own input so a
   forward camera can take it later. *2026-11-10: it did. The owner added a
   front camera (to be recorded with the rear, like a dashcam; recording is
   a later ADR), and press is now the only way back to the previous screen.*
2. **A digital switch, not an analog joystick module.** The usual hobby
   joystick is two potentiometers, and the Pi 5 has no ADC. Each switch
   contact closes to ground on its own GPIO, at the Pi's 3.3 V. It is a
   low-voltage switch in the cab, never a vehicle signal (CLAUDE.md rule 6
   doesn't apply), but its wiring is still documented and checked by a person
   ([power-and-inputs.md](../../wiring/power-and-inputs.md)).
3. **power-manager reads the switch.** It stays the single owner of the GPIO
   (ADR-0013) and passes the choice to camera-manager, as it was to pass
   reverse.
4. **Reverse comes from the gateway**, decoded from broadcast `230` byte 0,
   listen-only. Nothing is transmitted (ADR-0007). It needs the direct CAN
   adapter: with only the MX+ there is no broadcast stream. Until the decoder
   is verified, automatic reverse is off and the switch's Back is the way to
   see the rear camera.
5. **No opto board, no vehicle taps.** The reverse-lamp and flasher taps are
   dropped, and no 12 V vehicle signal goes near the Pi.
6. **Manual selection at any speed** (owner). The earlier policy allowed it
   only parked or slow. A speed limit stays available as configuration, off by
   default.

## Consequences

**Gains:**

- Fewer parts and no taps into the truck's lighting wiring.
- The camera policy shrinks to: reverse, else the switch's choice. No blink
  debounce, no hazard detection.
- Any camera, any time.

**Costs and risks:**

- **Automatic reverse depends on the gateway and the CAN adapter.** If the
  broadcast goes stale (adapter unplugged, gateway down), reverse is
  **unknown**, never "not in reverse". The UI says so (CLAUDE.md rule 4), and
  Back still works.
- **No automatic side view when signalling.** That was a feature of the old
  plan; it is now a deliberate press.
- **The decoder is not verified yet.** It needs a parked, listen-only
  session: several shifts into and out of R with the engine running, rolling
  backwards, and every lever position. Then a VERIFICATION_LOG entry and a
  decoder corroborated as in Stage B (4.4).
- Five GPIOs and a cable to the dash (H32), alongside the DAC8x (H27).

**Tests:**

- The camera policy (reverse priority, the latched choice, reverse ending,
  stale reverse) and the switch debounce are pure logic, unit-tested `[SIM]`.
- The reverse decoder gets test vectors from the truck captures once
  verified.

## Revisit if

- The `230` decoder can't be verified, or reverse proves unreliable on the
  bus. Then a reverse input comes back: one opto channel on the reverse-lamp
  feed.
- The owner wants automatic side views. Then the flasher taps and two opto
  channels come back.
