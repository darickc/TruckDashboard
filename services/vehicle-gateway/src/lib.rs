//! Vehicle gateway: the only process that talks to the truck.
//!
//! The decision logic lives in plain, clock-free state machines so it can be
//! tested exhaustively without hardware (docs/architecture/diagnostic-recovery.md):
//!
//! - [`poll`]: per-PID health (`ACTIVE → SUSPECT → BACKOFF → QUARANTINED`).
//! - [`scheduler`]: which signal to request next, within a throughput budget.
//! - [`link`]: the per-link state machine and its bounded recovery ladder.
//!
//! Times are `std::time::Duration` since an arbitrary monotonic origin,
//! passed in by the caller.

pub mod config;
pub mod core;
pub mod link;
pub mod poll;
pub mod scheduler;
pub mod server;
pub mod transport;
