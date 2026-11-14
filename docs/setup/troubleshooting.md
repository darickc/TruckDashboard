# Troubleshooting

Phase 7.5. Find the symptom, then work down its rows. Each row says what the
screen or log means, what to look at, and what usually fixes it. The
[acceptance checklist](acceptance.md) is the list of things to check; this is
for when one fails.

**Collect the evidence before changing anything.** A fix that works without a
record leaves the cause unknown, and the intermittent faults this project
exists to diagnose ([diagnostic-recovery.md](../architecture/diagnostic-recovery.md))
look like that.

```bash
make logs PI=raspberrypi5.local
```

`make logs` copies an archive of the journals and state into `build/logs/` on
the Mac. Then note what happened in the [bench log](../hardware/bench-log.md),
with `[TRUCK]` or `[BENCH]`.

**On the Pi** (AGL, `ssh root@raspberrypi5.local`): the project's tools
(`f250-can`, `f250-storage`, `camera-ctl`, `obd-console`) are in
`/opt/f250/bin`, which a login shell has on its PATH. Settings are in
`/etc/default/f250`; after editing it, restart the service it belongs to
(`systemctl restart f250-<name>`). Every service's log:
`journalctl -u f250-<name> -b` (this boot) or `-b -1` (the boot before, for
what happened before a power-off or crash). The services:

| Service | Does |
|---|---|
| `f250-gateway` | Vehicle data (CAN or the MX+, or the simulator) |
| `f250-can-auto` | Puts `can0` listen-only at boot, then active after a clean listen (`CAN_AUTO_ACTIVE=1`) |
| `f250-recorder` | Records the vehicle data and its health |
| `f250-dashboard` | The screen (never restart it alone: see below) |
| `f250-power-manager` | The power key, the camera switch, day/night and the backlight |
| `f250-camera-manager` | The cameras on screen, recording, automatic reverse |
| `f250-navigation` | GPS position, routing, search, saved places, spoken directions |
| `f250-audio-manager` | Phones, music, the speakers, the volume, calls |
| `f250-obexd` | The phone's cover art |
| `f250-usb-export` | Recordings to a USB stick |
| `f250-knob-link` | The knob display |
| `f250-map-import@…` | Map, routing and search data from a USB stick |

## The screen

| Symptom | Meaning | Look at | Usually |
|---|---|---|---|
| Panel dark | No picture at all: the panel, its cable or the compositor | `systemctl status agl-compositor`; `/opt/f250/share/agl/scripts/diagnose-display.sh` | [agl.md section 6](agl.md#6-fallback-is-it-the-hardware-or-agl): is it the hardware or AGL? |
| Black with a blinking cursor at the top | The text console: the compositor isn't running | `systemctl status agl-compositor`, `coredumpctl list` | `systemctl restart agl-compositor` (the dashboard comes back with it). **Never** restart `f250-dashboard` on its own: agl-compositor 0.0.24 aborts when a second homescreen app connects |
| Frozen, touch does nothing | The dashboard hung or the compositor did | `journalctl -u f250-dashboard -b`, `coredumpctl list` | `systemctl restart agl-compositor`; keep the journal |
| SIMULATED badge while driving | The gateway runs the simulator | `grep TRANSPORT /etc/default/f250` | The truck's settings (`TRANSPORT=can`, …); a reflash resets the file |
| Too dim or too bright | Day/night or a level | Settings → Display (it says where the location and clock come from) | Choose Day or Night by hand; Auto needs a location and a trusted clock ([ADR-0028](../architecture/adr/0028-day-night-and-backlight.md)) |

## Vehicle data

| Symptom | Meaning | Look at | Usually |
|---|---|---|---|
| **Not polling the truck** (critical) | Polling was asked for, but the gateway is passive; the alert says why (after 10 s) | `journalctl -u f250-can-auto -b`, `journalctl -u f250-gateway -b`, `f250-can status` | With the ignition off or on the bench, can-auto rightly stays listen-only: "not clean: 0 frames". In the truck: is the adapter plugged in (`ip link show can0`)? Then `systemctl restart f250-can-auto` |
| **Vehicle data lost** (critical) | No data from the gateway, or the link is down | The status bar's link; `systemctl status f250-gateway`; `ip -details link show can0` | Adapter unplugged or the bus quiet (key off). Values stay as STALE with their age; they come back by themselves when the data does |
| One value STALE, the rest current | That PID stopped answering; the gateway is recovering it | Diagnostics (each PID's successes and failures); `journalctl -u f250-gateway -b` | Leave it running: recovery is bounded and logged. Note the time and what the truck was doing; this is the dropout the project is chasing |
| Every value STALE, link up | The truck stopped answering every request | `ip -details -statistics link show can0` (bus state, error counters) | Key off? An ERROR-PASSIVE or BUS-OFF state: keep the statistics, then check the DLC connection ([can.md](can.md)) |
| A value marked unverified | Its formula isn't verified on this truck | The [verification log](../diagnostics/VERIFICATION_LOG.md) | Not a fault: verify it with the [truck session](../diagnostics/TRUCK_SESSION.md) |
| `can0` absent | The USB CAN adapter isn't seen | `ip link`, `lsusb`, `journalctl -k -b \| grep -i gs_usb` | Replug it; compare on Raspberry Pi OS ([agl.md section 6](agl.md#6-fallback-is-it-the-hardware-or-agl)) |

The gateway never transmits without `TRANSMIT=1`, and then only read services
([ADR-0007](../architecture/adr/0007-read-only-vehicle-access.md)). Nothing
here is fixed by clearing codes or writing to a module: that is refused in
code.

## Power

| Symptom | Meaning | Look at | Usually |
|---|---|---|---|
| Doesn't boot at key-on | No VOUT, or the Pi didn't start | The supply's LED and fuse; HDMI0 with a monitor | Wiring ([docs/wiring](../wiring/README.md)); the supply's timers ([power-states.md](../architecture/power-states.md)) |
| Shuts down with the key on | A power key press (the supply's pulse, or the button) after the boot window | `journalctl -b -1 -u f250-power-manager` | A quick key cycle inside OFFDELAY (H23); the supply's ON pulse arriving after `BOOT_KEY_IGNORE_S` (H21): lengthen the window, still shorter than OFFDELAY |
| Doesn't shut down after key-off | No pulse reached the Pi | `journalctl -b -1 -u f250-power-manager`: no "power off" line | PSW to J2 ([power-states.md](../architecture/power-states.md)); HARDOFF cuts the power anyway |
| Reboots while cranking | ACC dipped below what the supply rides through | `journalctl --list-boots` | Measure the dip (H22); the OFFDELAY preset |
| Dark until the next key cycle | The key came back during HARDOFF, after the halt | — | Expected: the Pi can't see the ignition ([power-states.md](../architecture/power-states.md#edge-cases-of-a-toggle-signal)) |

## Cameras

| Symptom | Meaning | Look at | Usually |
|---|---|---|---|
| "<camera> unavailable" | No frames from it | `camera-ctl view`, `ls -l /dev/v4l/by-path/`, `journalctl -u f250-camera-manager -b` | Replug it; Settings → Cameras assigns cameras by USB port: a camera moved to another port isn't found |
| Reverse doesn't bring the rear camera | No reverse from the bus, or auto-reverse off | `camera-ctl view` ("reverse unknown"?), `journalctl -u f250-camera-manager -b` | Auto-reverse needs the CAN transport (`TRANSPORT=can`) and the `230` frame ([ADR-0046](../architecture/adr/0046-automatic-reverse.md)); the mirrors stay the authority |
| The rear camera flashes up passing through R | A shift through R longer than the debounce | `CAMERA_REVERSE_DEBOUNCE_MS` | 300 ms (an example, from the 2026-11-14 drives) |
| "<camera> not recording" advisory | A camera set to record isn't | The advisory's reason; `ls /var/lib/f250/storage/video/`; `f250-storage status` | The data drive mounted? (`DATA_DRIVE=1`); free space against `RECORD_MIN_FREE_GB` |

## Audio and phones

| Symptom | Meaning | Look at | Usually |
|---|---|---|---|
| No sound | The chain from the phone to the DAC | `pw-link -l` (phone → loopback → `f250.speakers` → the DAC); Settings → Speakers says whether the crossover runs; the volume (muted?) | `systemctl restart f250-audio-manager`; the DAC's node name (`AUDIO_DAC_NODE`, `pw-cli ls Node`) |
| The phone won't pair | The pairing window isn't open, or the code was refused | Media → Phones; `bluetoothctl show` (`Discoverable`) | Open **Pair a phone**, pick "F-250" on the phone within the window, compare the codes |
| The phone doesn't reconnect | The driver disconnected it, or it was out of range past the retry window | Phones' note; `journalctl -u f250-audio-manager -b` ("trying … every 20 s") | Tap it on Phones to connect |
| No cover art | The phone doesn't offer it, or obexd isn't running | Media's note; `systemctl status f250-obexd` | Some phones don't send it over AVRCP ([ADR-0042](../architecture/adr/0042-cover-art-from-the-phone.md)) |
| Spoken directions not heard | Muted on the route, no voice, or a call | The route's voice toggle; `journalctl -u f250-navigation -b` ("voice: …") | Directions are skipped during a call and with a stale position, by design ([ADR-0040](../architecture/adr/0040-saved-places-and-spoken-directions.md)) |
| Calls stay on the phone | No call microphone configured, or hands-free isn't set up | Phones: "Calls stay on the phone: …" | Expected until calls are packaged ([ADR-0045](../architecture/adr/0045-phone-calls.md)) |

## Navigation

| Symptom | Meaning | Look at | Usually |
|---|---|---|---|
| No position | No receiver, no fix, or the simulator | `grep NAV_ /etc/default/f250`; `systemctl status gpsd`; `journalctl -u f250-navigation -b` | No receiver is fitted yet (H11): `NAV_SIMULATE=1` drives a simulated position, labelled SIMULATED |
| "Long-press the map to route" never shows | No routing data | `ls /var/lib/f250/storage/routing/` | A map stick with `ROUTING=` ([maps.md](maps.md#routing)) |
| Search finds nothing | No search data, or an old version | The Search panel ("Search unavailable: …"); `journalctl -u f250-navigation -b` ("search data: …") | A map stick with `SEARCH=` ([maps.md](maps.md#search)) |
| A map stick does nothing | Not recognised, or the copy failed | The status bar (MAP n%, MAP UPDATE FAILED); `journalctl -u 'f250-map-import@*' -b` | exFAT, the files and their checksums from `make map-stick` |

## The knob display

| Symptom | Meaning | Look at | Usually |
|---|---|---|---|
| The dial shows nothing current | No frames from knob-link | `journalctl -u f250-knob-link -b` ("dial on …"); `ls /dev/serial/by-id/` | Turn the USB-C plug over ([agl.md check 25](agl.md#5-bring-up-checks-phase-52)) |
| Everything stale on the dial | The gateway's data stopped | As "Vehicle data lost" above | — |

## After a crash or a strange boot

- `journalctl -b -1` is the boot before (the journal is kept on the SD card).
- `coredumpctl list` lists crashed programs.
- `systemctl --failed` lists failed units.
- `journalctl -b | grep -i watchdog` finds services systemd restarted because
  they stopped making progress (the gateway's and recorder's watchdogs).
- Back to the bench's simulated settings, when asked: keep the truck's file,
  `cp -p /etc/default/f250.bench-sim /etc/default/f250` if that copy exists,
  then restart `f250-can-auto` and `f250-gateway`.
