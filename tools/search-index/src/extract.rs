//! Which OpenStreetMap objects go into the search index, and as what.
//!
//! - `place=city|town|village|hamlet|suburb|quarter|neighbourhood|locality`
//!   with a name: a town.
//! - A way with `highway` of a road type and a `name` (else a `ref`): a
//!   street. Links (`*_link`), paths and footways are left out.
//! - A name and one of `amenity`, `shop`, `tourism`, `leisure`, `aeroway`,
//!   `office`, `healthcare`, `historic`, `craft` or `railway=station`: a named
//!   place, with its address if it has one. Street furniture (benches,
//!   parking, toilets, …) is left out.
//! - Otherwise `addr:housenumber` with `addr:street`: an address.
//!
//! Relations (multipolygons, routes) are not read: a place mapped only as a
//! multipolygon is missing. Address interpolation lines are not read either.

/// One object's part in the index, before it has a position.
#[derive(Clone, Debug, PartialEq)]
pub enum Feature {
    Town {
        name: String,
        category: String,
        population: Option<u64>,
    },
    Street {
        name: String,
    },
    Poi {
        name: String,
        category: String,
        addr: Option<Addr>,
    },
    Address(Addr),
}

#[derive(Clone, Debug, PartialEq)]
pub struct Addr {
    pub number: String,
    pub street: String,
    /// `addr:city`, if tagged.
    pub city: Option<String>,
}

const PLACES: &[&str] = &[
    "city",
    "town",
    "village",
    "hamlet",
    "suburb",
    "quarter",
    "neighbourhood",
    "locality",
];

const ROADS: &[&str] = &[
    "motorway",
    "trunk",
    "primary",
    "secondary",
    "tertiary",
    "unclassified",
    "residential",
    "living_street",
    "service",
    "road",
    "track",
];

/// Keys that make a named object a place worth searching for, in the order
/// their value becomes its category.
const POI_KEYS: &[&str] = &[
    "amenity",
    "shop",
    "tourism",
    "leisure",
    "aeroway",
    "office",
    "healthcare",
    "historic",
    "craft",
    "railway",
];

/// Named things nobody drives to.
const AMENITY_SKIP: &[&str] = &[
    "parking",
    "parking_space",
    "parking_entrance",
    "bench",
    "waste_basket",
    "waste_disposal",
    "recycling",
    "toilets",
    "bicycle_parking",
    "motorcycle_parking",
    "vending_machine",
    "drinking_water",
    "shelter",
    "hunting_stand",
    "telephone",
    "post_box",
    "fountain",
    "clock",
    "loading_dock",
    "water_point",
    "bbq",
];

const LEISURE: &[&str] = &[
    "park",
    "stadium",
    "golf_course",
    "sports_centre",
    "nature_reserve",
    "marina",
    "fairground",
    "water_park",
    "fitness_centre",
    "ice_rink",
    "swimming_pool",
];

/// What `tags` makes this object, if anything. `is_way` lets roads count.
pub fn classify(tags: &[(&str, &str)], is_way: bool) -> Option<Feature> {
    let get = |k: &str| {
        tags.iter()
            .find(|(key, _)| *key == k)
            .map(|(_, v)| v.trim())
            .filter(|v| !v.is_empty())
    };
    let name = get("name");

    if let (Some(place), Some(name)) = (get("place"), name)
        && PLACES.contains(&place)
    {
        return Some(Feature::Town {
            name: name.to_string(),
            category: place.to_string(),
            population: get("population").and_then(|p| p.replace([',', ' '], "").parse().ok()),
        });
    }

    if is_way && let Some(hw) = get("highway") {
        if !ROADS.contains(&hw) {
            return None;
        }
        let name = name.or_else(|| get("ref").and_then(|r| r.split(';').next()).map(str::trim))?;
        return Some(Feature::Street {
            name: name.to_string(),
        });
    }

    let addr = match (get("addr:housenumber"), get("addr:street")) {
        (Some(n), Some(s)) if get("addr:interpolation").is_none() => Some(Addr {
            number: n.to_string(),
            street: s.to_string(),
            city: get("addr:city").map(str::to_string),
        }),
        _ => None,
    };

    if let Some(name) = name {
        for key in POI_KEYS {
            let Some(value) = get(key) else { continue };
            let wanted = match *key {
                "amenity" => !AMENITY_SKIP.contains(&value),
                "leisure" => LEISURE.contains(&value),
                "tourism" => value != "information",
                "railway" => value == "station",
                _ => true,
            };
            if wanted {
                let category = if value == "yes" { *key } else { value };
                return Some(Feature::Poi {
                    name: name.to_string(),
                    category: category.to_string(),
                    addr,
                });
            }
        }
    }
    addr.map(Feature::Address)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn addr(n: &str, s: &str, c: Option<&str>) -> Addr {
        Addr {
            number: n.into(),
            street: s.into(),
            city: c.map(str::to_string),
        }
    }

    #[test]
    fn towns() {
        assert_eq!(
            classify(
                &[
                    ("place", "town"),
                    ("name", "Fairview"),
                    ("population", "2,150")
                ],
                false
            ),
            Some(Feature::Town {
                name: "Fairview".into(),
                category: "town".into(),
                population: Some(2150)
            })
        );
        assert_eq!(classify(&[("place", "town")], false), None);
        assert_eq!(classify(&[("place", "island"), ("name", "X")], false), None);
    }

    #[test]
    fn streets_are_named_road_ways() {
        let main = Some(Feature::Street {
            name: "North Main Street".into(),
        });
        assert_eq!(
            classify(
                &[("highway", "residential"), ("name", "North Main Street")],
                true
            ),
            main
        );
        // A node with a highway tag (a stop sign) is not a street.
        assert_eq!(classify(&[("highway", "stop"), ("name", "X")], false), None);
        assert_eq!(
            classify(&[("highway", "residential"), ("name", "X")], false),
            None
        );
        assert_eq!(
            classify(&[("highway", "footway"), ("name", "Park Path")], true),
            None
        );
        assert_eq!(
            classify(&[("highway", "primary_link"), ("name", "US 36")], true),
            None
        );
        assert_eq!(classify(&[("highway", "residential")], true), None);
        assert_eq!(
            classify(&[("highway", "primary"), ("ref", "US 36;US 281")], true),
            Some(Feature::Street {
                name: "US 36".into()
            })
        );
    }

    #[test]
    fn named_places_with_and_without_addresses() {
        assert_eq!(
            classify(
                &[
                    ("amenity", "fuel"),
                    ("name", "Casey's"),
                    ("addr:housenumber", "200"),
                    ("addr:street", "North Main Street"),
                ],
                false
            ),
            Some(Feature::Poi {
                name: "Casey's".into(),
                category: "fuel".into(),
                addr: Some(addr("200", "North Main Street", None)),
            })
        );
        assert_eq!(
            classify(&[("shop", "yes"), ("name", "Corner Store")], true),
            Some(Feature::Poi {
                name: "Corner Store".into(),
                category: "shop".into(),
                addr: None
            })
        );
        // Benches and unnamed shops are not.
        assert_eq!(
            classify(&[("amenity", "bench"), ("name", "In memory of")], false),
            None
        );
        assert_eq!(classify(&[("shop", "bakery")], false), None);
        assert_eq!(
            classify(&[("leisure", "pitch"), ("name", "Field 2")], false),
            None
        );
        assert_eq!(
            classify(&[("railway", "level_crossing"), ("name", "X")], false),
            None
        );
    }

    #[test]
    fn addresses() {
        assert_eq!(
            classify(
                &[
                    ("building", "house"),
                    ("addr:housenumber", "120"),
                    ("addr:street", "North Main Street"),
                    ("addr:city", "Fairview"),
                ],
                true
            ),
            Some(Feature::Address(addr(
                "120",
                "North Main Street",
                Some("Fairview")
            )))
        );
        // A named house is still an address.
        assert!(matches!(
            classify(
                &[
                    ("name", "The Smiths"),
                    ("addr:housenumber", "1"),
                    ("addr:street", "Elm Avenue")
                ],
                false
            ),
            Some(Feature::Address(_))
        ));
        assert_eq!(classify(&[("addr:housenumber", "120")], false), None);
        assert_eq!(
            classify(&[("addr:street", "Elm"), ("addr:housenumber", " ")], false),
            None
        );
        assert_eq!(
            classify(
                &[
                    ("addr:interpolation", "even"),
                    ("addr:housenumber", "1"),
                    ("addr:street", "Elm")
                ],
                true
            ),
            None
        );
    }
}
