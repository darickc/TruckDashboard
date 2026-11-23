//! Reads the backend every [`POLL`] and right after each action, and
//! publishes the status when it changed.

use std::sync::Arc;
use std::time::Duration;

use f250_proto::network::v1 as pb;
use tokio::sync::{Notify, watch};

use crate::Backend;

/// connman changes by itself (a network appears, the hotspot drops); this
/// is how soon the screen sees it. An example.
pub const POLL: Duration = Duration::from_secs(3);

pub async fn run<B: Backend>(
    backend: Arc<B>,
    poll: Duration,
    poke: Arc<Notify>,
    out: watch::Sender<pb::WifiStatus>,
    heartbeat: Option<f250_sd_notify::Heartbeat>,
) {
    let mut last_detail = String::new();
    loop {
        let s = backend.status().await;
        if s.detail != last_detail && !s.available {
            eprintln!("[network] {}", s.detail);
        }
        last_detail.clone_from(&s.detail);
        out.send_if_modified(|cur| {
            if *cur == s {
                false
            } else {
                *cur = s;
                true
            }
        });
        if let Some(h) = &heartbeat {
            h.beat();
        }
        tokio::select! {
            () = tokio::time::sleep(poll) => {}
            () = poke.notified() => {}
        }
    }
}
