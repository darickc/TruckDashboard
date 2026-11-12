//! Offline address and place search for navigation (ADR-0038).
//!
//! One SQLite file holds OpenStreetMap's addresses, named streets, towns and
//! named places for a region, with an FTS5 full-text index over their words.
//! `tools/search-index` builds it on the Mac from the same Geofabrik extract
//! as the routing data; `services/navigation` searches it and ranks the
//! answers near the truck.
//!
//! - [`text`]: the words of a name, and their common US abbreviations, the
//!   same on both sides (the builder and the search).
//! - [`index`]: the file's schema and the writer the builder uses.
//! - [`search`]: a query, read against the index and ranked.
//!
//! Coverage is only what OpenStreetMap has. House numbers are sparse outside
//! towns, so a search often finds only the street or the town; every result
//! says which.

pub mod index;
pub mod search;
pub mod text;

/// Great-circle distance in metres (haversine, mean Earth radius).
pub fn distance_m(a: (f64, f64), b: (f64, f64)) -> f64 {
    const R: f64 = 6_371_008.8;
    let (la1, lo1) = (a.0.to_radians(), a.1.to_radians());
    let (la2, lo2) = (b.0.to_radians(), b.1.to_radians());
    let h = ((la2 - la1) / 2.0).sin().powi(2)
        + la1.cos() * la2.cos() * ((lo2 - lo1) / 2.0).sin().powi(2);
    2.0 * R * h.sqrt().min(1.0).asin()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn distance_one_degree_of_latitude() {
        let d = distance_m((40.0, -100.0), (41.0, -100.0));
        assert!((d - 111_195.0).abs() < 100.0, "{d}");
        assert_eq!(distance_m((40.0, -100.0), (40.0, -100.0)), 0.0);
    }
}
