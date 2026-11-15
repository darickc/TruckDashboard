#!/usr/bin/env python3
"""Checks the head unit model (mechanical/head-unit, ADR-0047).

    check_head_unit.py            the parameters against the display's drawing
                                  and each other (no Fusion needed; make mech-test)
    check_head_unit.py --fusion   also the bodies built in the open Fusion design:
                                  size, place and volume against the parameters,
                                  every sketch fully constrained, the timeline
                                  healthy (make mech-fusion)
    check_head_unit.py --stl DIR  also the exported STLs' size and volume
                                  (make mech-stl)

The drawing is LMD-D/5624/KIT-LC-V3 rev 003 (Raspberry Pi RP-008246-DS). These
checks say nothing about fit on the truck or the display: nothing has been
printed.
"""

import json
import math
import struct
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PARAMS = ROOT / "mechanical/head-unit/parameters.json"
INSPECT = ROOT / "mechanical/head-unit/inspect_head_unit.py"
CLIENT = ROOT / "tools/mechanical/fusion_mcp.py"

# Printed on the drawing, independent of how the parameters express them.
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


def load():
    env = {}
    for p in json.loads(PARAMS.read_text())["parameters"]:
        env[p["name"]] = eval(p["expr"], {"__builtins__": {}}, env)  # noqa: S307 (our own file)
    return env


def near(a, b, tol=TOL):
    return abs(a - b) <= tol


def expected_bodies(v):
    """Each body's bounding box (min, max) and volume, from the parameters."""
    gw, gh = v["glass_w"], v["glass_h"]
    rc, rh, ri = v["m3_clear"] / 2, v["m3_head_d"] / 2, v["insert_d"] / 2
    holes = 2 * (math.pi * rc ** 2 * (v["rail_t"] - v["m3_head_h"]) + math.pi * rh ** 2 * v["m3_head_h"]) \
        + 4 * math.pi * ri ** 2 * v["insert_h"]
    z0, z1 = v["module_t"], v["module_t"] + v["rail_t"]
    lw = v["rail_l_in"] + v["ear_w"]
    rw = gw + v["ear_w"] - v["rail_r_in"]
    return {
        "Cover glass": ((0, 0, 0), (gw, gh, v["glass_t"]), gw * gh * v["glass_t"]),
        "Metal back": ((v["frame_x"], v["frame_y"], v["glass_t"]),
                       (v["frame_x"] + v["frame_w"], v["frame_y"] + v["frame_h"], v["module_t"]),
                       v["frame_w"] * v["frame_h"] * (v["module_t"] - v["glass_t"])),
        "Glass template": ((0, 0, -(v["template_t"] + v["template_gap"])), (gw, gh, -v["template_gap"]),
                           (gw * gh - v["va_w"] * v["va_h"] - v["notch_w"] * v["notch_h"]) * v["template_t"]),
        "Rail left": ((-v["ear_w"], 0, z0), (v["rail_l_in"], gh, z1), lw * gh * v["rail_t"] - holes),
        "Rail right": ((v["rail_r_in"], 0, z0), (gw + v["ear_w"], gh, z1), rw * gh * v["rail_t"] - holes),
    }


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
    mx, my = (v["m3_x0"], v["m3_x1"]), (v["m3_y0"], v["m3_y1"])
    check("M3 holes 126.2 x 65.65 apart", near(mx[1] - mx[0], DRAWING["m3_pitch"][0]) and near(my[1] - my[0], DRAWING["m3_pitch"][1]))
    check("M3 holes 20.0 in from the back's right edge and bottom", near(v["frame_x"] + v["frame_w"] - mx[1], DRAWING["m3_from_frame_edge"]) and near(my[0] - v["frame_y"], DRAWING["m3_from_frame_edge"]))
    check("M3 holes on the metal back", all(v["frame_x"] < x < v["frame_x"] + v["frame_w"] for x in mx) and all(v["frame_y"] < y < v["frame_y"] + v["frame_h"] for y in my))
    check("the display's M3 holes are behind the viewable area (so the rails sit behind the picture, and the template can't mark them)", all(v["va_x"] < x < v["va_x"] + v["va_w"] for x in mx) and all(v["va_y"] < y < v["va_y"] + v["va_h"] for y in my))
    check("template's window border at least 3 mm wide all round", min(v["va_x"], v["va_y"], v["glass_w"] - v["va_x"] - v["va_w"], v["glass_h"] - v["va_y"] - v["va_h"]) >= 3.0)
    check("template thin (<= 2 mm) to slip behind the dash", v["template_t"] <= 2.0)
    check("template notch inside the top border", v["notch_h"] < v["glass_h"] - v["va_y"] - v["va_h"])

    check("inserts stop short of the rail's front face (never reach the display)", v["insert_h"] < v["rail_t"])
    check("counterbore leaves at least 2 mm under the screw head", v["rail_t"] - v["m3_head_h"] >= 2.0)
    for side, hole_x, x0, x1, ear_x, box_x in (
        ("left", mx[0], -v["ear_w"], v["rail_l_in"], -v["ear_w"] / 2, v["box_l_x"]),
        ("right", mx[1], v["rail_r_in"], gw + v["ear_w"], gw + v["ear_w"] / 2, v["box_r_x"]),
    ):
        edge = v["m3_head_d"] / 2 + 1.0
        check(f"{side} rail: screw counterbores 1 mm inside the rail", x0 + edge <= hole_x <= x1 - edge)
        check(f"{side} rail: clear of the display's FPC connector", x1 <= DRAWING["fpc"][0] or x0 >= DRAWING["fpc"][1])
        ins = v["insert_d"] / 2 + 1.0
        ear = [(ear_x, y, v["insert_d"] / 2) for y in (v["ear_insert_y0"], gh - v["ear_insert_y0"])]
        box = [(box_x, y, v["insert_d"] / 2) for y in (v["box_insert_y0"], gh - v["box_insert_y0"])]
        holes = [(hole_x, y, v["m3_head_d"] / 2) for y in my] + ear + box
        check(f"{side} rail: inserts 1 mm inside the rail", all(x0 + ins <= x <= x1 - ins and ins <= y <= gh - ins for x, y, _ in ear + box))
        check(f"{side} rail: ear inserts beyond the glass", all(x < 0 or x > gw for x, _, _ in ear))
        check(f"{side} rail: rear-box inserts over the metal back", all(v["frame_x"] < x < v["frame_x"] + v["frame_w"] for x, _, _ in box))
        clash = any(
            math.dist(a[:2], b[:2]) < a[2] + b[2] + 1.5
            for i, a in enumerate(holes) for b in holes[i + 1:]
        )
        check(f"{side} rail: holes at least 1.5 mm apart", not clash)
    return out


def fusion_checks(v):
    run = subprocess.run([sys.executable, "-I", str(CLIENT), "script", str(INSPECT), "--ro"],
                         capture_output=True, text=True, check=False)
    if run.returncode:
        sys.exit(f"check_head_unit: Fusion inspection failed:\n{run.stdout}{run.stderr}")
    built = json.loads(json.loads(run.stdout)["message"])
    out = []
    for name, (lo, hi, vol) in expected_bodies(v).items():
        b = built["bodies"].get(name)
        ok = b is not None and all(near(a, e, 0.01) for a, e in zip(b["min"] + b["max"], list(lo) + list(hi))) \
            and abs(b["volume"] - vol) <= max(0.5, vol * 1e-4)
        out.append((f"Fusion: {name} where and as big as the parameters say", ok))
    loose = [k for k, full in built["sketches"].items() if not full]
    out.append((f"Fusion: every sketch fully constrained{' (not: ' + ', '.join(loose) + ')' if loose else ''}", not loose))
    out.append((f"Fusion: timeline healthy{' (' + '; '.join(built['unhealthy']) + ')' if built['unhealthy'] else ''}", not built["unhealthy"]))
    drift = [k for k, val in built["parameters"].items() if k in v and not near(val, v[k], 0.001)]
    out.append((f"Fusion: user parameters match parameters.json{' (changed in Fusion: ' + ', '.join(drift) + ')' if drift else ''}", not drift))
    return out


def stl_stats(path):
    data = path.read_bytes()
    if data[:5] == b"solid" and b"facet" in data[:400]:
        raise ValueError(f"{path}: ASCII STL not handled")
    n = struct.unpack_from("<I", data, 80)[0]
    lo, hi, vol = [math.inf] * 3, [-math.inf] * 3, 0.0
    for i in range(n):
        f = struct.unpack_from("<12f", data, 84 + 50 * i)
        a, b, c = f[3:6], f[6:9], f[9:12]
        for p in (a, b, c):
            lo = [min(x, y) for x, y in zip(lo, p)]
            hi = [max(x, y) for x, y in zip(hi, p)]
        vol += (a[0] * (b[1] * c[2] - b[2] * c[1]) - a[1] * (b[0] * c[2] - b[2] * c[0]) + a[2] * (b[0] * c[1] - b[1] * c[0])) / 6
    return lo, hi, abs(vol)


def stl_checks(v, folder):
    out = []
    exp = expected_bodies(v)
    for name, file in (("Glass template", "glass_template.stl"), ("Rail left", "rail_left.stl"), ("Rail right", "rail_right.stl")):
        p = Path(folder) / file
        if not p.exists():
            out.append((f"STL: {file} exists", False))
            continue
        lo, hi, vol = stl_stats(p)
        elo, ehi, evol = exp[name]
        # A mesh's holes are polygons, so a little more material than the
        # model's circles: 0.5 % on volume.
        ok = all(near(a, e, 0.02) for a, e in zip(lo + hi, list(elo) + list(ehi))) and abs(vol - evol) <= evol * 0.005
        out.append((f"STL: {file} size and volume match the parameters ({vol:.0f} mm³)", ok))
    return out


def main():
    v = load()
    results = checks(v)
    if "--fusion" in sys.argv:
        results += fusion_checks(v)
    if "--stl" in sys.argv:
        results += stl_checks(v, sys.argv[sys.argv.index("--stl") + 1])
    for what, ok in results:
        print(f"  {'ok  ' if ok else 'FAIL'}  {what}")
    failed = sum(not ok for _, ok in results)
    print(f"\n{len(results) - failed}/{len(results)} checks passed (nothing printed or fitted)")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
