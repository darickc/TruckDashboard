//! Automatic reverse (ADR-0046): follows vehicle-gateway's `WatchReverse`
//! and hands each message to the control loop as a policy input.
//!
//! - Engaged / not engaged → [`Input::Reverse`]; unknown →
//!   [`Input::ReverseInvalid`]. camera-policy debounces, holds and treats a
//!   silence longer than `rev_stale` as unknown on its own, so a stuck stream
//!   can't leave "not engaged" standing.
//! - No connection, or the stream ends: unknown, and a new try every
//!   [`RETRY_AFTER`]. A gateway that isn't running yet is normal at boot.
//!
//! It only reads: `WatchReverse` asks the gateway for nothing on the bus
//! (ADR-0026 decision 5: camera-manager never asks the gateway to transmit).

use std::time::Duration;

use camera_policy::Input;
use f250_proto::vehicle::v1 as vpb;
use hyper_util::rt::TokioIo;
use tokio::sync::mpsc;
use tokio_stream::StreamExt;
use tonic::transport::{Channel, Endpoint, Uri};

use crate::manager::Command;

/// Wait between connection attempts.
pub const RETRY_AFTER: Duration = Duration::from_secs(2);
const CONNECT_TIMEOUT: Duration = Duration::from_secs(3);

/// The policy input for one message, and its state for the log.
pub fn input_of(m: &vpb::WatchReverseResponse) -> (Input, &'static str) {
    match vpb::ReverseState::try_from(m.state) {
        Ok(vpb::ReverseState::Engaged) => (Input::Reverse(true), "engaged"),
        Ok(vpb::ReverseState::NotEngaged) => (Input::Reverse(false), "not engaged"),
        _ => (Input::ReverseInvalid, "unknown"),
    }
}

/// Connects to `unix:PATH` or `tcp:HOST:PORT`.
pub async fn connect(endpoint: &str) -> Result<Channel, String> {
    let fut = async {
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
            Endpoint::try_from(format!("http://{addr}"))
                .map_err(|e| e.to_string())?
                .connect()
                .await
                .map_err(|e| e.to_string())
        } else {
            Err(format!("must start with unix: or tcp:, got {endpoint}"))
        }
    };
    match tokio::time::timeout(CONNECT_TIMEOUT, fut).await {
        Ok(r) => r,
        Err(_) => Err("timed out".into()),
    }
}

/// Runs until the loop stops (its command channel closes).
pub async fn follow(endpoint: String, tx: mpsc::Sender<Command>) {
    let mut last_problem = String::new();
    loop {
        let problem = match stream_once(&endpoint, &tx).await {
            Ok(()) => return, // the loop stopped
            Err(p) => p,
        };
        let detail = format!("gateway {endpoint}: {problem}");
        if detail != last_problem {
            eprintln!(
                "[camera] reverse: unknown ({detail}); retrying every {} s",
                RETRY_AFTER.as_secs()
            );
            last_problem = detail.clone();
        }
        if tx
            .send(Command::Reverse {
                input: Input::ReverseInvalid,
                detail,
            })
            .await
            .is_err()
        {
            return;
        }
        tokio::time::sleep(RETRY_AFTER).await;
    }
}

/// One connection. `Ok` only when the loop has stopped; `Err` says why the
/// stream ended.
async fn stream_once(endpoint: &str, tx: &mpsc::Sender<Command>) -> Result<(), String> {
    let ch = connect(endpoint).await?;
    let mut client = vpb::vehicle_service_client::VehicleServiceClient::new(ch);
    let mut stream = client
        .watch_reverse(vpb::WatchReverseRequest {})
        .await
        .map_err(|s| s.message().to_string())?
        .into_inner();
    eprintln!("[camera] reverse: following the gateway at {endpoint}");
    let mut last: Option<&'static str> = None;
    while let Some(m) = stream.next().await {
        let m = m.map_err(|s| s.message().to_string())?;
        let (input, state) = input_of(&m);
        if last != Some(state) {
            eprintln!("[camera] reverse: {state} ({})", m.detail);
            last = Some(state);
        }
        if tx
            .send(Command::Reverse {
                input,
                detail: m.detail,
            })
            .await
            .is_err()
        {
            return Ok(());
        }
    }
    Err("the stream ended".into())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn msg(state: vpb::ReverseState) -> vpb::WatchReverseResponse {
        vpb::WatchReverseResponse {
            state: state as i32,
            ..Default::default()
        }
    }

    #[test]
    fn only_a_known_state_is_a_sample() {
        assert_eq!(
            input_of(&msg(vpb::ReverseState::Engaged)).0,
            Input::Reverse(true)
        );
        assert_eq!(
            input_of(&msg(vpb::ReverseState::NotEngaged)).0,
            Input::Reverse(false)
        );
        assert_eq!(
            input_of(&msg(vpb::ReverseState::Unknown)).0,
            Input::ReverseInvalid
        );
        assert_eq!(
            input_of(&msg(vpb::ReverseState::Unspecified)).0,
            Input::ReverseInvalid
        );
        let odd = vpb::WatchReverseResponse {
            state: 99,
            ..Default::default()
        };
        assert_eq!(input_of(&odd).0, Input::ReverseInvalid);
    }
}
