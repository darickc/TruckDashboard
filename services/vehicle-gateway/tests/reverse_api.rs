//! `WatchReverse` (ADR-0046) through the API, with a scripted `230` reader.
#![allow(clippy::unwrap_used)]

use std::collections::VecDeque;
use std::io;
use std::sync::Arc;
use std::time::Duration;

use f250_proto::vehicle::v1 as pb;
use pb::vehicle_service_server::VehicleService;
use tokio::sync::{mpsc, watch};
use tokio_stream::StreamExt;
use tonic::Request;
use vehicle_gateway::reverse::{self, BoxFuture, Feed, FrameReader, Opener};
use vehicle_gateway::server::Api;

/// Frames at set times, then silence.
struct Script(VecDeque<(Duration, Vec<u8>)>);

impl FrameReader for Script {
    fn recv(&mut self) -> BoxFuture<'_, io::Result<Vec<u8>>> {
        Box::pin(async move {
            match self.0.pop_front() {
                Some((wait, data)) => {
                    tokio::time::sleep(wait).await;
                    Ok(data)
                }
                None => std::future::pending().await,
            }
        })
    }
}

fn api(feed: Feed) -> Api {
    let (cmds, _rx) = mpsc::channel(1);
    let (_tx, snapshots) = watch::channel(Arc::new(pb::Snapshot::default()));
    Api::new(cmds, snapshots).with_reverse(feed)
}

async fn states(api: &Api, n: usize) -> Vec<(i32, String)> {
    let mut s = api
        .watch_reverse(Request::new(pb::WatchReverseRequest {}))
        .await
        .unwrap()
        .into_inner();
    let mut out = Vec::new();
    while out.len() < n {
        let m = tokio::time::timeout(Duration::from_secs(3), s.next())
            .await
            .unwrap()
            .unwrap()
            .unwrap();
        out.push((m.state, m.detail));
    }
    out
}

#[tokio::test]
async fn reports_reverse_then_unknown_when_the_broadcast_stops() {
    let ms = Duration::from_millis;
    let opener: Opener = Arc::new(move || {
        Box::pin(async move {
            Ok(Box::new(Script(
                vec![(ms(0), vec![0xF0]), (ms(50), vec![0x10])].into(),
            )) as Box<dyn FrameReader>)
        })
    });
    let feed = reverse::spawn("can0", ms(300), opener);
    let got = states(&api(feed), 12).await;
    let seen: Vec<i32> = got.iter().map(|g| g.0).collect();
    let engaged = pb::ReverseState::Engaged as i32;
    let unknown = pb::ReverseState::Unknown as i32;
    let at = seen.iter().position(|s| *s == engaged).unwrap();
    // After the last frame, silence: unknown, never "not engaged".
    let then = &seen[at..];
    assert!(then.contains(&unknown), "{got:?}");
    assert!(
        !then.contains(&(pb::ReverseState::NotEngaged as i32)),
        "{got:?}"
    );
    let last = got.last().unwrap();
    assert!(last.1.starts_with("no 230 frame for"), "{last:?}");
}

#[tokio::test]
async fn messages_keep_coming_while_nothing_changes() {
    let feed = Feed::absent("--transport sim: no CAN broadcast to read");
    let start = tokio::time::Instant::now();
    let got = states(&api(feed), 4).await;
    // One at once, then one every 100 ms: not sooner. With no reader the
    // stream once sent as fast as it was read (a core each in the gateway
    // and camera-manager, bench Pi 2026-11-19), which only a lower bound
    // catches.
    let took = start.elapsed();
    assert!(
        took >= Duration::from_millis(250),
        "4 messages in {took:?}: a flood"
    );
    assert!(took < Duration::from_millis(1000), "{took:?}");
    for (state, detail) in got {
        assert_eq!(state, pb::ReverseState::Unknown as i32);
        assert_eq!(detail, "--transport sim: no CAN broadcast to read");
    }
}
