//! Two captures compared: which IDs, bytes and bits differ between them.
//!
//! Made for the event captures (docs/setup/can.md): one capture with nothing
//! touched (A) and one with the brake held, or in reverse (B). A state the
//! driver changed for the whole of B shows as a **bit that flips**: clear in
//! (almost) every A frame, set in (almost) every B frame, or the other way.
//! A byte whose values in A and B don't overlap at all shows the same thing
//! for a multi-bit state.
//!
//! Counters, checksums and analog values change in both captures and are
//! left out unless their values don't overlap. A difference is a candidate,
//! never a decoder: it needs repeating and a VERIFICATION_LOG entry.

use std::collections::{BTreeMap, BTreeSet};

use crate::candump::Frame;

/// One capture's frames of one ID.
#[derive(Debug, Clone, PartialEq)]
pub struct Side {
    pub count: usize,
    pub hz: f64,
    pub lengths: BTreeSet<usize>,
    /// Distinct values per byte position.
    pub values: Vec<BTreeSet<u8>>,
    /// Per byte, per bit (0 = least significant): the share of frames long
    /// enough to have the byte in which the bit is set.
    pub bit_share: Vec<[f64; 8]>,
}

#[derive(Debug, Clone, PartialEq)]
pub struct ByteDiff {
    pub byte: usize,
    pub a: BTreeSet<u8>,
    pub b: BTreeSet<u8>,
    /// No value in common.
    pub disjoint: bool,
}

#[derive(Debug, Clone, PartialEq)]
pub struct BitDiff {
    pub byte: usize,
    pub bit: u8,
    pub a_share: f64,
    pub b_share: f64,
}

#[derive(Debug, Clone, PartialEq)]
pub struct IdDiff {
    pub id: u32,
    pub extended: bool,
    pub a: Side,
    pub b: Side,
    /// The rates differ by more than [`Options::rate_change`].
    pub rate_changed: bool,
    pub bytes: Vec<ByteDiff>,
    pub bits: Vec<BitDiff>,
}

#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Options {
    /// A bit is reported when its set share differs by at least this (0–1).
    pub bit_threshold: f64,
    /// A byte is reported when its values differ and one side has at most
    /// this many distinct values (or the values don't overlap at all).
    pub max_values: usize,
    /// Rates differing by more than this fraction are reported.
    pub rate_change: f64,
}

impl Default for Options {
    fn default() -> Self {
        Self {
            bit_threshold: 0.9,
            max_values: 4,
            rate_change: 0.2,
        }
    }
}

#[derive(Debug, Clone, PartialEq)]
pub struct Diff {
    pub a_duration: f64,
    pub b_duration: f64,
    /// (extended, id) → (count, Hz) for IDs seen in one capture only.
    pub only_a: Vec<(bool, u32, usize, f64)>,
    pub only_b: Vec<(bool, u32, usize, f64)>,
    /// IDs in both captures that differ, sorted by ID.
    pub changed: Vec<IdDiff>,
    /// IDs in both captures with nothing to report.
    pub same: usize,
}

fn duration(frames: &[Frame]) -> f64 {
    match (frames.first(), frames.last()) {
        (Some(a), Some(b)) => b.t - a.t,
        _ => 0.0,
    }
}

fn sides(frames: &[Frame]) -> BTreeMap<(bool, u32), Side> {
    let dur = duration(frames);
    let mut by_id: BTreeMap<(bool, u32), Vec<&Frame>> = BTreeMap::new();
    for f in frames {
        by_id.entry((f.extended, f.id)).or_default().push(f);
    }
    by_id
        .into_iter()
        .map(|(k, fs)| {
            let width = fs.iter().map(|f| f.data.len()).max().unwrap_or(0);
            let mut values = vec![BTreeSet::new(); width];
            let mut set = vec![[0usize; 8]; width];
            let mut have = vec![0usize; width];
            for f in &fs {
                for (i, &b) in f.data.iter().enumerate() {
                    values[i].insert(b);
                    have[i] += 1;
                    for (bit, n) in set[i].iter_mut().enumerate() {
                        if b & (1 << bit) != 0 {
                            *n += 1;
                        }
                    }
                }
            }
            let bit_share = set
                .iter()
                .zip(&have)
                .map(|(s, &h)| s.map(|n| if h == 0 { 0.0 } else { n as f64 / h as f64 }))
                .collect();
            let side = Side {
                count: fs.len(),
                hz: if dur > 0.0 {
                    fs.len() as f64 / dur
                } else {
                    0.0
                },
                lengths: fs.iter().map(|f| f.data.len()).collect(),
                values,
                bit_share,
            };
            (k, side)
        })
        .collect()
}

pub fn diff(a: &[Frame], b: &[Frame], opt: Options) -> Diff {
    let sa = sides(a);
    let sb = sides(b);
    let mut out = Diff {
        a_duration: duration(a),
        b_duration: duration(b),
        only_a: Vec::new(),
        only_b: Vec::new(),
        changed: Vec::new(),
        same: 0,
    };
    for (&(ext, id), s) in &sa {
        if !sb.contains_key(&(ext, id)) {
            out.only_a.push((ext, id, s.count, s.hz));
        }
    }
    for (&(ext, id), s) in &sb {
        if !sa.contains_key(&(ext, id)) {
            out.only_b.push((ext, id, s.count, s.hz));
        }
    }
    for (&(extended, id), a) in &sa {
        let Some(b) = sb.get(&(extended, id)) else {
            continue;
        };
        let width = a.values.len().min(b.values.len());
        let mut bytes = Vec::new();
        let mut bits = Vec::new();
        for i in 0..width {
            let (va, vb) = (&a.values[i], &b.values[i]);
            let disjoint = va.is_disjoint(vb);
            if va != vb && (disjoint || va.len() <= opt.max_values || vb.len() <= opt.max_values) {
                bytes.push(ByteDiff {
                    byte: i,
                    a: va.clone(),
                    b: vb.clone(),
                    disjoint,
                });
            }
            for bit in 0..8u8 {
                let (pa, pb) = (a.bit_share[i][bit as usize], b.bit_share[i][bit as usize]);
                if (pa - pb).abs() >= opt.bit_threshold {
                    bits.push(BitDiff {
                        byte: i,
                        bit,
                        a_share: pa,
                        b_share: pb,
                    });
                }
            }
        }
        let top = a.hz.max(b.hz);
        let rate_changed = top > 0.0 && (a.hz - b.hz).abs() / top > opt.rate_change;
        if bytes.is_empty() && bits.is_empty() && !rate_changed && a.lengths == b.lengths {
            out.same += 1;
            continue;
        }
        out.changed.push(IdDiff {
            id,
            extended,
            a: a.clone(),
            b: b.clone(),
            rate_changed,
            bytes,
            bits,
        });
    }
    out
}

/// A byte's values for a table: up to `max` in hex, else how many and the
/// range.
pub fn describe_values(v: &BTreeSet<u8>, max: usize) -> String {
    if v.is_empty() {
        return "-".into();
    }
    if v.len() <= max {
        return v
            .iter()
            .map(|b| format!("{b:02X}"))
            .collect::<Vec<_>>()
            .join(" ");
    }
    let (lo, hi) = (
        v.first().copied().unwrap_or(0),
        v.last().copied().unwrap_or(0),
    );
    format!("{} values {lo:02X}–{hi:02X}", v.len())
}

#[cfg(test)]
#[allow(clippy::unwrap_used)]
mod tests {
    use super::*;

    fn frames(id: u32, hz: f64, secs: f64, data: impl Fn(usize) -> Vec<u8>) -> Vec<Frame> {
        let n = (hz * secs) as usize;
        (0..n)
            .map(|i| Frame {
                t: i as f64 / hz,
                id,
                extended: false,
                fd: false,
                data: data(i),
            })
            .collect()
    }

    fn merged(mut parts: Vec<Vec<Frame>>) -> Vec<Frame> {
        let mut all: Vec<Frame> = parts.drain(..).flatten().collect();
        all.sort_by(|a, b| a.t.total_cmp(&b.t));
        all
    }

    /// Baseline: brake bit (byte 0 bit 4) clear; B: set. A rolling counter
    /// in byte 7 changes in both and must not be reported.
    #[test]
    fn finds_the_brake_bit_and_ignores_the_counter() {
        let a = merged(vec![
            frames(0x440, 50.0, 10.0, |i| {
                vec![0x01, 0, 0, 0, 0, 0, 0, (i % 16) as u8]
            }),
            frames(0x201, 100.0, 10.0, |i| vec![0, (i % 200) as u8, 0, 0]),
        ]);
        let b = merged(vec![
            frames(0x440, 50.0, 10.0, |i| {
                vec![0x11, 0, 0, 0, 0, 0, 0, (i % 16) as u8]
            }),
            frames(0x201, 100.0, 10.0, |i| vec![0, ((i + 7) % 200) as u8, 0, 0]),
        ]);
        let d = diff(&a, &b, Options::default());
        assert_eq!(
            d.same, 1,
            "201 only has an analog byte that changes in both"
        );
        let x = &d.changed[0];
        assert_eq!(x.id, 0x440);
        assert_eq!(
            x.bits,
            vec![BitDiff {
                byte: 0,
                bit: 4,
                a_share: 0.0,
                b_share: 1.0
            }]
        );
        assert_eq!(x.bytes.len(), 1);
        assert!(x.bytes[0].disjoint);
        assert_eq!(describe_values(&x.bytes[0].a, 4), "01");
        assert_eq!(describe_values(&x.bytes[0].b, 4), "11");
        assert!(!x.rate_changed);
    }

    #[test]
    fn ids_in_one_capture_only_and_rate_changes() {
        let a = merged(vec![
            frames(0x230, 10.0, 10.0, |_| vec![0x00]),
            frames(0x3B3, 5.0, 10.0, |_| vec![1]),
        ]);
        let b = merged(vec![
            frames(0x230, 20.0, 10.0, |_| vec![0x00]),
            frames(0x4FF, 1.0, 10.0, |_| vec![2]),
        ]);
        let d = diff(&a, &b, Options::default());
        assert_eq!(d.only_a.iter().map(|x| x.1).collect::<Vec<_>>(), [0x3B3]);
        assert_eq!(d.only_b.iter().map(|x| x.1).collect::<Vec<_>>(), [0x4FF]);
        assert_eq!(d.changed.len(), 1);
        assert!(d.changed[0].rate_changed);
        assert!(d.changed[0].bytes.is_empty());
    }

    #[test]
    fn a_bit_set_part_of_the_time_is_not_a_flip() {
        // Set in half of B's frames: a share difference of 0.5.
        let a = frames(0x420, 10.0, 10.0, |_| vec![0x00]);
        let b = frames(0x420, 10.0, 10.0, |i| {
            vec![if i % 2 == 0 { 0x01 } else { 0x00 }]
        });
        let d = diff(&a, &b, Options::default());
        let x = &d.changed[0];
        assert!(x.bits.is_empty());
        assert_eq!(x.bytes.len(), 1, "the byte's values still differ");
        assert!(!x.bytes[0].disjoint);
        let loose = diff(
            &a,
            &b,
            Options {
                bit_threshold: 0.5,
                ..Options::default()
            },
        );
        assert_eq!(loose.changed[0].bits.len(), 1);
    }

    #[test]
    fn lengths_and_empty_captures() {
        let a = frames(0x123, 10.0, 1.0, |_| vec![1, 2]);
        let b = frames(0x123, 10.0, 1.0, |_| vec![1, 2, 3]);
        let d = diff(&a, &b, Options::default());
        assert_eq!(d.changed.len(), 1, "a length change is reported");
        let e = diff(&[], &[], Options::default());
        assert!(e.changed.is_empty() && e.only_a.is_empty() && e.same == 0);
        assert_eq!(describe_values(&BTreeSet::new(), 4), "-");
        let many: BTreeSet<u8> = (0..10).collect();
        assert_eq!(describe_values(&many, 4), "10 values 00–09");
    }
}
