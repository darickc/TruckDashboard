//! A search against the index, ranked near the truck (ADR-0038 decision 4).
//!
//! The query "123 n main st fairview" is a house number ("123") and words.
//! The last word may be unfinished while typing, so it matches as a prefix
//! once it has three letters (two for town names, a small table), unless it
//! is a word of its own already: "st", "n", "ave" match only themselves. A
//! short prefix in 45 million rows is what makes a search slow.
//!
//! Candidates come from FTS5, every word required, one table per question:
//! - with a house number, `addrs`: that number and those words;
//! - `terms`, streets and named places: the words, at least one of the
//!   telling ones ([`Parsed::key_words`]) in the name, so "lebanon" isn't
//!   every street near Lebanon;
//! - `towns`: towns named by every word, anywhere.
//!
//! The first two go out in rings: the 1° cells around the truck, then the 5°
//! cells, then anywhere, each only while fewer than `limit` were found. No
//! ring is ordered by FTS rank: ranking is done here, on the candidates.
//!
//! When nothing has every word, a looser pass finds rows whose own name is in
//! the query ("elm st smallville" → Smallville, or Elm Street near another
//! town) and says which words they don't match.
//!
//! Then each is scored: an address with the asked house number first, a name
//! the query spells out in full, a town's size, and minus distance
//! (logarithmic: 10 km costs 1.6, 100 km 3.0, 1000 km 4.5). Without a
//! position there is no distance term.
//!
//! The search never pretends: a street found for "123 main st" is a street
//! (`house_number_missing`), a town is a town.
//!
//! A ZIP code at the end ("120 elm ave, 99001", or ZIP+4) is not a word to
//! match: OpenStreetMap streets don't carry one. It says where to look: the
//! results are ranked from the middle of that ZIP code's addresses
//! (`postcodes`) instead of from the truck. A ZIP code the data doesn't
//! have is said (`Found::postcode`, and each result's unmatched words). A
//! ZIP code alone finds its area.
//!
//! With US Census address ranges in the index (ADR-0041), a query with a
//! house number also looks for streets whose ranges hold it (`range_terms`,
//! in the same rings), and places the number along the piece of street by
//! interpolation: an `Estimated` result, ranked below a mapped address and
//! above a street without the number. A range whose ZIP code is the one the
//! query ended with is preferred. An estimate a mapped address already
//! covers (same number and street, same town) is dropped, and so is the
//! OSM street an estimate covers.

use std::path::Path;

use rusqlite::{Connection, OpenFlags, params};

use crate::index::{self, Kind, PostcodeSource};
use crate::ranges::{self, Edge, Parity, Side};
use crate::{line, text};

/// What a result is, as the screen labels it.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Match {
    /// The house number asked for, on that street.
    Address,
    /// A street; if the query had a house number, it isn't in the data.
    Street,
    /// A city, town or other named place, and nothing finer.
    Locality,
    /// A named business, park, school…
    Place,
    /// The house number asked for, placed along its street from the US
    /// Census Bureau's address ranges: an estimate, not a mapped address.
    Estimated,
}

#[derive(Clone, Debug, PartialEq)]
pub struct Hit {
    pub kind: Match,
    pub title: String,
    pub subtitle: String,
    pub lat: f64,
    pub lon: f64,
    /// Straight-line distance from the position the search was ranked from.
    pub distance_m: Option<f64>,
    /// The query had a house number and this result doesn't have it.
    pub house_number_missing: bool,
    /// Query words this result doesn't match (only from the looser pass).
    pub unmatched: Vec<String>,
    pub score: f64,
    /// Its town and state as the subtitle names them ("near Fairview, KS"),
    /// to tell the same place found twice.
    pub place: String,
}

/// What an index file covers, from its `meta` table.
#[derive(Clone, Debug, Default, PartialEq)]
pub struct Info {
    pub regions: Vec<String>,
    pub data_date: Option<String>,
    pub built_at: String,
    pub counts: index::Counts,
    /// The US Census address ranges' source ("US Census Bureau TIGER/Line
    /// 2026"); None without ranges.
    pub ranges_source: Option<String>,
}

pub struct Index {
    conn: Connection,
    pub info: Info,
}

impl std::fmt::Debug for Index {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("Index")
            .field("info", &self.info)
            .finish_non_exhaustive()
    }
}

/// Distance in the score: this much per tenfold distance in km (+1).
const DISTANCE_WEIGHT: f64 = 1.5;
/// What a search found, and what it made of a ZIP code in the query.
#[derive(Clone, Debug, PartialEq)]
pub struct Found {
    pub hits: Vec<Hit>,
    pub postcode: Option<Postcode>,
}

/// A ZIP code the query ended with.
#[derive(Clone, Debug, PartialEq)]
pub struct Postcode {
    /// Five digits.
    pub code: String,
    /// The middle of its addresses; None: not in the data (the results are
    /// ranked from the truck as usual).
    pub at: Option<(f64, f64)>,
    pub addresses: u64,
    /// Placed from OSM addresses, or from US Census address ranges.
    pub source: PostcodeSource,
}

/// The asked house number found.
const ADDRESS_BONUS: f64 = 3.0;
/// Every word of the result's own name is in the query: much for a town
/// ("fairview" means the town, not Fairview Road), a little otherwise.
const FULL_NAME_BONUS: f64 = 0.5;
const FULL_TOWN_NAME_BONUS: f64 = 2.0;
/// The looser pass: this much for all query words unmatched.
const UNMATCHED_PENALTY: f64 = 4.0;
/// The asked house number placed from US Census ranges: less than a mapped
/// address, more than a street without it.
const ESTIMATE_BONUS: f64 = 2.5;
/// An estimate from a range in the ZIP code the query ended with.
const ZIP_BONUS: f64 = 1.0;
/// Range streets whose pieces are read for one search, the nearest first.
const RANGE_STREETS: usize = 64;

/// Rows asked of each pass.
const RING_LIMIT: i64 = 2000;
const TOWNS_LIMIT: i64 = 2000;
/// The shortest prefix matched while typing, in the big tables and in towns.
const MIN_PREFIX: usize = 3;
const MIN_TOWN_PREFIX: usize = 2;

impl Index {
    /// Opens an index read-only. The file is never written while open: the
    /// stick import swaps a new one in by rename, and navigation reopens it.
    pub fn open(path: &Path) -> Result<Index, String> {
        if !path.is_file() {
            return Err(format!("no search data at {}", path.display()));
        }
        let uri = format!("file:{}?immutable=1", uri_path(path));
        let conn = Connection::open_with_flags(
            uri,
            OpenFlags::SQLITE_OPEN_READ_ONLY
                | OpenFlags::SQLITE_OPEN_URI
                | OpenFlags::SQLITE_OPEN_NO_MUTEX,
        )
        .map_err(|e| format!("{}: {e}", path.display()))?;
        let app: i32 = conn
            .pragma_query_value(None, "application_id", |r| r.get(0))
            .map_err(|e| format!("{} isn't search data: {e}", path.display()))?;
        if app != index::APPLICATION_ID {
            return Err(format!(
                "{} isn't search data (application id {app:#x})",
                path.display()
            ));
        }
        let version: i32 = conn
            .pragma_query_value(None, "user_version", |r| r.get(0))
            .map_err(|e| e.to_string())?;
        if version != index::SCHEMA_VERSION {
            return Err(format!(
                "{} is search data version {version}; this navigation reads version {} (rebuild it with make search-region)",
                path.display(),
                index::SCHEMA_VERSION
            ));
        }
        let info = read_info(&conn).map_err(|e| format!("{}: {e}", path.display()))?;
        Ok(Index { conn, info })
    }

    /// Up to `limit` results for `query`, best first, ranked from `near`.
    pub fn search(
        &self,
        query: &str,
        near: Option<(f64, f64)>,
        limit: usize,
    ) -> rusqlite::Result<Vec<Hit>> {
        Ok(self.find(query, near, limit)?.hits)
    }

    /// Where ZIP code `code` is, if the data has it.
    pub fn postcode(&self, code: &str) -> rusqlite::Result<Option<Postcode>> {
        let mut st = self
            .conn
            .prepare_cached("SELECT lat, lon, addresses, source FROM postcodes WHERE code = ?1")?;
        let mut rows = st.query(params![code])?;
        Ok(match rows.next()? {
            Some(r) => Some(Postcode {
                code: code.to_string(),
                at: Some((r.get(0)?, r.get(1)?)),
                addresses: u64::try_from(r.get::<_, i64>(2)?).unwrap_or(0),
                source: PostcodeSource::from_i64(r.get(3)?),
            }),
            None => None,
        })
    }

    /// `search`, and what was made of a ZIP code at the end of the query:
    /// the results are ranked from it when the data has it.
    pub fn find(
        &self,
        query: &str,
        near: Option<(f64, f64)>,
        limit: usize,
    ) -> rusqlite::Result<Found> {
        let q = Parsed::new(query);
        let postcode = match &q.postcode {
            Some(code) => Some(self.postcode(code)?.unwrap_or(Postcode {
                code: code.clone(),
                at: None,
                addresses: 0,
                source: PostcodeSource::Osm,
            })),
            None => None,
        };
        let near = postcode.as_ref().and_then(|p| p.at).or(near);
        if limit == 0 {
            return Ok(Found {
                hits: Vec::new(),
                postcode,
            });
        }
        if q.words.is_empty() {
            // A ZIP code alone: its area.
            let hits = match (&postcode, &q.number) {
                (
                    Some(Postcode {
                        code,
                        at: Some((lat, lon)),
                        addresses,
                        source,
                    }),
                    None,
                ) => vec![Hit {
                    kind: Match::Locality,
                    title: code.clone(),
                    subtitle: match source {
                        PostcodeSource::Osm => {
                            format!("ZIP code · the middle of its {addresses} addresses")
                        }
                        PostcodeSource::Census => format!(
                            "ZIP code · the middle of its {addresses} US Census address ranges"
                        ),
                    },
                    lat: *lat,
                    lon: *lon,
                    distance_m: None,
                    house_number_missing: false,
                    unmatched: Vec::new(),
                    score: 0.0,
                    place: String::new(),
                }],
                _ => Vec::new(),
            };
            return Ok(Found { hits, postcode });
        }
        let mut hits = self.hits(&q, near, limit)?;
        if let Some(Postcode { code, at: None, .. }) = &postcode {
            for h in &mut hits {
                h.unmatched.push(code.clone());
            }
        }
        Ok(Found { hits, postcode })
    }

    fn hits(
        &self,
        q: &Parsed,
        near: Option<(f64, f64)>,
        limit: usize,
    ) -> rusqlite::Result<Vec<Hit>> {
        let mut found: Vec<Row> = Vec::new();
        if let Some(n) = &q.number {
            let mut fts = format!(
                "number : \"{n}\" AND {}",
                q.all_words("street name locality", MIN_PREFIX)
            );
            if let Some(key) = q.key_words("street name", MIN_PREFIX) {
                fts = format!("{fts} AND {key}");
            }
            self.rings("addrs", &fts, near, limit, &mut found)?;
        }
        let mut fts = q.all_words("name locality", MIN_PREFIX);
        if let Some(key) = q.key_words("name", MIN_PREFIX) {
            fts = format!("{fts} AND {key}");
        }
        self.rings("terms", &fts, near, limit, &mut found)?;
        self.rows(
            "towns",
            &q.all_words("", MIN_TOWN_PREFIX),
            TOWNS_LIMIT,
            &mut found,
        )?;

        let mut hits: Vec<Hit> = found.iter().map(|r| score(r, q, near, false)).collect();
        if let Some(n) = q.range_number() {
            hits.extend(self.estimates(q, n, near, limit)?);
        }
        if hits.is_empty() {
            let mut rows = Vec::new();
            if let Some(loose) = q.any_word("name locality", MIN_PREFIX) {
                self.rings("terms", &loose, near, limit, &mut rows)?;
            }
            if let Some(loose) = q.any_word("", MIN_TOWN_PREFIX) {
                self.rows("towns", &loose, TOWNS_LIMIT, &mut rows)?;
            }
            hits = rows
                .iter()
                .filter(|r| r.named_by(q))
                .map(|r| score(r, q, near, true))
                .filter(|h| h.unmatched.len() < q.words.len())
                .collect();
        }
        Ok(best(hits, limit))
    }

    /// `fts` in `table`: around `near`, then wider, then anywhere, while
    /// fewer than `limit` rows were found.
    fn rings(
        &self,
        table: &str,
        fts: &str,
        near: Option<(f64, f64)>,
        limit: usize,
        out: &mut Vec<Row>,
    ) -> rusqlite::Result<()> {
        rings_of(fts, near, limit, out, |q, out| {
            self.rows(table, q, RING_LIMIT, out)
        })
    }

    /// The asked house number `n` placed on streets the query names, from
    /// the US Census address ranges (none in an index without them).
    fn estimates(
        &self,
        q: &Parsed,
        n: u32,
        near: Option<(f64, f64)>,
        limit: usize,
    ) -> rusqlite::Result<Vec<Hit>> {
        if self.info.counts.range_streets == 0 || q.words.is_empty() {
            return Ok(Vec::new());
        }
        let mut fts = q.all_words("name locality", MIN_PREFIX);
        if let Some(key) = q.key_words("name", MIN_PREFIX) {
            fts = format!("{fts} AND {key}");
        }
        let mut streets = Vec::new();
        rings_of(&fts, near, limit, &mut streets, |f, out| {
            self.range_rows(f, out)
        })?;
        if let Some(p) = near {
            streets.sort_by(|a, b| {
                crate::distance_m(p, (a.row.lat, a.row.lon))
                    .total_cmp(&crate::distance_m(p, (b.row.lat, b.row.lon)))
            });
        }
        streets.truncate(RANGE_STREETS);
        let zip = q.postcode.as_deref().and_then(|z| z.parse::<u32>().ok());
        let mut hits = Vec::new();
        for s in &streets {
            let edges = self.range_edges(s.first, s.count)?;
            let Some(((lat, lon), side_zip)) = ranges::locate(&edges, n, zip) else {
                continue;
            };
            let mut h = score(&s.row, q, near, false);
            h.kind = Match::Estimated;
            h.house_number_missing = false;
            h.title = format!("{n} {}", s.row.name);
            h.subtitle = join(&[
                h.place.clone(),
                side_zip.map(ranges::zip_text).unwrap_or_default(),
            ]);
            h.lat = lat;
            h.lon = lon;
            h.score += ESTIMATE_BONUS;
            if zip.is_some() && side_zip == zip {
                h.score += ZIP_BONUS;
            }
            if let Some(p) = near {
                // Distance to the house, not to the street's middle.
                let before = h.distance_m.unwrap_or(0.0);
                let d = crate::distance_m(p, (lat, lon));
                h.score += DISTANCE_WEIGHT
                    * ((1.0 + before / 1000.0).log10() - (1.0 + d / 1000.0).log10());
                h.distance_m = Some(d);
            }
            hits.push(h);
        }
        Ok(hits)
    }

    /// Up to [`RING_LIMIT`] range streets matching `fts`, each once.
    fn range_rows(&self, fts: &str, out: &mut Vec<RangeStreetRow>) -> rusqlite::Result<()> {
        let mut stmt = self.conn.prepare_cached(
            "SELECT r.id, r.name, r.locality, r.near, r.state, r.lat, r.lon, r.first, r.count
             FROM (SELECT rowid AS id FROM range_terms WHERE range_terms MATCH ?1 LIMIT ?2) t
             JOIN ranges r ON r.id = t.id",
        )?;
        let start = std::time::Instant::now();
        let rows = stmt.query_map(params![fts, RING_LIMIT], |r| {
            Ok(RangeStreetRow {
                row: Row {
                    id: r.get(0)?,
                    kind: Kind::Street,
                    name: r.get(1)?,
                    number: None,
                    street: None,
                    locality: r.get(2)?,
                    near: r.get(3)?,
                    category: None,
                    state: r.get(4)?,
                    lat: r.get(5)?,
                    lon: r.get(6)?,
                    weight: 0.0,
                },
                first: r.get(7)?,
                count: r.get(8)?,
            })
        })?;
        let mut n = 0;
        for row in rows {
            let row = row?;
            n += 1;
            if !out.iter().any(|o| o.row.id == row.row.id) {
                out.push(row);
            }
        }
        if std::env::var_os("F250_SEARCH_TRACE").is_some() {
            eprintln!(
                "[search] {:.1} ms, {n} rows from range_terms: {fts}",
                start.elapsed().as_secs_f64() * 1000.0
            );
        }
        Ok(())
    }

    /// A range street's pieces, rowids `first..first + count`.
    fn range_edges(&self, first: i64, count: i64) -> rusqlite::Result<Vec<Edge>> {
        let mut stmt = self.conn.prepare_cached(
            "SELECT lfrom, lto, lparity, lzip, rfrom, rto, rparity, rzip, line
             FROM range_edges WHERE id >= ?1 AND id < ?2 ORDER BY id",
        )?;
        let side = |r: &rusqlite::Row, i: usize| -> rusqlite::Result<Option<Side>> {
            let from: Option<i64> = r.get(i)?;
            let to: Option<i64> = r.get(i + 1)?;
            Ok(match (from, to) {
                (Some(from), Some(to)) => Some(Side {
                    from: u32::try_from(from).unwrap_or(0),
                    to: u32::try_from(to).unwrap_or(0),
                    parity: Parity::from_i64(r.get::<_, Option<i64>>(i + 2)?.unwrap_or(3)),
                    zip: r
                        .get::<_, Option<i64>>(i + 3)?
                        .and_then(|z| u32::try_from(z).ok()),
                }),
                _ => None,
            })
        };
        let rows = stmt.query_map(params![first, first + count], |r| {
            Ok(Edge {
                left: side(r, 0)?,
                right: side(r, 4)?,
                line: line::decode(&r.get::<_, Vec<u8>>(8)?).unwrap_or_default(),
            })
        })?;
        rows.collect()
    }

    /// Up to `limit` rows of `table` matching `fts`, each once in `out`.
    fn rows(&self, table: &str, fts: &str, limit: i64, out: &mut Vec<Row>) -> rusqlite::Result<()> {
        let sql = format!(
            "SELECT p.id, p.kind, p.name, p.number, p.street, p.locality, p.near, p.category, p.state, p.lat, p.lon, p.weight
             FROM (SELECT rowid AS id FROM {table} WHERE {table} MATCH ?1 LIMIT ?2) t
             JOIN place p ON p.id = t.id"
        );
        let start = std::time::Instant::now();
        let mut stmt = self.conn.prepare_cached(&sql)?;
        let rows = stmt.query_map(params![fts, limit], |r| {
            Ok(Row {
                id: r.get(0)?,
                kind: Kind::from_i64(r.get(1)?).unwrap_or(Kind::Poi),
                name: r.get(2)?,
                number: r.get(3)?,
                street: r.get(4)?,
                locality: r.get(5)?,
                near: r.get(6)?,
                category: r.get(7)?,
                state: r.get(8)?,
                lat: r.get(9)?,
                lon: r.get(10)?,
                weight: r.get(11)?,
            })
        })?;
        let mut n = 0;
        for row in rows {
            let row = row?;
            n += 1;
            if !out.iter().any(|o| o.id == row.id) {
                out.push(row);
            }
        }
        if std::env::var_os("F250_SEARCH_TRACE").is_some() {
            eprintln!(
                "[search] {:.1} ms, {n} rows from {table}: {fts}",
                start.elapsed().as_secs_f64() * 1000.0
            );
        }
        Ok(())
    }
}

fn read_info(conn: &Connection) -> rusqlite::Result<Info> {
    let mut stmt = conn.prepare("SELECT key, value FROM meta")?;
    let mut info = Info::default();
    let rows = stmt.query_map([], |r| Ok((r.get::<_, String>(0)?, r.get::<_, String>(1)?)))?;
    for row in rows {
        let (k, v) = row?;
        let n = || v.parse().unwrap_or(0);
        match k.as_str() {
            "regions" => {
                info.regions = v
                    .lines()
                    .filter(|l| !l.is_empty())
                    .map(str::to_string)
                    .collect()
            }
            "data_date" if !v.is_empty() => info.data_date = Some(v.clone()),
            "built_at" => info.built_at = v.clone(),
            "addresses" => info.counts.addresses = n(),
            "streets" => info.counts.streets = n(),
            "localities" => info.counts.localities = n(),
            "pois" => info.counts.pois = n(),
            "postcodes" => info.counts.postcodes = n(),
            "range_streets" => info.counts.range_streets = n(),
            "ranges" => info.counts.ranges = n(),
            "ranges_source" if !v.is_empty() => info.ranges_source = Some(v.clone()),
            _ => {}
        }
    }
    Ok(info)
}

/// `fts`, asked through `fetch`: around `near`, then wider, then anywhere,
/// while fewer than `limit` rows were found.
fn rings_of<T>(
    fts: &str,
    near: Option<(f64, f64)>,
    limit: usize,
    out: &mut Vec<T>,
    mut fetch: impl FnMut(&str, &mut Vec<T>) -> rusqlite::Result<()>,
) -> rusqlite::Result<()> {
    let before = out.len();
    if let Some((la, lo)) = near {
        for cells in [
            index::cells_around(la, lo),
            index::wide_cells_around(la, lo),
        ] {
            let c: Vec<String> = cells.iter().map(|c| format!("\"{c}\"")).collect();
            let ring = format!("({fts}) AND cells : ({})", c.join(" OR "));
            fetch(&ring, out)?;
            if out.len() - before >= limit {
                return Ok(());
            }
        }
    }
    fetch(fts, out)
}

/// A street with US Census address ranges, as the search reads it.
struct RangeStreetRow {
    row: Row,
    first: i64,
    count: i64,
}

/// A path for a SQLite URI: the characters a URI gives meaning to, escaped.
fn uri_path(path: &Path) -> String {
    let mut out = String::new();
    for c in path.to_string_lossy().chars() {
        match c {
            '%' => out.push_str("%25"),
            '?' => out.push_str("%3f"),
            '#' => out.push_str("%23"),
            c => out.push(c),
        }
    }
    out
}

fn in_columns(columns: &str, expr: &str) -> String {
    if columns.is_empty() {
        format!("({expr})")
    } else {
        format!("{{{columns}}} : ({expr})")
    }
}

/// A query, split.
#[derive(Debug, PartialEq)]
struct Parsed {
    number: Option<String>,
    /// A ZIP code the query ended with (five digits).
    postcode: Option<String>,
    words: Vec<String>,
    /// The last word may be unfinished: the query doesn't end in a space.
    typing: bool,
}

impl Parsed {
    fn new(query: &str) -> Parsed {
        let mut words = text::words(query);
        let mut postcode = None;
        // ZIP+4 ("99001-1234" splits into two words), or five digits last:
        // after other words, or alone. A first word of five digits followed
        // by words is a house number ("12345 main st").
        let n = words.len();
        let all = |w: &str, len: usize| w.len() == len && w.bytes().all(|b| b.is_ascii_digit());
        if n >= 2
            && all(&words[n - 1], 4)
            && all(&words[n - 2], 5)
            && (n > 2 || query.contains('-'))
        {
            words.pop();
            postcode = words.pop();
        } else if n >= 1 && all(&words[n - 1], 5) {
            postcode = words.pop();
        }
        let mut number = None;
        if words
            .first()
            .is_some_and(|w| text::looks_like_house_number(w))
        {
            number = Some(words.remove(0));
        }
        Parsed {
            number,
            postcode,
            words,
            typing: query.chars().last().is_some_and(char::is_alphanumeric),
        }
    }

    /// The house number as an address range can hold it: its digits
    /// ("123a" → 123).
    fn range_number(&self) -> Option<u32> {
        let n = self.number.as_deref()?;
        let digits: String = n.chars().take_while(char::is_ascii_digit).collect();
        digits.parse().ok()
    }

    /// Query word `i` as an FTS term: a prefix if it is the last word, still
    /// being typed, at least `min_prefix` long, and not a word of its own
    /// ("st", "n").
    fn term(&self, i: usize, min_prefix: usize) -> String {
        let w = &self.words[i];
        if self.is_prefix(i)
            && w.chars().count() >= min_prefix
            && text::synonyms(w).next().is_none()
        {
            format!("\"{w}\"*")
        } else {
            format!("\"{w}\"")
        }
    }

    fn is_prefix(&self, i: usize) -> bool {
        self.typing && i + 1 == self.words.len()
    }

    fn terms(&self, which: impl Iterator<Item = usize>, min_prefix: usize) -> Vec<String> {
        which.map(|i| self.term(i, min_prefix)).collect()
    }

    /// Every word, in these columns ("": any column; `towns` has one and no
    /// column filters).
    fn all_words(&self, columns: &str, min_prefix: usize) -> String {
        let t = self.terms(0..self.words.len(), min_prefix);
        in_columns(columns, &t.join(" AND "))
    }

    /// The words that tell something apart: not a street type or a direction
    /// ("st", "north"). Those are in millions of rows; "main" is not.
    fn telling(&self) -> impl Iterator<Item = usize> + '_ {
        (0..self.words.len()).filter(|&i| text::synonyms(&self.words[i]).next().is_none())
    }

    /// At least one telling word in these columns; None if there are none
    /// ("n st"), when the other words must do.
    fn key_words(&self, columns: &str, min_prefix: usize) -> Option<String> {
        let t = self.terms(self.telling(), min_prefix);
        (!t.is_empty()).then(|| in_columns(columns, &t.join(" OR ")))
    }

    /// Any telling word of two letters or more, in these columns: the looser
    /// pass. None if there is none.
    fn any_word(&self, columns: &str, min_prefix: usize) -> Option<String> {
        let t = self.terms(
            self.telling()
                .filter(|&i| self.words[i].chars().count() >= 2),
            min_prefix,
        );
        (!t.is_empty()).then(|| in_columns(columns, &t.join(" OR ")))
    }

    /// Whether query word `i` is `word` (or, the last one, starts it).
    fn matches(&self, i: usize, word: &str) -> bool {
        let q = &self.words[i];
        q == word || (self.is_prefix(i) && q.chars().count() >= 2 && word.starts_with(q.as_str()))
    }
}

#[derive(Clone, Debug)]
struct Row {
    id: i64,
    kind: Kind,
    name: String,
    number: Option<String>,
    street: Option<String>,
    locality: Option<String>,
    near: bool,
    category: Option<String>,
    state: Option<String>,
    lat: f64,
    lon: f64,
    weight: f64,
}

impl Row {
    /// The words that name this row: the place's name, or an address's
    /// street.
    fn own_words(&self) -> Vec<String> {
        if self.name.is_empty() {
            self.street.as_deref().map(text::words).unwrap_or_default()
        } else {
            text::words(&self.name)
        }
    }

    /// Every one of its own words (or another form of it) is in the query.
    fn named_by(&self, q: &Parsed) -> bool {
        let own = self.own_words();
        !own.is_empty()
            && own.iter().all(|w| {
                (0..q.words.len())
                    .any(|i| q.matches(i, w) || text::synonyms(w).any(|s| q.matches(i, s)))
            })
    }

    /// The query words none of its words (or their other forms) match.
    fn unmatched(&self, q: &Parsed) -> Vec<String> {
        let mut all = Vec::new();
        for t in [
            Some(&self.name),
            self.street.as_ref(),
            self.locality.as_ref(),
            self.state.as_ref(),
        ]
        .into_iter()
        .flatten()
        {
            all.extend(text::index_terms(t));
        }
        (0..q.words.len())
            .filter(|&i| !all.iter().any(|w| q.matches(i, w)))
            .map(|i| q.words[i].clone())
            .collect()
    }

    /// "near Fairview, KS", "Fairview, KS", "KS" or "".
    fn place(&self) -> String {
        let town = match (&self.locality, &self.state) {
            (Some(l), Some(s)) => format!("{l}, {s}"),
            (Some(l), None) => l.clone(),
            (None, Some(s)) => return s.clone(),
            (None, None) => return String::new(),
        };
        if self.near {
            format!("near {town}")
        } else {
            town
        }
    }

    fn address(&self) -> Option<String> {
        match (&self.number, &self.street) {
            (Some(n), Some(s)) => Some(format!("{n} {s}")),
            _ => None,
        }
    }
}

/// "fast_food" → "Fast food".
pub fn pretty(tag: &str) -> String {
    let s = tag.replace('_', " ");
    let mut c = s.chars();
    match c.next() {
        Some(f) => f.to_uppercase().chain(c).collect(),
        None => s,
    }
}

fn score(r: &Row, q: &Parsed, near: Option<(f64, f64)>, loose: bool) -> Hit {
    let has_number = q.number.is_some();
    let number_found = has_number
        && r.number.as_deref().and_then(text::house_number).as_deref() == q.number.as_deref();
    let kind = if number_found {
        Match::Address
    } else {
        match r.kind {
            Kind::Address | Kind::Street => Match::Street,
            Kind::Locality => Match::Locality,
            Kind::Poi => Match::Place,
        }
    };
    let unmatched = if loose { r.unmatched(q) } else { Vec::new() };
    let mut s = r.weight;
    if number_found {
        s += ADDRESS_BONUS;
    }
    if r.named_by(q) {
        s += if r.kind == Kind::Locality {
            FULL_TOWN_NAME_BONUS
        } else {
            FULL_NAME_BONUS
        };
    }
    s -= UNMATCHED_PENALTY * unmatched.len() as f64 / q.words.len().max(1) as f64;
    let distance_m = near.map(|p| crate::distance_m(p, (r.lat, r.lon)));
    if let Some(d) = distance_m {
        s -= DISTANCE_WEIGHT * (1.0 + d / 1000.0).log10();
    }

    let place = r.place();
    let (title, subtitle) = match kind {
        Match::Estimated => (String::new(), place.clone()),
        Match::Address if r.kind == Kind::Poi => (
            r.name.clone(),
            join(&[r.address().unwrap_or_default(), place.clone()]),
        ),
        Match::Address => (r.address().unwrap_or_default(), place.clone()),
        Match::Street => (
            r.street
                .clone()
                .filter(|_| r.name.is_empty())
                .unwrap_or_else(|| r.name.clone()),
            place.clone(),
        ),
        Match::Locality => (
            r.name.clone(),
            join(&[
                r.category
                    .as_deref()
                    .map(pretty)
                    .unwrap_or_else(|| "Place".to_string()),
                r.state.clone().unwrap_or_default(),
            ]),
        ),
        Match::Place => (
            r.name.clone(),
            join(&[
                r.category.as_deref().map(pretty).unwrap_or_default(),
                r.address()
                    .map_or(place.clone(), |a| join(&[a, place.clone()])),
            ]),
        ),
    };
    Hit {
        kind,
        title,
        subtitle,
        lat: r.lat,
        lon: r.lon,
        distance_m,
        house_number_missing: has_number && !number_found,
        unmatched,
        score: s,
        place,
    }
}

fn join(parts: &[String]) -> String {
    parts
        .iter()
        .filter(|p| !p.is_empty())
        .cloned()
        .collect::<Vec<_>>()
        .join(" · ")
}

/// Best first (a stable sort: ties keep the index's order), each place once (the same title and subtitle within 1 km is
/// the same place, found twice), at most `limit`.
fn best(mut hits: Vec<Hit>, limit: usize) -> Vec<Hit> {
    hits.sort_by(|a, b| b.score.total_cmp(&a.score));
    let mut out: Vec<Hit> = Vec::new();
    for h in hits {
        let dup = out.iter().any(|o| {
            o.title.eq_ignore_ascii_case(&h.title)
                && o.subtitle.eq_ignore_ascii_case(&h.subtitle)
                && crate::distance_m((o.lat, o.lon), (h.lat, h.lon)) < 1000.0
        });
        // A street the query named with a house number, where that number was
        // found or estimated: the address says it all. An estimate where a
        // mapped address has the same number and street: the address.
        let same_place =
            |o: &Hit| o.place.trim_start_matches("near ") == h.place.trim_start_matches("near ");
        let covered = match h.kind {
            Match::Street => out.iter().any(|o| {
                matches!(o.kind, Match::Address | Match::Estimated)
                    && same_place(o)
                    && text::ends_with_street(&o.title, &h.title)
            }),
            Match::Estimated => out.iter().any(|o| {
                o.kind == Match::Address
                    && same_place(o)
                    && text::ends_with_street(&o.title, &h.title)
                    && text::ends_with_street(&h.title, &o.title)
            }),
            _ => false,
        };
        if !dup && !covered {
            out.push(h);
        }
        if out.len() == limit {
            break;
        }
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parse_number_words_and_prefix() {
        let q = Parsed::new("123 N Main Stre");
        assert_eq!(q.number.as_deref(), Some("123"));
        assert_eq!(q.words, ["n", "main", "stre"]);
        assert!(q.typing);
        assert_eq!(
            q.all_words("name locality", 3),
            "{name locality} : (\"n\" AND \"main\" AND \"stre\"*)"
        );
        // "n" is a direction: not telling.
        assert_eq!(
            q.key_words("name", 3).as_deref(),
            Some("{name} : (\"main\" OR \"stre\"*)")
        );

        // "st" is a word of its own: never a prefix.
        let q = Parsed::new("main st");
        assert_eq!(q.all_words("name", 3), "{name} : (\"main\" AND \"st\")");
        assert_eq!(
            q.key_words("name", 3).as_deref(),
            Some("{name} : (\"main\")")
        );

        // A space ends the word.
        let q = Parsed::new("3rd street ");
        assert_eq!(q.number, None);
        assert!(!q.typing);
        assert_eq!(q.all_words("name", 3), "{name} : (\"3rd\" AND \"street\")");

        // Two letters: a prefix for towns only.
        let q = Parsed::new("sa");
        assert_eq!(q.all_words("name", 3), "{name} : (\"sa\")");
        assert_eq!(q.all_words("", 2), "(\"sa\"*)");

        let q = Parsed::new("n st");
        assert_eq!(q.key_words("name", 3), None);
        assert_eq!(q.any_word("name", 3), None);

        let q = Parsed::new("main s");
        assert_eq!(
            q.any_word("name locality", 3).as_deref(),
            Some("{name locality} : (\"main\")")
        );

        let q = Parsed::new("123");
        assert_eq!(q.number.as_deref(), Some("123"));
        assert!(q.words.is_empty());
    }

    #[test]
    fn a_zip_code_at_the_end_is_not_a_word() {
        let q = Parsed::new("120 elm ave, 99001");
        assert_eq!(q.number.as_deref(), Some("120"));
        assert_eq!(q.postcode.as_deref(), Some("99001"));
        assert_eq!(q.words, ["elm", "ave"]);
        let q = Parsed::new("elm ave 99001-1234");
        assert_eq!(q.postcode.as_deref(), Some("99001"));
        assert_eq!(q.words, ["elm", "ave"]);
        let q = Parsed::new("99001");
        assert_eq!(
            (q.postcode.as_deref(), q.number, q.words.len()),
            (Some("99001"), None, 0)
        );
        // Five digits first, then words: a house number.
        let q = Parsed::new("12345 main st");
        assert_eq!((q.number.as_deref(), q.postcode), (Some("12345"), None));
        // Other numbers stay words.
        assert_eq!(Parsed::new("county road 12").postcode, None);
        assert_eq!(Parsed::new("county road 1234").postcode, None);
    }

    #[test]
    fn pretty_tags() {
        assert_eq!(pretty("fast_food"), "Fast food");
        assert_eq!(pretty("town"), "Town");
        assert_eq!(pretty(""), "");
    }

    #[test]
    fn uri_paths_escape() {
        assert_eq!(
            uri_path(Path::new("/a/b%c?d#e.sqlite")),
            "/a/b%25c%3fd%23e.sqlite"
        );
    }
}
