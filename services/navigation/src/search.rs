//! Address and place search (ADR-0038): the index file on the data drive,
//! opened on first use and reopened when the map stick's import swaps in a
//! new one (it renames over the old file; the open file stays readable until
//! then). A missing or unreadable index is an answer, not an error: the
//! screen says why.

use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex};
use std::time::SystemTime;

use f250_proto::nav::v1 as pb;
use geocode::search::{Hit, Index, Match};

/// Results unless the request asks for fewer or more (at most [`MAX_LIMIT`]).
pub const DEFAULT_LIMIT: usize = 8;
pub const MAX_LIMIT: usize = 20;
/// Longer queries are cut here: nobody types more on the dashboard.
pub const MAX_QUERY_CHARS: usize = 200;

/// The file's identity: a new file from the stick differs in at least one.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
struct Stamp {
    len: u64,
    modified: Option<SystemTime>,
    inode: u64,
}

fn stamp(path: &Path) -> Option<Stamp> {
    let m = std::fs::metadata(path).ok()?;
    #[cfg(unix)]
    let inode = std::os::unix::fs::MetadataExt::ino(&m);
    #[cfg(not(unix))]
    let inode = 0;
    Some(Stamp {
        len: m.len(),
        modified: m.modified().ok(),
        inode,
    })
}

enum State {
    Closed,
    Open(Stamp, Index),
    /// The file at this stamp couldn't be opened; not tried again until it
    /// changes.
    Bad(Stamp, String),
}

pub struct Searcher {
    path: PathBuf,
    state: Mutex<State>,
}

/// One search's answer, before it becomes a response.
pub struct Answer {
    pub hits: Vec<Hit>,
    pub regions: Vec<String>,
    pub data_date: Option<String>,
}

impl Searcher {
    pub fn new(path: PathBuf) -> Arc<Searcher> {
        Arc::new(Searcher {
            path,
            state: Mutex::new(State::Closed),
        })
    }

    pub fn path(&self) -> &Path {
        &self.path
    }

    /// Opens the index if it changed, then searches it. Blocking (SQLite):
    /// run it on a blocking thread.
    pub fn search(
        &self,
        query: &str,
        near: Option<(f64, f64)>,
        limit: usize,
    ) -> Result<Answer, String> {
        let mut state = self
            .state
            .lock()
            .map_err(|_| "search state poisoned".to_string())?;
        let now = stamp(&self.path);
        let current = match (&*state, now) {
            (State::Open(s, _), Some(n)) | (State::Bad(s, _), Some(n)) => *s == n,
            _ => false,
        };
        if !current {
            *state = match now {
                None => State::Closed,
                Some(n) => match Index::open(&self.path) {
                    Ok(ix) => {
                        eprintln!(
                            "[navigation] search data: {} ({}; OSM data {})",
                            self.path.display(),
                            ix.info.regions.join(", "),
                            ix.info.data_date.as_deref().unwrap_or("of unknown date")
                        );
                        State::Open(n, ix)
                    }
                    Err(why) => {
                        eprintln!("[navigation] search data unusable: {why}");
                        State::Bad(n, why)
                    }
                },
            };
        }
        match &*state {
            State::Closed => Err(format!("no search data at {}", self.path.display())),
            State::Bad(_, why) => Err(why.clone()),
            State::Open(_, ix) => {
                let hits = ix
                    .search(query, near, limit)
                    .map_err(|e| format!("search failed: {e}"))?;
                Ok(Answer {
                    hits,
                    regions: ix.info.regions.clone(),
                    data_date: ix.info.data_date.clone(),
                })
            }
        }
    }
}

/// Where to rank from: the latest fix, current or last known.
pub fn ranked_from(p: &pb::Position) -> (Option<(f64, f64)>, pb::RankedFrom, f64) {
    match &p.fix {
        Some(f) if f.latitude_deg.is_finite() && f.longitude_deg.is_finite() => (
            Some((f.latitude_deg, f.longitude_deg)),
            if p.current {
                pb::RankedFrom::Current
            } else {
                pb::RankedFrom::LastKnown
            },
            f.age_ms as f64 / 1000.0,
        ),
        _ => (None, pb::RankedFrom::None, 0.0),
    }
}

pub fn hit_to_pb(h: &Hit) -> pb::SearchResult {
    pb::SearchResult {
        kind: match h.kind {
            Match::Address => pb::MatchKind::Address,
            Match::Street => pb::MatchKind::Street,
            Match::Locality => pb::MatchKind::Locality,
            Match::Place => pb::MatchKind::Place,
        } as i32,
        title: h.title.clone(),
        subtitle: h.subtitle.clone(),
        location: Some(pb::LatLon {
            latitude_deg: h.lat,
            longitude_deg: h.lon,
        }),
        distance_m: h.distance_m,
        house_number_missing: h.house_number_missing,
        unmatched_words: h.unmatched.clone(),
    }
}

/// The query as the service searches it: at most [`MAX_QUERY_CHARS`].
pub fn clip(query: &str) -> &str {
    match query.char_indices().nth(MAX_QUERY_CHARS) {
        Some((i, _)) => &query[..i],
        None => query,
    }
}

pub fn limit(asked: u32) -> usize {
    match asked {
        0 => DEFAULT_LIMIT,
        n => (n as usize).min(MAX_LIMIT),
    }
}

#[cfg(test)]
#[allow(clippy::unwrap_used, clippy::expect_used)]
mod tests {
    use super::*;
    use geocode::index::{Kind, Meta, Place, Writer};

    fn write(path: &Path, town: &str) {
        let mut w = Writer::create(path).unwrap();
        w.add(&Place {
            kind: Kind::Locality,
            name: town.into(),
            number: None,
            street: None,
            locality: None,
            locality_near: false,
            category: Some("town".into()),
            lat: 26.0,
            lon: -90.0,
            weight: 1.8,
            state: None,
        })
        .unwrap();
        w.finish(&Meta {
            regions: vec!["Gulf test".into()],
            data_date: None,
            built_at: String::new(),
        })
        .unwrap();
    }

    #[test]
    fn opens_reopens_and_says_why_not() {
        let dir = std::env::temp_dir().join(format!("f250-nav-search-{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        let path = dir.join("search.sqlite");
        let _ = std::fs::remove_file(&path);
        let s = Searcher::new(path.clone());

        let err = s.search("fairview", None, 8).err().unwrap();
        assert!(err.contains("no search data"), "{err}");

        write(&path, "Fairview");
        let a = s.search("fairview", None, 8).unwrap();
        assert_eq!(a.hits[0].title, "Fairview");
        assert_eq!(a.regions, ["Gulf test"]);

        // The stick's import renames a new file over it.
        let next = dir.join("search.sqlite.part");
        write(&next, "Hillsdale");
        std::fs::rename(&next, &path).unwrap();
        assert!(s.search("fairview", None, 8).unwrap().hits.is_empty());
        assert_eq!(
            s.search("hillsdale", None, 8).unwrap().hits[0].title,
            "Hillsdale"
        );

        std::fs::write(
            &path,
            b"not sqlite at all, just some bytes that are long enough",
        )
        .unwrap();
        let err = s.search("x", None, 8).err().unwrap();
        assert!(
            err.contains("isn't search data") || err.contains("not a database"),
            "{err}"
        );
        std::fs::remove_file(&path).unwrap();
        assert!(
            s.search("x", None, 8)
                .err()
                .unwrap()
                .contains("no search data")
        );
    }

    #[test]
    fn limits_and_clipping() {
        assert_eq!(limit(0), DEFAULT_LIMIT);
        assert_eq!(limit(3), 3);
        assert_eq!(limit(500), MAX_LIMIT);
        assert_eq!(clip("abc"), "abc");
        let long = "é".repeat(300);
        assert_eq!(clip(&long).chars().count(), MAX_QUERY_CHARS);
    }

    #[test]
    fn ranks_from_the_latest_fix() {
        let mut p = pb::Position::default();
        assert_eq!(ranked_from(&p).1, pb::RankedFrom::None);
        p.fix = Some(pb::Fix {
            latitude_deg: 26.0,
            longitude_deg: -90.0,
            age_ms: 4500,
            ..Default::default()
        });
        let (near, from, age) = ranked_from(&p);
        assert_eq!(near, Some((26.0, -90.0)));
        assert_eq!(from, pb::RankedFrom::LastKnown);
        assert_eq!(age, 4.5);
        p.current = true;
        assert_eq!(ranked_from(&p).1, pb::RankedFrom::Current);
    }
}
