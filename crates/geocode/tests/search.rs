//! The search against a small index of made-up places (no real addresses):
//! what is found, what it is called, and in what order near a position.
#![allow(clippy::unwrap_used, clippy::expect_used)]

use std::path::PathBuf;
use std::sync::atomic::{AtomicU32, Ordering};

use geocode::index::{self, Kind, Meta, Place, Writer};
use geocode::search::{Hit, Index, Match};

/// Fairview is a town at (38.50, -97.50); Hillsdale a village about 20 km
/// north-east; Port Ellis a city about 600 km west.
const FAIRVIEW: (f64, f64) = (38.50, -97.50);
const HILLSDALE: (f64, f64) = (38.60, -97.30);
const PORT_ELLIS: (f64, f64) = (38.80, -104.40);

fn temp(name: &str) -> PathBuf {
    static N: AtomicU32 = AtomicU32::new(0);
    let dir = std::env::temp_dir().join(format!(
        "f250-geocode-{}-{}",
        std::process::id(),
        N.fetch_add(1, Ordering::Relaxed)
    ));
    std::fs::create_dir_all(&dir).unwrap();
    dir.join(name)
}

fn town(name: &str, category: &str, at: (f64, f64)) -> Place {
    Place {
        kind: Kind::Locality,
        name: name.into(),
        number: None,
        street: None,
        locality: None,
        locality_near: false,
        category: Some(category.into()),
        lat: at.0,
        lon: at.1,
        weight: index::importance(Kind::Locality, Some(category), None),
        state: None,
    }
}

fn street(name: &str, near: &str, at: (f64, f64)) -> Place {
    Place {
        kind: Kind::Street,
        name: name.into(),
        number: None,
        street: None,
        locality: Some(near.into()),
        locality_near: true,
        category: None,
        lat: at.0,
        lon: at.1,
        weight: index::importance(Kind::Street, None, None),
        state: None,
    }
}

fn address(number: &str, street: &str, city: &str, at: (f64, f64)) -> Place {
    Place {
        kind: Kind::Address,
        name: String::new(),
        number: Some(number.into()),
        street: Some(street.into()),
        locality: Some(city.into()),
        locality_near: false,
        category: None,
        lat: at.0,
        lon: at.1,
        weight: 0.0,
        state: None,
    }
}

fn off(p: (f64, f64), dlat: f64, dlon: f64) -> (f64, f64) {
    (p.0 + dlat, p.1 + dlon)
}

fn fixture() -> Index {
    let path = temp("search.sqlite");
    let mut w = Writer::create(&path).unwrap();
    let places = vec![
        town("Fairview", "town", FAIRVIEW),
        town("Hillsdale", "village", HILLSDALE),
        town("Port Ellis", "city", PORT_ELLIS),
        town("St. Marys", "town", off(FAIRVIEW, 0.9, 0.9)),
        town("Cañon City", "town", off(PORT_ELLIS, -0.4, 0.4)),
        street("North Main Street", "Fairview", off(FAIRVIEW, 0.001, 0.0)),
        street("Elm Avenue", "Fairview", off(FAIRVIEW, -0.004, 0.002)),
        street("Port Ellis Road", "Fairview", off(FAIRVIEW, 0.01, 0.01)),
        street("Fairview Road", "Hillsdale", off(HILLSDALE, 0.005, 0.0)),
        street("Main Street", "Hillsdale", off(HILLSDALE, 0.001, 0.0)),
        street("Main Street", "Port Ellis", off(PORT_ELLIS, 0.001, 0.0)),
        address(
            "120",
            "North Main Street",
            "Fairview",
            off(FAIRVIEW, 0.0012, 0.0),
        ),
        address(
            "122",
            "North Main Street",
            "Fairview",
            off(FAIRVIEW, 0.0013, 0.0),
        ),
        address(
            "120",
            "Main Street",
            "Port Ellis",
            off(PORT_ELLIS, 0.0012, 0.0),
        ),
        Place {
            kind: Kind::Poi,
            name: "Casey's General Store".into(),
            number: Some("200".into()),
            street: Some("North Main Street".into()),
            locality: Some("Fairview".into()),
            locality_near: false,
            category: Some("fuel".into()),
            lat: FAIRVIEW.0 + 0.002,
            lon: FAIRVIEW.1,
            weight: index::importance(Kind::Poi, Some("fuel"), None),
            state: None,
        },
    ];
    // Two towns of one name in two made-up states, and a street in one.
    let westland = index::State {
        short: "WL".into(),
        name: "Westland".into(),
    };
    let eastland = index::State {
        short: "EL".into(),
        name: "Eastland".into(),
    };
    let places = places
        .into_iter()
        .chain([
            Place {
                state: Some(westland.clone()),
                ..town("Twin City", "city", off(FAIRVIEW, 2.0, -3.0))
            },
            Place {
                state: Some(eastland.clone()),
                ..town("Twin City", "city", off(FAIRVIEW, 2.0, 3.0))
            },
            Place {
                state: Some(eastland),
                ..street("Harbor Road", "Twin City", off(FAIRVIEW, 2.01, 3.0))
            },
        ])
        .collect::<Vec<_>>();
    for p in &places {
        w.add(p).unwrap();
    }
    let counts = w
        .finish(&Meta {
            regions: vec!["Testland".into()],
            data_date: Some("2026-11-11".into()),
            built_at: "2026-11-12T00:00:00Z".into(),
        })
        .unwrap();
    assert_eq!(counts.addresses, 3);
    assert_eq!(counts.localities, 7);
    Index::open(&path).unwrap()
}

fn titles(hits: &[Hit]) -> Vec<String> {
    hits.iter()
        .map(|h| format!("{} | {}", h.title, h.subtitle))
        .collect()
}

#[test]
fn reads_what_it_covers() {
    let ix = fixture();
    assert_eq!(ix.info.regions, ["Testland"]);
    assert_eq!(ix.info.data_date.as_deref(), Some("2026-11-11"));
    assert_eq!(ix.info.counts.streets, 7);
    assert_eq!(ix.info.counts.pois, 1);
}

#[test]
fn an_address_with_its_house_number_comes_first() {
    let ix = fixture();
    let hits = ix.search("120 n main st", Some(FAIRVIEW), 8).unwrap();
    assert_eq!(hits[0].kind, Match::Address);
    assert_eq!(hits[0].title, "120 North Main Street");
    assert_eq!(hits[0].subtitle, "Fairview");
    assert!(!hits[0].house_number_missing);
    assert!(hits[0].distance_m.unwrap() < 200.0);
    // The Port Ellis address doesn't have "north".
    assert!(
        !titles(&hits).iter().any(|t| t.contains("Port Ellis")),
        "{:?}",
        titles(&hits)
    );
    // The street itself isn't repeated under the address.
    assert!(
        !hits
            .iter()
            .any(|h| h.kind == Match::Street && h.title == "North Main Street")
    );
}

#[test]
fn a_missing_house_number_finds_the_street_and_says_so() {
    let ix = fixture();
    let hits = ix.search("125 main street", Some(FAIRVIEW), 8).unwrap();
    assert_eq!(hits[0].kind, Match::Street);
    assert_eq!(hits[0].title, "North Main Street");
    assert_eq!(hits[0].subtitle, "near Fairview");
    assert!(hits[0].house_number_missing);
    assert!(hits.iter().all(|h| h.kind != Match::Address));
}

#[test]
fn nearest_first() {
    let ix = fixture();
    let from_fairview = ix.search("main st", Some(FAIRVIEW), 8).unwrap();
    assert_eq!(
        titles(&from_fairview)[..3],
        [
            "North Main Street | near Fairview",
            "Main Street | near Hillsdale",
            "Main Street | near Port Ellis"
        ]
    );
    let from_hillsdale = ix.search("main st", Some(HILLSDALE), 8).unwrap();
    assert_eq!(titles(&from_hillsdale)[0], "Main Street | near Hillsdale");
    let from_port_ellis = ix.search("main st", Some(PORT_ELLIS), 8).unwrap();
    assert_eq!(titles(&from_port_ellis)[0], "Main Street | near Port Ellis");
}

#[test]
fn a_town_named_in_full_beats_a_road_named_after_it() {
    let ix = fixture();
    let hits = ix.search("port ellis", Some(FAIRVIEW), 8).unwrap();
    assert_eq!(hits[0].kind, Match::Locality);
    assert_eq!(titles(&hits)[0], "Port Ellis | City");
    assert!(titles(&hits).contains(&"Port Ellis Road | near Fairview".to_string()));

    let hits = ix.search("fairview", Some(HILLSDALE), 8).unwrap();
    assert_eq!(titles(&hits)[0], "Fairview | Town");
}

#[test]
fn street_and_town_together() {
    let ix = fixture();
    let hits = ix
        .search("main street hillsdale", Some(PORT_ELLIS), 8)
        .unwrap();
    assert_eq!(titles(&hits)[0], "Main Street | near Hillsdale");
    assert!(hits[0].unmatched.is_empty());
}

#[test]
fn the_last_word_matches_while_typing() {
    let ix = fixture();
    assert_eq!(
        ix.search("elm av", Some(FAIRVIEW), 8).unwrap()[0].title,
        "Elm Avenue"
    );
    assert_eq!(
        ix.search("elm aven", Some(FAIRVIEW), 8).unwrap()[0].title,
        "Elm Avenue"
    );
    assert_eq!(
        ix.search("hills", Some(FAIRVIEW), 8).unwrap()[0].title,
        "Hillsdale"
    );
    // A finished word (a space after it) must match whole.
    assert!(ix.search("hills ", Some(FAIRVIEW), 8).unwrap().is_empty());
}

#[test]
fn abbreviations_both_ways() {
    let ix = fixture();
    assert_eq!(
        ix.search("elm ave", Some(FAIRVIEW), 8).unwrap()[0].title,
        "Elm Avenue"
    );
    assert_eq!(
        ix.search("north main street", Some(FAIRVIEW), 8).unwrap()[0].title,
        "North Main Street"
    );
    assert_eq!(
        ix.search("saint marys", Some(FAIRVIEW), 8).unwrap()[0].title,
        "St. Marys"
    );
    assert_eq!(
        ix.search("st marys", Some(FAIRVIEW), 8).unwrap()[0].title,
        "St. Marys"
    );
}

#[test]
fn accents_and_case_do_not_matter() {
    let ix = fixture();
    assert_eq!(
        ix.search("CANON CITY", None, 8).unwrap()[0].title,
        "Cañon City"
    );
    assert_eq!(ix.search("cañon", None, 8).unwrap()[0].title, "Cañon City");
}

#[test]
fn a_named_place_with_its_address() {
    let ix = fixture();
    let hits = ix.search("caseys", Some(FAIRVIEW), 8).unwrap();
    assert_eq!(hits[0].kind, Match::Place);
    assert_eq!(hits[0].title, "Casey's General Store");
    assert_eq!(hits[0].subtitle, "Fuel · 200 North Main Street · Fairview");
    // Its house number finds it as an address.
    let hits = ix.search("200 n main", Some(FAIRVIEW), 8).unwrap();
    assert_eq!(hits[0].kind, Match::Address);
    assert_eq!(hits[0].title, "Casey's General Store");
}

#[test]
fn only_part_of_the_query_matched() {
    let ix = fixture();
    // Elm Avenue is in Fairview, not Hillsdale.
    let hits = ix
        .search("elm avenue hillsdale", Some(FAIRVIEW), 8)
        .unwrap();
    let elm = hits
        .iter()
        .find(|h| h.title == "Elm Avenue")
        .expect("Elm Avenue");
    assert_eq!(elm.unmatched, ["hillsdale"]);
    let town = hits
        .iter()
        .find(|h| h.title == "Hillsdale")
        .expect("Hillsdale");
    assert_eq!(town.kind, Match::Locality);
    assert_eq!(town.unmatched, ["elm", "avenue"]);
    // Nothing named by these words at all.
    assert!(ix.search("zzyzx", Some(FAIRVIEW), 8).unwrap().is_empty());
}

#[test]
fn far_away_and_without_a_position() {
    let ix = fixture();
    // The address is 600 km away: outside the cells around the truck.
    let hits = ix
        .search("120 main st port ellis", Some(FAIRVIEW), 8)
        .unwrap();
    assert_eq!(titles(&hits)[0], "120 Main Street | Port Ellis");
    assert!(hits[0].distance_m.unwrap() > 500_000.0);

    let hits = ix.search("main street", None, 8).unwrap();
    assert_eq!(hits.len(), 3);
    assert!(hits.iter().all(|h| h.distance_m.is_none()));
}

#[test]
fn nothing_to_search() {
    let ix = fixture();
    assert!(ix.search("", Some(FAIRVIEW), 8).unwrap().is_empty());
    assert!(ix.search("120", Some(FAIRVIEW), 8).unwrap().is_empty());
    assert!(ix.search("  ,, ", Some(FAIRVIEW), 8).unwrap().is_empty());
    assert!(ix.search("main", Some(FAIRVIEW), 0).unwrap().is_empty());
    assert_eq!(ix.search("main", Some(FAIRVIEW), 2).unwrap().len(), 2);
}

#[test]
fn states_tell_same_named_towns_apart() {
    let ix = fixture();
    let hits = ix.search("twin city", Some(FAIRVIEW), 8).unwrap();
    let t = titles(&hits);
    assert!(t.contains(&"Twin City | City · WL".to_string()), "{t:?}");
    assert!(t.contains(&"Twin City | City · EL".to_string()), "{t:?}");
    // By the state's short name, a town or a street.
    let hits = ix.search("twin city el", Some(FAIRVIEW), 8).unwrap();
    assert_eq!(titles(&hits)[0], "Twin City | City · EL");
    let hits = ix.search("harbor rd el", Some(FAIRVIEW), 8).unwrap();
    assert_eq!(titles(&hits)[0], "Harbor Road | near Twin City, EL");
    // The full name isn't searched: "twin city eastland" finds the towns by
    // their name and says "eastland" didn't match.
    let hits = ix.search("twin city eastland", Some(FAIRVIEW), 8).unwrap();
    assert!(hits.iter().all(|h| h.unmatched == ["eastland"]), "{hits:?}");
}

#[test]
fn refuses_other_files() {
    let missing = temp("nothing.sqlite");
    assert!(
        Index::open(&missing)
            .unwrap_err()
            .contains("no search data")
    );

    let other = temp("other.sqlite");
    rusqlite::Connection::open(&other)
        .unwrap()
        .execute_batch("CREATE TABLE t(x)")
        .unwrap();
    assert!(
        Index::open(&other)
            .unwrap_err()
            .contains("isn't search data")
    );

    let newer = temp("newer.sqlite");
    let c = rusqlite::Connection::open(&newer).unwrap();
    c.pragma_update(None, "application_id", index::APPLICATION_ID)
        .unwrap();
    c.pragma_update(None, "user_version", index::SCHEMA_VERSION + 1)
        .unwrap();
    drop(c);
    assert!(
        Index::open(&newer)
            .unwrap_err()
            .contains("make search-region")
    );
}
