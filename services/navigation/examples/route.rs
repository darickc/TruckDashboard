//! Asks a running navigation service for a route and prints its guidance:
//! a check from a terminal, without the dashboard.
//!
//!   cargo run -p navigation --example route -- tcp:127.0.0.1:50253 39.8103 -98.5559
//!   cargo run -p navigation --example route -- unix:/run/f250-nav/nav.sock 39.8103 -98.5559
//!
//! Ends on arrival, failure or after 30 s with no change of state.

use std::time::Duration;

use f250_proto::nav::v1 as pb;
use hyper_util::rt::TokioIo;
use pb::route_service_client::RouteServiceClient;
use tonic::transport::{Channel, Endpoint, Uri};

async fn connect(endpoint: &str) -> Result<Channel, String> {
    if let Some(path) = endpoint.strip_prefix("unix:") {
        let path = path.to_string();
        Endpoint::from_static("http://localhost")
            .connect_with_connector(tower::service_fn(move |_: Uri| {
                let path = path.clone();
                async move {
                    tokio::net::UnixStream::connect(path)
                        .await
                        .map(TokioIo::new)
                }
            }))
            .await
            .map_err(|e| e.to_string())
    } else if let Some(addr) = endpoint.strip_prefix("tcp:") {
        Endpoint::from_shared(format!("http://{addr}"))
            .map_err(|e| e.to_string())?
            .connect()
            .await
            .map_err(|e| e.to_string())
    } else {
        Err("the endpoint must start with unix: or tcp:".into())
    }
}

#[tokio::main(flavor = "current_thread")]
async fn main() -> Result<(), String> {
    let args: Vec<String> = std::env::args().skip(1).collect();
    let [endpoint, lat, lon] = args.as_slice() else {
        return Err("usage: route ENDPOINT LAT LON".into());
    };
    let to = pb::LatLon {
        latitude_deg: lat.parse().map_err(|e| format!("LAT: {e}"))?,
        longitude_deg: lon.parse().map_err(|e| format!("LON: {e}"))?,
    };
    let mut client = RouteServiceClient::new(connect(endpoint).await?);
    let mut stream = client
        .watch_guidance(pb::WatchGuidanceRequest {})
        .await
        .map_err(|e| e.to_string())?
        .into_inner();
    let started = std::time::Instant::now();
    client
        .set_destination(pb::SetDestinationRequest {
            destination: Some(to),
        })
        .await
        .map_err(|e| e.to_string())?;
    let mut route: Option<pb::Route> = None;
    let mut last_state = -1;
    loop {
        let g = match tokio::time::timeout(Duration::from_secs(30), stream.message()).await {
            Ok(Ok(Some(r))) => r.guidance.unwrap_or_default(),
            Ok(Ok(None)) => return Err("the service ended the stream".into()),
            Ok(Err(e)) => return Err(e.to_string()),
            Err(_) => return Err("nothing for 30 s".into()),
        };
        let state = pb::RouteState::try_from(g.state).unwrap_or_default();
        if g.route_id != 0 && route.as_ref().map(|r| r.id) != Some(g.route_id) {
            let r = client
                .get_route(pb::GetRouteRequest {
                    route_id: g.route_id,
                })
                .await
                .map_err(|e| e.to_string())?
                .into_inner()
                .route
                .ok_or("no route")?;
            println!(
                "route {} after {:.1} s: {:.1} km, {:.0} min, {} points, {} maneuvers, costing {}",
                r.id,
                started.elapsed().as_secs_f64(),
                r.length_m / 1000.0,
                r.time_s / 60.0,
                r.shape.len(),
                r.maneuvers.len(),
                r.costing
            );
            for (i, m) in r.maneuvers.iter().enumerate() {
                println!("  {i:2}  {:7.0} m  {}", m.start_m, m.instruction);
            }
            route = Some(r);
        }
        if g.state != last_state {
            println!("{:?} {}", state, g.detail);
            last_state = g.state;
        }
        if let (Some(p), Some(r)) = (&g.progress, &route) {
            let next = r.maneuvers.get(p.maneuver_index as usize);
            println!(
                "  in {:5.0} m: {}  ({:.1} km, {:.0} min left; {:.0} m off the line)",
                p.to_maneuver_m,
                next.map_or("", |m| m.instruction.as_str()),
                p.remaining_m / 1000.0,
                p.remaining_s / 60.0,
                p.off_route_m
            );
        }
        match state {
            pb::RouteState::Arrived | pb::RouteState::Failed | pb::RouteState::Unavailable => {
                return Ok(());
            }
            _ => {}
        }
    }
}
