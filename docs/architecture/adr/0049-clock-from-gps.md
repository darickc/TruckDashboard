# ADR 0049 — The clock from GPS: gps-clock

- **Status:** Accepted (owner, 2026-11-17: "Add for the gps to update the
  clock."). `[SIM]`: no GPS receiver is fitted yet (H11).
- **Date:** 2026-11-17
- **Refines:** [ADR-0028](0028-day-night-and-backlight.md) decision 3 ("the
  system clock is never changed … setting it belongs to whatever keeps
  time … a separate decision"), [ADR-0027](0027-front-and-rear-recording.md)
  decision 10 (when recordings are named with the time).

## Context

In the truck the Pi has no network most of the time, so network time
(connman's NTP client) rarely sets its clock. Since 2026-11-17 the RTC cell
keeps the time across power cuts, if it holds (H20); without that, the
clock starts at the last shutdown or 1970. Recording names, retention by
age and the screen's day/night all need the real time, and they only
believe a clock the system reports as synchronized.

A GPS receiver (H11, not chosen) gives UTC with every fix. navigation
already reads gpsd (ADR-0030), and power-manager already uses GPS time for
the sun, without changing the system clock.

| Fact | Source | Status |
|---|---|---|
| The image has gpsd (`/usr/sbin/gpsd`, `gpsd.socket` active), no chrony and no ntpd; connman keeps time (`FallbackTimeservers=pool.ntp.org`) | bench Pi, image 58beac2, 2026-11-17 | `[BENCH]` |
| `/dev/rtc0` is `root:clock 0660`; `/usr/sbin/hwclock` is BusyBox 1.37's (util-linux's isn't installed): `-w -u -f DEV`, no `--systohc` or `--noadjfile` | bench Pi, 2026-11-17 | `[BENCH]` |
| Under gps-clock's sandbox (user f250, group clock, CAP_SYS_TIME, `@system-service @clock`): `date -s` sets the clock and `hwclock -w -u -f /dev/rtc0` writes the RTC, no `/etc/adjtime` | bench Pi, 2026-11-17 (`systemd-run` with the unit's properties) | `[BENCH]` |
| gpsd's TPV time without PPS is the time of the fix, reported late by up to a fraction of a second, receiver-dependent | gpsd's documentation | Unverified for our receiver: none chosen |
| `clock_settime(CLOCK_REALTIME)` needs CAP_SYS_TIME; systemd's `ProtectClock=` blocks it | clock_settime(2), systemd.exec(5) | Verified |

## Options considered

1. **chrony with gpsd's shared memory (SHM) refclock.** The usual answer and
   the most accurate (with PPS, microseconds). But chrony isn't in the
   image (a new recipe), it would replace connman's time keeping (two NTP
   clients fight), and none of it can be tried without a receiver. Kept for
   later, if sub-second time ever matters (it doesn't for file names or
   the sun).
2. **navigation sets the clock.** It already reads gpsd, but it would need
   CAP_SYS_TIME in a service that also runs Valhalla and reads map data.
3. **power-manager sets the clock.** It already takes GPS time, but
   ADR-0028 kept CAP_SYS_TIME out of the service that owns the power key.
4. **A small service that only does this (chosen).**

For "the clock is synchronized" there were two ways: clear the kernel's
`STA_UNSYNC` with `adjtimex(2)` (what NTP daemons do; it needs an unsafe
call, which the workspace forbids, and it would make GPS time look like
network time to everything), or a flag file next to timesyncd's, which
`crates/clock-sync` already reads in the same way (chosen).

## Decision

1. **`services/gps-clock`**, a daemon with one privilege, CAP_SYS_TIME
   (`f250-gps-clock.service`, user f250, group clock for `/dev/rtc0`,
   AF_UNIX only, no network). It follows navigation's `WatchPosition`; it
   never talks to gpsd itself.
2. **Only a real, current fix's time:** not the simulated receiver, not a
   last-known fix, a 2D/3D fix with a UTC time, never before 2026 (a week
   rollover). The time is the fix's UTC plus its age.
3. **Network time wins.** While `clock_sync::network_synchronized()` says
   yes, gps-clock does nothing.
4. **Three readings that agree** (GPS minus the monotonic clock within
   0.5 s of each other) before anything, so one bad report sets nothing.
5. **Step only when the clock is more than 1 s off** (`--step-threshold-ms`,
   an example: without PPS, GPS time is good to a fraction of a second).
   Otherwise the clock is confirmed. After a step or the first
   confirmation, `hwclock -w -u -f /dev/rtc0` writes the RTC, so
   the next cold start begins at the right time.
6. **No second step within 10 minutes** of one: that means something else is
   setting the clock, and gps-clock logs it instead of fighting.
7. **The flag:** once it has stepped or confirmed the clock, gps-clock writes
   `/run/f250-gps-clock/synchronized` (`clock_sync::GPS_FILE`). `/run` is
   emptied at every boot. `clock_sync::system_synchronized()` (camera-manager,
   power-manager) counts it as synchronized, so recordings get their time
   and Auto day/night works with GPS and no network, without
   `RECORD_TRUST_CLOCK` or `DISPLAY_TRUST_CLOCK`.
8. **`--dry-run`** logs what it would do; `--accept-simulated` (development
   only, with `--dry-run`) lets the bench check the plumbing.

## Consequences

- With a receiver fitted, the clock is right within seconds of a fix even
  after the RTC cell fails or drifts, and the RTC is corrected too.
- power-manager's own GPS time (ADR-0028) stays: it covers the seconds
  before gps-clock has acted, and a fix it accepts gps-clock also accepts.
- Sub-second accuracy is not a goal. PPS or chrony would be a new decision.
- To verify with a receiver (H11): a cold start with Wi-Fi off and the
  clock set wrong (`date -s`), then `journalctl -u f250-gps-clock`
  shows "stepped the clock by …", `hwclock -r` agrees, and the flag file
  exists; with Wi-Fi on, "network time keeps the clock".
