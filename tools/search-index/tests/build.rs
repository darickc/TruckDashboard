//! From a real PBF file (tests/data/fixture.osm.pbf: made-up places in the
//! Gulf of Mexico) to an index the search reads.
#![allow(clippy::unwrap_used, clippy::expect_used)]

use std::path::PathBuf;

use geocode::search::{Index, Match};
use search_index::builder::{Options, build};

const FAIRVIEW: (f64, f64) = (26.0, -90.0);

fn fixture() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("tests/data/fixture.osm.pbf")
}

fn built() -> (Index, search_index::builder::Summary) {
    built_with(None)
}

fn built_with(states: Option<PathBuf>) -> (Index, search_index::builder::Summary) {
    static N: std::sync::atomic::AtomicU32 = std::sync::atomic::AtomicU32::new(0);
    let n = N.fetch_add(1, std::sync::atomic::Ordering::Relaxed);
    let dir = std::env::temp_dir().join(format!("f250-search-index-{}-{n}", std::process::id()));
    std::fs::create_dir_all(&dir).unwrap();
    let out = dir.join("search.sqlite");
    let summary = build(&Options {
        pbfs: vec![fixture()],
        out: out.clone(),
        regions: vec!["Gulf test".into()],
        data_date: None,
        states,
        verbose: false,
    })
    .unwrap();
    assert!(!dir.join("search.sqlite.part").exists());
    (Index::open(&out).unwrap(), summary)
}

#[test]
fn builds_what_the_extract_has() {
    let (ix, s) = built();
    // Fairview and Tiny; North Main Street (two ways, one row) and Elm
    // Avenue; 120 North Main Street and 5 Elm Avenue; Casey's. Not the
    // footway, the bench, the stop sign or the relation.
    assert_eq!(s.counts.localities, 2);
    assert_eq!(s.counts.streets, 2);
    assert_eq!(s.counts.addresses, 2);
    assert_eq!(s.counts.pois, 1);
    // Edge Road's nodes aren't in the file.
    assert_eq!(s.missing_nodes, 1);
    // From the header's replication timestamp.
    assert_eq!(s.data_date.as_deref(), Some("2026-11-11"));
    assert_eq!(ix.info.data_date.as_deref(), Some("2026-11-11"));
    assert_eq!(ix.info.regions, ["Gulf test"]);
}

#[test]
fn searches_what_was_built() {
    let (ix, _) = built();
    let hits = ix.search("120 n main st", Some(FAIRVIEW), 8).unwrap();
    assert_eq!(hits[0].kind, Match::Address);
    assert_eq!(hits[0].title, "120 North Main Street");
    assert_eq!(hits[0].subtitle, "near Fairview");
    // The building's first corner.
    assert!((hits[0].lat - 26.0012).abs() < 1e-6 && (hits[0].lon + 89.9998).abs() < 1e-6);

    let hits = ix.search("elm ave", Some(FAIRVIEW), 8).unwrap();
    assert_eq!(hits[0].title, "Elm Avenue");
    assert_eq!(hits[0].subtitle, "near Tiny");

    let hits = ix.search("caseys", Some(FAIRVIEW), 8).unwrap();
    assert_eq!(
        hits[0].subtitle,
        "Fuel · 200 North Main Street · near Fairview"
    );

    // One row for the street, on one of its own nodes.
    let hits = ix.search("north main", Some(FAIRVIEW), 8).unwrap();
    let main: Vec<_> = hits.iter().filter(|h| h.kind == Match::Street).collect();
    assert_eq!(main.len(), 1);
    assert!(
        [26.001, 26.002, 26.003, 26.004]
            .iter()
            .any(|l| (main[0].lat - l).abs() < 1e-6)
    );

    assert!(
        ix.search("park path", Some(FAIRVIEW), 8)
            .unwrap()
            .is_empty()
    );
    assert!(ix.search("memorial", Some(FAIRVIEW), 8).unwrap().is_empty());
    assert!(ix.search("not read", Some(FAIRVIEW), 8).unwrap().is_empty());
}

#[test]
fn with_state_boundaries_every_row_names_its_state() {
    // A made-up state around Fairview only; Tiny, 22 km north, is outside.
    let dir = std::env::temp_dir().join(format!("f250-search-index-states-{}", std::process::id()));
    std::fs::create_dir_all(&dir).unwrap();
    let states = dir.join("states.geojsonseq");
    std::fs::write(
        &states,
        "\u{1e}{\"type\":\"Feature\",\"geometry\":{\"type\":\"Polygon\",\"coordinates\":\
         [[[-90.1,25.9],[-89.9,25.9],[-89.9,26.1],[-90.1,26.1],[-90.1,25.9]]]},\
         \"properties\":{\"name\":\"Gulfland\",\"ISO3166-2\":\"US-GU\"}}\n",
    )
    .unwrap();
    let (ix, _) = built_with(Some(states));
    let hits = ix.search("120 n main st", Some(FAIRVIEW), 8).unwrap();
    assert_eq!(hits[0].subtitle, "near Fairview, GU");
    let hits = ix.search("fairview", Some(FAIRVIEW), 8).unwrap();
    assert_eq!(hits[0].subtitle, "Town · GU");
    let hits = ix.search("elm ave", Some(FAIRVIEW), 8).unwrap();
    assert_eq!(hits[0].subtitle, "near Tiny");
}

#[test]
fn a_missing_file_is_an_error() {
    let err = build(&Options {
        pbfs: vec![PathBuf::from("/nonexistent/x.osm.pbf")],
        out: std::env::temp_dir().join("f250-search-index-never.sqlite"),
        regions: vec![],
        data_date: None,
        states: None,
        verbose: false,
    })
    .unwrap_err();
    assert!(err.contains("/nonexistent/x.osm.pbf"), "{err}");
}
