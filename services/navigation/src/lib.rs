//! `navigation`: the truck's position (Phase 6.4, ADR-0030) and its routes
//! (6.5.2, ADR-0030 and ADR-0035) for the dashboard.
//!
//! - [`source`] reads gpsd's JSON over TCP, reconnecting on its own, or runs
//!   a simulated receiver ([`sim`]). Both send the same [`source::Event`]s.
//! - [`publisher`] feeds them to the `gpsd` crate's tracker and publishes an
//!   `f250.nav.v1.Position` on every report and once a second.
//! - [`guide`] keeps the destination and the route, follows the truck along
//!   it and asks [`valhalla`] for a new route when it leaves it.
//! - [`search`] answers address and place searches from the offline index
//!   (6.5.3, ADR-0038), ranked from the latest position.
//! - [`server`] serves `PositionService`, `RouteService` and `SearchService`.
//!
//! The dashboard never talks to gpsd; it reads this API (CLAUDE.md rule 5's
//! pattern, ADR-0030 decision 1).

pub mod guide;
pub mod publisher;
pub mod search;
pub mod server;
pub mod sim;
pub mod source;
pub mod valhalla;
