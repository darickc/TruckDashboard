//! `network`: Wi-Fi for the dashboard (ADR-0052). connman keeps Wi-Fi on the
//! Pi (ADR-0023); this service reads it and asks it to scan, join, leave and
//! forget networks, and serves that as `f250.network.v1.WifiService`.
//!
//! - [`model`] turns connman's properties into the API's messages, and its
//!   error names into words for the driver.
//! - [`connman`] talks to connman on the system D-Bus, with an agent that
//!   hands it the passphrase typed for a network.
//! - [`sim`] is a made-up radio for the Mac and the browser (`--simulate`).
//! - [`runner`] reads the backend every few seconds and right after each
//!   action, and publishes what changed.
//! - [`server`] serves `WifiService`.

use std::future::Future;

use f250_proto::network::v1 as pb;

pub mod connman;
pub mod model;
pub mod runner;
pub mod server;
pub mod sim;

/// Something that keeps Wi-Fi: connman, or the simulation.
pub trait Backend: Send + Sync + 'static {
    /// The state now. Never fails: an unreachable backend is a status with
    /// `available: false` and a reason.
    fn status(&self) -> impl Future<Output = pb::WifiStatus> + Send;
    fn set_enabled(&self, on: bool) -> impl Future<Output = Result<(), String>> + Send;
    fn scan(&self) -> impl Future<Output = Result<(), String>> + Send;
    /// Joins `id`, with `passphrase` if the network asks for one. `Ok` once
    /// connected; `Err` says why not, in the driver's words.
    fn connect(
        &self,
        id: &str,
        passphrase: &str,
    ) -> impl Future<Output = Result<(), String>> + Send;
    fn disconnect(&self, id: &str) -> impl Future<Output = Result<(), String>> + Send;
    fn forget(&self, id: &str) -> impl Future<Output = Result<(), String>> + Send;
}
