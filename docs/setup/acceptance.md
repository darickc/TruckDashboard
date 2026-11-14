# Acceptance checklist (in the truck)

Phase 7.5. Run this once the head unit is installed, and again after any change
to the wiring, the power supply's timers or the image. It checks the installed
system in the truck: the [bring-up checks](agl.md#5-bring-up-checks-phase-52)
check each piece on the bench first, and the
[truck session](../diagnostics/TRUCK_SESSION.md) verifies individual signals.

**How to record it.** Each item that passes gets a `[TRUCK]` entry in the
[bench log](../hardware/bench-log.md) with the date, the image (`cat
/etc/f250-release`) and what was measured. An item that fails gets an entry too,
with what happened. Nothing here counts as done from memory or from a
simulation (CLAUDE.md rule 7). When something fails, the
[troubleshooting guide](troubleshooting.md) says where to look.

**Every number below marked "example" is configuration**, not a requirement
(CLAUDE.md rule 10). Where a measurement sets one, record the measured value and
the setting chosen.

The **Status** column says what has already been shown, as of 2026-11-14, and
where. Everything else is still to do.

## 0. Before installing

These are the [human verification gates](../safety/assumptions.md#human-verification-gates):
a person signs each off in the bench log before going ahead.

| # | Check | Pass | Status |
|---|---|---|---|
| 0.1 | Wiring diagrams ([docs/wiring](../wiring/README.md), Phase 7.1): PSW to J2, VOUT to the Pi, the TVS, the ground scheme, the DLC tap, the amplifiers' signal, remote and fused power, the camera switch's cable, camera power | Each reviewed and signed by a person | Not drawn yet |
| 0.2 | The DLC connection | Termination measured with the truck off, before anything is plugged in ([can.md](can.md)) | Measured 2026-11-06 `[TRUCK]` |
| 0.3 | No 12 V signal reaches Pi GPIO | The only GPIO input is the camera switch on the Pi's own 3.3 V ([ADR-0024](../architecture/adr/0024-camera-selection-switch-and-can-reverse.md)); confirm on the wiring as installed | — |
| 0.4 | Bring-up checks 1–25 for the parts fitted | Each has a `[BENCH]` entry | Most done; see [agl.md](agl.md#5-bring-up-checks-phase-52) |
| 0.5 | Settings for the truck | `/etc/default/f250` has the transport and options meant for driving (`TRANSPORT=can`, `CAN_AUTO_ACTIVE=1`, and so on), with a copy kept | — |

## 1. Power

The supply's behaviour is in [power-states.md](../architecture/power-states.md).

| # | Check | Pass | Status |
|---|---|---|---|
| 1.1 | Key on | The Pi boots on ACC; record the time from key-on to the dashboard showing live data | Boots on the bench supply only |
| 1.2 | Cranking with the unit running | No reboot, no dashboard restart (`journalctl -b` has no new boot; `uptime`). Record the ACC feed's dip if measured (H22) | — |
| 1.3 | Key off | After OFFDELAY the supply pulses PSW and the Pi halts cleanly: after the next boot, `journalctl -b -1 -u f250-power-manager` ends with "power off: power key after the boot window". Record OFFDELAY and the shutdown time | Power key `[BENCH]` with the Pi's own button; PSW on J2 not wired |
| 1.4 | HARDOFF is long enough | The worst measured shutdown time from 1.3, with margin, is shorter than HARDOFF | — |
| 1.5 | A quick key cycle | Key off and back on inside OFFDELAY: note whether the supply cancels its pulse (H23) and what the Pi does | — |
| 1.6 | The supply's ON pulse | Inside the boot window (`BOOT_KEY_IGNORE_S`, 30 s, an example): "ignored: inside the boot window" in power-manager's log; record when it arrives (H21) | — |
| 1.7 | Parked draw | Measured with the unit off after HARDOFF; the target is ≤ 1 mA ([PROJECT_PLAN](../PROJECT_PLAN.md) 7.2) | — |
| 1.8 | Overnight | The truck starts normally after a night parked with the unit installed | — |
| 1.9 | A hard cut | Pull VOUT with the Pi running; it boots next time, and recordings and settings are intact (`RECORD_UNCLEAN_PROTECT_MIN` protects the segments before the cut) | — |

## 2. The vehicle bus

[ADR-0007](../architecture/adr/0007-read-only-vehicle-access.md): listen-only
at boot, active only after a clean listen with `CAN_AUTO_ACTIVE=1`.

| # | Check | Pass | Status |
|---|---|---|---|
| 2.1 | Listen first | `journalctl -u f250-can-auto -b`: "listening 3 s", then active only after a clean listen (at least 1000 frames, no errors; examples) | Drives 2026-11-10 and 2026-11-14 `[TRUCK]` |
| 2.2 | The truck doesn't notice | With the unit on for a whole drive: no new warning lights or messages on the cluster, and the truck drives as it does without it | — |
| 2.3 | Every signal enabled answers | Diagnostics shows each enabled PID current through a drive; no "Not polling the truck" | Every signal answered on the 2026-11-14 drives `[TRUCK]` |
| 2.4 | Pull the adapter while driving | Within seconds the values go STALE with their age and "Vehicle data lost" shows; nothing is shown as current. Plug it back in: values return without a restart | — |
| 2.5 | Ignition off with the unit up | can-auto and the gateway don't fault while the bus goes quiet before the halt | — |
| 2.6 | Bus health after a long drive | `ip -details -statistics link show can0`: no bus-off, error counters near zero | — |

## 3. What's on screen

| # | Check | Pass | Status |
|---|---|---|---|
| 3.1 | Values against the truck | Each signal with an entry in the [verification log](../diagnostics/VERIFICATION_LOG.md) reads as logged; any other is marked unverified on screen | Per signal, in the log |
| 3.2 | Stale data is never current | With 2.4: every gauge shows its last value, its age and STALE; EOT − ECT and other computed values blank while an input is stale | `[SIM]` tests; 2.4 to do |
| 3.3 | Alerts | Each configured threshold (examples, set in the dashboard's configuration) raises its alert; critical alerts show on every screen and in camera mode, and can't be cleared | `[SIM]` tests |
| 3.4 | Readable | In direct sun and at night, from the driver's seat: the gauges at a glance, the status bar's badges; Auto day/night switches at dusk (check 15) | — |
| 3.5 | Touch | Every button works with one tap from the driver's seat, at speed on a rough road | — |
| 3.6 | First drive (gate 4) | A person confirms nothing distracts the driver or blocks the view: the screen's position, its brightness at night, glare, the knob | — |

## 4. Cameras

| # | Check | Pass | Status |
|---|---|---|---|
| 4.1 | Reverse | Shift into R: the rear camera within about a second; out of R: gone after the hold (2 s, an example); through R into P: no flash ([ADR-0046](../architecture/adr/0046-automatic-reverse.md)) | 0.89–0.97 s on 2026-11-14 `[TRUCK]`; the 300 ms debounce not driven yet |
| 4.2 | A cold start in R | Starting in reverse brings the rear camera up once the bus is heard | — |
| 4.3 | No reverse signal | Unplug the CAN adapter: "reverse unknown"; the camera doesn't come up by itself | `[BENCH]` on vcan0 |
| 4.4 | The camera switch | Each position shows its camera; press closes ([ADR-0024](../architecture/adr/0024-camera-selection-switch-and-can-reverse.md)) | Switch not wired |
| 4.5 | Recording | After a drive, `ls /var/lib/f250/storage/video/*` has continuous segments for each recorded camera; no "not recording" advisory; Save clip protects a clip | — |
| 4.6 | Picture at night and in sun | Usable for reversing; the mirrors stay the authority ([safety](../safety/assumptions.md)) | — |

## 5. Audio

| # | Check | Pass | Status |
|---|---|---|---|
| 5.1 | Key on and off | No loud pop through the amplifiers at either; key-off cuts them (their remote is on ACC) | DAC8x not fitted |
| 5.2 | A crash with the key on (H5) | With music playing, crash the Pi with the key on (a kernel panic, then a watchdog reset): silence or a short pop is acceptable, a sustained buzz is not ([power-states.md](../architecture/power-states.md#crash-and-reset-behaviour-to-be-verified-on-hardware)) | — |
| 5.3 | The phone at key-on | The last phone reconnects by itself and its music resumes as the phone decides | Reconnecting `[BENCH]` 2026-11-12 |
| 5.4 | Speakers | Fader, balance and sub level change what is heard; the crossover set by ear (examples) | — |
| 5.5 | Volume | Starts no louder than the start cap; the knob follows without lag | No knob chosen yet |
| 5.6 | Spoken directions over music | Heard over road noise; the music stops at once and resumes about a second after | The music's cork `[BENCH]` 2026-11-12; the phone's pause untested |
| 5.7 | Phone calls, once enabled | Calls stay on the phone until a microphone is configured. When it is: ring, answer, both sides heard over road noise, no echo at the far end, the knob's push ([ADR-0045](../architecture/adr/0045-phone-calls.md)) | `[SIM]`; S2–S4 on the bench first |

## 6. Navigation

| # | Check | Pass | Status |
|---|---|---|---|
| 6.1 | Position | With a GPS receiver fitted (H11) and `NAV_SIMULATE=0`: a fix within a few minutes of a cold start; the dashboard never shows a lost fix as current | No receiver yet |
| 6.2 | Map, routing and search data | Present on the data drive (checks 17, 18, 20); a route to a known address; a re-route after a wrong turn | Import, routing and search `[BENCH]` 2026-11-12, simulated position |
| 6.3 | Heavy vehicles | Every route says it isn't checked for heavy vehicles or trailers ([safety](../safety/assumptions.md)) | `[SIM]` |

## 7. Heat and long runs

| # | Check | Pass | Status |
|---|---|---|---|
| 7.1 | A closed cab in summer (Phase 7.3) | Log `/sys/class/thermal/thermal_zone0/temp` through a hot soak and the drive after it; the dashboard stays responsive; record the peak | — |
| 7.2 | Long drives (Phase 7.4) | Several hours: no service restarts (`journalctl -b` for "Watchdog timeout" or "Main process exited"), the recorder's data complete, the gateway's recoveries counted on Diagnostics and in the recorder | — |

## Sign-off

| Date | Image | Sections passed | Sections failed or left | Who |
|---|---|---|---|---|
| | | | | |
