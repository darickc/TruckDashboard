//! Search end to end [SIM]: an index of made-up places, the service on a
//! unix socket, a gRPC client. Ranked from the position the service has,
//! and honest about no index and no position.
#![allow(clippy::unwrap_used, clippy::expect_used)]

use std::path::Path;
use std::time::Duration;

use f250_proto::nav::v1 as pb;
use geocode::index::{self, Kind, Meta, Place, Writer};
use hyper_util::rt::TokioIo;
use navigation::search::Searcher;
use navigation::server::{self, Api};
use pb::search_service_client::SearchServiceClient;
use tokio::sync::watch;
use tonic::transport::{Endpoint, Uri};

fn dir(test: &str) -> std::path::PathBuf {
    let d = std::env::temp_dir().join(format!("f250-nav-search-e2e-{test}-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&d);
    std::fs::create_dir_all(&d).unwrap();
    d
}

fn place(
    kind: Kind,
    name: &str,
    near: Option<&str>,
    category: Option<&str>,
    at: (f64, f64),
) -> Place {
    Place {
        kind,
        name: name.into(),
        number: None,
        street: None,
        locality: near.map(str::to_string),
        locality_near: near.is_some(),
        category: category.map(str::to_string),
        lat: at.0,
        lon: at.1,
        weight: index::importance(kind, category, None),
        state: None,
    }
}

fn write_index(path: &Path) {
    let mut w = Writer::create(path).unwrap();
    for p in [
        place(
            Kind::Locality,
            "Fairview",
            None,
            Some("town"),
            (26.0, -90.0),
        ),
        place(
            Kind::Locality,
            "Hillsdale",
            None,
            Some("village"),
            (26.1, -89.8),
        ),
        place(
            Kind::Street,
            "Main Street",
            Some("Fairview"),
            None,
            (26.001, -90.0),
        ),
        place(
            Kind::Street,
            "Main Street",
            Some("Hillsdale"),
            None,
            (26.101, -89.8),
        ),
    ] {
        w.add(&p).unwrap();
    }
    w.finish(&Meta {
        regions: vec!["Gulf test".into()],
        data_date: Some("2026-11-11".into()),
        built_at: "2026-11-12T00:00:00Z".into(),
    })
    .unwrap();
}

async fn client(path: &Path) -> SearchServiceClient<tonic::transport::Channel> {
    let path = path.to_path_buf();
    for _ in 0..100 {
        if path.exists() {
            break;
        }
        tokio::time::sleep(Duration::from_millis(20)).await;
    }
    let channel = Endpoint::from_static("http://localhost")
        .connect_with_connector(tower::service_fn(move |_: Uri| {
            let path = path.clone();
            async move {
                tokio::net::UnixStream::connect(path)
                    .await
                    .map(TokioIo::new)
            }
        }))
        .await
        .expect("connect");
    SearchServiceClient::new(channel)
}

fn fix(lat: f64, lon: f64, current: bool) -> pb::Position {
    pb::Position {
        status: pb::FixStatus::Fix3d as i32,
        fix: Some(pb::Fix {
            latitude_deg: lat,
            longitude_deg: lon,
            age_ms: if current { 200 } else { 60_000 },
            ..Default::default()
        }),
        current,
        ..Default::default()
    }
}

async fn search(
    c: &mut SearchServiceClient<tonic::transport::Channel>,
    q: &str,
) -> pb::SearchResponse {
    c.search(pb::SearchRequest {
        query: q.into(),
        limit: 0,
    })
    .await
    .unwrap()
    .into_inner()
}

#[tokio::test]
async fn searches_ranked_from_the_position() {
    let d = dir("ranked");
    let index = d.join("search.sqlite");
    write_index(&index);
    let sock = d.join("nav.sock");
    let (tx, position) = watch::channel(fix(26.0, -90.0, true));
    let api = Api::new(position).with_search(Searcher::new(index));
    let listen = format!("unix:{}", sock.display());
    tokio::spawn(async move { server::serve(&listen, api).await });
    let mut c = client(&sock).await;

    let r = search(&mut c, "main st").await;
    assert!(r.available, "{}", r.detail);
    assert_eq!(r.query, "main st");
    assert_eq!(r.regions, ["Gulf test"]);
    assert_eq!(r.data_date, "2026-11-11");
    assert_eq!(r.ranked_from, pb::RankedFrom::Current as i32);
    assert_eq!(r.results.len(), 2);
    assert_eq!(r.results[0].subtitle, "near Fairview");
    assert_eq!(r.results[0].kind, pb::MatchKind::Street as i32);
    assert!(r.results[0].distance_m.unwrap() < 200.0);

    // From Hillsdale, last known: Hillsdale's Main Street first.
    tx.send(fix(26.1, -89.8, false)).unwrap();
    let r = search(&mut c, "main st").await;
    assert_eq!(r.ranked_from, pb::RankedFrom::LastKnown as i32);
    assert_eq!(r.position_age_s, 60.0);
    assert_eq!(r.results[0].subtitle, "near Hillsdale");

    // A house number that isn't there.
    let r = search(&mut c, "12 main st").await;
    assert!(r.results.iter().all(|h| h.house_number_missing));

    // No position: unranked, no distances.
    tx.send(pb::Position::default()).unwrap();
    let r = search(&mut c, "fairview").await;
    assert_eq!(r.ranked_from, pb::RankedFrom::None as i32);
    assert_eq!(r.results[0].title, "Fairview");
    assert_eq!(r.results[0].subtitle, "Town");
    assert!(r.results[0].distance_m.is_none());
}

#[tokio::test]
async fn no_index_is_an_answer() {
    let d = dir("missing");
    let sock = d.join("nav.sock");
    let (_tx, position) = watch::channel(fix(26.0, -90.0, true));
    let api = Api::new(position).with_search(Searcher::new(d.join("search.sqlite")));
    let listen = format!("unix:{}", sock.display());
    tokio::spawn(async move { server::serve(&listen, api).await });
    let mut c = client(&sock).await;

    let r = search(&mut c, "main st").await;
    assert!(!r.available);
    assert!(r.detail.contains("no search data"), "{}", r.detail);
    assert!(r.results.is_empty());

    // The stick brings it: found on the next search, no restart.
    write_index(&d.join("search.sqlite"));
    let r = search(&mut c, "main st").await;
    assert!(r.available, "{}", r.detail);
    assert_eq!(r.results.len(), 2);
}
