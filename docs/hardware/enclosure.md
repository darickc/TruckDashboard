# The head unit enclosure

**Status: DESIGN, NOT FITTED.** Nothing here has been printed, held against
the truck or screwed to the display. Decision:
[ADR-0047](../architecture/adr/0047-head-unit-enclosure.md). Model:
[`mechanical/head-unit/`](../../mechanical/head-unit/README.md) (Autodesk Fusion,
built from `parameters.json` by a Fusion script).

## The idea

```
   dash trim (its back face)
        │ foam gasket on the glass's black border
        ▼ ▼
  ──────┐ ┌──────────────── cover glass (192.96 × 110.76) ─────────┐ ┌──────
        │ │░░░│                 picture                 │░░░│     │ │
        └─┘   └─── viewable area 154.88 × 86.72 ────────┘   └─────┘ └─
              [ metal back of the display, 4 × M3 holes ]
   [ear]═════[rail]                                    [rail]═════[ear]
     │                                                               │
  side bracket → the radio opening's mounting points            side bracket
              [ rear box: Pi 5 + DAC8x + NVMe, DCDC-USB, (hub), fan ]
```

The glass sits behind the opening, and the dash's back face presses on the
glass's black border. The display hangs from its own four M3 holes, on two
printed rails. Ears on the rails bolt to side brackets, which bolt to the
truck. A printed box behind it holds the electronics. The amplifier goes
elsewhere.

## Will the opening work? (H34)

Every edge of the opening must fall on the glass's black border. Measured in
from the matching edge of the glass:

| Opening's edge | At least (the dash bears on 3 mm of glass, an example) | At most (where the picture starts) |
|---|---|---|
| Left | 3 mm | 19.04 mm |
| Right | 3 mm | 19.04 mm |
| Bottom | 3 mm | 13.03 mm |
| Top | 3 mm | 11.01 mm |

So the opening is between **154.9 × 86.7 mm** (the picture, nothing hidden)
and about **187 × 105 mm**. It can sit up to 1 mm off centre vertically, since
the border is 13.03 at the bottom and 11.01 at the top.

The quickest check is the **glass template**: print it (1.2 mm, about ten
minutes) and hold it behind the opening, notch up. Then look from the
driver's seat:

- None of the template should show anywhere round the opening.
- The window should fill it, or sit inside it, with the dash's edge on the
  template all round.

## Measurements to take on the truck

Take these with the Pioneer and its dash kit out, and photograph them with a
ruler in view. Put the numbers in
[open-questions.md](open-questions.md) H34–H35.

1. **The opening** (H34), from the front:
   - width and height
   - corner radius
   - whether the opening is the factory dash itself or a dash kit's trim
     plate (if a kit, its make and part number)
2. **The dash wall at the opening** (H34): its thickness at the edge, and
   whether its back face is flat for about 15 mm all round the opening. Note
   any ribs or clips there, which would press on the glass; the Miata build
   trimmed them.
3. **The space directly behind the opening** (H35): the glass is
   192.96 × 110.76, larger than the opening. Measure the clear width and
   height just behind the dash wall, and note anything in the way: the
   radio cage, the HVAC ducts, the harness.
4. **The cavity** (H35): the clear depth from the dash's back face to the
   first obstruction, at the top, middle and bottom. Also the width and
   height further back, where the box will be.
5. **The mounting points** (H35): how the Pioneer's cage or kit is held (the
   factory radio brackets, screw holes, their positions relative to the
   opening), with photos.
6. **The display's M3 holes** (H36), on the bench: do they take an M3
   screw (threaded), and how deep is a hole before the screw meets
   resistance? Probe with a pin; never force a screw. The rails' screws must
   be shorter than that, because a long screw can push into the LCD.

## Parts

| Part | Status | Printing |
|---|---|---|
| Glass template | Modelled in Fusion; prints now (`make mech-stl`) | ASA, PETG or PLA (it's a gauge); flat, 1.2 mm |
| Rails (left, right) | Modelled in Fusion; ears are an example until H35 | ASA; front face (against the display) on the bed; 4 walls, 40 % infill or more |
| Side brackets | Waits for H35 (mounting points) | ASA; flat |
| Rear box | Waits for H35, the DAC8x and the NVMe board fitted together (H4) | ASA; flat panels, M3 inserts at the joints |
| Amplifier bracket | Waits for H37 (where it goes) | ASA; flat |

**Material:** ASA, or ABS. Not PLA: a parked cab passes its softening
point. PETG only after a summer test in the cab. Print the template in
anything.

**Hardware (example sizes; set `insert_d` and the screw sizes in Fusion's parameters, and in `parameters.json`, for what you buy):**

- M3 socket or pan-head screws, 6–12 mm
- M3 heat-set inserts (the model's holes: 4.0 mm across, 5 mm deep)
- 1 mm closed-cell foam tape for the gasket
- a quiet 40 mm 12 V fan, with a fuse on its feed
- grommets or printed strain reliefs for the leads

## USB and the amplifier

- **USB:** one camera needs no hub: CAN adapter, GPS, knob display and camera
  take the Pi's four ports. With more cameras, see ADR-0047 decision 6: the
  cameras on the Pi's ports, the rest on a USB 2.0 hub.
- **Amplifier:** the Taramps TS 400x4 fits the plan. Set its crossover
  switches to FULL. It needs an inch of air round its heatsink. It goes on
  its own bracket, behind the dash or under the rear seat (H37), with a 20 A
  fuse at the battery and 11 AWG power and ground (its manual's figures).
  Wiring: [wiring/audio.md](../wiring/audio.md).
