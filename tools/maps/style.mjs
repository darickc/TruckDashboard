// Writes the MapLibre style that tileserver-gl renders the raster map with
// (ADR-0031). Run by tools/maps/build-raster-map.py from a work directory
// where @protomaps/basemaps is installed at the pinned version:
//
//   node style.mjs OUT.json FLAVOR LANG
//
// FLAVOR is a Protomaps named flavor (light, dark, white, grayscale, black).
// Glyphs and sprites are local to tileserver-gl (basemaps-assets, pinned).
import { writeFileSync } from "node:fs";
import { layers, namedFlavor } from "@protomaps/basemaps";

const [out, flavor = "light", lang = "en"] = process.argv.slice(2);
if (!out) {
  console.error("usage: node style.mjs OUT.json [FLAVOR] [LANG]");
  process.exit(2);
}

const style = {
  version: 8,
  name: `Protomaps ${flavor} (F-250 raster)`,
  glyphs: "{fontstack}/{range}.pbf",
  // Sprite sheets exist for light, dark, white, grayscale and black.
  sprite: flavor,
  sources: {
    protomaps: {
      type: "vector",
      // tileserver-gl resolves this to the data entry "protomaps" in config.json.
      url: "pmtiles://{protomaps}",
      attribution: "Protomaps © OpenStreetMap contributors",
    },
  },
  layers: layers("protomaps", namedFlavor(flavor), { lang }),
};

writeFileSync(out, JSON.stringify(style));
console.log(`${out}: ${style.layers.length} layers, flavor ${flavor}, language ${lang}`);
