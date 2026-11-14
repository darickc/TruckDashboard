# ADR 0043 — One master volume in audio-manager, and the volume knob as Linux input

- **Status:** Accepted (owner asked for the volume control, 2026-11-13). [SIM] only:
  - the level, its limits, mute, saving, the filter-chain's gains, `SetVolume`, the knob's
    event handling (from recorded `struct input_event` bytes and a fake sysfs) and the
    dashboard's controls are tested (`make test`) and seen in the browser preview;
  - **not on the Pi**: bench check 24 ([setup/agl.md](../../setup/agl.md)). Nothing heard.
  - **Which knob** (a USB volume knob, a rotary encoder on Pi GPIO, or one on the ESP32)
    is the owner's choice and still open: TODO.
- **Date:** 2026-11-13
- **Refines:** [ADR-0039](0039-audio-manager.md) ("not decided here: the volume knob and
  its cap"), [ADR-0014](0014-multichannel-dac8x.md). Phase 6.3.

## Context

The head unit has no volume control. audio-routing.md asked for one master
volume with a configurable maximum, plus a physical knob. The speakers' DSP
already runs as audio-manager's PipeWire filter-chain (ADR-0039 decision 6)
with a gain stage on every output (fader, balance, sub level) that changes
live through `pw-cli set-param` without restarting the chain (a restart lets
full range reach the doors for a moment, bench-log 2026-11-12).

The knob's hardware isn't chosen. PROJECT_PLAN 6.3 says "on the ESP32
(encoder) or on Pi GPIO"; a USB volume knob is a third way. What Linux gives:

| Fact | Source | Status |
|---|---|---|
| `KEY_MUTE` 113, `KEY_VOLUMEDOWN` 114, `KEY_VOLUMEUP` 115, `KEY_PLAYPAUSE` 164; `EV_REL` 0x02, `REL_X` 0x00, `REL_DIAL` 0x07, `REL_WHEEL` 0x08 | `include/uapi/linux/input-event-codes.h` | Verified |
| A key event's value is 1 for a press, 0 for a release, 2 for autorepeat | `Documentation/input/input.rst` (event interface) | Verified |
| `/sys/class/input/eventN/device/capabilities/rel` is the device's relative-axis bitmap, printed like `capabilities/key` | `drivers/input/input.c` (`INPUT_DEV_CAP_ATTR(REL, rel)`) | Verified from source |
| USB HID volume knobs report Consumer Control volume up/down/mute and play/pause, which the kernel's HID input maps to `KEY_VOLUMEUP`/`KEY_VOLUMEDOWN`/`KEY_MUTE`/`KEY_PLAYPAUSE` | `drivers/hid/hid-input.c` (usage page 0x0c: 0xe2, 0xe9, 0xea, 0xcd) | Verified from source; no particular knob tested |
| The owner's candidate knob (2026-11-13): Waveshare ESP32-S3-Knob-Touch-LCD-1.8, a 360×360 round touch screen with a knob, ESP32-S3 and a second ESP32; its USB-C connects the S3's USB or the second ESP32's UART depending on the plug's orientation | waveshare.com product page and wiki, read 2026-11-13 | From the maker's pages; whether the knob has a push switch, and the USB-C switching, are UNVERIFIED (schematic not read). Not bought |
| The kernel's `rotary-encoder` driver reports turns on one axis (`linux,axis`), relative with `rotary-encoder,relative-axis` (±1 a step) | `Documentation/devicetree/bindings/input/rotary-encoder.yaml` | Verified from source |
| The Pi firmware's `rotary-encoder` overlay takes `pin_a`, `pin_b`, `relative_axis`, `linux_axis` | `/boot/overlays/README` | **UNVERIFIED**: not read from the Vimba 22.0.1 image; check there before writing config.txt. Nothing is added to config.txt here |
| A rotary encoder's push switch can be a key with the `gpio-key` overlay (`keycode=113` for mute) | the camera switch already uses `gpio-key` ([ADR-0024](0024-camera-selection-switch-and-can-reverse.md)) | The overlay is in use; a mute key on it is UNVERIFIED |

## Decision

1. **audio-manager owns the volume** (CLAUDE.md rule 5): one master level,
   applied as a gain in the speakers' filter-chain. It multiplies every
   output's gain (front, rear, sub), is never above 1 (0 dB), so it never
   boosts, and changes live like the fader. Spoken directions go through the
   same chain, so they follow it too.
2. **Steps, in dB.** The level runs 0..=`steps`; the top step is 0 dB, each
   step below it `step_db` quieter, 0 silent. Examples (CLAUDE.md rule 10;
   `AUDIO_VOLUME_*`): 30 steps of 2 dB (step 1 is −58 dB).
   - **The cap** (`max`, example 30, i.e. none): the driver can't go above
     it; for speakers that can't take the amplifiers' full output.
   - **The start cap** (`start_max`, example 15): audio-manager starts at the
     level it saved, but no louder than this, so the truck never starts at
     full volume.
3. **Mute** is its own state; the level is kept. Turning the volume up
   unmutes. Mute silences everything the speakers play, spoken directions
   included. audio-manager starts unmuted.
4. **Saved** in `volume.json` (its state directory) 2 s after the last
   change, so a knob turn doesn't write the SD card at every detent; at
   shutdown if a change is waiting.
5. **Coalesced.** Changes are applied by one task: one `pw-cli` at a time,
   always the newest level (a fast turn sends the last one, not every step).
   The speaker settings and the volume are applied under one lock, each with
   the other's latest value.
6. **The API:** `WatchAudioResponse.volume` (`level`, `max`, `steps`,
   `muted`, `applied`, `detail`) and `SetVolume` (a level, a number of steps,
   or mute/unmute/toggle). A level above the cap is set to the cap, and the
   answer says so.
7. **The knob is Linux input**, read by audio-manager from `/dev/input/event*`
   (the same reader as power-manager's power key, now `crates/evdev`):
   - `KEY_VOLUMEUP`/`KEY_VOLUMEDOWN`: one step a press, and a step at each
     autorepeat (holding a button ramps); `KEY_MUTE`: a press toggles mute.
     From every device that has them: a USB volume knob, a keyboard's media
     keys, buttons on `gpio-key`.
   - `KEY_PLAYPAUSE`: a press (not a hold) pauses the phone if it is
     playing, plays it otherwise, as Media's Play/Pause does (amended
     2026-11-13, owner: a push or tap on the knob plays and pauses). With no
     phone or no player it is logged and does nothing. For the knob display
     below, its push or a tap on its screen would send it as USB HID
     Consumer Play/Pause.
   - `REL_DIAL`: each event's value in steps, clockwise up
     (`AUDIO_KNOB_INVERT=1` turns it round). From every device that has it: a
     rotary encoder through the kernel's driver with `linux,axis = 7`. Not
     `REL_X` or `REL_WHEEL`, so a mouse never changes the volume.
   - Devices are found from sysfs and rescanned every 5 s (a USB knob plugged
     in later). `AUDIO_KNOB=0` turns it off.
   - So the hardware choice changes no code: a USB knob works as it is; a GPIO
     encoder needs only its overlay in config.txt (UNVERIFIED, above). An
     ESP32 encoder would need a way into the Pi: for the owner's candidate
     knob display, its S3 appearing on USB as a HID knob (volume, mute,
     play/pause) alongside a serial port for the gauge data:
     [ADR-0044](0044-knob-display.md).
8. **Without the filter-chain** (`AUDIO_DSP=0`, or it isn't running) the
   level is kept and shown with "not applied" and why; nothing else changes
   the volume.
9. **The dashboard:** on Media, Volume −, the level, Volume + and Mute
   beside the transport controls (60 px). On every other screen, a level bar
   over the bottom of the screen area for 2 s after any change, below the
   alert banner, which it never covers. Not on Media (it shows the level, and
   the bar would cover its buttons), and not in camera mode (the camera's
   window is over that part of the screen).

## Alternatives considered

- **The DAC's own volume** (`wpctl set-volume` on the sink, or ALSA): a
  second place that changes the level, out of sight of the filter-chain's
  gains and their limits; and the DAC8x's mixer controls are UNVERIFIED.
  Rejected.
- **The knob read by the dashboard** (the compositor sends key events to the
  focused window): the volume would stop working when the dashboard isn't
  running or isn't focused, and the knob would be a UI concern. Rejected.
- **AVRCP absolute volume** (the phone's volume slider as the head unit's):
  one volume per phone, and how PipeWire's bluez5 plugin applies it here is
  UNVERIFIED. Not decided: the phone's own volume multiplies with the master
  for now.
- **Writing `volume.json` at every change:** tens of writes a turn. Rejected
  for the 2 s delay.

## Consequences

- audio-manager reads `/dev/input` now: its unit gets group `input`,
  `DeviceAllow=char-input r` and no `PrivateDevices`, as power-manager has.
- A keyboard plugged in for setup turns the volume with its media keys.
- Spoken directions are silent while muted, and as quiet as the music.
- With the filter-chain not running, the knob changes a number on the screen
  and nothing else; the screen says "not applied".

## To verify on the Pi (bench check 24)

1. Media: Volume + and − change the level; the speakers follow (a phone
   playing); Mute silences them, Volume + unmutes. `journalctl -u
   f250-audio-manager` shows no `pw-cli` failures.
2. `systemctl restart f250-audio-manager` at a level above the start cap: it
   comes back at the start cap. `cat /var/lib/f250-audio/volume.json`.
3. With the chosen knob: its events show `KEY_VOLUMEUP`… or `REL_DIAL`
   ([agl.md, input events](../../setup/agl.md#input-events): the image has no
   `evtest`); audio-manager's log names the device ("volume knob: …"); a
   turn moves the level by one step a detent; clockwise is up (else
   `AUDIO_KNOB_INVERT=1`). Its play/pause (`KEY_PLAYPAUSE`) pauses a playing
   phone and plays a paused one.
4. A fast turn: the level follows without lag, and the log shows one
   `pw-cli` at a time.
5. Spoken directions at a low level: heard, quiet. While muted: silent.
