//! Which state a point is in, from OSM's state boundaries (admin_level=4),
//! so a result says "Kansas City · KS" and not just "Kansas City".
//!
//! `osmium export` writes the boundaries as GeoJSON features, one per line
//! (`tools/maps/build-search.py` runs it); this reads them and answers
//! point-in-polygon questions. A boundary only partly in the extract can't
//! be assembled and is missing: places there get no state.
//!
//! Each boundary's edges are kept in 0.1° latitude bands, so a question
//! looks only at the edges that cross the point's latitude.

use std::collections::HashMap;
use std::path::Path;

/// One state.
#[derive(Debug)]
struct State {
    /// "KS" from ISO3166-2 "US-KS", else the name.
    short: String,
    name: String,
    /// west, south, east, north
    bbox: (f64, f64, f64, f64),
    /// Edges (lon1, lat1, lon2, lat2) by 0.1° latitude band.
    bands: HashMap<i64, Vec<(f64, f64, f64, f64)>>,
}

const BAND: f64 = 0.1;

fn band(lat: f64) -> i64 {
    (lat / BAND).floor() as i64
}

#[derive(Default, Debug)]
pub struct States {
    states: Vec<State>,
}

/// A state's two names.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct StateName {
    pub short: String,
    pub name: String,
}

impl States {
    /// Reads GeoJSON features (one per line, optionally after an RS
    /// character), keeping Polygons and MultiPolygons with a name.
    pub fn read(path: &Path) -> Result<States, String> {
        let text = std::fs::read_to_string(path).map_err(|e| format!("{}: {e}", path.display()))?;
        States::parse(&text).map_err(|e| format!("{}: {e}", path.display()))
    }

    pub fn parse(text: &str) -> Result<States, String> {
        let mut out = States::default();
        for (n, line) in text.lines().enumerate() {
            let line = line.trim_start_matches('\u{1e}').trim();
            if line.is_empty() {
                continue;
            }
            let f: serde_json::Value =
                serde_json::from_str(line).map_err(|e| format!("line {}: {e}", n + 1))?;
            let props = &f["properties"];
            let Some(name) = props["name"].as_str() else {
                continue;
            };
            let short = props["ISO3166-2"]
                .as_str()
                .and_then(|iso| iso.split_once('-').map(|(_, s)| s.to_string()))
                .unwrap_or_else(|| name.to_string());
            let g = &f["geometry"];
            let polygons: Vec<&serde_json::Value> = match g["type"].as_str() {
                Some("Polygon") => vec![&g["coordinates"]],
                Some("MultiPolygon") => g["coordinates"]
                    .as_array()
                    .map(|a| a.iter().collect())
                    .unwrap_or_default(),
                _ => continue,
            };
            let mut s = State {
                short,
                name: name.to_string(),
                bbox: (f64::MAX, f64::MAX, f64::MIN, f64::MIN),
                bands: HashMap::new(),
            };
            for ring in polygons.iter().filter_map(|p| p.as_array()).flatten() {
                let pts: Vec<(f64, f64)> = ring
                    .as_array()
                    .into_iter()
                    .flatten()
                    .filter_map(|p| Some((p[0].as_f64()?, p[1].as_f64()?)))
                    .collect();
                for w in pts.windows(2) {
                    let ((x1, y1), (x2, y2)) = (w[0], w[1]);
                    s.bbox = (
                        s.bbox.0.min(x1),
                        s.bbox.1.min(y1),
                        s.bbox.2.max(x1),
                        s.bbox.3.max(y1),
                    );
                    for b in band(y1.min(y2))..=band(y1.max(y2)) {
                        s.bands.entry(b).or_default().push((x1, y1, x2, y2));
                    }
                }
            }
            if !s.bands.is_empty() {
                out.states.push(s);
            }
        }
        Ok(out)
    }

    pub fn len(&self) -> usize {
        self.states.len()
    }

    pub fn is_empty(&self) -> bool {
        self.states.is_empty()
    }

    /// The state the point is in, if any (even-odd rule: holes and islands
    /// both work).
    pub fn at(&self, lat: f64, lon: f64) -> Option<StateName> {
        let b = band(lat);
        self.states
            .iter()
            .filter(|s| lon >= s.bbox.0 && lon <= s.bbox.2 && lat >= s.bbox.1 && lat <= s.bbox.3)
            .find(|s| {
                let mut inside = false;
                for &(x1, y1, x2, y2) in s.bands.get(&b).into_iter().flatten() {
                    if (y1 > lat) != (y2 > lat) && lon < x1 + (lat - y1) * (x2 - x1) / (y2 - y1) {
                        inside = !inside;
                    }
                }
                inside
            })
            .map(|s| StateName {
                short: s.short.clone(),
                name: s.name.clone(),
            })
    }
}

#[cfg(test)]
#[allow(clippy::unwrap_used, clippy::expect_used)]
mod tests {
    use super::*;

    /// Two made-up square states side by side, the first with a hole.
    const TWO: &str = concat!(
        "\u{1e}{\"type\":\"Feature\",\"geometry\":{\"type\":\"MultiPolygon\",\"coordinates\":[[",
        "[[-100,25],[-95,25],[-95,30],[-100,30],[-100,25]],",
        "[[-98,27],[-97,27],[-97,28],[-98,28],[-98,27]]",
        "]]},\"properties\":{\"name\":\"Westland\",\"ISO3166-2\":\"US-WL\",\"admin_level\":\"4\"}}\n",
        "{\"type\":\"Feature\",\"geometry\":{\"type\":\"Polygon\",\"coordinates\":[",
        "[[-95,25],[-90,25],[-90,30],[-95,30],[-95,25]]",
        "]},\"properties\":{\"name\":\"Eastland\"}}\n",
        "{\"type\":\"Feature\",\"geometry\":{\"type\":\"LineString\",\"coordinates\":[[0,0],[1,1]]},\"properties\":{\"name\":\"X\"}}\n",
    );

    #[test]
    fn point_in_state() {
        let s = States::parse(TWO).unwrap();
        assert_eq!(s.len(), 2);
        let w = s.at(26.0, -99.0).unwrap();
        assert_eq!((w.short.as_str(), w.name.as_str()), ("WL", "Westland"));
        // No ISO code: the name stands in.
        assert_eq!(s.at(26.0, -92.0).unwrap().short, "Eastland");
        // In the hole, and outside both.
        assert_eq!(s.at(27.5, -97.5), None);
        assert_eq!(s.at(31.0, -92.0), None);
        assert_eq!(s.at(26.0, -101.0), None);
    }

    #[test]
    fn bad_lines_are_errors() {
        assert!(States::parse("{not json").unwrap_err().contains("line 1"));
        assert!(States::parse("").unwrap().is_empty());
    }
}
