//! Builds navigation's offline search index from OpenStreetMap extracts
//! (ADR-0038). `tools/maps/build-search.py` (`make search-region`) downloads
//! the extracts and runs it; the index goes on the map stick.
//!
//! - [`extract`]: which objects are kept, and as what.
//! - [`builder`]: two passes over the PBF files, towns for every row, streets
//!   joined, then the file (`geocode::index::Writer`).
//! - [`states`]: the state each row is in, from OSM's state boundaries.

pub mod builder;
pub mod extract;
pub mod states;
