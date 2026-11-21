//! A one-way link from the 5-way switch to another service: camera-manager
//! for long presses ([`camera_link`](crate::camera_link)), audio-manager for
//! short ones ([`audio_link`](crate::audio_link)).
//!
//! The power key comes first. Nothing here can hold up the main loop:
//!
//! - [`Link::send`] never waits. Presses go into a short queue; when it is
//!   full the press is dropped and the caller logs it.
//! - One task makes the calls, each with a timeout ([`LinkConfig::call_timeout`]).
//! - A press that waited longer than [`LinkConfig::max_age`] is dropped, not
//!   sent: a camera change or a skip the driver asked for seconds ago is a
//!   surprise, not a help.
//! - A press that fails isn't retried. The driver presses again.
//!
//! The connection is lazy: power-manager starts and runs without the other
//! service, and finds it once it is there, or again after it restarts.
//!
//! Both times are example values, not measured requirements.

use std::future::Future;
use std::time::Duration;

use hyper_util::rt::TokioIo;
use tokio::sync::mpsc;
use tokio::time::Instant;
use tonic::transport::{Channel, Endpoint, Uri};

/// How many presses may wait for the call before newer ones are dropped.
const QUEUE: usize = 4;

#[derive(Debug, Clone)]
pub struct LinkConfig {
    /// `unix:PATH` or `tcp:HOST:PORT`.
    pub endpoint: String,
    /// Connecting plus the call. An example value.
    pub call_timeout: Duration,
    /// A press older than this when its turn comes is dropped. An example
    /// value.
    pub max_age: Duration,
}

/// What became of one press.
#[derive(Debug, Clone, PartialEq)]
pub enum Outcome {
    /// The service took it; what it answered, in words.
    Delivered(String),
    /// The service refused it, said why, or the call failed or timed out.
    Failed(String),
    /// It waited too long behind other calls and wasn't sent.
    TooOld(Duration),
}

/// Why [`Link::send`] didn't queue a press.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum NotQueued {
    /// Calls are slower than the switch: the press is dropped.
    QueueFull,
    /// The task ended (it shouldn't).
    Closed,
}

/// The sending side. Dropping it ends the task once the queue is empty.
#[derive(Debug)]
pub struct Link<T> {
    tx: mpsc::Sender<(T, Instant)>,
}

impl<T> Clone for Link<T> {
    fn clone(&self) -> Self {
        Link {
            tx: self.tx.clone(),
        }
    }
}

impl<T: Clone + Send + 'static> Link<T> {
    /// Starts the task that makes the calls: `call` for each item, within
    /// the call timeout, then `report` with what became of it.
    pub fn spawn<C, F, R>(cfg: &LinkConfig, call: C, mut report: R) -> Link<T>
    where
        C: Fn(T) -> F + Send + 'static,
        F: Future<Output = Outcome> + Send,
        R: FnMut(T, Outcome) + Send + 'static,
    {
        let (tx, mut rx) = mpsc::channel::<(T, Instant)>(QUEUE);
        let (timeout, max_age) = (cfg.call_timeout, cfg.max_age);
        tokio::spawn(async move {
            while let Some((item, at)) = rx.recv().await {
                let waited = at.elapsed();
                let outcome = if waited > max_age {
                    Outcome::TooOld(waited)
                } else {
                    match tokio::time::timeout(timeout, call(item.clone())).await {
                        Ok(o) => o,
                        Err(_) => {
                            Outcome::Failed(format!("no answer in {} ms", timeout.as_millis()))
                        }
                    }
                };
                report(item, outcome);
            }
        });
        Link { tx }
    }

    /// Queues an item without waiting.
    pub fn send(&self, item: T) -> Result<(), NotQueued> {
        self.tx
            .try_send((item, Instant::now()))
            .map_err(|e| match e {
                mpsc::error::TrySendError::Full(_) => NotQueued::QueueFull,
                mpsc::error::TrySendError::Closed(_) => NotQueued::Closed,
            })
    }
}

/// A status without tonic's debug noise: the code, then the message.
pub fn status_text(status: &tonic::Status) -> String {
    let message = status.message();
    if message.is_empty() {
        format!("{:?}", status.code())
    } else {
        format!("{:?}: {message}", status.code())
    }
}

/// A channel that connects on first use and again after a failure. `flag`
/// names the option, for the error.
pub fn channel(cfg: &LinkConfig, flag: &str) -> Result<Channel, String> {
    let endpoint = &cfg.endpoint;
    if let Some(path) = endpoint.strip_prefix("unix:") {
        let path = path.to_string();
        Ok(Endpoint::from_static("http://localhost")
            .connect_timeout(cfg.call_timeout)
            .connect_with_connector_lazy(tower::service_fn(move |_: Uri| {
                let path = path.clone();
                async move {
                    tokio::net::UnixStream::connect(path)
                        .await
                        .map(TokioIo::new)
                }
            })))
    } else if let Some(addr) = endpoint.strip_prefix("tcp:") {
        Ok(Endpoint::try_from(format!("http://{addr}"))
            .map_err(|e| format!("bad {flag} {endpoint}: {e}"))?
            .connect_timeout(cfg.call_timeout)
            .connect_lazy())
    } else {
        Err(format!(
            "{flag} must start with unix: or tcp:, got {endpoint}"
        ))
    }
}

#[allow(clippy::unwrap_used, clippy::expect_used)]
#[cfg(test)]
mod tests {
    use super::*;

    fn cfg(timeout_ms: u64, max_age_ms: u64) -> LinkConfig {
        LinkConfig {
            endpoint: "tcp:127.0.0.1:1".into(),
            call_timeout: Duration::from_millis(timeout_ms),
            max_age: Duration::from_millis(max_age_ms),
        }
    }

    #[test]
    fn a_bad_endpoint_is_refused() {
        let mut c = cfg(100, 1000);
        c.endpoint = "/run/f250-camera/camera.sock".into();
        let err = channel(&c, "--camera-manager").expect_err("no scheme");
        assert!(
            err.contains("--camera-manager must start with unix: or tcp:"),
            "{err}"
        );
    }
}
