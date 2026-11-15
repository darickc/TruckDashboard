"""Builds the F-250 head unit parts in Autodesk Fusion (ADR-0047).

Run it in an empty Fusion design: Utilities > Scripts and Add-Ins, or
`make mech-fusion` through Fusion's MCP server. It reads parameters.json
(next to this file, or PARAMS when the MCP client passes it) into Fusion user
parameters, then draws dimensioned sketches driven by them. After the build,
edit the parameters in Fusion (Modify > Change Parameters) and the parts
follow.

Components:
  Display (reference)  the cover glass and the metal back; not printed
  Glass template       the glass with the picture cut out, to hold behind the
                       dash's opening (H34)
  Rail left/right      screw to the display's M3 holes; ears past the glass
                       for the truck's brackets; inserts for the rear box

Coordinates: mm, seen from the driver's seat; origin at the glass's
bottom-left corner on its front face; X right, Y up, Z into the dash.

Status: DESIGN, NOT FITTED. Nothing printed.
"""

import json
import os

import adsk.core
import adsk.fusion

MARK = ("f250", "head-unit")   # attribute on the root component: this design is ours


def load_params():
    if "PARAMS" in globals():
        return globals()["PARAMS"]
    here = os.path.dirname(os.path.abspath(__file__))
    with open(os.path.join(here, "parameters.json")) as f:
        return json.load(f)


def evaluate(params):
    """The parameters' values in mm, as Python numbers (for placing geometry;
    the dimensions themselves carry the expressions)."""
    env = {}
    for p in params:
        env[p["name"]] = eval(p["expr"], {"__builtins__": {}}, env)
    return env


def P(x_mm, y_mm):
    return adsk.core.Point3D.create(x_mm / 10.0, y_mm / 10.0, 0)   # the API is in cm


def V(expr):
    return adsk.core.ValueInput.createByString(expr)


class Sketcher:
    def __init__(self, comp, plane, name):
        self.s = comp.sketches.add(plane)
        self.s.name = name
        self.dims = self.s.sketchDimensions
        self.cons = self.s.geometricConstraints
        self.o = self.s.originPoint
        self.placed = []
        self.H = adsk.fusion.DimensionOrientations.HorizontalDimensionOrientation
        self.V = adsk.fusion.DimensionOrientations.VerticalDimensionOrientation

    def _place(self, pt, x, y, ex, ey):
        """Fix a point by its distance from the sketch origin. A point level
        with one already placed is tied to it instead: Fusion 2706 rejects a
        second origin dimension of the same length and direction as over
        constrained (seen 2026-11-15)."""
        same_x = next((q for q, qx, _ in self.placed if abs(qx - x) < 1e-6), None)
        same_y = next((q for q, _, qy in self.placed if abs(qy - y) < 1e-6), None)
        if abs(x) < 1e-6:
            self.cons.addVerticalPoints(self.o, pt)
        elif same_x is not None:
            self.cons.addVerticalPoints(same_x, pt)
        else:
            self.dims.addDistanceDimension(self.o, pt, self.H, P(x / 2, y - 6)).parameter.expression = ex
        if abs(y) < 1e-6:
            self.cons.addHorizontalPoints(self.o, pt)
        elif same_y is not None:
            self.cons.addHorizontalPoints(same_y, pt)
        else:
            self.dims.addDistanceDimension(self.o, pt, self.V, P(x - 6, y / 2)).parameter.expression = ey
        self.placed.append((pt, x, y))

    def rect(self, x, y, w, h, ex, ey, ew, eh):
        """A rectangle with its bottom-left corner at (x, y); ex and ey are the
        corner's distances from the origin as expressions (magnitudes)."""
        lines = self.s.sketchCurves.sketchLines.addTwoPointRectangle(P(x, y), P(x + w, y + h))
        pts = []
        for i in range(lines.count):
            ln = lines.item(i)
            pts += [ln.startSketchPoint, ln.endSketchPoint]
            # Fusion 2706's two-point rectangle comes without horizontal and
            # vertical constraints (seen 2026-11-15); without them a changed
            # parameter could skew it.
            kinds = {ln.geometricConstraints.item(j).objectType for j in range(ln.geometricConstraints.count)}
            if not any(k.endswith(("HorizontalConstraint", "VerticalConstraint")) for k in kinds):
                a, b = ln.startSketchPoint.geometry, ln.endSketchPoint.geometry
                if abs(a.y - b.y) < 1e-9:
                    self.cons.addHorizontal(ln)
                else:
                    self.cons.addVertical(ln)

        def at(px, py):
            return min(pts, key=lambda q: (q.geometry.x * 10 - px) ** 2 + (q.geometry.y * 10 - py) ** 2)

        bl, br, tl = at(x, y), at(x + w, y), at(x, y + h)
        self._place(bl, x, y, ex, ey)
        self.dims.addDistanceDimension(bl, br, self.H, P(x + w / 2, y - 3)).parameter.expression = ew
        self.dims.addDistanceDimension(bl, tl, self.V, P(x - 3, y + h / 2)).parameter.expression = eh

    def circle(self, x, y, d, ex, ey, ed):
        c = self.s.sketchCurves.sketchCircles.addByCenterRadius(P(x, y), d / 2)
        self.dims.addDiameterDimension(c, P(x + d, y + d)).parameter.expression = ed
        self._place(c.centerSketchPoint, x, y, ex, ey)

    def profiles(self):
        col = adsk.core.ObjectCollection.create()
        for i in range(self.s.profiles.count):
            col.add(self.s.profiles.item(i))
        return col


def offset_plane(comp, expr, name):
    inp = comp.constructionPlanes.createInput()
    inp.setByOffset(comp.xYConstructionPlane, V(expr))
    pl = comp.constructionPlanes.add(inp)
    pl.name = name
    pl.isLightBulbOn = False
    return pl


def extrude_new(comp, sk, expr, name):
    inp = comp.features.extrudeFeatures.createInput(sk.profiles(), adsk.fusion.FeatureOperations.NewBodyFeatureOperation)
    inp.setDistanceExtent(False, V(expr))
    feat = comp.features.extrudeFeatures.add(inp)
    body = feat.bodies.item(0)
    body.name = name
    return body


def cut(comp, sk, expr, body, negative):
    inp = comp.features.extrudeFeatures.createInput(sk.profiles(), adsk.fusion.FeatureOperations.CutFeatureOperation)
    direction = (adsk.fusion.ExtentDirections.NegativeExtentDirection if negative
                 else adsk.fusion.ExtentDirections.PositiveExtentDirection)
    inp.setOneSideExtent(adsk.fusion.DistanceExtentDefinition.create(V(expr)), direction)
    inp.participantBodies = [body]
    comp.features.extrudeFeatures.add(inp)


def new_component(root, name):
    occ = root.occurrences.addNewComponent(adsk.core.Matrix3D.create())
    occ.component.name = name
    return occ.component


def run(_context: str):
    app = adsk.core.Application.get()
    design = adsk.fusion.Design.cast(app.activeProduct)
    if design is None or design.designType != adsk.fusion.DesignTypes.ParametricDesignType:
        raise RuntimeError("Open an empty parametric Fusion design first")
    root = design.rootComponent
    ours = root.attributes.itemByName(*MARK) is not None
    if not ours and (root.occurrences.count or root.bRepBodies.count or root.sketches.count):
        raise RuntimeError("The active design isn't empty: open a new design, so nothing of yours is changed")
    if ours:
        raise RuntimeError("The head unit is already built in this design: edit its parameters, or start a new design")
    # A new design may be a Part design, which holds one component. An empty
    # one can become a Hybrid design (components that each model). The
    # designIntent API is a preview feature in Fusion 2706.
    if design.designIntent == adsk.fusion.DesignIntentTypes.PartDesignIntentType:
        design.designIntent = adsk.fusion.DesignIntentTypes.HybridDesignIntentType

    data = load_params()
    params = data["parameters"]
    v = evaluate(params)

    # User parameters, so the owner can change them in Fusion.
    ups = design.userParameters
    for p in params:
        existing = ups.itemByName(p["name"])
        if existing:
            existing.expression = p["expr"]
            existing.comment = p.get("comment", "")
        else:
            ups.add(p["name"], V(p["expr"]), "mm", p.get("comment", ""))
    root.attributes.add(MARK[0], MARK[1], "built by mechanical/head-unit/build_head_unit.py")

    # Display (reference): the glass and the metal back, from the drawing.
    disp = new_component(root, "Display (reference, not printed)")
    sk = Sketcher(disp, disp.xYConstructionPlane, "glass")
    sk.rect(0, 0, v["glass_w"], v["glass_h"], None, None, "glass_w", "glass_h")
    glass = extrude_new(disp, sk, "glass_t", "Cover glass")
    pl = offset_plane(disp, "glass_t", "behind the glass")
    sk = Sketcher(disp, pl, "metal back")
    sk.rect(v["frame_x"], v["frame_y"], v["frame_w"], v["frame_h"], "frame_x", "frame_y", "frame_w", "frame_h")
    extrude_new(disp, sk, "module_t - glass_t", "Metal back")
    sk = Sketcher(disp, disp.xYConstructionPlane, "viewable area")
    sk.rect(v["va_x"], v["va_y"], v["va_w"], v["va_h"], "va_x", "va_y", "va_w", "va_h")
    for i in range(disp.bRepBodies.count):
        disp.bRepBodies.item(i).opacity = 0.5

    # Glass template: printed flat, 1.2 mm.
    tpl = new_component(root, "Glass template")
    pl = offset_plane(tpl, "-(template_t + template_gap)", "template")
    sk = Sketcher(tpl, pl, "outline")
    sk.rect(0, 0, v["glass_w"], v["glass_h"], None, None, "glass_w", "glass_h")
    body = extrude_new(tpl, sk, "template_t", "Glass template")
    sk = Sketcher(tpl, pl, "window and notch")
    sk.rect(v["va_x"], v["va_y"], v["va_w"], v["va_h"], "va_x", "va_y", "va_w", "va_h")
    nx, ny = v["glass_w"] / 2 - v["notch_w"] / 2, v["glass_h"] - v["notch_h"]
    sk.rect(nx, ny, v["notch_w"], v["notch_h"] + 1, "glass_w / 2 - notch_w / 2", "glass_h - notch_h", "notch_w", "notch_h + 1 mm")
    cut(tpl, sk, "template_t", body, negative=False)

    # Rails: front face on the display's metal back (z = module_t).
    for side in ("left", "right"):
        comp = new_component(root, f"Rail {side}")
        front = offset_plane(comp, "module_t", "rail front")
        back = offset_plane(comp, "module_t + rail_t", "rail back")
        if side == "left":
            x0, w = -v["ear_w"], v["rail_l_in"] + v["ear_w"]
            ex0, ew = "ear_w", "rail_l_in + ear_w"
            hx, ehx = v["m3_x0"], "m3_x0"
            earx, eearx = -v["ear_w"] / 2, "ear_w / 2"
            boxx, eboxx = v["box_l_x"], "box_l_x"
        else:
            x0, w = v["rail_r_in"], v["glass_w"] + v["ear_w"] - v["rail_r_in"]
            ex0, ew = "rail_r_in", "glass_w + ear_w - rail_r_in"
            hx, ehx = v["m3_x1"], "m3_x1"
            earx, eearx = v["glass_w"] + v["ear_w"] / 2, "glass_w + ear_w / 2"
            boxx, eboxx = v["box_r_x"], "box_r_x"
        sk = Sketcher(comp, front, "outline")
        sk.rect(x0, 0, w, v["glass_h"], ex0, None, ew, "glass_h")
        body = extrude_new(comp, sk, "rail_t", f"Rail {side}")
        # The display's M3 screws: clearance through, counterbore from the back.
        sk = Sketcher(comp, front, "M3 clearance")
        for y, ey in ((v["m3_y0"], "m3_y0"), (v["m3_y1"], "m3_y1")):
            sk.circle(hx, y, v["m3_clear"], ehx, ey, "m3_clear")
        cut(comp, sk, "rail_t", body, negative=False)
        sk = Sketcher(comp, back, "M3 counterbores")
        for y, ey in ((v["m3_y0"], "m3_y0"), (v["m3_y1"], "m3_y1")):
            sk.circle(hx, y, v["m3_head_d"], ehx, ey, "m3_head_d")
        cut(comp, sk, "m3_head_h", body, negative=True)
        # Heat-set inserts from the back: the ear (truck brackets), the rear box.
        sk = Sketcher(comp, back, "inserts")
        for y, ey in ((v["ear_insert_y0"], "ear_insert_y0"), (v["glass_h"] - v["ear_insert_y0"], "glass_h - ear_insert_y0")):
            sk.circle(earx, y, v["insert_d"], eearx, ey, "insert_d")
        for y, ey in ((v["box_insert_y0"], "box_insert_y0"), (v["glass_h"] - v["box_insert_y0"], "glass_h - box_insert_y0")):
            sk.circle(boxx, y, v["insert_d"], eboxx, ey, "insert_d")
        cut(comp, sk, "insert_h", body, negative=True)

    app.activeViewport.fit()
    print("built: display (reference), glass template, rails left and right;",
          ups.count, "user parameters")
