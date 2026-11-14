# ADR 0028 — Day/night and the backlight belong to power-manager

- **Status:** Accepted. [SIM] only: the sun calculation, the day/night
  decision, the brightness ramp and the API are unit-tested, and the dashboard
  follows a simulated source and a fake power-manager. Nothing has dimmed the
  Pi's panel through power-manager yet. Amended 2026-11-14: the location and
  the clock from GPS (below), [SIM]
- **Date:** 2026-11-11
- **Refines:** [power-states.md](../power-states.md) "Day/night and
  brightness", [ADR-0013](0013-dcdc-usb-power-supply.md) (no illumination
  wire; power-manager owns the head unit's hardware outputs)

## Context

The dashboard has a day and a night palette, picked by hand under
Diagnostics, and nothing changes the backlight. There is no illumination
(dash-lights) wire and no light sensor, so the only automatic input is the
sun's position, which needs the time and where the truck is. GPS (6.4) isn't
built; the Pi 5 has no RTC cell yet (H20), so after a cold start its clock is
the last shutdown's time until network time arrives.

The panel's backlight is `/sys/class/backlight/10-0045` on the Pi 5 with
AGL 22.0.1, `max_brightness` 255, and it takes writes
([bench-log](../../hardware/bench-log.md) 2026-11-06, check 4).
systemd-backlight saves the level at shutdown and restores it at boot.

## Decision

1. **power-manager decides day or night and drives the backlight.** The
   dashboard follows it and never writes sysfs. One authority, so the theme
   and the brightness can't disagree.
2. **The sun's elevation** (the Astronomical Almanac's low-precision
   formulas, ±0.1°) from the wall clock and a configured location,
   `DISPLAY_LATITUDE` and `DISPLAY_LONGITUDE` in `/etc/default/f250`. GPS
   replaces the configured location when 6.4 lands. Night when the sun is
   below `DISPLAY_NIGHT_BELOW_DEG` (−3°), day again once it is above that
   plus `DISPLAY_HYSTERESIS_DEG` (1°). **Both are example values.**
   Evaluated every 30 s.
3. **Auto runs only on a clock and a location it can believe.** Otherwise the
   display uses `DISPLAY_FALLBACK` and says why on screen ("Auto unavailable:
   clock not synchronized"):
   - no location configured
   - the clock isn't trusted: by default only while the system reports it
     synchronized (`NTPSynchronized`, as camera-manager decides for
     recordings, ADR-0027 decision 10). `DISPLAY_TRUST_CLOCK=always` trusts
     it anyway, for the bench and once the RTC cell is verified (H20)
   - the clock reads before 2026 (never plausible), whatever the setting
4. **The fallback is Day**, an example value. A dim night screen in daylight
   can make an alert unreadable; a bright screen at night is uncomfortable,
   and the driver fixes it with one tap.
5. **The driver's choice: Auto, Day or Night**, and a brightness for each of
   day and night. power-manager keeps them in its state directory
   (`/var/lib/f250-power/display`), so they survive a key cycle. Defaults:
   Auto, day 100 %, night 40 % (examples).
6. **The backlight**
   - the first device under `/sys/class/backlight`, or `DISPLAY_BACKLIGHT`;
     never a hard-coded path
   - a percentage of `max_brightness`, never below
     `DISPLAY_MIN_BRIGHTNESS_PCT` (10 %, an example), so the screen and its
     alerts never go dark
   - changes ramp over 1 s
   - written by a thread of its own, so a slow or hung I2C write never holds
     up the power key
   - no backlight, or a write that fails, is reported to the dashboard; the
     theme still changes
   - a udev rule (`60-f250-backlight.rules`) gives group f250 write access
     to `brightness`. The unit drops `ProtectKernelTunables=`, which would
     make all of `/sys` read-only; file permissions still keep the service
     to that one file
7. **The API is `f250.power.v1` `DisplayService`** (`WatchDisplay`,
   `SetDisplay`) on `/run/f250-power/power.sock`, group f250 like the
   gateway's socket. If the dashboard loses it, it keeps the last theme it
   was told, says day/night and brightness aren't being controlled, and lets
   the driver pick Day or Night for the screen alone.

## Consequences

- In the truck, Auto works only after network time or with
  `DISPLAY_TRUST_CLOCK=always` once the RTC cell holds the time. Until then
  the screen sits on the fallback and says so. GPS time (6.4) would remove
  this.
- A location in `/etc/default/f250` is a setting the owner must fill in; with
  it empty, Auto says so instead of guessing.
- The dashboard's theme no longer lives in its own settings.

## To verify on the Pi

- the udev rule applies to `10-0045` (group f250, `g+w` on `brightness`)
- power-manager's sandbox writes it without `ProtectKernelTunables=`
- the ramp looks smooth on the panel, and 10 % is readable
- systemd-backlight's restore at boot followed by power-manager's level

## Amendment, 2026-11-14: the location and the clock from GPS

GPS is built (6.4, ADR-0030): navigation serves `f250.nav.v1`
`WatchPosition` on `/run/f250-nav/nav.sock`. Decision 2 said GPS would
replace the configured location; this is how, and it also takes the
Consequences' "GPS time would remove this" at its word.

1. **power-manager follows navigation's `WatchPosition`**
   (`DISPLAY_NAVIGATION`, `unix:/run/f250-nav/nav.sock` from the unit;
   empty: none). It never talks to gpsd (CLAUDE.md rule 5's spirit: one
   owner per device). AF_UNIX, so its sandbox is unchanged; a missing
   navigation is logged and the display runs on what it had.
2. **Location, in order:** this run's latest GPS fix, *current or not*
   (the sun needs roughly where the truck is: 0.1° of longitude moves
   sunset by 24 s, and a truck is never far from its last fix); the last
   GPS position saved in `/var/lib/f250-power/location`; the configured
   `DISPLAY_LATITUDE/LONGITUDE`; nothing. The position is saved rounded to
   0.1° (about 11 km), only once the truck is 0.1° from the saved one, so
   a parked truck's jitter never writes the SD card, written whole
   (temporary file, synced, renamed). A damaged file is ignored and
   rewritten at the next fix. Delete it to forget it.
3. **Clock, in order:** the system clock while the system reports it
   synchronized; GPS time; the system clock trusted by
   `DISPLAY_TRUST_CLOCK=always`; none (the fallback, as before). GPS time is
   taken only from a **current, real fix with a fix status and a UTC time
   from 2026 on** (a week-rollover receiver reporting 2019 is refused), as
   the fix's time plus its age, then carried forward with the monotonic
   clock for as long as power-manager runs. **The system clock is never
   changed:** power-manager has no `CAP_SYS_TIME`, and setting it belongs
   to whatever keeps time (connman today; chrony with gpsd's shared memory
   would be the way, a separate decision).
4. **The simulated receiver is never the truck.** Its positions are
   ignored unless `--gps-accept-simulated` (development only, labelled
   SIMULATED on screen, never saved), and its time is never used.
5. **The API says where both came from:** `Display.location_source` (none,
   GPS, saved GPS, configured, simulated GPS), `location_age_s` (GPS only:
   how old the fix was when the sun was last worked out) and
   `clock_source` (none, system, GPS, trusted). Settings → Display shows
   them under the mode ("Location: GPS (last fix 10 min old) · Clock: GPS
   time"); an older power-manager that doesn't say gets no line. A first
   fix or GPS time decides at once, not at the next 30 s tick.

Tested `[SIM]`: the order of locations and clocks, saving (jitter, a drive,
a saved position from an earlier run), the time rules (not current, no fix
status, 2019, no time, carried forward, kept after the fix is lost), the
simulated receiver both ways, nonsense fixes, the file round trip and damage;
the display task deciding at once on a fix and saving it; and the real binary
against a fake navigation on a unix socket (a real fix: GPS location and
time, saved; restarted without navigation: the saved position; a simulated
fix: ignored, or labelled with the flag). The dashboard's line and its
mapping, at 800×480 in both themes. **Not on the Pi; no receiver is chosen
yet (H11).**

To verify on the Pi with a receiver: the line reads GPS and GPS time after
a cold start with Wi-Fi off; `/var/lib/f250-power/location` appears after
the first fix and isn't rewritten while parked.
