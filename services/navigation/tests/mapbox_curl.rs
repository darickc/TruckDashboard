//! navigation's Mapbox client through the real `curl` (ADR-0052), against a
//! local stand-in for api.mapbox.com: the URL and token go to curl on its
//! input, the status and content type come back, a server that never answers
//! times out, and no server at all is "unreachable". The answers are the
//! hand-written test vector, not Mapbox's.
//!
//! Skipped (with a message) where there is no curl.

#![allow(clippy::unwrap_used, clippy::expect_used)]

use std::sync::{Arc, Mutex};
use std::time::Duration;

use navigation::mapbox::{self, Curl, Failure, Fetch, Mapbox, Tiles};
use navigation::valhalla::{Costing, RouteRequest, Units};
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::TcpListener;

const ROUTE: &str = include_str!("data/mapbox-directions-handwritten.json");

fn have_curl() -> bool {
    std::process::Command::new("curl")
        .arg("--version")
        .output()
        .is_ok_and(|o| o.status.success())
}

/// A tiny HTTP/1.1 server: each request line is recorded, and answered by
/// `answer(path)` as (status, content type, body). `None`: never answers.
async fn serve(
    answer: impl Fn(&str) -> Option<(u16, &'static str, Vec<u8>)> + Send + Sync + 'static,
) -> (String, Arc<Mutex<Vec<String>>>) {
    let l = TcpListener::bind("127.0.0.1:0").await.unwrap();
    let base = format!("http://{}", l.local_addr().unwrap());
    let seen = Arc::new(Mutex::new(Vec::new()));
    let seen2 = seen.clone();
    let answer = Arc::new(answer);
    tokio::spawn(async move {
        loop {
            let (mut s, _) = l.accept().await.unwrap();
            let seen = seen2.clone();
            let answer = answer.clone();
            tokio::spawn(async move {
                let mut buf = vec![0u8; 8192];
                let n = s.read(&mut buf).await.unwrap_or(0);
                let head = String::from_utf8_lossy(&buf[..n]).to_string();
                let path = head
                    .lines()
                    .next()
                    .and_then(|l| l.split_whitespace().nth(1))
                    .unwrap_or("")
                    .to_string();
                seen.lock().unwrap().push(path.clone());
                match answer(&path) {
                    Some((status, ctype, body)) => {
                        let h = format!(
                            "HTTP/1.1 {status} X\r\nContent-Type: {ctype}\r\nContent-Length: {}\r\nConnection: close\r\n\r\n",
                            body.len()
                        );
                        let _ = s.write_all(h.as_bytes()).await;
                        let _ = s.write_all(&body).await;
                    }
                    None => tokio::time::sleep(Duration::from_secs(30)).await,
                }
            });
        }
    });
    (base, seen)
}

fn req() -> RouteRequest {
    RouteRequest {
        from: (39.80, -98.60),
        heading_deg: Some(90.0),
        to: (39.8103, -98.5559),
        costing: Costing::Auto,
        units: Units::Imperial,
    }
}

#[tokio::test]
async fn a_route_and_a_tile_through_curl() {
    if !have_curl() {
        eprintln!("skip: no curl");
        return;
    }
    let (base, seen) = serve(|path| {
        if path.starts_with("/directions/v5/mapbox/driving-traffic/") {
            Some((
                200,
                "application/json; charset=utf-8",
                ROUTE.as_bytes().to_vec(),
            ))
        } else if path.starts_with("/styles/v1/mapbox/navigation-day-v1/tiles/512/") {
            Some((200, "image/png", b"\x89PNG\r\n\x1a\nfake".to_vec()))
        } else {
            Some((
                404,
                "application/json",
                br#"{"message":"Not Found"}"#.to_vec(),
            ))
        }
    })
    .await;
    let mut m = Mapbox::new(Curl::default(), "pk.TEST").unwrap();
    m.api = base;
    let m = Arc::new(m);
    let r = m.route(&req()).await.unwrap();
    assert_eq!(r.provider, mapbox::PROVIDER);
    assert_eq!(r.maneuvers.len(), 3);
    let tiles = Tiles::new(Some(m), mapbox::STYLE_DAY, mapbox::STYLE_NIGHT);
    let t = tiles.get(false, 3, 1, 2).await.unwrap();
    assert_eq!(t.content_type, "image/png");
    assert!(t.body.starts_with(b"\x89PNG"));
    // The night style isn't served here: a 404, said without the token.
    let e = tiles.get(true, 3, 1, 2).await.unwrap_err().unwrap();
    assert_eq!(e, "Mapbox tile HTTP 404 Not Found");
    let seen = seen.lock().unwrap().clone();
    assert!(seen[0].contains("access_token=pk.TEST"));
    assert!(seen[0].contains("bearings=90,60;"));
    assert_eq!(
        seen[1],
        "/styles/v1/mapbox/navigation-day-v1/tiles/512/3/1/2?access_token=pk.TEST"
    );
}

#[tokio::test]
async fn a_refused_token_is_unreachable() {
    if !have_curl() {
        eprintln!("skip: no curl");
        return;
    }
    let (base, _) = serve(|_| {
        Some((
            401,
            "application/json",
            br#"{"message":"Not Authorized - Invalid Token"}"#.to_vec(),
        ))
    })
    .await;
    let mut m = Mapbox::new(Curl::default(), "pk.BAD").unwrap();
    m.api = base;
    assert_eq!(
        m.route(&req()).await.unwrap_err(),
        Failure::Unreachable("Mapbox HTTP 401: Not Authorized - Invalid Token".into())
    );
}

#[tokio::test]
async fn no_server_and_a_silent_server() {
    if !have_curl() {
        eprintln!("skip: no curl");
        return;
    }
    // Nothing listens on a port just freed.
    let port = {
        let l = std::net::TcpListener::bind("127.0.0.1:0").unwrap();
        l.local_addr().unwrap().port()
    };
    let curl = Curl::default();
    let e = curl
        .get(
            &format!("http://127.0.0.1:{port}/x?access_token=pk.SECRET"),
            Duration::from_secs(3),
        )
        .await
        .unwrap_err();
    assert!(e.starts_with("curl: (7)"), "{e}");
    assert!(!e.contains("SECRET"));

    let (base, _) = serve(|_| None).await;
    let started = std::time::Instant::now();
    let e = curl
        .get(&format!("{base}/slow"), Duration::from_secs(1))
        .await
        .unwrap_err();
    assert!(e.starts_with("curl: (28)"), "{e}");
    assert!(started.elapsed() < Duration::from_secs(5));
}
