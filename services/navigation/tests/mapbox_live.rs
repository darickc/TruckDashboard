//! The navigation program against the real Mapbox (ADR-0052): opt-in, as it
//! needs a token and the internet, which the default suite never does
//! (CLAUDE.md rule 9).
//!
//!   MAPBOX_ACCESS_TOKEN=pk.… cargo test -p navigation --test mapbox_live -- --ignored
//!
//! It runs the binary with the simulated receiver and no Valhalla, sets a
//! destination near the receiver's loop, and checks that the route came
//! from Mapbox, that the online map is configured and serves a day and a
//! night tile, that search answers from Mapbox, and that the token never
//! reached the log. Each run makes one Directions request, two tile requests
//! and one Geocoding request on the token's account.

#![allow(clippy::unwrap_used, clippy::expect_used)]

use std::process::Stdio;
use std::time::Duration;

use f250_proto::nav::v1 as pb;
use pb::online_map_service_client::OnlineMapServiceClient;
use pb::route_service_client::RouteServiceClient;
use pb::search_service_client::SearchServiceClient;
use tokio::io::AsyncReadExt;
use tonic::transport::Endpoint;

/// The slippy-map tile at zoom `z` holding a point.
fn tile(lat: f64, lon: f64, z: u32) -> (u32, u32) {
    let n = f64::from(1u32 << z);
    let x = ((lon + 180.0) / 360.0 * n).floor();
    let r = lat.to_radians();
    let y = ((1.0 - (r.tan() + 1.0 / r.cos()).ln() / std::f64::consts::PI) / 2.0 * n).floor();
    (x as u32, y as u32)
}

#[tokio::test]
#[ignore = "needs MAPBOX_ACCESS_TOKEN and the internet"]
async fn a_route_and_tiles_from_mapbox() {
    let token = std::env::var("MAPBOX_ACCESS_TOKEN").expect("set MAPBOX_ACCESS_TOKEN");
    let dir = std::env::temp_dir().join(format!("f250-mapbox-live-{}", std::process::id()));
    std::fs::create_dir_all(&dir).unwrap();
    let port = {
        let l = std::net::TcpListener::bind("127.0.0.1:0").unwrap();
        l.local_addr().unwrap().port()
    };
    let mut child = tokio::process::Command::new(env!("CARGO_BIN_EXE_navigation"))
        .args(["--listen", &format!("tcp:127.0.0.1:{port}"), "--simulate"])
        .args(["--valhalla", "/nonexistent/valhalla_service"])
        .arg("--run-dir")
        .arg(&dir)
        .arg("--places-dir")
        .arg(&dir)
        .arg("--places-fallback-dir")
        .arg(&dir)
        .args(["--search-index", "/nonexistent/search.sqlite"])
        .env("MAPBOX_ACCESS_TOKEN", &token)
        .env_remove("CREDENTIALS_DIRECTORY")
        .stdout(Stdio::null())
        .stderr(Stdio::piped())
        .kill_on_drop(true)
        .spawn()
        .unwrap();

    let endpoint = Endpoint::from_shared(format!("http://127.0.0.1:{port}")).unwrap();
    let mut channel = None;
    for _ in 0..100 {
        if let Ok(c) = endpoint.connect().await {
            channel = Some(c);
            break;
        }
        tokio::time::sleep(Duration::from_millis(100)).await;
    }
    let channel = channel.expect("navigation didn't start");
    let mut routes = RouteServiceClient::new(channel.clone());
    let mut online = OnlineMapServiceClient::new(channel.clone());
    let mut search = SearchServiceClient::new(channel);

    let status = online
        .get_online_map_status(pb::GetOnlineMapStatusRequest {})
        .await
        .unwrap()
        .into_inner();
    assert!(status.configured, "{}", status.detail);
    assert_eq!(status.tile_size, 512);

    // Near the simulated loop (sim.rs), the destination the tests use.
    routes
        .set_destination(pb::SetDestinationRequest {
            destination: Some(pb::LatLon {
                latitude_deg: 39.8103,
                longitude_deg: -98.5559,
            }),
            name: "Live test".into(),
            detail: String::new(),
        })
        .await
        .unwrap();
    let mut guidance = routes
        .watch_guidance(pb::WatchGuidanceRequest {})
        .await
        .unwrap()
        .into_inner();
    let route_id = tokio::time::timeout(Duration::from_secs(30), async {
        loop {
            let g = guidance.message().await.unwrap().unwrap().guidance.unwrap();
            match pb::RouteState::try_from(g.state).unwrap() {
                pb::RouteState::Active | pb::RouteState::Arrived if g.route_id != 0 => {
                    return g.route_id;
                }
                pb::RouteState::Failed => panic!("routing failed: {}", g.detail),
                _ => {}
            }
        }
    })
    .await
    .expect("no route within 30 s");
    let route = routes
        .get_route(pb::GetRouteRequest { route_id })
        .await
        .unwrap()
        .into_inner()
        .route
        .unwrap();
    assert_eq!(route.provider, "mapbox");
    assert!(route.shape.len() >= 2);
    assert!(!route.maneuvers.is_empty());
    assert!(route.length_m > 0.0);
    eprintln!(
        "route: {:.0} m, {:.0} s, {} maneuvers, first \"{}\"",
        route.length_m,
        route.time_s,
        route.maneuvers.len(),
        route.maneuvers[0].instruction
    );

    // 512-pixel tiles at Mapbox's zoom 14 over Lebanon, day and night.
    let (x, y) = tile(39.8103, -98.5559, 14);
    for style in [pb::MapStyle::Day, pb::MapStyle::Night] {
        let t = online
            .get_tile(pb::GetTileRequest {
                style: style as i32,
                z: 14,
                x,
                y,
            })
            .await
            .unwrap()
            .into_inner();
        assert!(t.content_type.starts_with("image/"), "{}", t.content_type);
        assert!(t.data.starts_with(b"\x89PNG") || t.data.starts_with(b"\xff\xd8"));
        eprintln!(
            "{style:?} tile 14/{x}/{y}: {} bytes, {}",
            t.data.len(),
            t.content_type
        );
    }

    // A town and a street, from Mapbox (no offline index here).
    let found = search
        .search(pb::SearchRequest {
            query: "main st lebanon ks".into(),
            limit: 5,
        })
        .await
        .unwrap()
        .into_inner();
    assert!(found.available, "{}", found.detail);
    assert_eq!(found.provider, "mapbox");
    assert!(!found.results.is_empty());
    for r in &found.results {
        eprintln!(
            "search: {:?} \"{}\", {} ({:.0} m)",
            pb::MatchKind::try_from(r.kind).unwrap(),
            r.title,
            r.subtitle,
            r.distance_m.unwrap_or(f64::NAN)
        );
    }

    child.start_kill().unwrap();
    let mut log = String::new();
    child
        .stderr
        .take()
        .unwrap()
        .read_to_string(&mut log)
        .await
        .unwrap();
    assert!(
        log.contains("online: Mapbox routes (driving-traffic), map"),
        "{log}"
    );
    assert!(!log.contains(&token), "the token reached the log");
}

#[test]
fn tiles_of_a_point() {
    // Lebanon, Kansas at zoom 10 (checked by hand against a tile fetched
    // from Mapbox on 2026-11-23).
    assert_eq!(tile(39.8, -98.58, 10), (231, 388));
}
