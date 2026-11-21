# ADR 0051 — The 5-way switch: short press for media and calls, long press for cameras, directions learned on the dashboard

- **Status:** Accepted (owner, 2026-11-21). `[SIM]` only: power-manager's
  classifier, mapping and learning are unit-tested; the real binary is
  tested end to end on the Mac with switch events written into a FIFO;
  audio-manager's `PressMediaKey` is tested against its simulated phone; the
  dashboard's screen against a fake and a simulated switch. No switch is
  wired yet (H32), so nothing is `[BENCH]` or `[TRUCK]`.
- **Date:** 2026-11-21
- **Amends:** [ADR-0024](0024-camera-selection-switch-and-can-reverse.md)
  decision 1 (what the switch does),
  [ADR-0025](0025-camera-switch-through-gpio-key.md) decisions 4–5 (what
  counts as a press, where it goes),
  [ADR-0029](0029-settings-screen.md) (a setting for the switch)
- **Refines:** [ADR-0045](0045-phone-calls.md) decision 6 (the push answers
  and hangs up) and [ADR-0043](0043-master-volume-and-the-volume-knob.md)
  (the master volume's steps)

## Context

The 5-way switch in the cab only picked cameras: each closure was a camera
move. The owner wants it to do more, because it is the one control that can
be reached without looking:

| Direction | Short press | Long press |
|---|---|---|
| Left / Right | Previous / next track | Left / right camera |
| Up / Down | Volume up / down a step | Front / rear camera |
| Press | Play/pause; answer a ringing call; hang up a call in progress | Close the camera |

The owner doesn't know yet how the switch will be mounted, so which wire is
"up" can't be fixed in configuration. It has to be set once the switch is in
the truck.

audio-manager already has the centre press's behaviour: the volume knob's
push answers, hangs up, or plays/pauses (`Manager::knob_push`, ADR-0045
decision 6). It had no API for it.

## Options considered

1. **audio-manager reads the switch's keys too**, and decides short presses
   itself. Rejected: two services would have to agree on the long-press
   time, and a press near it could do both or neither.
2. **power-manager decides short or long, and sends each to the service
   that acts on it.** Chosen. It already owns the switch (ADR-0025) and
   camera-manager's link (ADR-0026).
3. For the directions: **a rotation and mirror setting.** Rejected: it
   assumes the wires follow the switch's labels in order.
4. **Assign each wire by hand.** Rejected: the driver has to work out which
   wire is which.
5. **Press to learn**: the screen asks for each direction in turn and the
   driver pushes the switch that way. Chosen (owner). Any wiring order and
   any mounting work.

## Decision

1. **Wires and roles.** power-manager names the five contacts by their key
   (F13–F17, `Wire`) and gives each a **role**: Up, Down, Left, Right or
   Press. The mapping must use each role once. The default follows the
   wiring doc: BCM6 up, BCM16 down, BCM12 left, BCM13 right, BCM17 press.
   The `gpio-key` labels now name the pin (`SW_BCM12`), not a direction.
2. **Short and long.**
   - A press starts once its contact has been the only one closed for the
     debounce time (30 ms, unchanged).
   - Held for `--switch-long-press-ms` (600 ms from the contact closing,
     `SWITCH_LONG_PRESS_MS`, an example), it is **long**. It is reported at
     once, so the camera comes while the switch is still held. Its release
     does nothing.
   - Released sooner, it is **short**. It is reported once the contact has
     stayed open for the debounce time; closing again inside it is bounce.
   - A second contact during a press cancels it. That contact must open
     before it starts another press.
   - Holding a direction doesn't repeat. A hold is the camera.
3. **Where presses go.**
   - A long press goes to camera-manager's `Move`, as before: Up is the API's
     `FORWARD` and Down its `BACK`. camera-manager and the camera policy don't
     change.
   - A short press goes to audio-manager's new `PressMediaKey`:
     - PLAY_PAUSE is the knob's push.
     - NEXT and PREVIOUS are refused during a call, so a skip can't reach
       the phone's player mid-call.
     - VOLUME_UP and VOLUME_DOWN are one step of the master volume.
   - Both links use the existing link rules (`crate::link`):
     - a short queue
     - a call timeout
     - a press older than 1 s is dropped, not sent late
     - no retry
     - a missing service never holds up the power key
4. **Learning.** power-manager serves `f250.power.v1` `SwitchService` on its
   existing socket:
   - `WatchSwitch` streams the state and each press, with what became of it.
   - `SetLearning`, `SetMapping` and `ResetMapping` change the setting.
   - While learning, presses are reported and **not sent**, so set-up
     doesn't change the volume or the camera.
   - Learning ends after 60 s without a press (an example), on Save, on
     Cancel, or when the screen goes away. A crashed screen can't leave the
     switch doing nothing.
   - The mapping is saved in `/var/lib/f250-power/switch` (`--switch-state`),
     written whole and renamed. A bad file gives the default and says so.
5. **The screen.** Settings › System opens it from a full-width row at the
   top of the left column ("5-way switch · default directions ›"), which
   says whether directions have been set. The screen (design review
   2026-11-21, on the F-250 Head Unit Redesign canvas):
   - **The switch is drawn as you face it.** Each direction sits where the
     thumb goes, with its tap action large and its hold action under it. The
     drawing shows the switch; it isn't a control.
   - Beside the drawing:
     - the last press and what it did
     - that Press also answers and hangs up, and that skips are ignored
       during a call
     - the wires on one small line, marking any that aren't readable
     - **Set up directions** as the filled primary button, and **Reset to
       default**
   - **Set-up** uses the same drawing:
     - the direction asked for is lit with an arrow, found ones are green
       with their pin, and the rest are dim
     - "Push DOWN" in large type
     - a countdown to power-manager's timeout, worked out from the store's
       clock with no timer of its own
     - a repeated push shows as an amber warning
     - nothing changes until **Save**; **Cancel** and **Start over** are
       always there
   - Without power-manager it says so and offers no buttons.
   - In the simulation it is marked SIMULATED, with stand-in buttons for the
     five wires.

   It isn't a fifth section button: five buttons beside Diagnostics and
   Power would shrink each word below its size in the panel's font.

## Consequences

**Gains:**

- One control in reach does volume, tracks, calls and cameras.
- The switch can be mounted and wired in any orientation, and set up from
  the seat.

**Costs and risks:**

- **A camera now comes after about 600 ms, not 30 ms.** The dashboard's
  camera buttons and automatic reverse are unaffected.
- **Media keys act on release**, about 30 ms after it.
- **The long-press time is a guess.** Tune it on the fitted switch.
- **Learning's timeout and the long-press time are examples**, not measured
  requirements.
- **A second service link.** power-manager now reaches audio-manager's
  socket (group f250, mode 0770). No sandbox change was needed.

**Tests:** `[SIM]`.

- The classifier, every transition: short, long, long then release, bounce
  on close and release, a blip, diagonals before and after the long time,
  rolling, unpolled release, zero debounce.
- The mapping's rules and file.
- Learning's routing and timeout.
- The links' mapping.
- The real binary over the API: presses, learning, a refused and a saved
  mapping, reset.
- audio-manager's keys, a ring answered and hung up, a skip refused in a
  call.
- The screen's learn flow, refusals, cancel, timeout, link loss and the
  simulation.
- `make agl-test`: the wrapper's options and each key's pin against
  power-manager's.

**Still to verify:** wiring checks 8–9 with the chosen switch (H32), then
acceptance 4.4 on the Pi.
