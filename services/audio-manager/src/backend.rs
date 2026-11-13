//! The Bluetooth side, behind a trait: BlueZ over D-Bus on the Pi
//! (`bluez.rs`), a simulated phone on the Mac and in the tests (`sim.rs`).

use tokio::sync::watch;

use crate::model::{Command, CoverArt, Snapshot};

#[tonic::async_trait]
pub trait Bluetooth: Send + Sync {
    /// The current state, replaced as a whole on each change.
    fn snapshot(&self) -> watch::Receiver<Snapshot>;
    /// The connected phone's cover art (ADR-0042), replaced on each change.
    fn cover_art(&self) -> watch::Receiver<CoverArt>;
    /// Makes the adapter discoverable and pairable (`on`), with BlueZ's own
    /// timeouts set to `timeout_s` as a backstop, or neither.
    async fn set_pairing(&self, on: bool, timeout_s: u32) -> Result<(), String>;
    /// Sends a transport command to the connected phone's player.
    async fn control(&self, cmd: Command) -> Result<(), String>;
    /// Marks a phone paired in the window as trusted, so it reconnects
    /// without asking again.
    async fn trust(&self, address: &str) -> Result<(), String>;
    /// Connects a paired phone, disconnecting any other phone first (one
    /// phone at a time). Returns once it is connected or has failed.
    async fn connect(&self, address: &str) -> Result<(), String>;
    /// Disconnects a phone (it stays paired).
    async fn disconnect(&self, address: &str) -> Result<(), String>;
    /// Removes a phone's pairing (BlueZ forgets the device).
    async fn remove(&self, address: &str) -> Result<(), String>;
}
