//! The search index: one SQLite file (ADR-0038).
//!
//! - `place`: one row per address, street, town or named place, with what the
//!   screen shows and where it is.
//! - Three FTS5 indexes over the rows' words ([`crate::text::index_terms`]),
//!   contentless (the words are in `place`), each holding only what one kind
//!   of question needs, so no question pays for the 35 million addresses of
//!   the lower 48 unless it has a house number:
//!   - `terms`: streets and named places, by name and town;
//!   - `towns`: towns, by name (small: prefixes are cheap here);
//!   - `addrs`: everything with a house number (addresses, and named places
//!     with an address), by number, street, name and town.
//!
//!   `terms` and `addrs` also hold each row's cells ([`cell_tokens`]), so the
//!   search can ask for "these words, near here" in one FTS query.
//! - `meta`: what the data covers, and when it was built.
//!
//! The file says what it is with `PRAGMA application_id` ([`APPLICATION_ID`],
//! "F250") and `user_version` ([`SCHEMA_VERSION`]); the stick import checks
//! the first, the search both.

use std::path::Path;

use rusqlite::{Connection, params};

use crate::text;

/// "F250" in the SQLite header (bytes 68..72, big-endian).
pub const APPLICATION_ID: i32 = 0x4632_3530;
/// Bumped when the schema changes; the search refuses another version.
pub const SCHEMA_VERSION: i32 = 1;

/// What a row is.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub enum Kind {
    /// A house number on a street (addr:housenumber + addr:street).
    Address = 1,
    /// A named street: OSM's pieces of it near one town, as one row.
    Street = 2,
    /// A city, town, village, hamlet or other named place (place=*).
    Locality = 3,
    /// A named business, park, school… (amenity, shop, tourism…).
    Poi = 4,
}

impl Kind {
    pub fn from_i64(v: i64) -> Option<Kind> {
        match v {
            1 => Some(Kind::Address),
            2 => Some(Kind::Street),
            3 => Some(Kind::Locality),
            4 => Some(Kind::Poi),
            _ => None,
        }
    }
}

/// One row, as the builder adds it.
#[derive(Clone, Debug, PartialEq)]
pub struct Place {
    pub kind: Kind,
    /// The street's, town's or place's name; empty for a bare address.
    pub name: String,
    /// The house number as OSM has it ("123A").
    pub number: Option<String>,
    pub street: Option<String>,
    /// The address's own town (addr:city), or the nearest town.
    pub locality: Option<String>,
    /// `locality` is only the nearest town ("near Fairview").
    pub locality_near: bool,
    /// The place=* value for a locality ("town"), the tag value for a named
    /// place ("fuel").
    pub category: Option<String>,
    pub lat: f64,
    pub lon: f64,
    /// [`importance`].
    pub weight: f64,
    /// The state it is in, from OSM's boundaries, when the build had them.
    pub state: Option<State>,
}

/// A state's short name ("KS", from ISO 3166-2) and full name ("Kansas").
/// The short one is shown and searchable ("main st lebanon ks"). The full
/// name isn't: "kansas city" would match everything named "City" in Kansas.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct State {
    pub short: String,
    pub name: String,
}

/// How much a row counts before distance, in the units of the ranking
/// (search.rs). Cities outrank towns outrank villages, so a far city can
/// beat a near street of the same name. Examples, tuned by hand on Kansas
/// data; a population tag adds a little.
pub fn importance(kind: Kind, category: Option<&str>, population: Option<u64>) -> f64 {
    let base = match kind {
        Kind::Address => 0.0,
        Kind::Street | Kind::Poi => 0.5,
        Kind::Locality => match category {
            Some("city") => 3.0,
            Some("town") => 1.8,
            Some("village") => 1.0,
            Some("suburb" | "quarter" | "neighbourhood") => 0.6,
            Some("hamlet") => 0.4,
            _ => 0.2,
        },
    };
    let people = population.map_or(0.0, |n| {
        ((n as f64).max(1.0).log10() - 3.0).clamp(0.0, 3.0) * 0.3
    });
    base + if kind == Kind::Locality { people } else { 0.0 }
}

/// The 1° cell a point is in, as an index token ("g129x81").
pub fn cell(lat: f64, lon: f64) -> String {
    let la = (lat.floor() as i64 + 90).clamp(0, 179);
    let lo = (lon.floor() as i64 + 180).rem_euclid(360);
    format!("g{la}x{lo}")
}

/// The 5° cell a point is in ("h25x16"), for the wider search.
pub fn wide_cell(lat: f64, lon: f64) -> String {
    let la = ((lat / 5.0).floor() as i64 + 18).clamp(0, 35);
    let lo = ((lon / 5.0).floor() as i64 + 36).rem_euclid(72);
    format!("h{la}x{lo}")
}

/// A row's cell tokens: its 1° and 5° cells.
pub fn cell_tokens(lat: f64, lon: f64) -> String {
    format!("{} {}", cell(lat, lon), wide_cell(lat, lon))
}

/// The cell around a point and its eight neighbours: about 330 × 260 km at
/// 40° N.
pub fn cells_around(lat: f64, lon: f64) -> Vec<String> {
    around(lat, lon, 1.0, cell)
}

/// The 5° cell around a point and its neighbours: about 1600 × 1300 km.
pub fn wide_cells_around(lat: f64, lon: f64) -> Vec<String> {
    around(lat, lon, 5.0, wide_cell)
}

fn around(lat: f64, lon: f64, step: f64, f: fn(f64, f64) -> String) -> Vec<String> {
    let mut out = Vec::with_capacity(9);
    for dla in [-step, 0.0, step] {
        for dlo in [-step, 0.0, step] {
            let la = lat + dla;
            if !(-90.0..90.0).contains(&la) {
                continue;
            }
            let c = f(la, lon + dlo);
            if !out.contains(&c) {
                out.push(c);
            }
        }
    }
    out
}

/// What the file covers.
#[derive(Clone, Debug, Default, PartialEq)]
pub struct Meta {
    /// e.g. ["Kansas"], from the Geofabrik regions it was built from.
    pub regions: Vec<String>,
    /// The OSM data's date (YYYY-MM-DD), if known.
    pub data_date: Option<String>,
    /// When the index was built (UTC, RFC 3339).
    pub built_at: String,
}

/// Rows per kind in a finished index.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct Counts {
    pub addresses: u64,
    pub streets: u64,
    pub localities: u64,
    pub pois: u64,
}

impl Counts {
    fn add(&mut self, kind: Kind) {
        match kind {
            Kind::Address => self.addresses += 1,
            Kind::Street => self.streets += 1,
            Kind::Locality => self.localities += 1,
            Kind::Poi => self.pois += 1,
        }
    }
}

const SCHEMA: &str = "
CREATE TABLE meta(key TEXT PRIMARY KEY, value TEXT NOT NULL) WITHOUT ROWID;
CREATE TABLE place(
  id INTEGER PRIMARY KEY,
  kind INTEGER NOT NULL,
  name TEXT NOT NULL,
  number TEXT,
  street TEXT,
  locality TEXT,
  near INTEGER NOT NULL,
  category TEXT,
  state TEXT,
  lat REAL NOT NULL,
  lon REAL NOT NULL,
  weight REAL NOT NULL
);
CREATE VIRTUAL TABLE terms USING fts5(
  name, locality, cells,
  content = '', detail = 'column', tokenize = 'unicode61 remove_diacritics 2'
);
CREATE VIRTUAL TABLE towns USING fts5(
  name,
  content = '', detail = 'none', tokenize = 'unicode61 remove_diacritics 2'
);
CREATE VIRTUAL TABLE addrs USING fts5(
  number, street, name, locality, cells,
  content = '', detail = 'column', tokenize = 'unicode61 remove_diacritics 2'
);
";

/// Builds an index file, replacing any file at that path.
pub struct Writer {
    conn: Connection,
    next_id: i64,
    counts: Counts,
}

impl Writer {
    pub fn create(path: &Path) -> rusqlite::Result<Writer> {
        let _ = std::fs::remove_file(path);
        let conn = Connection::open(path)?;
        // Built once and then only read: no journal to pay for.
        conn.execute_batch(
            "PRAGMA journal_mode = OFF; PRAGMA synchronous = OFF; PRAGMA cache_size = -262144;",
        )?;
        conn.pragma_update(None, "application_id", APPLICATION_ID)?;
        conn.pragma_update(None, "user_version", SCHEMA_VERSION)?;
        conn.execute_batch(SCHEMA)?;
        conn.execute_batch("BEGIN")?;
        Ok(Writer {
            conn,
            next_id: 1,
            counts: Counts::default(),
        })
    }

    pub fn add(&mut self, p: &Place) -> rusqlite::Result<()> {
        let id = self.next_id;
        self.next_id += 1;
        self.conn
            .prepare_cached(
                "INSERT INTO place(id, kind, name, number, street, locality, near, category, state, lat, lon, weight)
                 VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12)",
            )?
            .execute(params![
                id,
                p.kind as i64,
                p.name,
                p.number,
                p.street,
                p.locality,
                p.locality_near,
                p.category,
                p.state.as_ref().map(|s| s.short.as_str()),
                p.lat,
                p.lon,
                p.weight
            ])?;
        let name = text::index_terms(&p.name);
        let street = p
            .street
            .as_deref()
            .map(text::index_terms)
            .unwrap_or_default();
        let mut locality = p
            .locality
            .as_deref()
            .map(text::index_terms)
            .unwrap_or_default();
        let mut town = name.clone();
        if let Some(st) = &p.state {
            let short = text::words(&st.short);
            town.extend(short.iter().cloned());
            locality.extend(short);
        }
        let cells = cell_tokens(p.lat, p.lon);
        match p.kind {
            Kind::Locality => {
                self.conn
                    .prepare_cached("INSERT INTO towns(rowid, name) VALUES (?1, ?2)")?
                    .execute(params![id, town.join(" ")])?;
            }
            Kind::Street | Kind::Poi => {
                self.conn
                    .prepare_cached(
                        "INSERT INTO terms(rowid, name, locality, cells) VALUES (?1, ?2, ?3, ?4)",
                    )?
                    .execute(params![id, name.join(" "), locality.join(" "), cells])?;
            }
            Kind::Address => {}
        }
        if let Some(number) = p.number.as_deref().and_then(text::house_number) {
            self.conn
                .prepare_cached(
                    "INSERT INTO addrs(rowid, number, street, name, locality, cells)
                     VALUES (?1, ?2, ?3, ?4, ?5, ?6)",
                )?
                .execute(params![
                    id,
                    number,
                    street.join(" "),
                    name.join(" "),
                    locality.join(" "),
                    cells
                ])?;
        }
        self.counts.add(p.kind);
        Ok(())
    }

    /// Writes `meta`, merges the full-text index and compacts the file.
    pub fn finish(self, meta: &Meta) -> rusqlite::Result<Counts> {
        let c = self.counts;
        let rows: Vec<(&str, String)> = vec![
            ("regions", meta.regions.join("\n")),
            ("data_date", meta.data_date.clone().unwrap_or_default()),
            ("built_at", meta.built_at.clone()),
            ("addresses", c.addresses.to_string()),
            ("streets", c.streets.to_string()),
            ("localities", c.localities.to_string()),
            ("pois", c.pois.to_string()),
            ("source", "© OpenStreetMap contributors, ODbL".to_string()),
        ];
        for (k, v) in rows {
            self.conn.execute(
                "INSERT INTO meta(key, value) VALUES (?1, ?2)",
                params![k, v],
            )?;
        }
        self.conn.execute_batch(
            "INSERT INTO terms(terms) VALUES ('optimize');
             INSERT INTO towns(towns) VALUES ('optimize');
             INSERT INTO addrs(addrs) VALUES ('optimize');
             COMMIT; ANALYZE; VACUUM;",
        )?;
        Ok(c)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn cells() {
        assert_eq!(cell(39.8, -98.6), "g129x81");
        assert_eq!(cell(-0.5, 179.5), "g89x359");
        assert_eq!(cell(0.0, -180.0), "g90x0");
        let around = cells_around(39.8, -98.6);
        assert_eq!(around.len(), 9);
        assert!(around.contains(&"g128x80".to_string()));
        assert!(around.contains(&"g130x82".to_string()));
        // Across the antimeridian.
        assert!(cells_around(10.0, 179.5).contains(&"g100x0".to_string()));
        assert_eq!(wide_cell(39.8, -98.6), "h25x16");
        assert_eq!(cell_tokens(39.8, -98.6), "g129x81 h25x16");
        let wide = wide_cells_around(39.8, -98.6);
        assert_eq!(wide.len(), 9);
        assert!(wide.contains(&"h24x15".to_string()) && wide.contains(&"h26x17".to_string()));
    }

    #[test]
    fn importance_orders_places() {
        let city = importance(Kind::Locality, Some("city"), None);
        let town = importance(Kind::Locality, Some("town"), None);
        let village = importance(Kind::Locality, Some("village"), None);
        assert!(city > town && town > village);
        assert!(
            importance(Kind::Locality, Some("town"), Some(50_000))
                > importance(Kind::Locality, Some("town"), Some(500))
        );
        assert_eq!(importance(Kind::Address, None, Some(100_000)), 0.0);
    }
}
