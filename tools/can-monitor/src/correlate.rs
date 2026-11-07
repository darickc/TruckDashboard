//! Fits broadcast byte fields against a decoded PID series.
//!
//! For each PID answer at time `t`, the field is read from the latest frame
//! of its ID at or before `t` (no older than `max_age`), and a straight line
//! `pid ≈ slope × raw + intercept` is fitted by least squares.
//!
//! A high |r| makes a field a candidate, nothing more. Signals that move
//! together fool it: RPM and road speed are nearly proportional within one
//! gear. A drive with stops, idling and several gears separates them.

use std::collections::BTreeMap;
use std::fmt;
use std::str::FromStr;

use crate::candump::Frame;
use crate::pids::Sample;

#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord)]
pub enum Kind {
    U8,
    /// Big-endian 16 bits.
    U16Be,
    /// Big-endian 16 bits with the top bit masked off (a flag sharing the
    /// word, as `201` bytes 0–1 seems to have).
    U15Be,
    U16Le,
}

impl Kind {
    pub const ALL: [Kind; 4] = [Kind::U8, Kind::U16Be, Kind::U15Be, Kind::U16Le];

    fn width(self) -> usize {
        match self {
            Kind::U8 => 1,
            _ => 2,
        }
    }

    fn name(self) -> &'static str {
        match self {
            Kind::U8 => "u8",
            Kind::U16Be => "u16be",
            Kind::U15Be => "u15be",
            Kind::U16Le => "u16le",
        }
    }
}

/// A field: `ID:byte:kind`, e.g. `201:0:u15be` (ID in hex, byte from 0).
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord)]
pub struct Field {
    pub id: u32,
    pub byte: usize,
    pub kind: Kind,
}

impl Field {
    pub fn extract(&self, data: &[u8]) -> Option<f64> {
        let b = data.get(self.byte..self.byte + self.kind.width())?;
        Some(f64::from(match self.kind {
            Kind::U8 => u16::from(b[0]),
            Kind::U16Be => u16::from_be_bytes([b[0], b[1]]),
            Kind::U15Be => u16::from_be_bytes([b[0], b[1]]) & 0x7FFF,
            Kind::U16Le => u16::from_le_bytes([b[0], b[1]]),
        }))
    }
}

impl fmt::Display for Field {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{:03X}:{}:{}", self.id, self.byte, self.kind.name())
    }
}

impl FromStr for Field {
    type Err = String;
    fn from_str(s: &str) -> Result<Self, String> {
        let usage = || format!("field '{s}': expected ID:byte:kind, e.g. 201:0:u15be");
        let mut it = s.split(':');
        let (Some(id), Some(byte), Some(kind), None) = (it.next(), it.next(), it.next(), it.next())
        else {
            return Err(usage());
        };
        let id = u32::from_str_radix(id.trim_start_matches("0x"), 16).map_err(|_| usage())?;
        let byte: usize = byte.parse().map_err(|_| usage())?;
        let kind = Kind::ALL
            .into_iter()
            .find(|k| k.name() == kind.to_ascii_lowercase())
            .ok_or_else(|| format!("field '{s}': kind must be u8, u16be, u15be or u16le"))?;
        if byte + kind.width() > 8 {
            return Err(format!("field '{s}': runs past byte 7"));
        }
        Ok(Field { id, byte, kind })
    }
}

/// Frames by ID, in time order, for "latest at or before t" lookups.
pub struct Index<'a> {
    by_id: BTreeMap<u32, Vec<&'a Frame>>,
}

impl<'a> Index<'a> {
    /// Indexes 11-bit frames other than OBD requests and answers.
    pub fn broadcasts(frames: &'a [Frame]) -> Self {
        let mut by_id: BTreeMap<u32, Vec<&Frame>> = BTreeMap::new();
        for f in frames {
            if !f.extended
                && !crate::pids::is_request_id(f.id)
                && !crate::pids::is_response_id(f.id)
            {
                by_id.entry(f.id).or_default().push(f);
            }
        }
        for v in by_id.values_mut() {
            v.sort_by(|a, b| a.t.total_cmp(&b.t));
        }
        Index { by_id }
    }

    fn latest(&self, id: u32, t: f64, max_age: f64) -> Option<&'a Frame> {
        let v = self.by_id.get(&id)?;
        let k = v.partition_point(|f| f.t <= t);
        let f = *v.get(k.checked_sub(1)?)?;
        (t - f.t <= max_age).then_some(f)
    }

    /// Every field that fits in each ID's longest frame.
    pub fn all_fields(&self) -> Vec<Field> {
        let mut out = Vec::new();
        for (&id, frames) in &self.by_id {
            let len = frames.iter().map(|f| f.data.len()).max().unwrap_or(0);
            for kind in Kind::ALL {
                for byte in 0..=len.saturating_sub(kind.width()) {
                    if byte + kind.width() <= len {
                        out.push(Field { id, byte, kind });
                    }
                }
            }
        }
        out
    }
}

#[derive(Debug, Clone, PartialEq)]
pub struct Fit {
    pub field: Field,
    /// PID samples that had a fresh frame of the field's ID.
    pub n: usize,
    /// Pearson correlation.
    pub r: f64,
    pub slope: f64,
    pub intercept: f64,
    /// Root-mean-square residual, in the PID's unit.
    pub rms: f64,
    pub raw_min: f64,
    pub raw_max: f64,
    pub distinct_raw: usize,
    /// Other fields that gave exactly the same fit (e.g. `u16be` and `u15be`
    /// when the top bit never set, or a word an ID repeats).
    pub aliases: Vec<Field>,
}

impl Fit {
    fn same_as(&self, other: &Fit) -> bool {
        self.n == other.n
            && self.r == other.r
            && self.slope == other.slope
            && self.intercept == other.intercept
    }
}

/// Fits one field. `None` when fewer than 3 pairs, or either side is constant.
pub fn fit(index: &Index, field: Field, samples: &[Sample], max_age: f64) -> Option<Fit> {
    let pairs: Vec<(f64, f64)> = samples
        .iter()
        .filter_map(|s| {
            let frame = index.latest(field.id, s.t, max_age)?;
            Some((field.extract(&frame.data)?, s.value))
        })
        .collect();
    let n = pairs.len();
    if n < 3 {
        return None;
    }
    let nf = n as f64;
    let mx = pairs.iter().map(|p| p.0).sum::<f64>() / nf;
    let my = pairs.iter().map(|p| p.1).sum::<f64>() / nf;
    let (mut sxx, mut syy, mut sxy) = (0.0, 0.0, 0.0);
    for &(x, y) in &pairs {
        sxx += (x - mx) * (x - mx);
        syy += (y - my) * (y - my);
        sxy += (x - mx) * (y - my);
    }
    if sxx == 0.0 || syy == 0.0 {
        return None;
    }
    let slope = sxy / sxx;
    let intercept = my - slope * mx;
    let rms = (pairs
        .iter()
        .map(|&(x, y)| (y - (slope * x + intercept)).powi(2))
        .sum::<f64>()
        / nf)
        .sqrt();
    let mut raws: Vec<u32> = pairs.iter().map(|p| p.0 as u32).collect();
    raws.sort_unstable();
    raws.dedup();
    Some(Fit {
        field,
        n,
        r: sxy / (sxx * syy).sqrt(),
        slope,
        intercept,
        rms,
        raw_min: pairs.iter().map(|p| p.0).fold(f64::INFINITY, f64::min),
        raw_max: pairs.iter().map(|p| p.0).fold(f64::NEG_INFINITY, f64::max),
        distinct_raw: raws.len(),
        aliases: Vec::new(),
    })
}

/// Fits every field and returns them best first (by |r|). Fields with fewer
/// than `min_distinct` raw values are dropped: flags and counters that barely
/// move can't be told apart from chance.
pub fn scan(index: &Index, samples: &[Sample], max_age: f64, min_distinct: usize) -> Vec<Fit> {
    let mut fits: Vec<Fit> = index
        .all_fields()
        .into_iter()
        .filter_map(|field| fit(index, field, samples, max_age))
        .filter(|f| f.distinct_raw >= min_distinct)
        .collect();
    fits.sort_by(|a, b| b.r.abs().total_cmp(&a.r.abs()).then(a.field.cmp(&b.field)));
    // Identical fits sort next to each other: fold them into one row.
    let mut out: Vec<Fit> = Vec::with_capacity(fits.len());
    for f in fits {
        match out.last_mut() {
            Some(prev) if prev.same_as(&f) => prev.aliases.push(f.field),
            _ => out.push(f),
        }
    }
    out
}

#[cfg(test)]
#[allow(clippy::unwrap_used)]
mod tests {
    use super::*;

    fn f(t: f64, id: u32, data: Vec<u8>) -> Frame {
        Frame {
            t,
            id,
            extended: false,
            fd: false,
            data,
        }
    }

    /// A fake drive: RPM wanders, a flag shares RPM's top bit, speed is a
    /// different shape, and one byte is pure noise.
    fn drive() -> (Vec<Frame>, Vec<Sample>, Vec<Sample>) {
        let mut frames = Vec::new();
        let (mut rpm_s, mut spd_s) = (Vec::new(), Vec::new());
        let rpm = |t: f64| 750.0 + 700.0 * (t / 7.0).sin().abs() + 300.0 * (t / 2.3).cos();
        let spd = |t: f64| (60.0 * (t / 31.0).sin()).max(0.0);
        for k in 0..12_000 {
            let t = k as f64 * 0.008;
            let r = rpm(t).round() as u16;
            let flag: u16 = if (t as u64 / 9) % 2 == 1 { 0x8000 } else { 0 };
            let w = (r | flag).to_be_bytes();
            let noise = (k * 7919 % 251) as u8;
            frames.push(f(t, 0x201, vec![w[0], w[1], noise, 0, 0, 0, 0, 0x80]));
            if k % 3 == 0 {
                let s = (spd(t) * 100.0 + 10_000.0).round() as u16;
                let b = s.to_be_bytes();
                frames.push(f(
                    t + 0.001,
                    0x215,
                    vec![b[0], b[1], b[0], b[1], 0, 0, 0, 0],
                ));
            }
            if k % 30 == 5 {
                // The tester's answers arrive between broadcasts.
                rpm_s.push(Sample {
                    t: t + 0.003,
                    value: rpm(t),
                });
                spd_s.push(Sample {
                    t: t + 0.003,
                    value: spd(t).round(),
                });
            }
        }
        (frames, rpm_s, spd_s)
    }

    #[test]
    fn scan_finds_rpm_under_a_flag_bit() {
        let (frames, rpm, _) = drive();
        let index = Index::broadcasts(&frames);
        let fits = scan(&index, &rpm, 0.25, 10);
        let best = &fits[0];
        assert_eq!(best.field, "201:0:u15be".parse().unwrap());
        assert!(best.r > 0.999, "{best:?}");
        assert!((best.slope - 1.0).abs() < 0.01);
        assert!(best.intercept.abs() < 5.0);
        // The same word with the flag left in is much worse.
        let with_flag = fits
            .iter()
            .find(|f| f.field.to_string() == "201:0:u16be")
            .unwrap();
        assert!(with_flag.r.abs() < 0.5, "{with_flag:?}");
    }

    #[test]
    fn scan_finds_speed_and_its_scaling() {
        let (frames, _, spd) = drive();
        let index = Index::broadcasts(&frames);
        let fits = scan(&index, &spd, 0.25, 10);
        let best = &fits[0];
        // Bytes 0–1 repeat in 2–3 and the top bit never sets, so the same word
        // has five names (bytes 1–2 little-endian included): one row.
        assert_eq!(best.field.to_string(), "215:0:u16be");
        let aliases: Vec<_> = best.aliases.iter().map(Field::to_string).collect();
        assert_eq!(
            aliases,
            ["215:0:u15be", "215:1:u16le", "215:2:u16be", "215:2:u15be"]
        );
        assert!(best.r > 0.999);
        // value = (raw - 10000) / 100
        assert!((best.slope - 0.01).abs() < 1e-3);
        assert!((best.intercept + 100.0).abs() < 2.0);
    }

    #[test]
    fn stale_or_missing_frames_are_skipped() {
        let frames = vec![
            f(0.0, 0x201, vec![0, 1]),
            f(0.1, 0x201, vec![0, 2]),
            f(0.2, 0x201, vec![0, 3]),
        ];
        let index = Index::broadcasts(&frames);
        let field: Field = "201:1:u8".parse().unwrap();
        let samples = [
            Sample {
                t: 0.05,
                value: 10.0,
            },
            Sample {
                t: 0.15,
                value: 20.0,
            },
            Sample {
                t: 0.25,
                value: 30.0,
            },
            Sample {
                t: 5.0,
                value: 99.0,
            }, // frame too old
            Sample {
                t: -1.0,
                value: 99.0,
            }, // before any frame
        ];
        let fit = fit(&index, field, &samples, 0.25).unwrap();
        assert_eq!(fit.n, 3);
        assert!((fit.r - 1.0).abs() < 1e-12);
        assert!((fit.slope - 10.0).abs() < 1e-9);
        assert_eq!((fit.raw_min, fit.raw_max, fit.distinct_raw), (1.0, 3.0, 3));
        // Constant input: no fit.
        let flat = [
            Sample {
                t: 0.05,
                value: 1.0,
            },
            Sample {
                t: 0.15,
                value: 1.0,
            },
            Sample {
                t: 0.25,
                value: 1.0,
            },
        ];
        assert!(super::fit(&index, field, &flat, 0.25).is_none());
    }

    #[test]
    fn field_parsing_and_extraction() {
        let fld: Field = "201:0:u15be".parse().unwrap();
        assert_eq!(fld.to_string(), "201:0:u15be");
        assert_eq!(fld.extract(&[0x83, 0x10]), Some(784.0));
        let le: Field = "0x215:2:U16LE".parse().unwrap();
        assert_eq!(le.extract(&[0, 0, 0x7A, 0x27]), Some(10106.0));
        assert_eq!("215:7:u8".parse::<Field>().unwrap().extract(&[0; 4]), None);
        for bad in [
            "201",
            "201:0",
            "201:x:u8",
            "zz:0:u8",
            "201:7:u16be",
            "201:0:s8",
        ] {
            assert!(bad.parse::<Field>().is_err(), "{bad}");
        }
    }

    #[test]
    fn obd_frames_are_not_broadcasts() {
        let frames = vec![
            f(0.0, 0x7DF, vec![2, 1, 0xC]),
            f(0.0, 0x7E8, vec![4, 0x41, 0xC, 0, 0]),
            f(0.0, 0x201, vec![1]),
        ];
        let fields = Index::broadcasts(&frames).all_fields();
        assert!(fields.iter().all(|f| f.id == 0x201));
        assert_eq!(fields.len(), 1);
    }
}
