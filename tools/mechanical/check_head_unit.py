#!/usr/bin/env python3
"""Checks mechanical/head-unit/head_unit.scad without OpenSCAD (ADR-0047).

It reads the file's top-level `name = value;` lines, evaluates them, and
checks them against the display's mechanical drawing (LMD-D/5624/KIT-LC-V3
rev 003, Raspberry Pi RP-008246-DS) and against each other: the margins
printed on the drawing, the screw holes inside the parts, no hole breaking
through to the display, the rails clear of the display's cable.

These are arithmetic checks on the design. They say nothing about fit on the
truck or the display; nothing here has been printed.

    python3 -I tools/mechanical/check_head_unit.py   (make mech-test)
"""

import re
import sys
from pathlib import Path

SCAD = Path(__file__).resolve().parents[2] / "mechanical/head-unit/head_unit.scad"

# Printed on the drawing, independent of how the model expresses them.
DRAWING = {
    "glass": (192.96, 110.76),
    "va": (154.88, 86.72),
    "va_right_margin": 19.04,
    "va_top_margin": 11.01,
    "frame_from_right": 11.89,  # back view's left edge = the front's right
    "frame": (166.2, 100.6),
    "frame_from_bottom": 3.53,
    "m3_pitch": (126.2, 65.65),
    "m3_from_frame_edge": 20.0,
    # The display's FPC connector, front view: 25.5 wide, 83.74 from the
    # glass's right edge.
    "fpc": (192.96 - 83.74 - 25.5, 192.96 - 83.74),
}
TOL = 0.011


def load(path):
    """The top-level assignments, evaluated in order."""
    env = {}
    for line in path.read_text().splitlines():
        m = re.match(r"^([a-z_][a-z0-9_]*)\s*=\s*(.+?);", line)
        if not m or m.group(1) == "part":
            continue
        name, expr = m.groups()
        if expr.startswith('"'):
            continue
        env[name] = eval(expr, {"__builtins__": {}}, env)  # noqa: S307 (our own file)
    return env


def near(a, b):
    return abs(a - b) <= TOL


def checks(v):
    out = []

    def check(what, ok):
        out.append((what, bool(ok)))

    gw, gh = DRAWING["glass"]
    check("glass size matches the drawing", near(v["glass_w"], gw) and near(v["glass_h"], gh))
    check("viewable area size matches", near(v["va_w"], DRAWING["va"][0]) and near(v["va_h"], DRAWING["va"][1]))
    check("viewable area 19.04 from the right edge", near(v["glass_w"] - v["va_x"] - v["va_w"], DRAWING["va_right_margin"]))
    check("viewable area 11.01 from the top edge", near(v["glass_h"] - v["va_y"] - v["va_h"], DRAWING["va_top_margin"]))
    check("metal back 11.89 from the right edge", near(v["glass_w"] - v["frame_x"] - v["frame_w"], DRAWING["frame_from_right"]))
    check("metal back size and height above the bottom", near(v["frame_w"], DRAWING["frame"][0]) and near(v["frame_h"], DRAWING["frame"][1]) and near(v["frame_y"], DRAWING["frame_from_bottom"]))
    mx, my = v["m3_x"], v["m3_y"]
    check("M3 holes 126.2 x 65.65 apart", near(mx[1] - mx[0], DRAWING["m3_pitch"][0]) and near(my[1] - my[0], DRAWING["m3_pitch"][1]))
    check("M3 holes 20.0 in from the back's right edge and bottom", near(v["frame_x"] + v["frame_w"] - mx[1], DRAWING["m3_from_frame_edge"]) and near(my[0] - v["frame_y"], DRAWING["m3_from_frame_edge"]))
    check("M3 holes on the metal back", all(v["frame_x"] < x < v["frame_x"] + v["frame_w"] for x in mx) and all(v["frame_y"] < y < v["frame_y"] + v["frame_h"] for y in my))

    # Glass template
    check("the display's M3 holes are behind the viewable area (so the rails sit behind the picture, and the template can't mark them)", all(v["va_x"] < x < v["va_x"] + v["va_w"] for x in mx) and all(v["va_y"] < y < v["va_y"] + v["va_h"] for y in my))
    check("template's window border at least 3 mm wide all round", min(v["va_x"], v["va_y"], v["glass_w"] - v["va_x"] - v["va_w"], v["glass_h"] - v["va_y"] - v["va_h"]) >= 3.0)
    check("template thin (<= 2 mm) to slip behind the dash", v["template_t"] <= 2.0)

    # Rails
    check("inserts stop short of the rail's front face (never reach the display)", v["insert_h"] < v["rail_t"])
    check("counterbore leaves at least 2 mm under the screw head", v["rail_t"] - v["m3_head_h"] >= 2.0)
    for side, hole_x in (("left", mx[0]), ("right", mx[1])):
        if side == "left":
            x0, x1 = -v["ear_w"], hole_x + v["rail_half"]
            ear_x = -v["ear_w"] / 2
            box_x = (hole_x + v["rail_half"] + v["frame_x"]) / 2
        else:
            x0, x1 = hole_x - v["rail_half"], gw + v["ear_w"]
            ear_x = gw + v["ear_w"] / 2
            box_x = (hole_x - v["rail_half"] + v["frame_x"] + v["frame_w"]) / 2
        edge = v["m3_head_d"] / 2 + 1.0
        check(f"{side} rail: screw counterbores 1 mm inside the rail", x0 + edge <= hole_x <= x1 - edge)
        check(f"{side} rail: clear of the display's FPC connector", x1 <= DRAWING["fpc"][0] or x0 >= DRAWING["fpc"][1])
        ins = v["insert_d"] / 2 + 1.0
        holes = [(hole_x, y, v["m3_head_d"] / 2) for y in my]
        holes += [(ear_x, y, v["insert_d"] / 2) for y in v["ear_insert_y"]]
        holes += [(box_x, y, v["insert_d"] / 2) for y in v["box_insert_y"]]
        check(f"{side} rail: inserts 1 mm inside the rail", all(x0 + ins <= x <= x1 - ins and ins <= y <= gh - ins for x, y, _ in holes[2:]))
        check(f"{side} rail: ear inserts beyond the glass", all(x < 0 or x > gw for x, _, _ in holes[2:4]))
        clash = any(
            ((a[0] - b[0]) ** 2 + (a[1] - b[1]) ** 2) ** 0.5 < a[2] + b[2] + 1.5
            for i, a in enumerate(holes) for b in holes[i + 1:]
        )
        check(f"{side} rail: holes at least 1.5 mm apart", not clash)
    return out


def main():
    v = load(SCAD)
    results = checks(v)
    for what, ok in results:
        print(f"  {'ok  ' if ok else 'FAIL'}  {what}")
    failed = sum(not ok for _, ok in results)
    print(f"\n{len(results) - failed}/{len(results)} checks passed (arithmetic only: nothing printed or fitted)")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
