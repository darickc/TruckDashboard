"""Reports the head unit as built in Fusion, for tools/mechanical/check_head_unit.py
--fusion (ADR-0047). Read-only: prints one JSON line with each body's bounding
box (mm), volume (mm^3) and face count, whether each sketch is fully
constrained, and any timeline item that isn't healthy."""

import json

import adsk.core
import adsk.fusion


def run(_context: str):
    design = adsk.fusion.Design.cast(adsk.core.Application.get().activeProduct)
    root = design.rootComponent
    out = {"bodies": {}, "sketches": {}, "unhealthy": [], "parameters": {}}
    for occ in root.allOccurrences:
        comp = occ.component
        for i in range(comp.bRepBodies.count):
            b = comp.bRepBodies.item(i)
            bb = b.boundingBox
            out["bodies"][b.name] = {
                "min": [round(c * 10, 3) for c in (bb.minPoint.x, bb.minPoint.y, bb.minPoint.z)],
                "max": [round(c * 10, 3) for c in (bb.maxPoint.x, bb.maxPoint.y, bb.maxPoint.z)],
                "volume": round(b.volume * 1000, 2),
                "faces": b.faces.count,
            }
        for i in range(comp.sketches.count):
            s = comp.sketches.item(i)
            out["sketches"][f"{comp.name}/{s.name}"] = s.isFullyConstrained
    for i in range(design.timeline.count):
        item = design.timeline.item(i)
        if item.healthState != adsk.fusion.FeatureHealthStates.HealthyFeatureHealthState:
            out["unhealthy"].append(f"{item.name}: {item.errorOrWarningMessage}")
    for i in range(design.userParameters.count):
        p = design.userParameters.item(i)
        out["parameters"][p.name] = round(p.value * 10, 4)
    print(json.dumps(out))
