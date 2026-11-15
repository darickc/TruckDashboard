# Head unit model

The parts that hold the 7" display flush behind the F-250's radio opening,
built in **Autodesk Fusion**
([ADR-0047](../../docs/architecture/adr/0047-head-unit-enclosure.md),
[enclosure guide](../../docs/hardware/enclosure.md)).

**Status: DESIGN, NOT FITTED.** Nothing printed yet. The display's numbers
are from its drawing; the truck's are TODO.

| File | What it is |
|---|---|
| `parameters.json` | Every dimension, as Fusion user-parameter expressions in mm. The source of truth in the repo |
| `build_head_unit.py` | Fusion script: makes the user parameters, then dimensioned, fully constrained sketches driven by them, and the bodies |
| `inspect_head_unit.py` | Fusion script (read-only): what was built, for the checks |
| `export_head_unit.py` | Fusion script: STLs of the printable bodies |

| Component in Fusion | What it is |
|---|---|
| Display (reference, not printed) | The cover glass and the metal back, from the drawing |
| Glass template | The glass with the picture cut out, 1.2 mm. Hold it behind the dash's opening to check the opening falls on the black border |
| Rail left, Rail right | Screw to the display's M3 holes; ears beyond the glass for the truck's brackets; heat-set insert holes on the back for the rear box |

## Building it

With Fusion running and its MCP server on, open a **new, empty design**
(the build refuses a design with anything in it), then:

```bash
make mech-fusion
```

```bash
make mech-stl
```

`mech-fusion` builds the parts and checks what Fusion made:
- each body's size, place and volume against the parameters
- every sketch fully constrained
- the timeline healthy

`mech-stl` writes `build/mechanical/*.stl` and checks them. `make mech-test`
checks the parameters against the drawing without Fusion. Without the MCP
server, run `build_head_unit.py` from Fusion's Utilities > Scripts and
Add-Ins; it reads `parameters.json` from its own folder.

The build makes an empty Part design a Hybrid one, so it can hold several
components. It uses Fusion's `designIntent`, a preview API in Fusion 2706.
Saving the design is up to you.

## Changing it

Change the parameters in Fusion (Modify > Change Parameters), for example
`insert_d` for your heat-set inserts, or `ear_w` once the truck's brackets
are known. The sketches follow. To keep a change, put the same expression
in `parameters.json`. `make mech-fusion`'s check reports any parameter that
differs between Fusion and the file.

Coordinates are in mm, seen from the driver's seat:
- origin at the glass's bottom-left corner, on its front face
- X to the right, Y up
- Z into the dash, which is Fusion's up, so its Top view looks at the back of
  the display

In the slicer, lay each part on its largest face. The rails' front face, the
one against the display, goes down.
