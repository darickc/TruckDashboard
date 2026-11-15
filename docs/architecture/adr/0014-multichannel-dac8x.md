# ADR 0014 — Multichannel DAC (HiFiBerry DAC8x), a new 4-channel amp, and the R150-2 kept

- **Status:** Proposed (decided by the owner; the DAC's boot behaviour, its
  header pass-through and the R150-2's bridged input are pending)
- **Date:** 2026-11-04. Amended 2026-11-05: the amplifier remote is on ACC
  through a delay-on timer, not on the Pi (decision 6). Amended 2026-11-09
  (owner): ACC goes straight to the amps' remote leads, with no timer.
  Amended 2026-11-15: the board bought is a RaspiAudio 8xOUT on the same
  driver; channels identified on the bench
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
6. **The amplifiers' remote leads are switched by ACC**, not by the Pi (owner,
   2026-11-05). This replaces the GPIO-driven switch planned in ADR-0013.
   - **Amended 2026-11-09 (owner): ACC straight to both REM leads, through a
     small fuse, with no timer.** The 2026-11-05 version put a delay-on timer
     relay in between, so the amps came on after the DAC was up.
   - The amps come on at key-on, while the Pi is still booting.
   - At key-off the amps go off at once, before the Pi shuts down.
   - The Pi has no amplifier output, no GPIO for it, and no crash-state
     requirement on one.
7. **The GPIO plan moves to fit the DAC8x.** Its overlay claims BCM18–27 and
   reads BCM5. Proposed:
   - reverse moves to BCM6
   - turn signals to BCM12 and BCM13
   - BCM5 left unconnected

   **Superseded 2026-11-09** ([ADR-0024](0024-camera-selection-switch-and-can-reverse.md)):
   no reverse or turn-signal inputs. BCM6, 12, 13, 16 and 17 are proposed for
   the camera switch. BCM5 stays unconnected.

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
- **Mute at boot is undocumented** (H6), and the amps are on while the DAC
  initialises (decision 6). Any pop or DC step at power-up reaches the
  speakers. The bench scope check ([audio.md check 3](../../wiring/audio.md#checks-before-sign-off))
  shows whether there is one; if it is audible, a delay-on timer relay goes
  back between ACC and REM, with no change on the Pi (Revisit if).
- **A Pi crash with the key on leaves the amps on** (decision 6). Usually that's
  silence; the worst case is a repeating-buffer buzz until key-off (H5). Key-off
  always cuts the amps. The safety assumption is "key-off always cuts the
  amplifiers", not "a crash leaves them off".
- **If ACC drops while cranking** (H22), the amps drop out with it and come
  back when it returns.
- **A software crossover means a misconfiguration sends full-range audio to the
  subs or bass to small door speakers.** The R150-2's own low-pass can stay on
  as a backstop. The audio-manager config gets validation tests.
- **The AGL image's support for the overlay is unknown.** It is in the
  Raspberry Pi kernel tree (`rpi-6.12.y`); whether the AGL Vimba kernel carries
  it is checked in Phase 5.
- A new amplifier and power wiring: more installation work than a Y-split.

**Tests:**

- The PipeWire channel map, crossover and fader configuration: generated and
  validated by audio-manager, unit-tested `[SIM]` (done 2026-11-12,
  [ADR-0039](0039-audio-manager.md); not run in PipeWire yet).
- Everything electrical is `[BENCH]` first: line level, boot pop, remote-off on
  crash. Then `[TRUCK]`: polarity, whine, gain. The checklist is in
  [wiring/audio.md](../../wiring/audio.md#checks-before-sign-off).

## Revisit if

- The DAC8x pops audibly at power-up with the amps on (H6). First put a
  delay-on timer relay between ACC and the REM leads, set above the measured
  boot-to-audio time. If the pop also comes at other times, or AGL can't load
  the overlay, use a USB multichannel DAC, or a stereo DAC into a car DSP.
- The header can't be shared with the camera switch's wiring (H27).
- A Pi crash produces a buzz or loud noise through the amps (H5). Then go back
  to a Pi-controlled remote with a hardware heartbeat timer that drops it.
- The owner replaces the R150-2 and the new 4-ch amp with one 5-channel amp.
  The channel map stays the same.

## Amendment, 2026-11-15: the board is a RaspiAudio 8xOUT `[BENCH]`

The owner bought a **RaspiAudio 8xOUT**, not a HiFiBerry DAC8x. The channel
map, the filter-chain and the GPIO plan above stand. Bench details in
[bench-log](../../hardware/bench-log.md) (2026-11-15); facts and sources in
the [compatibility matrix](../../hardware/compatibility-matrix.md#raspiaudio-8xout).

1. **Same driver.** Its HAT EEPROM reads vendor "Raspiaudio.com", product
   "8xOUT", and loads the `hifiberry-dac8x` overlay by itself: the card is
   `snd_rpi_hifiberry_dac8x` on AGL 22's kernel (6.18), with
   `dtoverlay=hifiberry-dac8x` still commented out in `config.txt`.
   RaspiAudio's guide names the same overlay, and four PCM5102A DACs.
2. **PipeWire's default profile is wrong for it.** ACP offers
   `output:stereo-fallback` (2 channels, the first jack only) and `pro-audio`
   (one 8-channel sink, `AUX0`–`AUX7`), and picks the first; AGL's
   WirePlumber is stateless, so a profile chosen by hand is lost at boot.
   **Decision:** `62-f250-dac.conf` makes `pro-audio` this card's preferred
   profile (`device.profile.priority.rules`), and `/etc/default/f250` ships
   `AUDIO_DAC_NODE=alsa_output.platform-soc_107c000000_sound.pro-output-0`
   and `AUDIO_DAC_POSITIONS=AUX0,…,AUX7`.
3. **Jacks and channels**, identified with a spoken "channel N" per channel
   into a powered speaker (left and right correct on all four). Jacks are
   numbered from the end **furthest from the Pi's USB ports**, so jack *n*
   carries `AUX(2n−2)`/`AUX(2n−1)`, and the default pairs (0,1 / 2,3 / 4,5)
   put front, rear and sub on jacks 1, 2 and 3 as decision 2 planned; jack 4,
   nearest the USB ports, is the spare.
4. **It must see the header's I2S pins.** With the owner's PoE HAT (kept for
   its fan) between the Pi and the 8xOUT, the EEPROM was read and the stream
   ran on GPIO18–27, but no jack made a sound; directly on the header it
   worked. Which of the PoE HAT's pins don't pass through wasn't checked.
   So the Pi needs other cooling under the DAC: decision 7 of
   [ADR-0047](0047-head-unit-enclosure.md) already plans the Active Cooler
   on a 16 mm stacking header (fit UNVERIFIED with the 8xOUT).
5. **Open:** RaspiAudio's pinout lists one output's data line on GPIO17
   (header pin 11), which the overlay doesn't use and the camera switch
   claims ([ADR-0024](0024-camera-selection-switch-and-can-reverse.md)).
   All four jacks played with the overlay's pins (GPIO21/23/25/27), so the
   guide's line looks wrong for this board, but the board's traces weren't
   checked: check that pin 11 isn't connected on the 8xOUT before wiring the
   camera switch (H27). Mute at power-up (H6), the line level, and the boot
   pop with the amplifiers are still to measure.
