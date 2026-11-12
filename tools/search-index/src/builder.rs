//! From PBF extracts to the index file, in two passes over each extract.
//!
//! 1. Every object [`classify`] keeps: nodes with their position, ways with
//!    one node to stand for them (a street's middle node, a building's first
//!    corner). PBF blocks decode in parallel.
//! 2. The positions of those stand-in nodes.
//!
//! Then every street, address and named place gets a town: an address's own
//! `addr:city`, else the nearest city, town, village or hamlet within its
//! reach ([`reach_km`]), shown as "near …". The pieces OSM splits a street
//! into become one row per street name and town, placed on the piece nearest
//! their middle (a point on the road, so a route ends on it).
//!
//! With state boundaries ([`crate::states`]), every row gets the state it is
//! in, in parallel.
//!
//! Memory grows with the extract: two numbers per stand-in node, plus the
//! names. Kansas is a few hundred MB; the lower 48 a few GB.

use std::collections::HashMap;
use std::path::{Path, PathBuf};
use std::sync::Mutex;

use geocode::index::{self, Counts, Kind, Meta, Place, Writer};
use osmpbf::{BlobDecode, BlobReader, PrimitiveBlock};
use rayon::prelude::*;

use crate::extract::{Addr, Feature, classify};
use crate::states::States;

pub struct Options {
    pub pbfs: Vec<PathBuf>,
    pub out: PathBuf,
    /// What the index covers, for the screen ("Kansas").
    pub regions: Vec<String>,
    /// The OSM data's date; else the newest extract's replication timestamp.
    pub data_date: Option<String>,
    /// State boundaries as GeoJSON lines (`osmium export`), if any.
    pub states: Option<PathBuf>,
    /// Progress lines on stderr.
    pub verbose: bool,
}

#[derive(Debug)]
pub struct Summary {
    pub counts: Counts,
    pub data_date: Option<String>,
    /// Ways whose stand-in node wasn't in the extract (cut at its edge).
    pub missing_nodes: usize,
}

/// One kept object.
struct Found {
    feature: Feature,
    at: At,
}

enum At {
    Here(f64, f64),
    /// A way, by its stand-in node.
    Node(i64),
}

#[derive(Default)]
struct Pass1 {
    found: Vec<Found>,
    timestamp: Option<i64>,
}

pub fn build(o: &Options) -> Result<Summary, String> {
    let say = |m: &str| {
        if o.verbose {
            eprintln!("search-index: {m}");
        }
    };
    let mut all = Pass1::default();
    for pbf in &o.pbfs {
        say(&format!("reading {}", pbf.display()));
        let p = pass1(pbf)?;
        all.found.extend(p.found);
        all.timestamp = all.timestamp.max(p.timestamp);
    }
    let mut wanted: Vec<i64> = all
        .found
        .iter()
        .filter_map(|f| match f.at {
            At::Node(id) => Some(id),
            At::Here(..) => None,
        })
        .collect();
    wanted.sort_unstable();
    wanted.dedup();
    say(&format!(
        "{} objects kept; locating {} way nodes",
        all.found.len(),
        wanted.len()
    ));
    let mut coords = vec![(f64::NAN, f64::NAN); wanted.len()];
    for pbf in &o.pbfs {
        for (i, lat, lon) in pass2(pbf, &wanted)? {
            coords[i] = (lat, lon);
        }
    }

    let mut placed = Vec::with_capacity(all.found.len());
    let mut missing_nodes = 0;
    for f in all.found {
        let (lat, lon) = match f.at {
            At::Here(lat, lon) => (lat, lon),
            At::Node(id) => match wanted.binary_search(&id).map(|i| coords[i]) {
                Ok((lat, lon)) if lat.is_finite() => (lat, lon),
                _ => {
                    missing_nodes += 1;
                    continue;
                }
            },
        };
        placed.push((f.feature, lat, lon));
    }

    say("assigning towns and joining streets");
    let mut places = assemble(placed);
    if let Some(path) = &o.states {
        let states = States::read(path)?;
        say(&format!(
            "{} state boundaries: placing every row in one",
            states.len()
        ));
        places.par_iter_mut().for_each(|p| {
            p.state = states.at(p.lat, p.lon).map(|s| index::State {
                short: s.short,
                name: s.name,
            });
        });
    }
    say(&format!(
        "writing {} rows to {}",
        places.len(),
        o.out.display()
    ));
    if let Some(dir) = o.out.parent() {
        std::fs::create_dir_all(dir).map_err(|e| format!("{}: {e}", dir.display()))?;
    }
    let part = o.out.with_extension("sqlite.part");
    let mut w = Writer::create(&part).map_err(|e| format!("{}: {e}", part.display()))?;
    for p in &places {
        w.add(p).map_err(|e| format!("{}: {e}", part.display()))?;
    }
    let data_date = o.data_date.clone().or_else(|| all.timestamp.map(date_of));
    let counts = w
        .finish(&Meta {
            regions: o.regions.clone(),
            data_date: data_date.clone(),
            built_at: rfc3339(now_s()),
        })
        .map_err(|e| format!("{}: {e}", part.display()))?;
    std::fs::rename(&part, &o.out).map_err(|e| format!("{}: {e}", o.out.display()))?;
    Ok(Summary {
        counts,
        data_date,
        missing_nodes,
    })
}

fn blocks(pbf: &Path) -> Result<BlobReader<std::io::BufReader<std::fs::File>>, String> {
    BlobReader::from_path(pbf).map_err(|e| format!("{}: {e}", pbf.display()))
}

fn pass1(pbf: &Path) -> Result<Pass1, String> {
    let out = Mutex::new(Pass1::default());
    let error = Mutex::new(None::<String>);
    blocks(pbf)?.par_bridge().for_each(|blob| {
        let decoded = blob
            .as_ref()
            .map_err(|e| e.to_string())
            .and_then(|b| b.decode().map_err(|e| e.to_string()));
        match decoded {
            Ok(BlobDecode::OsmData(block)) => {
                let found = keep(&block);
                if let Ok(mut o) = out.lock() {
                    o.found.extend(found);
                }
            }
            Ok(BlobDecode::OsmHeader(h)) => {
                if let Ok(mut o) = out.lock() {
                    o.timestamp = o.timestamp.max(h.osmosis_replication_timestamp());
                }
            }
            Ok(BlobDecode::Unknown(_)) => {}
            Err(e) => {
                if let Ok(mut err) = error.lock() {
                    err.get_or_insert(format!("{}: {e}", pbf.display()));
                }
            }
        }
    });
    if let Some(e) = error.into_inner().map_err(|e| e.to_string())? {
        return Err(e);
    }
    out.into_inner().map_err(|e| e.to_string())
}

fn keep(block: &PrimitiveBlock) -> Vec<Found> {
    let mut found = Vec::new();
    let mut tags: Vec<(&str, &str)> = Vec::new();
    for group in block.groups() {
        for n in group.dense_nodes() {
            tags.clear();
            tags.extend(n.tags());
            if !tags.is_empty()
                && let Some(feature) = classify(&tags, false)
            {
                found.push(Found {
                    feature,
                    at: At::Here(n.lat(), n.lon()),
                });
            }
        }
        for n in group.nodes() {
            tags.clear();
            tags.extend(n.tags());
            if !tags.is_empty()
                && let Some(feature) = classify(&tags, false)
            {
                found.push(Found {
                    feature,
                    at: At::Here(n.lat(), n.lon()),
                });
            }
        }
        for w in group.ways() {
            tags.clear();
            tags.extend(w.tags());
            let Some(feature) = classify(&tags, true) else {
                continue;
            };
            let refs = w.raw_refs();
            if refs.is_empty() {
                continue;
            }
            // raw_refs are delta-coded.
            let ids: Vec<i64> = refs
                .iter()
                .scan(0i64, |acc, d| {
                    *acc += d;
                    Some(*acc)
                })
                .collect();
            let pick = match feature {
                Feature::Street { .. } => ids[ids.len() / 2],
                _ => ids[0],
            };
            found.push(Found {
                feature,
                at: At::Node(pick),
            });
        }
    }
    found
}

fn pass2(pbf: &Path, wanted: &[i64]) -> Result<Vec<(usize, f64, f64)>, String> {
    let out = Mutex::new(Vec::new());
    let error = Mutex::new(None::<String>);
    blocks(pbf)?.par_bridge().for_each(|blob| {
        let decoded = blob
            .as_ref()
            .map_err(|e| e.to_string())
            .and_then(|b| b.decode().map_err(|e| e.to_string()));
        match decoded {
            Ok(BlobDecode::OsmData(block)) => {
                let mut local = Vec::new();
                for group in block.groups() {
                    for n in group.dense_nodes() {
                        if let Ok(i) = wanted.binary_search(&n.id()) {
                            local.push((i, n.lat(), n.lon()));
                        }
                    }
                    for n in group.nodes() {
                        if let Ok(i) = wanted.binary_search(&n.id()) {
                            local.push((i, n.lat(), n.lon()));
                        }
                    }
                }
                if let Ok(mut o) = out.lock() {
                    o.extend(local);
                }
            }
            Ok(_) => {}
            Err(e) => {
                if let Ok(mut err) = error.lock() {
                    err.get_or_insert(format!("{}: {e}", pbf.display()));
                }
            }
        }
    });
    if let Some(e) = error.into_inner().map_err(|e| e.to_string())? {
        return Err(e);
    }
    out.into_inner().map_err(|e| e.to_string())
}

/// How far a place lends its name to what is around it, as "near …".
/// Examples: a hamlet only to its own few roads.
pub fn reach_km(category: &str) -> Option<f64> {
    match category {
        "city" => Some(30.0),
        "town" => Some(15.0),
        "village" => Some(8.0),
        "hamlet" => Some(4.0),
        _ => None,
    }
}

/// Towns that lend their names, in 0.25° cells.
struct Towns {
    towns: Vec<(String, f64, f64, f64)>, // name, lat, lon, reach km
    grid: HashMap<(i64, i64), Vec<usize>>,
}

const CELL: f64 = 0.25;

fn cell_of(lat: f64, lon: f64) -> (i64, i64) {
    ((lat / CELL).floor() as i64, (lon / CELL).floor() as i64)
}

impl Towns {
    fn new(placed: &[(Feature, f64, f64)]) -> Towns {
        let mut t = Towns {
            towns: Vec::new(),
            grid: HashMap::new(),
        };
        for (f, lat, lon) in placed {
            if let Feature::Town { name, category, .. } = f
                && let Some(reach) = reach_km(category)
            {
                t.grid
                    .entry(cell_of(*lat, *lon))
                    .or_default()
                    .push(t.towns.len());
                t.towns.push((name.clone(), *lat, *lon, reach));
            }
        }
        t
    }

    /// The town whose reach this point is deepest inside, if any.
    fn nearest(&self, lat: f64, lon: f64) -> Option<usize> {
        let (cy, cx) = cell_of(lat, lon);
        // 30 km is under 2 cells of latitude, and of longitude below 57° N.
        let mut best: Option<(f64, usize)> = None;
        for dy in -2..=2 {
            for dx in -2..=2 {
                for &i in self.grid.get(&(cy + dy, cx + dx)).into_iter().flatten() {
                    let (_, tl, tn, reach) = &self.towns[i];
                    let d = geocode::distance_m((lat, lon), (*tl, *tn)) / 1000.0;
                    let r = d / reach;
                    if r <= 1.0 && best.is_none_or(|(b, _)| r < b) {
                        best = Some((r, i));
                    }
                }
            }
        }
        best.map(|(_, i)| i)
    }

    fn name(&self, i: usize) -> &str {
        &self.towns[i].0
    }
}

/// Rows for the index: towns, streets joined per name and town, named
/// places, addresses.
pub fn assemble(placed: Vec<(Feature, f64, f64)>) -> Vec<Place> {
    let towns = Towns::new(&placed);
    let near = |lat: f64, lon: f64| towns.nearest(lat, lon).map(|i| towns.name(i).to_string());
    let locality = |a: &Addr, lat: f64, lon: f64| match &a.city {
        Some(c) => (Some(c.clone()), false),
        None => (near(lat, lon), true),
    };

    #[derive(Default)]
    struct Group {
        name: String,
        town: Option<usize>,
        points: Vec<(f64, f64)>,
    }
    /// A street's name (lowercased), its town, and its cell when it has none.
    type StreetKey = (String, Option<usize>, Option<(i64, i64)>);
    let mut streets: HashMap<StreetKey, Group> = HashMap::new();
    let mut out = Vec::new();
    for (f, lat, lon) in placed {
        match f {
            Feature::Town {
                name,
                category,
                population,
            } => out.push(Place {
                kind: Kind::Locality,
                weight: index::importance(Kind::Locality, Some(&category), population),
                state: None,
                name,
                number: None,
                street: None,
                locality: None,
                locality_near: false,
                category: Some(category),
                lat,
                lon,
            }),
            Feature::Street { name } => {
                let town = towns.nearest(lat, lon);
                // Away from any town, the same name is joined only within a
                // cell, so County Road 12 isn't one row across the state.
                let cell = town.is_none().then(|| cell_of(lat, lon));
                let g = streets
                    .entry((name.to_lowercase(), town, cell))
                    .or_insert_with(|| Group {
                        name: name.clone(),
                        town,
                        points: Vec::new(),
                    });
                g.points.push((lat, lon));
            }
            Feature::Poi {
                name,
                category,
                addr,
            } => {
                let (loc, is_near) = match &addr {
                    Some(a) => locality(a, lat, lon),
                    None => (near(lat, lon), true),
                };
                out.push(Place {
                    kind: Kind::Poi,
                    weight: index::importance(Kind::Poi, Some(&category), None),
                    state: None,
                    name,
                    number: addr.as_ref().map(|a| a.number.clone()),
                    street: addr.map(|a| a.street),
                    locality: loc,
                    locality_near: is_near,
                    category: Some(category),
                    lat,
                    lon,
                });
            }
            Feature::Address(a) => {
                let (loc, is_near) = locality(&a, lat, lon);
                out.push(Place {
                    kind: Kind::Address,
                    weight: index::importance(Kind::Address, None, None),
                    state: None,
                    name: String::new(),
                    number: Some(a.number),
                    street: Some(a.street),
                    locality: loc,
                    locality_near: is_near,
                    category: None,
                    lat,
                    lon,
                });
            }
        }
    }
    let mut groups: Vec<Group> = streets.into_values().collect();
    // A stable order, so the same data builds the same file.
    groups.sort_by(|a, b| {
        (
            a.name.as_str(),
            a.town,
            a.points.first().map(|p| (p.0.to_bits(), p.1.to_bits())),
        )
            .cmp(&(
                b.name.as_str(),
                b.town,
                b.points.first().map(|p| (p.0.to_bits(), p.1.to_bits())),
            ))
    });
    for g in groups {
        let n = g.points.len() as f64;
        let mid = (
            g.points.iter().map(|p| p.0).sum::<f64>() / n,
            g.points.iter().map(|p| p.1).sum::<f64>() / n,
        );
        let at = g
            .points
            .iter()
            .copied()
            .min_by(|a, b| geocode::distance_m(*a, mid).total_cmp(&geocode::distance_m(*b, mid)))
            .unwrap_or(mid);
        out.push(Place {
            kind: Kind::Street,
            weight: index::importance(Kind::Street, None, None),
            state: None,
            name: g.name,
            number: None,
            street: None,
            locality: g.town.map(|i| towns.name(i).to_string()),
            locality_near: true,
            category: None,
            lat: at.0,
            lon: at.1,
        });
    }
    out
}

fn now_s() -> i64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map_or(0, |d| d.as_secs() as i64)
}

/// Days since 1970-01-01 as (year, month, day) (Howard Hinnant's civil_from_days).
fn civil(days: i64) -> (i64, u32, u32) {
    let z = days + 719_468;
    let era = z.div_euclid(146_097);
    let doe = z.rem_euclid(146_097);
    let yoe = (doe - doe / 1460 + doe / 36_524 - doe / 146_096) / 365;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let d = (doy - (153 * mp + 2) / 5 + 1) as u32;
    let m = if mp < 10 { mp + 3 } else { mp - 9 } as u32;
    (yoe + era * 400 + i64::from(m <= 2), m, d)
}

pub fn date_of(unix_s: i64) -> String {
    let (y, m, d) = civil(unix_s.div_euclid(86_400));
    format!("{y:04}-{m:02}-{d:02}")
}

pub fn rfc3339(unix_s: i64) -> String {
    let s = unix_s.rem_euclid(86_400);
    format!(
        "{}T{:02}:{:02}:{:02}Z",
        date_of(unix_s),
        s / 3600,
        s % 3600 / 60,
        s % 60
    )
}

#[cfg(test)]
#[allow(clippy::unwrap_used, clippy::expect_used)]
mod tests {
    use super::*;

    #[test]
    fn dates() {
        assert_eq!(date_of(0), "1970-01-01");
        assert_eq!(rfc3339(1_794_355_200), "2026-11-11T00:00:00Z");
        assert_eq!(rfc3339(951_782_400 + 3661), "2000-02-29T01:01:01Z");
    }

    fn town(name: &str, category: &str, lat: f64, lon: f64) -> (Feature, f64, f64) {
        (
            Feature::Town {
                name: name.into(),
                category: category.into(),
                population: None,
            },
            lat,
            lon,
        )
    }

    fn street(name: &str, lat: f64, lon: f64) -> (Feature, f64, f64) {
        (Feature::Street { name: name.into() }, lat, lon)
    }

    #[test]
    fn streets_join_per_town_and_take_the_nearest_town() {
        let rows = assemble(vec![
            town("Fairview", "town", 38.50, -97.50),
            town("Hillsdale", "village", 38.60, -97.30),
            // Three pieces of Main Street in Fairview, one in Hillsdale.
            street("Main Street", 38.500, -97.500),
            street("Main Street", 38.502, -97.500),
            street("Main Street", 38.510, -97.500),
            street("Main Street", 38.601, -97.300),
            // Far from any town: its own row per cell, no town.
            street("County Road 12", 37.00, -99.00),
            street("County Road 12", 37.60, -99.00),
        ]);
        let streets: Vec<&Place> = rows.iter().filter(|p| p.kind == Kind::Street).collect();
        assert_eq!(streets.len(), 4, "{streets:#?}");
        let fairview = streets
            .iter()
            .find(|p| p.name == "Main Street" && p.locality.as_deref() == Some("Fairview"))
            .unwrap();
        // The piece nearest the middle of the three.
        assert_eq!((fairview.lat, fairview.lon), (38.502, -97.500));
        assert!(fairview.locality_near);
        assert!(
            streets
                .iter()
                .any(|p| p.locality.as_deref() == Some("Hillsdale"))
        );
        assert_eq!(
            streets
                .iter()
                .filter(|p| p.name == "County Road 12" && p.locality.is_none())
                .count(),
            2
        );
    }

    #[test]
    fn a_bigger_place_reaches_farther() {
        let rows = assemble(vec![
            town("Big City", "city", 38.0, -97.0),
            town("Tiny", "hamlet", 38.10, -97.0),
            // 8 km from Tiny (beyond a hamlet's 4 km), 19 km from the city.
            (
                Feature::Address(Addr {
                    number: "5".into(),
                    street: "Elm".into(),
                    city: None,
                }),
                38.17,
                -97.0,
            ),
            // With its own city tag.
            (
                Feature::Address(Addr {
                    number: "6".into(),
                    street: "Elm".into(),
                    city: Some("Tiny".into()),
                }),
                38.17,
                -97.0,
            ),
        ]);
        let a: Vec<&Place> = rows.iter().filter(|p| p.kind == Kind::Address).collect();
        assert_eq!(a[0].locality.as_deref(), Some("Big City"));
        assert!(a[0].locality_near);
        assert_eq!(a[1].locality.as_deref(), Some("Tiny"));
        assert!(!a[1].locality_near);
    }
}
