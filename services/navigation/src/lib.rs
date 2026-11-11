//! `navigation`: the truck's position (Phase 6.4) for the dashboard, and in
//! 6.5.2 its routes (ADR-0030).
//!
//! - [`source`] reads gpsd's JSON over TCP, reconnecting on its own, or runs
//!   a simulated receiver ([`sim`]). Both send the same [`source::Event`]s.
//! - [`publisher`] feeds them to the `gpsd` crate's tracker and publishes an
//!   `f250.nav.v1.Position` on every report and once a second.
//! - [`server`] serves `PositionService`.
//!
//! The dashboard never talks to gpsd; it reads this API (CLAUDE.md rule 5's
//! pattern, ADR-0030 decision 1).

pub mod publisher;
pub mod server;
pub mod sim;
pub mod source;
