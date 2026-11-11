#!/usr/bin/env python3
"""Writes the dashboard's vector-map assets (ADR-0032) into
apps/infotainment/assets/map/:

  styles/light.json, styles/dark.json   the @protomaps/basemaps style for each
                                        flavor, rewritten for vector_tile_renderer
  sprites/light@2x.{json,png}, dark@2x  the icons (protomaps/basemaps-assets)
  fonts/NotoSans-*.ttf, fonts/OFL.txt   the label fonts (Noto Sans, SIL OFL)

Every input is pinned (here and in build-map.py). The output is committed; run
this again (`make map-assets`) only to change a pin or the rewrite below.

Needs Node.js 18+ with npm and curl. Nothing here runs at test time.
"""
import importlib.util
import json
import os
import shutil
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
OUT = os.path.join(ROOT, "apps", "infotainment", "assets", "map")

_spec = importlib.util.spec_from_file_location("build_map", os.path.join(HERE, "build-map.py"))
build_map = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(build_map)

FLAVORS = ["light", "dark"]
LANG = "en"

# Noto Sans static TTFs (unhinted) from notofonts/notofonts.github.io.
NOTO_COMMIT = "4cf78353cd1668040ba8efa13029cd910fcdf9e2"
NOTO_URL = ("https://raw.githubusercontent.com/notofonts/notofonts.github.io/"
            f"{NOTO_COMMIT}/fonts/NotoSans/unhinted/ttf/{{file}}")
# The style's font names (text-font) → the files; the dashboard's pubspec
# declares each name as a font family.
FONTS = {"Noto Sans Regular": "NotoSans-Regular.ttf",
         "Noto Sans Medium": "NotoSans-Medium.ttf",
         "Noto Sans Italic": "NotoSans-Italic.ttf"}

# Labels are drawn from the English name, else the local name. The upstream
# style's `format` expressions (two-line labels in several scripts) aren't
# supported by vector_tile_renderer 6.1.0.
NAME = ["coalesce", ["get", f"name:{LANG}"], ["get", "name"]]


def log(msg):
    print(msg, flush=True)


def is_op(e, op):
    return isinstance(e, list) and len(e) > 0 and e[0] == op


def contains(e, op):
    return isinstance(e, list) and (is_op(e, op) or any(contains(x, op) for x in e))


def rewrite(e, in_filter=False):
    """Rewrites the expressions vector_tile_renderer 6.1.0 can't parse into
    ones it can. Each rule is listed in ADR-0032."""
    if isinstance(e, dict):
        return {k: rewrite(v, in_filter) for k, v in e.items()}
    if not isinstance(e, list) or not e:
        return e
    # ["in", x, ["literal", [a, b]]] → ["match", x, [a, b], true, false]
    if e[0] == "in" and len(e) == 3 and is_op(e[2], "literal") and isinstance(e[2][1], list):
        return ["match", rewrite(e[1], in_filter), e[2][1], True, False]
    # ["length", ["get", "shield_text"]] (choosing a shield width) → the
    # number of digits of a numeric route, else 3.
    if e[0] == "length" and len(e) == 2:
        n = ["to-number", rewrite(e[1], in_filter)]
        return ["case", ["<", n, 10], 1, ["<", n, 100], 2, 3]
    # A filter's per-feature zoom test (["zoom"] isn't supported in filters):
    # dropped, so those features show from the layer's own minzoom.
    if in_filter and e[0] in ("<", "<=", ">", ">=", "==") and len(e) == 3 \
            and (e[1] == ["zoom"] or e[2] == ["zoom"]):
        return True
    return [rewrite(x, in_filter) for x in e]


def font_of(expr):
    """A text-font value as a plain list: an expression choosing between
    fonts becomes its last (default) choice."""
    if isinstance(expr, list) and expr and all(isinstance(x, str) for x in expr) \
            and not is_op(expr, "literal") and not is_op(expr, "case"):
        return expr
    if is_op(expr, "literal"):
        return expr[1]
    if is_op(expr, "case") or is_op(expr, "match"):
        return font_of(expr[-1])
    raise ValueError(f"unexpected text-font {expr!r}")


def convert(style):
    out = {
        "version": 8,
        "id": "protomaps",
        "name": style.get("name", "protomaps"),
        "metadata": {"f250:source": f"{build_map.BASEMAPS_NPM}, rewritten by tools/maps/map-assets.py"},
        "sources": {"protomaps": {"type": "vector", "attribution": build_map.ATTRIBUTION}},
        "layers": [],
    }
    for layer in style["layers"]:
        layer = json.loads(json.dumps(layer))
        if "filter" in layer:
            layer["filter"] = rewrite(layer["filter"], in_filter=True)
        layout = layer.get("layout", {})
        if "text-field" in layout and contains(layout["text-field"], "format"):
            layout["text-field"] = NAME
        if "text-font" in layout:
            layout["text-font"] = font_of(layout["text-font"])
            for f in layout["text-font"]:
                if f not in FONTS:
                    raise ValueError(f"layer {layer['id']}: font {f!r} isn't bundled")
        for key in ("layout", "paint"):
            if key in layer:
                layer[key] = rewrite(layer[key])
        out["layers"].append(layer)
    return out


def main():
    for tool in ("node", "npm", "curl"):
        build_map.need(tool, "Node.js 18+ with npm, and curl")
    work = os.path.join(ROOT, "build", "maps", "assets.work")
    server = os.path.join(work, "server")
    os.makedirs(server, exist_ok=True)
    for d in ("styles", "sprites", "fonts"):
        os.makedirs(os.path.join(OUT, d), exist_ok=True)

    for flavor in FLAVORS:
        build_map.fetch_assets(work, server, flavor)
        build_map.write_style(work, server, flavor, LANG)
        with open(os.path.join(server, "style.json")) as f:
            style = convert(json.load(f))
        style["id"] = style["name"] = f"protomaps-{flavor}"
        dest = os.path.join(OUT, "styles", f"{flavor}.json")
        with open(dest, "w") as f:
            json.dump(style, f, indent=1, ensure_ascii=False)
            f.write("\n")
        log(f"{dest}: {len(style['layers'])} layers")
        for ext in ("json", "png"):
            shutil.copyfile(os.path.join(server, "sprites", f"{flavor}@2x.{ext}"),
                            os.path.join(OUT, "sprites", f"{flavor}@2x.{ext}"))

    shutil.copyfile(os.path.join(server, "fonts", "OFL.txt"), os.path.join(OUT, "fonts", "OFL.txt"))
    for file in FONTS.values():
        dest = os.path.join(OUT, "fonts", file)
        subprocess.run(["curl", "-sfL", "--retry", "3", "-o", dest + ".part",
                        NOTO_URL.format(file=file)], check=True)
        os.replace(dest + ".part", dest)
        log(f"{dest}: {os.path.getsize(dest):,} bytes")


if __name__ == "__main__":
    sys.exit(main())
