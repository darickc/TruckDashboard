//! Routing end to end [SIM]: the simulated receiver, the guide and the API
//! over a unix socket, with a fake `valhalla_service` (a shell script) that
//! answers with Valhalla 3.9.1's real output from `tests/data/`. The real
//! Valhalla is run by hand (docs/setup/maps.md), not by the test suite.
#![allow(clippy::unwrap_used, clippy::expect_used)]

use std::path::{Path, PathBuf};
use std::sync::Arc;
use std::time::Duration;

use f250_proto::nav::v1 as pb;
use hyper_util::rt::TokioIo;
use navigation::guide::{self, GuideConfig};
use navigation::publisher::{self, PublisherConfig};
use navigation::server::{self, Api, RoutingApi};
use navigation::sim::{self, SimConfig};
use navigation::valhalla::{DEFAULT_TIMEOUT, ValhallaCli};
use pb::route_service_client::RouteServiceClient;
use tokio::sync::{mpsc, watch};
use tonic::transport::{Endpoint, Uri};

const DATA: &str = concat!(env!("CARGO_MANIFEST_DIR"), "/tests/data");

fn temp(test: &str) -> PathBuf {
    let dir = std::env::temp_dir().join(format!("f250-route-{test}-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).expect("temp dir");
    dir
}

/// Sets up `tests/data/fake-valhalla.sh` (see there) to answer with
/// `answer` from `tests/data/` and exit with `code`.
fn fake_valhalla(dir: &Path, answer: &str, code: i32) -> PathBuf {
    std::fs::copy(Path::new(DATA).join(answer), dir.join("answer.json")).expect("answer");
    std::fs::write(dir.join("exit-code"), code.to_string()).expect("exit code");
    Path::new(DATA).join("fake-valhalla.sh")
}

struct Service {
    dir: PathBuf,
    client: RouteServiceClient<tonic::transport::Channel>,
}

async fn start(test: &str, answer: &str, code: i32, with_tiles: bool) -> Service {
    let dir = temp(test);
    let tiles = dir.join("valhalla_tiles.tar");
    if with_tiles {
        std::fs::write(&tiles, b"not read by the fake").expect("tiles");
    }
    let router = Arc::new(ValhallaCli {
        program: fake_valhalla(&dir, answer, code),
        template: Path::new(env!("CARGO_MANIFEST_DIR")).join("valhalla/valhalla-3.9.1.json"),
        tiles,
        config: dir.join("run/valhalla.json"),
        timeout: DEFAULT_TIMEOUT,
    });

    let (events_tx, events_rx) = mpsc::channel(64);
    let (route_tx, route_rx) = watch::channel(None);
    let (pos_tx, position) = watch::channel(pb::Position::default());
    tokio::spawn(publisher::run(
        PublisherConfig {
            stale_after: Duration::from_millis(500),
            simulated: true,
            tick: Duration::from_millis(100),
        },
        events_rx,
        pos_tx,
        None,
    ));
    let sim_cfg = SimConfig {
        period: Duration::from_millis(50),
        speed_mps: 2_000.0, // the 23 km route in 12 s
        // A loop well away from the fake's route. The default loop passes
        // near the route's end, which would match there before the receiver
        // jumps to the route's start (a jump no truck makes).
        corners: vec![(39.0, -99.0), (39.0, -98.99), (39.01, -98.99)],
        ..SimConfig::default()
    };
    tokio::spawn(sim::run(sim_cfg, events_tx, Some(route_rx.clone())));
    let (commands_tx, commands_rx) = mpsc::channel(8);
    let (guidance_tx, guidance_rx) = watch::channel(pb::Guidance::default());
    tokio::spawn(guide::run(
        GuideConfig::default(),
        router,
        commands_rx,
        position.clone(),
        guidance_tx,
        route_tx,
    ));
    let api = Api::new(position).with_routing(RoutingApi {
        commands: commands_tx,
        guidance: guidance_rx,
        route: route_rx,
    });
    let sock = dir.join("nav.sock");
    let listen = format!("unix:{}", sock.display());
    tokio::spawn(async move { server::serve(&listen, api).await });
    for _ in 0..100 {
        if sock.exists() {
            break;
        }
        tokio::time::sleep(Duration::from_millis(20)).await;
    }
    let channel = Endpoint::from_static("http://localhost")
        .connect_with_connector(tower::service_fn(move |_: Uri| {
            let sock = sock.clone();
            async move {
                tokio::net::UnixStream::connect(sock)
                    .await
                    .map(TokioIo::new)
            }
        }))
        .await
        .expect("connect");
    Service {
        dir,
        client: RouteServiceClient::new(channel),
    }
}

async fn until(
    stream: &mut tonic::Streaming<pb::WatchGuidanceResponse>,
    mut want: impl FnMut(&pb::Guidance) -> bool,
) -> pb::Guidance {
    let mut last = None;
    let found = tokio::time::timeout(Duration::from_secs(20), async {
        loop {
            let g = stream
                .message()
                .await
                .expect("stream ok")
                .expect("stream open")
                .guidance
                .expect("guidance");
            if want(&g) {
                return g;
            }
            last = Some(g);
        }
    })
    .await;
    found.unwrap_or_else(|_| panic!("not in time; the last guidance: {last:?}"))
}

fn dest() -> pb::LatLon {
    pb::LatLon {
        latitude_deg: 39.8103,
        longitude_deg: -98.5559,
    }
}

#[tokio::test]
async fn routes_guides_and_arrives() {
    let mut s = start("ok", "valhalla-3.9.1-route-auto.json", 0, true).await;
    let mut stream = s
        .client
        .watch_guidance(pb::WatchGuidanceRequest {})
        .await
        .expect("watch")
        .into_inner();
    let g = until(&mut stream, |g| g.state != 0).await;
    assert_eq!(g.state, pb::RouteState::Idle as i32);

    s.client
        .set_destination(pb::SetDestinationRequest {
            destination: Some(dest()),
        })
        .await
        .expect("set");
    // The simulated receiver drives the route, then arrives. Everything is
    // recorded from here, and checked afterwards: a slow machine may drive
    // past a step before the test looks. (The fake answers with a route from
    // elsewhere, so the receiver first jumps from its loop to the route's
    // start; a real route starts where the receiver is.)
    let mut active = Vec::new();
    until(&mut stream, |g| {
        if g.state == pb::RouteState::Active as i32 {
            active.push(g.clone());
        }
        g.state == pb::RouteState::Arrived as i32
    })
    .await;
    let first = active.first().expect("active before arriving");
    assert_eq!(first.route_id, 1);
    assert_eq!(first.destination, Some(dest()));
    let on_route: Vec<(u32, f64)> = active
        .iter()
        .filter_map(|g| g.progress.as_ref())
        .filter(|p| !p.off_route)
        .map(|p| (p.maneuver_index, p.remaining_m))
        .collect();
    assert!(
        on_route.iter().any(|&(m, _)| m >= 5),
        "guided along the route: {on_route:?}"
    );
    // From the route's first 19 km (before it, the receiver may still have
    // been on its loop), the distance left only falls.
    let start = on_route
        .iter()
        .position(|&(m, _)| m <= 3)
        .expect("seen on the route's first maneuvers");
    assert!(
        on_route[start..].windows(2).all(|w| w[1].1 <= w[0].1 + 1.0),
        "the distance left only falls: {on_route:?}"
    );

    // What navigation asked Valhalla.
    let req: serde_json::Value = serde_json::from_str(
        &std::fs::read_to_string(s.dir.join("last-request.json")).expect("request"),
    )
    .expect("json");
    assert_eq!(req["costing"], "auto");
    assert_eq!(req["locations"][1]["lat"], 39.8103);

    // The route stays fetchable after arriving, until cleared.
    let route = s
        .client
        .get_route(pb::GetRouteRequest { route_id: 1 })
        .await
        .expect("route")
        .into_inner()
        .route
        .expect("a route");
    assert_eq!(route.shape.len(), 149);
    assert_eq!(route.maneuvers.len(), 9);
    assert_eq!(
        route.maneuvers[3].instruction,
        "Turn right onto US 36/US 281."
    );
    let missing = s
        .client
        .get_route(pb::GetRouteRequest { route_id: 99 })
        .await
        .unwrap_err();
    assert_eq!(missing.code(), tonic::Code::NotFound);

    s.client
        .clear_route(pb::ClearRouteRequest {})
        .await
        .expect("clear");
    let g = until(&mut stream, |g| g.state == pb::RouteState::Idle as i32).await;
    assert_eq!((g.route_id, g.destination), (0, None));
}

#[tokio::test]
async fn valhalla_errors_are_shown() {
    let mut s = start("fail", "valhalla-3.9.1-error-171.json", 1, true).await;
    let mut stream = s
        .client
        .watch_guidance(pb::WatchGuidanceRequest {})
        .await
        .expect("watch")
        .into_inner();
    s.client
        .set_destination(pb::SetDestinationRequest {
            destination: Some(dest()),
        })
        .await
        .expect("set");
    let g = until(&mut stream, |g| g.state == pb::RouteState::Failed as i32).await;
    assert_eq!(
        g.detail,
        "Valhalla error 171: No suitable edges near location"
    );
    assert_eq!(g.route_id, 0);
    let bad = s
        .client
        .set_destination(pb::SetDestinationRequest {
            destination: Some(pb::LatLon {
                latitude_deg: 91.0,
                longitude_deg: 0.0,
            }),
        })
        .await
        .unwrap_err();
    assert_eq!(bad.code(), tonic::Code::InvalidArgument);
}

#[tokio::test]
async fn no_routing_data_is_unavailable() {
    let mut s = start("nodata", "valhalla-3.9.1-route-auto.json", 0, false).await;
    let mut stream = s
        .client
        .watch_guidance(pb::WatchGuidanceRequest {})
        .await
        .expect("watch")
        .into_inner();
    let g = until(&mut stream, |g| g.state != 0).await;
    assert_eq!(g.state, pb::RouteState::Unavailable as i32);
    assert!(g.detail.starts_with("no routing data at "), "{}", g.detail);
    // The data arrives (a stick, say): routing becomes available.
    std::fs::write(s.dir.join("valhalla_tiles.tar"), b"now").expect("tiles");
    until(&mut stream, |g| g.state == pb::RouteState::Idle as i32).await;
    s.client
        .set_destination(pb::SetDestinationRequest {
            destination: Some(dest()),
        })
        .await
        .expect("set");
    until(&mut stream, |g| g.state == pb::RouteState::Active as i32).await;
}
