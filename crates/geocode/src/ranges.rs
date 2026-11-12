//! US Census Bureau address ranges (TIGER/Line ADDRFEAT, ADR-0041): which
//! side of a street's piece holds a house number, and where along it.
//!
//! Each piece of street between two crossings (an "edge") may carry a range
//! on its left and on its right side: "from" at the piece's first point and
//! "to" at its last (checked against the data: neighbouring pieces meet at
//! matching numbers in 14,162 of 14,205 joins in three counties, ADR-0041).
//! A range may run either way ("4498" to "4400"), and holds only odd, only
//! even or both kinds of numbers. A number inside a range is placed by
//! linear interpolation between the ends: an estimate of where the house
//! is, not a mapped address. Ranges are potential numbers, so a number
//! inside one may not exist on the ground.

use crate::line;

/// Which numbers a range holds (TIGER's PARITYL/PARITYR).
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Parity {
    Odd = 1,
    Even = 2,
    Both = 3,
}

impl Parity {
    /// TIGER's code ("O", "E", "B"); without one, what the ends say: both
    /// odd, both even, or mixed.
    pub fn from_code(code: &str, from: u32, to: u32) -> Parity {
        match code {
            "O" => Parity::Odd,
            "E" => Parity::Even,
            "B" => Parity::Both,
            _ => match (from % 2, to % 2) {
                (1, 1) => Parity::Odd,
                (0, 0) => Parity::Even,
                _ => Parity::Both,
            },
        }
    }

    pub fn from_i64(v: i64) -> Parity {
        match v {
            1 => Parity::Odd,
            2 => Parity::Even,
            _ => Parity::Both,
        }
    }

    pub fn holds(self, n: u32) -> bool {
        match self {
            Parity::Odd => !n.is_multiple_of(2),
            Parity::Even => n.is_multiple_of(2),
            Parity::Both => true,
        }
    }
}

/// One side's range.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Side {
    /// The number at the piece's first point.
    pub from: u32,
    /// The number at its last point.
    pub to: u32,
    pub parity: Parity,
    /// The side's ZIP code, as a number (00501 is 501).
    pub zip: Option<u32>,
}

impl Side {
    /// How far along the piece `n` is (0 at the first point, 1 at the
    /// last), if this side holds it. A range of one number puts it in the
    /// middle.
    pub fn fraction(&self, n: u32) -> Option<f64> {
        let (lo, hi) = (self.from.min(self.to), self.from.max(self.to));
        if n < lo || n > hi || !self.parity.holds(n) {
            return None;
        }
        if self.from == self.to {
            return Some(0.5);
        }
        Some((f64::from(n) - f64::from(self.from)) / (f64::from(self.to) - f64::from(self.from)))
    }
}

/// A piece of street between two crossings and its ranges.
#[derive(Clone, Debug, PartialEq)]
pub struct Edge {
    /// Its points, first to last ([`line::encode`]d in the index).
    pub line: Vec<(f64, f64)>,
    pub left: Option<Side>,
    pub right: Option<Side>,
}

/// Where `n` is on one of `edges`: the position, and that side's ZIP code.
/// A side whose ZIP code is `zip` comes first, then the first side that
/// holds it, in the edges' order.
pub fn locate(edges: &[Edge], n: u32, zip: Option<u32>) -> Option<((f64, f64), Option<u32>)> {
    let mut first = None;
    for e in edges {
        for side in [&e.left, &e.right].into_iter().flatten() {
            let Some(t) = side.fraction(n) else {
                continue;
            };
            let Some(at) = line::along(&e.line, t) else {
                continue;
            };
            if zip.is_some() && side.zip == zip {
                return Some((at, side.zip));
            }
            first.get_or_insert((at, side.zip));
        }
    }
    first
}

/// A ZIP code as five digits ("00501").
pub fn zip_text(zip: u32) -> String {
    format!("{zip:05}")
}

#[cfg(test)]
#[allow(clippy::unwrap_used)]
mod tests {
    use super::*;

    fn side(from: u32, to: u32, parity: &str, zip: Option<u32>) -> Side {
        Side {
            from,
            to,
            parity: Parity::from_code(parity, from, to),
            zip,
        }
    }

    #[test]
    fn parity_from_the_code_or_the_ends() {
        assert_eq!(Parity::from_code("O", 100, 198), Parity::Odd);
        assert_eq!(Parity::from_code("E", 1, 99), Parity::Even);
        assert_eq!(Parity::from_code("B", 1, 99), Parity::Both);
        assert_eq!(Parity::from_code("", 101, 199), Parity::Odd);
        assert_eq!(Parity::from_code("", 100, 198), Parity::Even);
        assert_eq!(Parity::from_code("", 100, 199), Parity::Both);
        for p in [Parity::Odd, Parity::Even, Parity::Both] {
            assert_eq!(Parity::from_i64(p as i64), p);
        }
    }

    #[test]
    fn odd_and_even_sides() {
        let left = side(101, 199, "O", None);
        let right = side(100, 198, "E", None);
        assert_eq!(left.fraction(101), Some(0.0));
        assert_eq!(left.fraction(199), Some(1.0));
        assert_eq!(left.fraction(150), None, "even number on the odd side");
        assert_eq!(right.fraction(150), Some(50.0 / 98.0));
        assert_eq!(right.fraction(151), None, "odd number on the even side");
        assert_eq!(right.fraction(98), None);
        assert_eq!(right.fraction(200), None);
        // Both kinds.
        assert_eq!(side(1, 11, "B", None).fraction(6), Some(0.5));
    }

    #[test]
    fn reversed_ranges_count_down_from_the_first_point() {
        let s = side(4498, 4400, "E", None);
        assert_eq!(s.fraction(4498), Some(0.0));
        assert_eq!(s.fraction(4400), Some(1.0));
        assert_eq!(s.fraction(4449), None);
        assert!((s.fraction(4474).unwrap() - 24.0 / 98.0).abs() < 1e-12);
        // One number: the middle.
        assert_eq!(side(7, 7, "O", None).fraction(7), Some(0.5));
        assert_eq!(side(7, 7, "O", None).fraction(9), None);
    }

    #[test]
    fn locate_interpolates_and_prefers_the_zip() {
        // A piece 0.01° north, numbers 100..=200 on the right, and a second
        // piece where the same numbers have another ZIP code.
        let edges = vec![
            Edge {
                line: vec![(10.0, 20.0), (10.01, 20.0)],
                left: Some(side(101, 201, "O", Some(99001))),
                right: Some(side(100, 200, "E", Some(99001))),
            },
            Edge {
                line: vec![(11.0, 20.0), (11.01, 20.0)],
                left: None,
                right: Some(side(200, 100, "E", Some(99002))),
            },
        ];
        let ((lat, lon), zip) = locate(&edges, 150, None).unwrap();
        assert!((lat - 10.005).abs() < 1e-9 && lon == 20.0, "{lat}");
        assert_eq!(zip, Some(99001));
        let ((lat, _), zip) = locate(&edges, 150, Some(99002)).unwrap();
        assert!((lat - 11.005).abs() < 1e-9);
        assert_eq!(zip, Some(99002));
        // The odd side; reversed on the second piece.
        let ((lat, _), _) = locate(&edges, 191, None).unwrap();
        assert!((lat - 10.009).abs() < 1e-9);
        let ((lat, _), _) = locate(&edges, 180, Some(99002)).unwrap();
        assert!((lat - 11.002).abs() < 1e-9);
        assert_eq!(locate(&edges, 300, None), None);
        assert_eq!(zip_text(501), "00501");
    }
}
