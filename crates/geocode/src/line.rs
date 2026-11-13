//! A street's line, small enough to keep for every US address range
//! (ADR-0041), and the point a house number falls on along it.
//!
//! Stored as varints: each point's latitude and longitude in millionths of
//! a degree (about 0.1 m), as the difference from the point before
//! (zigzag-coded, so a small step either way is one or two bytes). A rural
//! road's piece between two crossings is typically 15–40 bytes.

/// The points of `line` as a blob. Points are rounded to 1e-6°.
pub fn encode(line: &[(f64, f64)]) -> Vec<u8> {
    let mut out = Vec::with_capacity(4 + line.len() * 4);
    let (mut la0, mut lo0) = (0i64, 0i64);
    for &(lat, lon) in line {
        let (la, lo) = (micro(lat), micro(lon));
        varint(&mut out, zigzag(la - la0));
        varint(&mut out, zigzag(lo - lo0));
        (la0, lo0) = (la, lo);
    }
    out
}

/// The points of a blob from [`encode`]; None if it is cut short.
pub fn decode(blob: &[u8]) -> Option<Vec<(f64, f64)>> {
    let mut out = Vec::new();
    let (mut la, mut lo) = (0i64, 0i64);
    let mut i = 0;
    while i < blob.len() {
        la += unzigzag(read_varint(blob, &mut i)?);
        lo += unzigzag(read_varint(blob, &mut i)?);
        out.push((la as f64 / 1e6, lo as f64 / 1e6));
    }
    Some(out)
}

/// The point a fraction `t` (0 at the first point, 1 at the last) of the
/// way along `line`, by length. Lengths are measured flat (east–west
/// scaled by the cosine of the latitude), which is exact enough for the
/// few hundred metres between two crossings.
pub fn along(line: &[(f64, f64)], t: f64) -> Option<(f64, f64)> {
    let first = *line.first()?;
    let t = if t.is_finite() {
        t.clamp(0.0, 1.0)
    } else {
        0.5
    };
    let k = first.0.to_radians().cos();
    let seg =
        |a: (f64, f64), b: (f64, f64)| ((b.0 - a.0).powi(2) + ((b.1 - a.1) * k).powi(2)).sqrt();
    let total: f64 = line.windows(2).map(|w| seg(w[0], w[1])).sum();
    if total == 0.0 {
        return Some(first);
    }
    let mut left = t * total;
    for w in line.windows(2) {
        let l = seg(w[0], w[1]);
        if left <= l && l > 0.0 {
            let f = left / l;
            return Some((
                w[0].0 + (w[1].0 - w[0].0) * f,
                w[0].1 + (w[1].1 - w[0].1) * f,
            ));
        }
        left -= l;
    }
    line.last().copied()
}

fn micro(deg: f64) -> i64 {
    (deg * 1e6).round() as i64
}

fn zigzag(v: i64) -> u64 {
    ((v << 1) ^ (v >> 63)) as u64
}

fn unzigzag(v: u64) -> i64 {
    ((v >> 1) as i64) ^ -((v & 1) as i64)
}

fn varint(out: &mut Vec<u8>, mut v: u64) {
    while v >= 0x80 {
        out.push((v as u8) | 0x80);
        v >>= 7;
    }
    out.push(v as u8);
}

fn read_varint(blob: &[u8], i: &mut usize) -> Option<u64> {
    let mut v = 0u64;
    for shift in (0..64).step_by(7) {
        let b = *blob.get(*i)?;
        *i += 1;
        v |= u64::from(b & 0x7f) << shift;
        if b & 0x80 == 0 {
            return Some(v);
        }
    }
    None
}

#[cfg(test)]
#[allow(clippy::unwrap_used)]
mod tests {
    use super::*;

    #[test]
    fn round_trips_to_a_millionth_of_a_degree() {
        let line = [
            (38.5, -97.5),
            (38.500_123_4, -97.499_9),
            (-0.000_001, 179.999_999),
        ];
        let blob = encode(&line);
        let back = decode(&blob).unwrap();
        assert_eq!(back.len(), 3);
        for (a, b) in line.iter().zip(&back) {
            assert!(
                (a.0 - b.0).abs() < 6e-7 && (a.1 - b.1).abs() < 6e-7,
                "{a:?} {b:?}"
            );
        }
        // Small steps are small.
        let short = encode(&[(38.5, -97.5), (38.5001, -97.5001), (38.5002, -97.5)]);
        assert!(short.len() <= 8 + 4 * 2, "{}", short.len());
        assert_eq!(decode(&[]).unwrap(), Vec::<(f64, f64)>::new());
        // Cut in the middle of a varint.
        assert_eq!(decode(&blob[..blob.len() - 1]), None);
        assert_eq!(decode(&[0x80]), None);
    }

    #[test]
    fn points_along_a_line() {
        // An L: 0.01° north, then 0.01° east (at the equator, as long).
        let l = [(0.0, 0.0), (0.01, 0.0), (0.01, 0.01)];
        let p = |t| along(&l, t).unwrap();
        assert_eq!(p(0.0), (0.0, 0.0));
        assert_eq!(p(1.0), (0.01, 0.01));
        let (a, b) = p(0.5);
        assert!((a - 0.01).abs() < 1e-12 && b.abs() < 1e-12);
        let (a, b) = p(0.75);
        assert!((a - 0.01).abs() < 1e-12 && (b - 0.005).abs() < 1e-12);
        // Out of range clamps; NaN is the middle.
        assert_eq!(p(-1.0), (0.0, 0.0));
        assert_eq!(p(2.0), (0.01, 0.01));
        assert_eq!(along(&[], 0.5), None);
        assert_eq!(along(&[(1.0, 2.0)], 0.5), Some((1.0, 2.0)));
        assert_eq!(along(&[(1.0, 2.0), (1.0, 2.0)], 0.3), Some((1.0, 2.0)));
    }
}
