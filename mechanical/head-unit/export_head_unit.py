"""Exports the head unit's printable bodies from Fusion as STL (ADR-0047).

`make mech-stl` runs it through Fusion's MCP server with OUT_DIR set to
build/mechanical. In Fusion's Scripts dialog it writes next to this file's
folder, in build/mechanical of the checkout. The display (reference) is not
exported. STLs are in model coordinates: lay each part on its largest face in
the slicer (the rails' front face, the side against the display, goes down).
"""

import os

import adsk.core
import adsk.fusion

PRINTED = {"Glass template": "glass_template", "Rail left": "rail_left", "Rail right": "rail_right"}


def run(_context: str):
    design = adsk.fusion.Design.cast(adsk.core.Application.get().activeProduct)
    out = globals().get("OUT_DIR") or os.path.join(
        os.path.dirname(os.path.abspath(__file__)), "..", "..", "build", "mechanical")
    os.makedirs(out, exist_ok=True)
    found = {}
    for occ in design.rootComponent.allOccurrences:
        for i in range(occ.component.bRepBodies.count):
            body = occ.component.bRepBodies.item(i)
            if body.name in PRINTED:
                found[body.name] = body
    missing = set(PRINTED) - set(found)
    if missing:
        raise RuntimeError(f"not in this design: {sorted(missing)} (build it with build_head_unit.py)")
    em = design.exportManager
    for name, body in found.items():
        path = os.path.join(out, PRINTED[name] + ".stl")
        opts = em.createSTLExportOptions(body, path)
        opts.meshRefinement = adsk.fusion.MeshRefinementSettings.MeshRefinementHigh
        if not em.execute(opts):
            raise RuntimeError(f"export failed: {path}")
        print(path)
