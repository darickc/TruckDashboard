# ADR 0013 — Power from a mini-box DCDC-USB; the CarPiHAT is dropped

- **Status:** Proposed (decided by the owner; the PSW-to-J2 link and the
  timers are pending bench measurement)
- **Date:** 2026-11-04
- **Amends:** [power-states.md](../power-states.md),
  [camera-policy.md](../camera-policy.md),
  [audio-routing.md](../audio-routing.md), and Phases 4.3, 5.2, 6.2, 6.6,
  6.7 and 7.1 in [PROJECT_PLAN.md](../../PROJECT_PLAN.md). It settles the
  "CarPiHAT decision is still open" consequence of
  [ADR-0012](0012-direct-can-usb-adapter.md).

## Context

The plan used the CarPiHAT PRO 5 for:

- 12 V→5 V power and an ignition latch
- opto inputs for ignition, reverse, both turn signals and illumination
- two 12 V outputs (the amplifier remote)
- the I2S DAC
- CAN

[ADR-0012](0012-direct-can-usb-adapter.md) already moved CAN to a USB adapter.
Two of the HAT's open questions are still unanswered: its unpublished input
protection (H2) and whether the DSI ribbon clears it (H3).

The owner chose the **mini-box DCDC-USB** for power (2026-11-04). It is a 6–34 V
buck-boost converter. In automotive mode it is ignition-aware and sends an
ON/OFF pulse to a motherboard's power-switch pins. The documented facts and the
gaps are in the
[compatibility matrix](../../hardware/compatibility-matrix.md#mini-box-dcdc-usb).

On the Pi side, the Raspberry Pi 5 has a **J2** breakout for a normally-open
momentary power button. Closing it briefly does the same thing as the onboard
button ([matrix](../../hardware/compatibility-matrix.md#raspberry-pi-5-power-button-and-5-v-input)).

## Decision

1. **Power: DCDC-USB in AUTOMOTIVE mode.**
   - VIN: a fused constant 12 V feed.
   - IGN: the radio harness's accessory (ACC) feed.
   - VOUT: set to about 5 V and fed into the Pi 5.
   - PSW: wired to the Pi 5's J2 pads, once H21 confirms PSW is a dry or
     open-collector contact.
2. **The DCDC-USB is the single authority on power timing.**
   - The Pi never halts on its own because the ignition went off. It shuts
     down when the PSW pulse arrives.
   - OFFDELAY and HARDOFF are set over USB. HARDOFF is the hard backstop: it
     cuts power even if the Pi hangs.
3. **power-manager handles the power key itself.**
   - logind is set to `HandlePowerKey=ignore`.
   - power-manager ignores a press during the boot window, which covers the
     supply's ON pulse.
   - It acts on a press when the ignition is off, according to the
     DCDC-USB's USB telemetry. If that telemetry is unavailable, it acts on
     any press outside the boot window.
   - It reads the ignition and input voltages from the DCDC-USB over USB. This
     is unverified on Linux (H24). Without it, the system runs pulse-only.
4. **The CarPiHAT PRO 5 is dropped entirely.** Its other jobs are replaced
   separately:

   | Job | Replacement |
   |---|---|
   | Reverse input | A **protected opto-isolated input board** on Pi GPIO, read by power-manager. Its output side is powered from the Pi's **3.3 V**, never 5 V. At least 4 channels, so the turn signals can be added later |
   | Turn signals | **First check HS-CAN** with a listen-only event capture ([can.md](../../setup/can.md#event-captures-turn-signals-and-reverse)). If they aren't there, use two more channels on the same opto board |
   | Illumination | No input. Day/night comes from sun position (GPS time and location) and a manual override |
   | DAC | An I2S DAC HAT. Pick it by its documented line level and mute-at-boot behaviour (H6). **Chosen: the HiFiBerry DAC8x ([ADR-0014](0014-multichannel-dac8x.md))** |
   | Amplifier remote | A GPIO-driven switched 12 V output that fails **off**, part TBD (H5). It waits on the amplifier inventory (H8). **Superseded 2026-11-05:** ACC through a delay-on timer relay, not on the Pi ([ADR-0014](0014-multichannel-dac8x.md)) |
   | CAN | The USB adapter (ADR-0012), unchanged |

5. **The UI offers Restart, not Shut down, while the ignition is on.** If the
   Pi halts with ACC still on, the next off-pulse would wake it, and HARDOFF
   would then cut it mid-boot. The existing dashboard **Power** button belongs
   to the temporary truck setup (3.5.3) and is revisited in Phase 6.7.

## Consequences

**Gains:**

- The supply has documented input protection and a deep-discharge cutoff
  (11.2 V during HARDOFF). It boosts from 6 V, which should ride through
  cranking dips better than a plain buck converter. This is unverified on this
  truck (Phase 7.2).
- A hung Pi still loses power after HARDOFF. The CarPiHAT design needed the Pi
  to release its latch.
- The HAT's open questions about termination, protection and ribbon fit
  (H1–H3) no longer apply.

**Costs and risks:**

- **The PSW pulse is a toggle, not a level.** These cases are handled in
  [power-states.md](../power-states.md#edge-cases-of-a-toggle-signal), not
  eliminated:
  - a stray ON pulse during boot
  - an off-pulse when the Pi is already halted
  - the ignition returning during HARDOFF (H23)
- **Without the USB telemetry, the Pi can't see the ignition.** The countdown
  banner and the reboot-instead-of-halt check need H24.
- **More parts:** an opto board, a DAC HAT and an amplifier-remote switch (now a delay-on timer relay on ACC, ADR-0014),
  instead of one HAT.
- **The radio harness's ACC behaviour is unknown on this truck (H22).** It may
  drop while cranking, or stay on after key-off (Ford accessory delay).
  OFFDELAY must cover a cranking dropout.
- **Feeding the Pi 5 from a supply that doesn't negotiate USB-PD**: the Pi
  limits its USB ports to 600 mA unless it is told it has a 5 A supply
  (`PSU_MAX_CURRENT=5000` in the EEPROM). Whether the DCDC-USB delivers 5 A at
  5 V is unverified (H25).

**Tests:**

- power-manager's handling of the power key, telemetry loss, the boot window
  and reboot-instead-of-halt is pure logic, unit-tested `[SIM]` in Phase 6.7.
- Everything electrical is `[BENCH]` first: H21, H23, H25, and HARDOFF against
  the measured shutdown time.

## Revisit if

- PSW turns out to be a driven voltage that can't be adapted cleanly. Then a
  small relay or optocoupler goes between PSW and J2.
- The ignition-return-during-HARDOFF case (H23) leaves the head unit dead
  often enough to matter.
- The DCDC-USB can't hold 5 V at the Pi's load. Then it runs at 12 V into a
  dedicated 5 V / 5 A converter.
