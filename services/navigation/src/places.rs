//! Saved places (ADR-0040): Home, favourites with a name, and the recent
//! destinations, in one JSON file on the data drive.
//!
//! - **Atomic:** every change is written to a temporary file in the same
//!   directory, flushed to disk, renamed over the old one, and the directory
//!   flushed. A power cut leaves the old file or the new one, never half.
//! - **Never fatal:** an unreadable file is renamed aside (`places.json.bad`)
//!   and reported, and an empty list starts. A file from a newer version is
//!   left alone and the places are read-only. Places that don't make sense
//!   (a latitude of 200) are dropped and counted.
//! - **Bounded:** at most [`MAX_FAVOURITES`] favourites (more are refused),
//!   [`MAX_RECENTS`] recents (the oldest drops), names of [`MAX_NAME_CHARS`].
//!
//! The Pi has no clock in the truck, so nothing here is timestamped: recents
//! are kept in order, newest first.

use std::io::Write;
use std::path::{Path, PathBuf};

use f250_proto::nav::v1 as pb;
use serde_json::{Value, json};

use crate::valhalla::{LatLon, distance_m};

/// Limits. Not safety thresholds: sizes for an 800×480 list.
pub const MAX_FAVOURITES: usize = 50;
pub const MAX_RECENTS: usize = 10;
pub const MAX_NAME_CHARS: usize = 40;
pub const MAX_DETAIL_CHARS: usize = 80;

/// A new recent destination this close to an older one replaces it (moves
/// it to the top) rather than adding a second.
pub const SAME_PLACE_M: f64 = 50.0;

/// What the file says it is.
const FORMAT: &str = "f250-places";
const VERSION: u64 = 1;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Kind {
    Home,
    Favourite,
    Recent,
}

impl Kind {
    fn key(self) -> &'static str {
        match self {
            Kind::Home => "home",
            Kind::Favourite => "favourite",
            Kind::Recent => "recent",
        }
    }
}

#[derive(Debug, Clone, PartialEq)]
pub struct Place {
    pub id: u64,
    pub kind: Kind,
    pub name: String,
    pub detail: String,
    pub at: LatLon,
}

/// Where the file is kept, as the screen says it.
#[derive(Debug, Clone, PartialEq)]
pub struct Location {
    pub file: PathBuf,
    /// "the data drive", "the SD card: the data drive isn't mounted".
    pub described: String,
}

/// Picks the file: on the data drive when one is expected and mounted;
/// otherwise the fallback on the SD card, saying why. `drive` is None when
/// the head unit has no data drive configured (DATA_DRIVE=0).
pub fn choose_location(
    on_drive: &Path,
    drive: Option<&Path>,
    fallback: &Path,
    mounted: impl Fn(&Path) -> bool,
) -> Location {
    match drive {
        Some(d) if mounted(d) => Location {
            file: on_drive.to_path_buf(),
            described: "the data drive".to_string(),
        },
        Some(_) => Location {
            file: fallback.to_path_buf(),
            described: "the SD card: the data drive isn't mounted, so places saved now stay there"
                .to_string(),
        },
        None => Location {
            file: on_drive.to_path_buf(),
            described: "this head unit".to_string(),
        },
    }
}

/// Whether `dir` is a mount point: a different device from its parent.
pub fn is_mount_point(dir: &Path) -> bool {
    use std::os::unix::fs::MetadataExt;
    let Ok(here) = std::fs::metadata(dir) else {
        return false;
    };
    let parent = dir.parent().unwrap_or(Path::new("/"));
    match std::fs::metadata(parent) {
        Ok(up) => here.dev() != up.dev() || here.ino() == up.ino(),
        Err(_) => false,
    }
}

/// Why a change was refused.
#[derive(Debug, Clone, PartialEq)]
pub enum Refused {
    /// The request itself is wrong (no name, too long, bad coordinates).
    Invalid(String),
    NotFound(u64),
    /// Too many favourites, or the store is read-only.
    Full(String),
    /// The file couldn't be written; nothing changed.
    Write(String),
}

impl std::fmt::Display for Refused {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Refused::Invalid(s) | Refused::Full(s) | Refused::Write(s) => f.write_str(s),
            Refused::NotFound(id) => write!(f, "no saved place {id}"),
        }
    }
}

#[derive(Debug)]
pub struct Places {
    location: Location,
    home: Option<Place>,
    favourites: Vec<Place>,
    recents: Vec<Place>,
    next_id: u64,
    writable: bool,
    /// What went wrong reading or writing, for the screen.
    problem: String,
}

impl Places {
    /// Reads the file at `location`, or starts empty. Never fails: what went
    /// wrong is kept in [`Places::problem`].
    pub fn open(location: Location) -> Self {
        let mut p = Places {
            location,
            home: None,
            favourites: Vec::new(),
            recents: Vec::new(),
            next_id: 1,
            writable: true,
            problem: String::new(),
        };
        let file = p.location.file.clone();
        let text = match std::fs::read(&file) {
            Ok(bytes) => bytes,
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => return p,
            Err(e) => {
                p.writable = false;
                p.problem = format!("Saved places can't be read ({e}); not changing them");
                return p;
            }
        };
        match parse(&text) {
            Ok(Parsed::Current(f)) => {
                p.home = f.home;
                p.favourites = f.favourites;
                p.recents = f.recents;
                p.next_id = f.next_id;
                if f.dropped > 0 {
                    p.problem = format!(
                        "{} saved place{} couldn't be read and {} left out",
                        f.dropped,
                        if f.dropped == 1 { "" } else { "s" },
                        if f.dropped == 1 { "was" } else { "were" }
                    );
                }
            }
            Ok(Parsed::Newer(v)) => {
                p.writable = false;
                p.problem = format!(
                    "The saved places file is version {v}, newer than this software reads; \
                     left unchanged (read-only)"
                );
            }
            Err(why) => {
                let aside = bad_path(&file);
                match std::fs::rename(&file, &aside) {
                    Ok(()) => {
                        p.problem = format!(
                            "The saved places file was unreadable ({why}); it was kept as {} \
                             and a new list started",
                            aside.display()
                        );
                    }
                    Err(e) => {
                        p.writable = false;
                        p.problem = format!(
                            "The saved places file is unreadable ({why}) and couldn't be moved \
                             aside ({e}); not changing it"
                        );
                    }
                }
            }
        }
        p
    }

    pub fn location(&self) -> &Location {
        &self.location
    }

    pub fn problem(&self) -> &str {
        &self.problem
    }

    pub fn home(&self) -> Option<&Place> {
        self.home.as_ref()
    }

    pub fn favourites(&self) -> &[Place] {
        &self.favourites
    }

    pub fn recents(&self) -> &[Place] {
        &self.recents
    }

    /// Saves Home (replacing any) or a favourite.
    pub fn save(
        &mut self,
        kind: Kind,
        name: &str,
        detail: &str,
        at: LatLon,
    ) -> Result<u64, Refused> {
        check_at(at)?;
        let detail = clip(detail, MAX_DETAIL_CHARS);
        let name = name.trim();
        if name.chars().count() > MAX_NAME_CHARS {
            return Err(Refused::Invalid(format!(
                "a name is at most {MAX_NAME_CHARS} characters"
            )));
        }
        self.change(|p| {
            let id = p.next_id;
            match kind {
                Kind::Home => {
                    p.home = Some(Place {
                        id,
                        kind,
                        name: if name.is_empty() { "Home" } else { name }.to_string(),
                        detail,
                        at,
                    });
                }
                Kind::Favourite => {
                    if name.is_empty() {
                        return Err(Refused::Invalid("a favourite needs a name".to_string()));
                    }
                    if p.favourites.len() >= MAX_FAVOURITES {
                        return Err(Refused::Full(format!(
                            "{MAX_FAVOURITES} favourites already: delete one first"
                        )));
                    }
                    p.favourites.push(Place {
                        id,
                        kind,
                        name: name.to_string(),
                        detail,
                        at,
                    });
                }
                Kind::Recent => {
                    return Err(Refused::Invalid(
                        "recent destinations are added by routing to them".to_string(),
                    ));
                }
            }
            p.next_id += 1;
            Ok(id)
        })
    }

    /// A destination routed to: newest first, one entry per place, the
    /// oldest dropped past [`MAX_RECENTS`].
    pub fn add_recent(&mut self, name: &str, detail: &str, at: LatLon) -> Result<u64, Refused> {
        check_at(at)?;
        let name = clip(name, MAX_NAME_CHARS);
        let detail = clip(detail, MAX_DETAIL_CHARS);
        self.change(|p| {
            let old = p
                .recents
                .iter()
                .position(|r| distance_m(r.at, at) <= SAME_PLACE_M);
            let place = match old {
                Some(i) => {
                    let mut r = p.recents.remove(i);
                    if !name.is_empty() {
                        r.name = name.clone();
                        r.detail = detail.clone();
                    }
                    r.at = at;
                    r
                }
                None => {
                    let id = p.next_id;
                    p.next_id += 1;
                    Place {
                        id,
                        kind: Kind::Recent,
                        name: name.clone(),
                        detail: detail.clone(),
                        at,
                    }
                }
            };
            let id = place.id;
            p.recents.insert(0, place);
            p.recents.truncate(MAX_RECENTS);
            Ok(id)
        })
    }

    pub fn rename(&mut self, id: u64, name: &str) -> Result<(), Refused> {
        let name = name.trim().to_string();
        if name.is_empty() {
            return Err(Refused::Invalid("a name is required".to_string()));
        }
        if name.chars().count() > MAX_NAME_CHARS {
            return Err(Refused::Invalid(format!(
                "a name is at most {MAX_NAME_CHARS} characters"
            )));
        }
        self.change(|p| {
            let place = p
                .home
                .iter_mut()
                .chain(p.favourites.iter_mut())
                .chain(p.recents.iter_mut())
                .find(|x| x.id == id)
                .ok_or(Refused::NotFound(id))?;
            place.name = name.clone();
            Ok(())
        })
    }

    pub fn delete(&mut self, id: u64) -> Result<(), Refused> {
        self.change(|p| {
            if p.home.as_ref().is_some_and(|h| h.id == id) {
                p.home = None;
                return Ok(());
            }
            for list in [&mut p.favourites, &mut p.recents] {
                if let Some(i) = list.iter().position(|x| x.id == id) {
                    list.remove(i);
                    return Ok(());
                }
            }
            Err(Refused::NotFound(id))
        })
    }

    /// Applies `f`, writes the file, and keeps the change only if it was
    /// written: on a failed write nothing changes.
    fn change<T>(
        &mut self,
        f: impl FnOnce(&mut Places) -> Result<T, Refused>,
    ) -> Result<T, Refused> {
        if !self.writable {
            return Err(Refused::Full(format!(
                "saved places are read-only: {}",
                self.problem
            )));
        }
        let before = (
            self.home.clone(),
            self.favourites.clone(),
            self.recents.clone(),
            self.next_id,
        );
        let out = f(self)?;
        if let Err(e) = write_atomic(&self.location.file, self.to_json().as_bytes()) {
            (self.home, self.favourites, self.recents, self.next_id) = before;
            let why = format!("couldn't save to {}: {e}", self.location.file.display());
            self.problem = format!("Saved places: {why}");
            return Err(Refused::Write(why));
        }
        // A write that worked clears an old write failure, but not a note
        // about how the file was found.
        if self.problem.starts_with("Saved places: couldn't save") {
            self.problem.clear();
        }
        Ok(out)
    }

    fn to_json(&self) -> String {
        let place = |p: &Place| {
            json!({
                "id": p.id,
                "kind": p.kind.key(),
                "name": p.name,
                "detail": p.detail,
                "lat": p.at.0,
                "lon": p.at.1,
            })
        };
        let v = json!({
            "format": FORMAT,
            "version": VERSION,
            "next_id": self.next_id,
            "home": self.home.as_ref().map(place),
            "favourites": self.favourites.iter().map(place).collect::<Vec<_>>(),
            "recents": self.recents.iter().map(place).collect::<Vec<_>>(),
        });
        // Pretty, so the owner can read it on the drive.
        serde_json::to_string_pretty(&v).unwrap_or_default() + "\n"
    }

    pub fn to_pb(&self) -> pb::Places {
        let place = |p: &Place| pb::Place {
            id: p.id,
            kind: match p.kind {
                Kind::Home => pb::PlaceKind::Home,
                Kind::Favourite => pb::PlaceKind::Favourite,
                Kind::Recent => pb::PlaceKind::Recent,
            } as i32,
            name: p.name.clone(),
            detail: p.detail.clone(),
            location: Some(pb::LatLon {
                latitude_deg: p.at.0,
                longitude_deg: p.at.1,
            }),
        };
        pb::Places {
            home: self.home.as_ref().map(place),
            favourites: self.favourites.iter().map(place).collect(),
            recents: self.recents.iter().map(place).collect(),
            storage: Some(pb::PlacesStorage {
                writable: self.writable,
                location: self.location.described.clone(),
                problem: self.problem.clone(),
            }),
            max_favourites: MAX_FAVOURITES as u32,
            max_recents: MAX_RECENTS as u32,
            max_name_chars: MAX_NAME_CHARS as u32,
        }
    }
}

fn check_at(at: LatLon) -> Result<(), Refused> {
    if at.0.is_finite()
        && at.1.is_finite()
        && (-90.0..=90.0).contains(&at.0)
        && (-180.0..=180.0).contains(&at.1)
    {
        Ok(())
    } else {
        Err(Refused::Invalid(
            "a location in degrees is required".to_string(),
        ))
    }
}

/// At most `max` characters, trimmed.
fn clip(s: &str, max: usize) -> String {
    s.trim()
        .chars()
        .take(max)
        .collect::<String>()
        .trim_end()
        .to_string()
}

fn bad_path(file: &Path) -> PathBuf {
    let mut s = file.as_os_str().to_owned();
    s.push(".bad");
    PathBuf::from(s)
}

struct FileContents {
    home: Option<Place>,
    favourites: Vec<Place>,
    recents: Vec<Place>,
    next_id: u64,
    dropped: usize,
}

enum Parsed {
    Current(FileContents),
    /// A version this software doesn't know.
    Newer(u64),
}

fn parse(bytes: &[u8]) -> Result<Parsed, String> {
    let v: Value = serde_json::from_slice(bytes).map_err(|e| format!("not JSON: {e}"))?;
    if v.get("format").and_then(Value::as_str) != Some(FORMAT) {
        return Err("not a saved places file".to_string());
    }
    let version = v
        .get("version")
        .and_then(Value::as_u64)
        .ok_or("no version")?;
    if version > VERSION {
        return Ok(Parsed::Newer(version));
    }
    if version != VERSION {
        return Err(format!("version {version}"));
    }
    let mut dropped = 0;
    let mut max_id = 0;
    let mut read = |p: &Value, kind: Kind, dropped: &mut usize| -> Option<Place> {
        let place = (|| {
            let id = p.get("id")?.as_u64()?;
            let at = (p.get("lat")?.as_f64()?, p.get("lon")?.as_f64()?);
            check_at(at).ok()?;
            let name = p.get("name")?.as_str()?.to_string();
            if kind == Kind::Favourite && name.trim().is_empty() {
                return None;
            }
            Some(Place {
                id,
                kind,
                name: clip(&name, MAX_NAME_CHARS),
                detail: clip(
                    p.get("detail").and_then(Value::as_str).unwrap_or(""),
                    MAX_DETAIL_CHARS,
                ),
                at,
            })
        })();
        match &place {
            Some(pl) => max_id = max_id.max(pl.id),
            None => *dropped += 1,
        }
        place
    };
    let list = |key: &str| -> Result<Vec<Value>, String> {
        match v.get(key) {
            None | Some(Value::Null) => Ok(Vec::new()),
            Some(Value::Array(a)) => Ok(a.clone()),
            Some(_) => Err(format!("{key} isn't a list")),
        }
    };
    let home = match v.get("home") {
        None | Some(Value::Null) => None,
        Some(h) => read(h, Kind::Home, &mut dropped),
    };
    let favourites_in = list("favourites")?;
    let recents_in = list("recents")?;
    let mut favourites: Vec<Place> = favourites_in
        .iter()
        .filter_map(|p| read(p, Kind::Favourite, &mut dropped))
        .collect();
    let mut recents: Vec<Place> = recents_in
        .iter()
        .filter_map(|p| read(p, Kind::Recent, &mut dropped))
        .collect();
    // Bounds and unique ids hold whatever the file says.
    let mut seen = std::collections::HashSet::new();
    if let Some(h) = &home {
        seen.insert(h.id);
    }
    let before = favourites.len() + recents.len();
    favourites.retain(|p| seen.insert(p.id));
    recents.retain(|p| seen.insert(p.id));
    dropped += before - favourites.len() - recents.len();
    if favourites.len() > MAX_FAVOURITES {
        dropped += favourites.len() - MAX_FAVOURITES;
        favourites.truncate(MAX_FAVOURITES);
    }
    recents.truncate(MAX_RECENTS);
    let next_id = v
        .get("next_id")
        .and_then(Value::as_u64)
        .unwrap_or(0)
        .max(max_id + 1);
    Ok(Parsed::Current(FileContents {
        home,
        favourites,
        recents,
        next_id,
        dropped,
    }))
}

/// Writes `bytes` to `path` so a crash or power cut leaves the old file or
/// the new one: a temporary file in the same directory, flushed, renamed
/// over `path`, then the directory flushed so the rename itself lasts.
pub fn write_atomic(path: &Path, bytes: &[u8]) -> std::io::Result<()> {
    let dir = path
        .parent()
        .filter(|d| !d.as_os_str().is_empty())
        .unwrap_or(Path::new("."));
    std::fs::create_dir_all(dir)?;
    let mut tmp_name = path
        .file_name()
        .ok_or_else(|| std::io::Error::other("no file name"))?
        .to_owned();
    tmp_name.push(format!(".tmp-{}", std::process::id()));
    let tmp = dir.join(tmp_name);
    let result = (|| {
        let mut f = std::fs::File::create(&tmp)?;
        f.write_all(bytes)?;
        f.sync_all()?;
        drop(f);
        std::fs::rename(&tmp, path)?;
        std::fs::File::open(dir)?.sync_all()
    })();
    if result.is_err() {
        let _ = std::fs::remove_file(&tmp);
    }
    result
}

#[cfg(test)]
#[allow(clippy::unwrap_used, clippy::expect_used)]
mod tests {
    use super::*;

    struct Dir(PathBuf);
    impl Drop for Dir {
        fn drop(&mut self) {
            let _ = std::fs::remove_dir_all(&self.0);
        }
    }

    fn dir(name: &str) -> Dir {
        let d = std::env::temp_dir().join(format!(
            "f250-places-{name}-{}-{:?}",
            std::process::id(),
            std::thread::current().id()
        ));
        let _ = std::fs::remove_dir_all(&d);
        std::fs::create_dir_all(&d).unwrap();
        Dir(d)
    }

    fn at(d: &Dir) -> Location {
        Location {
            file: d.0.join("navigation/places.json"),
            described: "a test directory".to_string(),
        }
    }

    const FAIRVIEW: LatLon = (39.84, -98.54);

    #[test]
    fn empty_without_a_file() {
        let d = dir("empty");
        let p = Places::open(at(&d));
        assert!(p.home().is_none() && p.favourites().is_empty() && p.recents().is_empty());
        assert_eq!(p.problem(), "");
        assert!(p.to_pb().storage.unwrap().writable);
        assert!(!at(&d).file.exists(), "nothing written until a change");
    }

    #[test]
    fn survives_a_restart() {
        let d = dir("restart");
        let mut p = Places::open(at(&d));
        let home = p.save(Kind::Home, "", "Fairview", FAIRVIEW).unwrap();
        let feed = p
            .save(Kind::Favourite, "Feed store", "Hiawatha", (39.85, -95.53))
            .unwrap();
        p.add_recent("Casey's", "Fairview", (39.83, -98.53))
            .unwrap();
        p.rename(feed, "Co-op").unwrap();
        drop(p);
        let p = Places::open(at(&d));
        assert_eq!(p.problem(), "");
        let h = p.home().unwrap();
        assert_eq!(
            (h.id, h.name.as_str(), h.detail.as_str()),
            (home, "Home", "Fairview")
        );
        assert_eq!(p.favourites()[0].name, "Co-op");
        assert_eq!(p.recents()[0].name, "Casey's");
        // Ids keep counting after a restart.
        let mut p = p;
        let next = p.save(Kind::Favourite, "Gas", "", (39.0, -98.0)).unwrap();
        assert!(next > feed);
        // The file is readable JSON, with no temporary file left behind.
        let names: Vec<_> = std::fs::read_dir(d.0.join("navigation"))
            .unwrap()
            .map(|e| e.unwrap().file_name().into_string().unwrap())
            .collect();
        assert_eq!(names, ["places.json"]);
    }

    #[test]
    fn home_is_replaced_not_added() {
        let d = dir("home");
        let mut p = Places::open(at(&d));
        p.save(Kind::Home, "", "", FAIRVIEW).unwrap();
        let second = p.save(Kind::Home, "Ranch", "", (39.0, -97.0)).unwrap();
        let h = p.home().unwrap();
        assert_eq!(
            (h.id, h.name.as_str(), h.at),
            (second, "Ranch", (39.0, -97.0))
        );
        p.delete(second).unwrap();
        assert!(p.home().is_none());
    }

    #[test]
    fn refuses_what_doesnt_make_sense() {
        let d = dir("refuse");
        let mut p = Places::open(at(&d));
        assert!(matches!(
            p.save(Kind::Favourite, "  ", "", FAIRVIEW),
            Err(Refused::Invalid(_))
        ));
        assert!(matches!(
            p.save(
                Kind::Favourite,
                &"x".repeat(MAX_NAME_CHARS + 1),
                "",
                FAIRVIEW
            ),
            Err(Refused::Invalid(_))
        ));
        assert!(
            p.save(Kind::Favourite, &"x".repeat(MAX_NAME_CHARS), "", FAIRVIEW)
                .is_ok()
        );
        assert!(matches!(
            p.save(Kind::Favourite, "x", "", (91.0, 0.0)),
            Err(Refused::Invalid(_))
        ));
        assert!(matches!(
            p.save(Kind::Favourite, "x", "", (f64::NAN, 0.0)),
            Err(Refused::Invalid(_))
        ));
        assert!(matches!(
            p.save(Kind::Recent, "x", "", FAIRVIEW),
            Err(Refused::Invalid(_))
        ));
        assert_eq!(p.rename(999, "x"), Err(Refused::NotFound(999)));
        assert_eq!(p.delete(999), Err(Refused::NotFound(999)));
        assert!(matches!(
            p.rename(p.favourites()[0].id, ""),
            Err(Refused::Invalid(_))
        ));
        // A long detail is clipped, not refused.
        let id = p
            .save(Kind::Favourite, "y", &"d".repeat(200), FAIRVIEW)
            .unwrap();
        let y = p.favourites().iter().find(|f| f.id == id).unwrap();
        assert_eq!(y.detail.chars().count(), MAX_DETAIL_CHARS);
    }

    #[test]
    fn favourites_are_limited() {
        let d = dir("limit");
        let mut p = Places::open(at(&d));
        for i in 0..MAX_FAVOURITES {
            p.save(
                Kind::Favourite,
                &format!("F{i}"),
                "",
                (39.0, -98.0 + i as f64 * 0.01),
            )
            .unwrap();
        }
        let err = p
            .save(Kind::Favourite, "one more", "", FAIRVIEW)
            .unwrap_err();
        assert!(matches!(err, Refused::Full(_)), "{err:?}");
        assert!(err.to_string().contains("delete one first"));
        p.delete(p.favourites()[3].id).unwrap();
        assert!(p.save(Kind::Favourite, "one more", "", FAIRVIEW).is_ok());
    }

    #[test]
    fn recents_are_bounded_newest_first_and_merged() {
        let d = dir("recents");
        let mut p = Places::open(at(&d));
        for i in 0..MAX_RECENTS + 3 {
            p.add_recent(&format!("R{i}"), "", (39.0 + i as f64 * 0.01, -98.0))
                .unwrap();
        }
        assert_eq!(p.recents().len(), MAX_RECENTS);
        assert_eq!(p.recents()[0].name, format!("R{}", MAX_RECENTS + 2));
        assert_eq!(p.recents().last().unwrap().name, "R3", "the oldest dropped");
        // The same place again (within 50 m) moves to the top, keeping its id.
        let r5 = p.recents().iter().find(|r| r.name == "R5").unwrap().clone();
        let again = p.add_recent("", "", (r5.at.0 + 0.0002, r5.at.1)).unwrap();
        assert_eq!(again, r5.id);
        assert_eq!(p.recents()[0].name, "R5", "an unnamed visit keeps the name");
        assert_eq!(p.recents().len(), MAX_RECENTS);
        // A recent can be renamed and deleted like any place.
        p.rename(r5.id, "Grain elevator").unwrap();
        p.delete(r5.id).unwrap();
        assert!(p.recents().iter().all(|r| r.id != r5.id));
    }

    #[test]
    fn a_corrupt_file_is_kept_aside_and_reported() {
        let d = dir("corrupt");
        let loc = at(&d);
        std::fs::create_dir_all(loc.file.parent().unwrap()).unwrap();
        std::fs::write(
            &loc.file,
            b"{\"format\": \"f250-places\", \"version\": 1, \"home\": {",
        )
        .unwrap();
        let mut p = Places::open(loc.clone());
        assert!(p.problem().contains("unreadable"), "{}", p.problem());
        assert!(p.problem().contains("places.json.bad"));
        assert!(p.home().is_none());
        let bad = std::fs::read(loc.file.with_extension("json.bad")).unwrap();
        assert!(bad.starts_with(b"{\"format\""), "the old bytes are kept");
        // Saving still works, in a new file.
        p.save(Kind::Home, "", "", FAIRVIEW).unwrap();
        assert!(Places::open(loc).home().is_some());
    }

    #[test]
    fn not_a_places_file_is_corrupt_too() {
        for text in ["[1, 2, 3]", "{\"format\": \"something\"}", "", "\u{0}\u{1}"] {
            let d = dir("other");
            let loc = at(&d);
            std::fs::create_dir_all(loc.file.parent().unwrap()).unwrap();
            std::fs::write(&loc.file, text).unwrap();
            let p = Places::open(loc.clone());
            assert!(
                p.problem().contains("unreadable"),
                "{text:?}: {}",
                p.problem()
            );
            assert!(loc.file.with_extension("json.bad").exists());
        }
    }

    #[test]
    fn a_newer_file_is_left_alone() {
        let d = dir("newer");
        let loc = at(&d);
        std::fs::create_dir_all(loc.file.parent().unwrap()).unwrap();
        let text = "{\"format\": \"f250-places\", \"version\": 2, \"whatever\": true}";
        std::fs::write(&loc.file, text).unwrap();
        let mut p = Places::open(loc.clone());
        assert!(p.problem().contains("version 2"), "{}", p.problem());
        assert!(!p.to_pb().storage.unwrap().writable);
        assert!(matches!(
            p.save(Kind::Home, "", "", FAIRVIEW),
            Err(Refused::Full(_))
        ));
        assert_eq!(
            std::fs::read_to_string(&loc.file).unwrap(),
            text,
            "untouched"
        );
    }

    #[test]
    fn bad_entries_are_dropped_and_counted() {
        let d = dir("dropped");
        let loc = at(&d);
        std::fs::create_dir_all(loc.file.parent().unwrap()).unwrap();
        std::fs::write(
            &loc.file,
            r#"{"format": "f250-places", "version": 1, "next_id": 3,
                "home": {"id": 1, "kind": "home", "name": "Home", "lat": 39.8, "lon": -98.5},
                "favourites": [
                    {"id": 2, "name": "Good", "lat": 39.0, "lon": -98.0},
                    {"id": 7, "name": "Off the planet", "lat": 200.0, "lon": -98.0},
                    {"id": 8, "name": "", "lat": 39.0, "lon": -98.0},
                    {"id": 2, "name": "Same id", "lat": 39.0, "lon": -98.0}
                ],
                "recents": [{"id": 9, "name": "", "lat": 39.1, "lon": -98.1}]}"#,
        )
        .unwrap();
        let mut p = Places::open(loc);
        assert_eq!(
            p.problem(),
            "3 saved places couldn't be read and were left out"
        );
        assert_eq!(p.favourites().len(), 1);
        assert_eq!(p.recents().len(), 1, "a recent may have no name");
        // New ids never collide with any in the file, dropped or not.
        let id = p.save(Kind::Favourite, "New", "", FAIRVIEW).unwrap();
        assert!(id > 9, "{id}");
    }

    #[test]
    fn a_failed_write_changes_nothing() {
        let d = dir("readonly");
        let mut p = Places::open(at(&d));
        // Then the directory becomes a file, so nothing can be written there.
        let blocker = d.0.join("navigation");
        std::fs::write(&blocker, b"").unwrap();
        let err = p.save(Kind::Favourite, "x", "", FAIRVIEW).unwrap_err();
        assert!(matches!(err, Refused::Write(_)), "{err:?}");
        assert!(p.favourites().is_empty(), "rolled back");
        assert!(p.problem().starts_with("Saved places: couldn't save"));
        // Once it can write, the problem goes.
        std::fs::remove_file(&blocker).unwrap();
        p.save(Kind::Favourite, "x", "", FAIRVIEW).unwrap();
        assert_eq!(p.problem(), "");
    }

    #[test]
    fn an_unreadable_file_is_read_only() {
        let d = dir("unreadable");
        // Something in the way of reading (not a missing file): change nothing.
        std::fs::write(d.0.join("navigation"), b"").unwrap();
        let mut p = Places::open(at(&d));
        assert!(p.problem().contains("can't be read"), "{}", p.problem());
        assert!(!p.to_pb().storage.unwrap().writable);
        assert!(matches!(
            p.add_recent("x", "", FAIRVIEW),
            Err(Refused::Full(_))
        ));
    }

    #[test]
    fn atomic_write_replaces_whole() {
        let d = dir("atomic");
        let f = d.0.join("a/b/file.json");
        write_atomic(&f, b"first").unwrap();
        write_atomic(&f, b"second, longer").unwrap();
        assert_eq!(std::fs::read(&f).unwrap(), b"second, longer");
        let left: Vec<_> = std::fs::read_dir(f.parent().unwrap()).unwrap().collect();
        assert_eq!(left.len(), 1, "no temporary file left");
    }

    #[test]
    fn location_follows_the_drive() {
        let on = Path::new("/var/lib/f250/storage/navigation/places.json");
        let fb = Path::new("/var/lib/f250-nav/places.json");
        let drive = Path::new("/var/lib/f250/storage");
        let l = choose_location(on, Some(drive), fb, |_| true);
        assert_eq!(
            (l.file.as_path(), l.described.as_str()),
            (on, "the data drive")
        );
        let l = choose_location(on, Some(drive), fb, |_| false);
        assert_eq!(l.file, fb);
        assert!(l.described.contains("isn't mounted"));
        let l = choose_location(on, None, fb, |_| false);
        assert_eq!(l.file, on);
        // A plain directory isn't a mount point; / is.
        let d = dir("mount");
        assert!(!is_mount_point(&d.0));
        assert!(is_mount_point(Path::new("/")));
    }
}
