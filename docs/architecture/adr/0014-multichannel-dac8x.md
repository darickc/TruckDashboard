# ADR 0014 — Multichannel DAC (HiFiBerry DAC8x), a new 4-channel amp, and the R150-2 kept

- **Status:** Proposed (decided by the owner; the DAC's boot behaviour, its
  header pass-through and the R150-2's bridged input are pending)
- **Date:** 2026-11-04. Amended 2026-11-05: the amplifier remote is on ACC
  through a delay-on timer, not on the Pi (decision 6)
- **Amends:** [audio-routing.md](../audio-routing.md),
  [power-and-inputs.md](../../wiring/power-and-inputs.md) (GPIO pins), and the
  "I2S DAC HAT, model TBD" row of [ADR-0013](0013-dcdc-usb-power-supply.md).
  Wiring: [wiring/audio.md](../../wiring/audio.md).

## Context

The Pioneer DEH-P770MP being replaced (owner, 2026-11-04):

- drives the 4 factory speakers (SuperCab) from its built-in amplifier
- feeds a Rockford Fosgate Prime R150-2, bridged mono into two 10" subs, from
  its sub pre-out
- gives a fader, sub level and crossover

The Pi has no speaker amplifier and outputs line level only. So it needs a new
4-channel amplifier for the speakers, and its own feed for the R150-2.

There were two ways to feed them:

1. **A stereo DAC and RCA Y-splitters.** Cheapest. But the same signal goes to
   front, rear and sub: no fader, and the sub level and crossover become knobs
   on the amplifiers.
2. **A multichannel DAC.** Separate outputs for front, rear and sub. Fader, sub
   level and crossover are software, reachable from the touchscreen.

## Decision

1. **The HiFiBerry DAC8x** (8 channels as 4 stereo jacks, 2.1 Vrms maximum,
   Pi 5) is the DAC. Facts and sources:
   [compatibility matrix](../../hardware/compatibility-matrix.md#hifiberry-dac8x).
2. **Channel map:**
   - jack 1 to the front pair
   - jack 2 to the rear pair
   - jack 3 to the sub, mono on both legs
   - jack 4 spare
3. **A new 4-channel amplifier** drives the factory speakers through the
   existing radio harness adapter. The model is chosen by the owner against
   the criteria in the [shopping list](../../hardware/shopping-list.md).
4. **The R150-2 stays**, fed from jack 3.
5. **Crossover, fader, balance and sub level run in PipeWire** (a filter-chain
   in front of the DAC8x sink), owned by audio-manager (Phase 6). The
   amplifiers' own crossovers are set flat, or used only as a backstop.
6. **The amplifiers' remote leads are switched by ACC through a delay-on
   timer relay**, not by the Pi (owner, 2026-11-05). This replaces the
   GPIO-driven switch planned in ADR-0013.
   - The delay is longer than the Pi's boot-to-audio time, so the amps come on
     after the DAC is up.
   - At key-off the amps go off at once, before the Pi shuts down.
   - The Pi has no amplifier output, no GPIO for it, and no crash-state
     requirement on one.
7. **The GPIO plan moves to fit the DAC8x.** Its overlay claims BCM18–27 and
   reads BCM5. Proposed:
   - reverse moves to BCM6
   - turn signals to BCM12 and BCM13
   - BCM5 left unconnected

## Consequences

**Gains:**

- The Pioneer's fader, sub level and crossover survive, in the UI.
- No Y-splitters: each amplifier input sees one source.
- A spare stereo pair for later (for example a separate navigation-prompt
  channel).

**Costs and risks:**

- **Pi 5 only.** HiFiBerry describes it as a DAC for the Pi 5. Fine for this
  project; it ties the head unit to the Pi 5.
- **3.5 mm jacks**, not RCA: three adapter leads, and jacks that must be
  strain-relieved in a vibrating truck.
- **It uses most of the header's I2S side.** BCM18–27 and BCM5 are gone. Header
  pass-through with the HAT fitted is unknown (H27).
- **Mute at boot is undocumented** (H6). The delay-on timer keeps the amps off
  while the DAC initialises, provided the delay is set above the measured
  boot time.
- **A Pi crash with the key on leaves the amps on** (decision 6). Usually that's
  silence; the worst case is a repeating-buffer buzz until key-off (H5). Key-off
  always cuts the amps. The safety assumption is "key-off always cuts the
  amplifiers", not "a crash leaves them off".
- **Cranking can reset the timer** if ACC drops (H22): the amps come on one
  delay after the engine starts.
- **A software crossover means a misconfiguration sends full-range audio to the
  subs or bass to small door speakers.** The R150-2's own low-pass can stay on
  as a backstop. The audio-manager config gets validation tests.
- **The AGL image's support for the overlay is unknown.** It is in the
  Raspberry Pi kernel tree (`rpi-6.12.y`); whether the AGL Vimba kernel carries
  it is checked in Phase 5.
- A new amplifier and power wiring: more installation work than a Y-split.

**Tests:**

- The PipeWire channel map, crossover and fader configuration: generated or
  validated by audio-manager, unit-tested `[SIM]` in Phase 6.
- Everything electrical is `[BENCH]` first: line level, boot pop, remote-off on
  crash. Then `[TRUCK]`: polarity, whine, gain. The checklist is in
  [wiring/audio.md](../../wiring/audio.md#checks-before-sign-off).

## Revisit if

- The DAC8x pops at boot in a way the remote sequencing can't hide, or AGL can't
  load its overlay. Then use a USB multichannel DAC, or a stereo DAC into a car
  DSP.
- The header can't be shared with the opto board (H27).
- A Pi crash produces a buzz or loud noise through the amps (H5). Then go back
  to a Pi-controlled remote with a hardware heartbeat timer that drops it.
- The owner replaces the R150-2 and the new 4-ch amp with one 5-channel amp.
  The channel map stays the same.
