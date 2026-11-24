//! `navigation`: the truck's position (Phase 6.4, ADR-0030) and its routes
//! (6.5.2, ADR-0030 and ADR-0035) for the dashboard.
//!
//! - [`source`] reads gpsd's JSON over TCP, reconnecting on its own, or runs
//!   a simulated receiver ([`sim`]). Both send the same [`source::Event`]s.
//! - [`publisher`] feeds them to the `gpsd` crate's tracker and publishes an
//!   `f250.nav.v1.Position` on every report and once a second.
//! - [`guide`] keeps the destination and the route, follows the truck along
//!   it and asks [`valhalla`] for a new route when it leaves it.
//! - [`mapbox`] routes with Mapbox first while there is a network, Valhalla
//!   otherwise, and fetches the online map's tiles (ADR-0052).
//! - [`search`] answers address and place searches from the offline index
//!   (6.5.3, ADR-0038), ranked from the latest position.
//! - [`places`] keeps Home, favourites and recent destinations on the data
//!   drive (6.5.2, ADR-0040).
//! - [`voice`] speaks the directions from Valhalla's own words, only from a
//!   current position (6.5.2, ADR-0040).
//! - [`server`] serves `PositionService`, `RouteService`, `SearchService`,
//!   `PlacesService` and `OnlineMapService`.
//!
//! The dashboard never talks to gpsd; it reads this API (CLAUDE.md rule 5's
//! pattern, ADR-0030 decision 1).

pub mod audio_speaker;
pub mod guide;
pub mod mapbox;
pub mod mapbox_search;
pub mod mapbox_vector;
pub mod places;
pub mod publisher;
pub mod search;
pub mod server;
pub mod sim;
pub mod source;
pub mod valhalla;
pub mod voice;
