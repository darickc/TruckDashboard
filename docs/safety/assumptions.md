# Safety assumptions and boundaries

These apply to every phase. A change that would weaken one needs an ADR and the
owner's explicit agreement.

## What the system is not

- **Not a safety system.** The factory instrument cluster, its warnings, the
  mirrors and normal reversing procedures remain authoritative. The cameras may
  be unavailable while booting, after a crash, or when hardware fails. They are
  never presented as a certified backup camera.
- **Not a vehicle controller.** No actuator control, no ECU programming, no
  immobilizer or security-access work, no module configuration writes, no
  safety-module interaction.
- **Not a navigation authority for heavy vehicles.** OSM routing doesn't
  guarantee clearances, weight limits or trailer suitability.

## What it must do

- **Read-only by default** ([ADR-0007](../architecture/adr/0007-read-only-vehicle-access.md)).
  It boots in listen-only and `PASSIVE_ONLY` mode. Diagnostic transmit is an
  explicit opt-in, gated on a recorded electrical checklist, and limited to an
  allow-list of read services.
- **Honest data.** Stale, invalid or unverified values are marked as such and
  never shown as current. Derived values need every input to be valid and
  current.
- **Independent failure.** If the Pi fails, the truck behaves exactly as it
  would without the Pi. The CAN node must not disturb the bus. This means
  correct bitrate, correct termination, and listen-only until verified.
- **Electrical isolation from vehicle signals.** No 12 V signal ever reaches Pi
  GPIO. Inputs go through a protected opto-isolated input board whose output
  side runs from the Pi's 3.3 V.
- **Failure-safe audio.** Key-off always cuts the amplifiers: their remote
  leads are on ACC through a delay-on timer, not on the Pi
  ([ADR-0014](../architecture/adr/0014-multichannel-dac8x.md)). A Pi crash with
  the key on can leave them on. It must not produce a sustained loud noise;
  this is to be verified ([H5](../hardware/open-questions.md)).
- **Battery protection.** The unit must not drain the truck's batteries when
  parked. The off-state draw is to be measured.

## Human verification gates

These steps need a person to inspect and sign off in
[bench-log.md](../hardware/bench-log.md) before they go ahead:

1. Connecting anything to the DLC: termination measured, wiring reviewed.
2. Moving from listen-only to any transmit.
3. Any permanent power, ground, signal or amplifier wiring.
4. First drive with the unit installed: confirm nothing distracts the driver
   or obstructs the view.

## Driver distraction

- Touch targets are at least 60×60 px (about 11 mm on the 7" panel).
- Glanceable layouts with large numerals.
- Text entry (navigation search) is meant for when the truck is parked. Whether
  to lock it out while moving is an owner decision, recorded when navigation
  lands.
- Critical alerts are visible on every screen. Nothing else interrupts the
  driver.
