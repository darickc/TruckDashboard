//! Asks a running navigation service to search, as the dashboard does, and
//! prints the answer: a check from a terminal (ADR-0038).
//!
//!   cargo run -p navigation --example search -- tcp:127.0.0.1:50253 "120 n main st"
//!   cargo run -p navigation --example search -- unix:/run/f250-nav/nav.sock "smith center"

use f250_proto::nav::v1 as pb;
use hyper_util::rt::TokioIo;
use pb::search_service_client::SearchServiceClient;
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
    let [endpoint, query] = args.as_slice() else {
        return Err("usage: search ENDPOINT QUERY".into());
    };
    let mut client = SearchServiceClient::new(connect(endpoint).await?);
    let start = std::time::Instant::now();
    let r = client
        .search(pb::SearchRequest {
            query: query.clone(),
            limit: 0,
        })
        .await
        .map_err(|e| e.to_string())?
        .into_inner();
    let ms = start.elapsed().as_secs_f64() * 1000.0;
    if !r.available {
        println!("unavailable: {}", r.detail);
        return Ok(());
    }
    println!(
        "{} results in {ms:.0} ms (round trip); {} · OSM {} · ranked from {:?}{}",
        r.results.len(),
        r.regions.join(", "),
        r.data_date,
        r.ranked_from(),
        if r.ranked_from() == pb::RankedFrom::LastKnown {
            format!(" ({:.0} s old)", r.position_age_s)
        } else {
            String::new()
        }
    );
    for h in &r.results {
        let at = h.location.as_ref().map_or(String::new(), |l| {
            format!("{:.5},{:.5}", l.latitude_deg, l.longitude_deg)
        });
        println!(
            "  {:?}{} {} | {} {} {}{}",
            h.kind(),
            if h.house_number_missing {
                " (no such number)"
            } else {
                ""
            },
            h.title,
            h.subtitle,
            h.distance_m
                .map(|d| format!("{:.1} km", d / 1000.0))
                .unwrap_or_default(),
            at,
            if h.unmatched_words.is_empty() {
                String::new()
            } else {
                format!(" not matched: {}", h.unmatched_words.join(" "))
            }
        );
    }
    Ok(())
}
