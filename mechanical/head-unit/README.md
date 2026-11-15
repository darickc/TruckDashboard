# Head unit model

OpenSCAD source for the parts that hold the 7" display flush behind the
F-250's radio opening ([ADR-0047](../../docs/architecture/adr/0047-head-unit-enclosure.md),
[enclosure guide](../../docs/hardware/enclosure.md)).

**Status: DESIGN, NOT FITTED.** Nothing printed yet. The display's numbers
are from its drawing; the truck's are TODO.

| Part (`part=`) | What it is |
|---|---|
| `glass_template` | The cover glass with the picture cut out, 1.2 mm. Hold it behind the dash's opening to check the opening falls on the black border |
| `rail_left`, `rail_right` | Screw to the display's M3 holes; ears beyond the glass for the truck's brackets; inserts on the back for the rear box |
| `assembly` | A view of the display, the rails and the template (not a part) |

```bash
make mech-test
```

```bash
make mech-stl
```

`mech-test` checks the model's numbers against the drawing, without
OpenSCAD. `mech-stl` writes `build/mechanical/*.stl` and needs OpenSCAD:
set `OPENSCAD=/path/to/openscad` if it isn't on `PATH`. Homebrew's
`openscad` cask is disabled (it fails macOS's Gatekeeper check since
2026-09-01); `openscad@snapshot` or the app from openscad.org are the
alternatives.

All dimensions are in millimetres, as seen from the driver's seat, with the
glass's bottom-left corner as the origin. Set the hardware sizes (inserts,
screws) at the top of `head_unit.scad` to what you buy.
