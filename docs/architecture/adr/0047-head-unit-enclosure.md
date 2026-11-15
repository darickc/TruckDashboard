# ADR 0047 — The head unit's enclosure: the display flush behind the dash, a printed box, the amplifier outside it

- **Status:** Proposed (owner asked, 2026-11-15: "Start working on the truck
  installation"). Design only: nothing printed, fitted or measured on the
  truck. The display's numbers come from its drawing; the truck's are TODO
  ([H34–H37](../../hardware/open-questions.md)).
- **Date:** 2026-11-15
- **Relates to:** [ADR-0013](0013-dcdc-usb-power-supply.md) (power),
  [ADR-0014](0014-multichannel-dac8x.md) (DAC and amplifiers),
  [ADR-0027](0027-front-and-rear-recording.md) (cameras),
  [ADR-0044](0044-knob-display.md) (the knob display, a separate USB device).

## Context

The head unit replaces the Pioneer DEH-P770MP in the 2007 F-250's radio
opening. It holds the original Raspberry Pi 7" Touch Display, the Pi 5 with
the DAC8x and an NVMe drive, the mini-box DCDC-USB, and perhaps a USB hub. A
new 4-channel amplifier replaces the Pioneer's built-in one
([wiring/audio.md](../../wiring/audio.md)).

The owner's requests (2026-11-15):

- The screen is larger than the dash's opening. Mount it **flush behind the
  opening**, the dash's back face against the screen, as in a Miata build
  that does this with the same display
  ([Thingiverse 5193830](https://www.thingiverse.com/thing:5193830): side
  mounts bolted to the radio opening's hardware, the dash trim's ribs trimmed
  where they would press on the screen, printed in ASA).
- Parts printed as flat as possible, joined with screws into heat-set
  inserts, or glued. The owner has a 3D printer.
- Amplifier candidate: Taramps TS 400x4. Hub candidate: a 4-port USB 3 hub
  (Amazon `B0CN3F9Y1Z`, sold as an Acer hub; not checked). USB devices: the
  CAN adapter, a GPS receiver, the knob display, and one to four cameras (one,
  the rear, to start).
- A fan, probably.

Facts used (sources and status in the
[compatibility matrix](../../hardware/compatibility-matrix.md)):

| Fact | Source | Status |
|---|---|---|
| Display cover glass 192.96 × 110.76 mm; touch viewable area 154.88 × 86.72 (LCD active area 154.08 × 85.92), 19.04 from each side, 11.01 from the top, 13.03 from the bottom; the rest is black ink on the glass's back | Display drawing LMD-D/5624/KIT-LC-V3 rev 003 (Raspberry Pi RP-008246-DS) | Verified from the drawing |
| The module is 5.96 thick (glass to metal back); the metal back is 166.2 × 100.6, so the glass overhangs it by 11.89–14.87 at the sides, 3.53 below and 6.63 above | Same drawing | Verified from the drawing |
| Four M3 mounting holes in the metal back, 126.2 × 65.65 apart, all behind the viewable area; four M2.5 standoffs for the Pi (58 × 49) | Same drawing | Verified from the drawing; thread depth not given (H36) |
| −20 to +70 °C operating; 250 cd/m²; outer size 192.96 × 110.76 | [Raspberry Pi Touch Display docs](https://www.raspberrypi.com/documentation/accessories/display.html) | Verified from the docs |
| Whole display 20 mm deep with its adapter board and standoffs | An older spec sheet ("194mm x 110mm x 20mm (including standoffs)"), seen only as a search result | UNVERIFIED: measure |
| TS 400x4: 4 × 63 W RMS at 4 Ω, 4 × 100 W at 2 Ω (13.8 V, THD ≤ 10 %); 4 RCA inputs; REM terminal; FULL/HPF/LPF switch per pair; 20 A fuse, 11 AWG power and ground up to 4 m; at least 1" around the heatsink; heatsink normally 65 °C; idle 0.8 A (manual) or 0.40 A (web page) | [Manual R02](https://www.taramps.com.br/wp-content/uploads/2022/09/MN_R02_TS-400X4_ENG.pdf), [product page](https://taramps.com.br/en/?p=596) | Verified from the maker; the two documents disagree on idle current and size (138 × 49 × 121 vs 140 × 48 × 101 mm) |
| The Pi 5's four USB ports are on two controllers, one USB 3 and one USB 2 port each | Raspberry Pi docs | Verified |
| USB 3 signalling radiates broadband noise into the 2.4 GHz band, degrading nearby Bluetooth and Wi-Fi | Intel white paper "USB 3.0 Radio Frequency Interference Impact on 2.4 GHz Wireless Devices" (2012) | Widely cited; not re-read for this ADR |

## Decision

1. **The display sits behind the opening, its glass pressed against the
   dash's back face.** The opening shows the picture through the glass's
   black border, like a factory bezel. It works when every edge of the
   opening falls on the black ink. So the opening is at least the viewable
   area, 154.88 × 86.72 mm, so nothing of the picture is hidden. And it is
   smaller than the glass by enough for the dash to bear on it: 3 mm a side
   as an example, so at most about 187 × 104 mm. The opening needn't be
   centred: the border is 19 mm at the sides, 11 at the top and 13 at the
   bottom. A thin foam gasket (about 1 mm) on the black border, where the
   dash bears, takes up the dash's unevenness and keeps dust out. The glass is
   never clamped on its edges: the display is held by its own four M3 holes.
   The touch area is the viewable area, so a dash edge resting on the border
   doesn't touch the sensor's working area. Whether the truck's opening fits
   is H34; the glass template (decision 3) checks it before anything else is
   printed.
2. **Printed rails carry the display.** Two flat rails screw to the display's
   M3 holes from behind (clearance holes, counterbored). Each has an ear past
   the glass's side edge, with heat-set inserts for the truck's side brackets,
   and inserts on its back for the rear box. The side brackets are flat plates
   with slots, so the glass can be drawn forward against the dash. They bolt
   to the radio opening's own mounting points, as the Miata build does. Their
   shape waits for H35.
3. **Flat parts, a parametric model, checked numbers.**
   [`mechanical/head-unit/head_unit.scad`](../../../mechanical/head-unit/head_unit.scad)
   (OpenSCAD) holds every dimension, with the drawing's numbers converted to
   front-view coordinates. `make mech-test` checks them against the drawing
   and each other without OpenSCAD. `make mech-stl` renders the parts. The
   first parts are the **glass template** and the **rails**. The template is
   the glass's outline with the viewable area cut out, 1.2 mm thick, to hold
   behind the dash. The side brackets and the rear box come after the
   measurements. Parts print flat on their largest face and join with M3
   screws into heat-set inserts; glue only where nothing will need to come
   apart. Material: **ASA** (or ABS); not PLA, which softens in a parked
   cab; PETG only if tested in the cab.
4. **A rear box holds the electronics.** The Pi stays on the display's four
   M2.5 standoffs, the display's own arrangement: the shortest display cable,
   and the stack is serviced by removing the box. The box screws to the
   rails' back inserts and holds:
   - the Pi with the DAC8x above it
   - the NVMe board: whether it stacks with the DAC8x is still H4
   - the DCDC-USB
   - the hub, if one is fitted
   - cable exits with strain relief for the USB, RCA, power, CAN and antenna
     leads

   Its shape waits for the DAC8x and the NVMe board to be fitted together,
   and for the cavity's size (H35).
5. **The amplifier is not in the box.** The TS 400x4 meets the criteria in
   the [shopping list](../../hardware/shopping-list.md#stage-3--chosen-after-measurement-phase-6):
   - 63 W × 4 at 4 Ω
   - stable at 2 Ω
   - four RCA inputs, so the front and rear pairs are separate
   - a REM input
   - small

   So it is accepted as the owner's choice. Its crossover switches go to
   FULL, because the Pi does the crossover. Its heatsink runs at about 65 °C,
   and it needs an inch of free air all round. That heat must not go into the
   box with the Pi and the display. It goes on a bracket of its own, either
   behind the dash beside the box (if the cavity leaves an inch round it) or
   under the rear seat beside the R150-2. Which one is H37. Power comes from
   the battery through a 20 A fuse in 11 AWG (the manual's figures, up to
   4 m), or shares the R150-2's feed if that is big enough (H28).
6. **USB: no hub for one camera; a USB 2 hub for the low-rate devices when
   the cameras come.**
   - With one camera the Pi's four ports take the CAN adapter, the GPS
     receiver, the knob display and the camera.
   - With more cameras, the cameras go on the Pi's own ports, split across
     both controllers ([ADR-0027](0027-front-and-rear-recording.md)). The
     CAN adapter, the GPS and the knob share one port through a hub, and a
     fourth camera joins them.
   - None of those devices needs USB 3. USB 3 links put noise into the
     2.4 GHz band, which the Pi's Bluetooth uses for music and calls, and
     the GPS antenna will be nearby. So a **USB 2.0 hub** is preferred over
     the candidate USB 3 hub. Either would work.
   - A powered hub, or feeding the cameras from a separate 5 V supply, is
     needed if the total passes what the Pi supplies at the DCDC-USB's 5 V
     (H25).
7. **Cooling: the Pi's Active Cooler and one quiet fan through the box.**
   - The official Active Cooler goes on the Pi 5, under the DAC8x on a 16 mm
     stacking header. That combination is UNVERIFIED (vendors fit HATs over
     the cooler this way; not tried with the DAC8x).
   - The box gets one 40 mm fan exhausting at the top or back, with intake
     vents low at the front edge.
   - The fan runs from the switched 12 V through its own fuse, so it runs
     whenever the key is on, with no software in the way.
   - Whether this is enough is Phase 7.3 (a closed cab in summer, with
     throttle logging). The display's 70 °C limit is the one most at risk in
     sun.

## Consequences

- Nothing truck-specific can be printed until H34 (the opening), H35 (the
  space behind it and the mounting points) and H36 (the display's M3 holes)
  are answered. The template and the rails can be printed now. The rails can
  be screwed to the display to check the hole positions before the truck is
  involved.
- The drawing is the bare LCD module's. The Pi's display adds its adapter
  board on the back, which the drawing doesn't show. The rails keep to the
  edges, clear of the cable from the panel, but the board's outline is still
  to check on the part.
- The glass sits a dash-wall's thickness behind the face of the dash, as a
  factory screen does. It is not flush with the front.
- The display is 250 cd/m². That may be hard to read in direct sun. The
  enclosure doesn't change this, but a shade lip in the dash trim could. To
  judge on the truck.
- The amplifier needs its own bracket and its own power run. The head unit
  enclosure stays low-power, under the DCDC-USB's limits.
- A USB 2 hub costs nothing in speed for these devices and avoids a known
  interference source. If the USB 3 hub is already bought it can be used, and
  the Bluetooth and GPS checked with it plugged in.

## Rejected

- **Clamping the glass at its edges.** That puts stress on the glass and its
  bond; the display has M3 holes for mounting.
- **A screen in front of the dash.** Owner wants it behind the opening.
- **The amplifier inside the head unit box.** About 65 °C at the heatsink
  next to the Pi and a display rated to 70 °C.
- **The Pi on the box's back wall** (a longer display cable, the stack
  reachable from behind). Kept as the fallback if the DAC8x, NVMe board and
  cooler don't fit on the display's standoffs.
