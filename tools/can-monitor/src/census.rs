//! Per-ID census: rate, period, jitter, length, which bytes change, and
//! silences in the whole log.

use std::collections::{BTreeMap, BTreeSet};

use crate::candump::Frame;

#[derive(Debug, Clone, PartialEq)]
pub struct IdStats {
    pub id: u32,
    pub extended: bool,
    pub count: usize,
    /// Frames per second over the whole log.
    pub hz: f64,
    pub median_period_ms: f64,
    /// Population standard deviation of the period.
    pub jitter_ms: f64,
    pub lengths: BTreeSet<usize>,
    pub distinct_payloads: usize,
    /// Byte positions that took more than one value.
    pub changing_bytes: Vec<usize>,
    pub first: Vec<u8>,
    pub last: Vec<u8>,
}

#[derive(Debug, Clone, PartialEq)]
pub struct Gap {
    /// Seconds from the start of the log to the last frame before the gap.
    pub at_s: f64,
    pub len_s: f64,
}

#[derive(Debug, Clone, PartialEq)]
pub struct Census {
    pub duration_s: f64,
    pub frames: usize,
    pub ids: Vec<IdStats>,
    pub gaps: Vec<Gap>,
}

pub fn census(frames: &[Frame], gap_threshold_s: f64) -> Census {
    let (Some(first), Some(last)) = (frames.first(), frames.last()) else {
        return Census {
            duration_s: 0.0,
            frames: 0,
            ids: Vec::new(),
            gaps: Vec::new(),
        };
    };
    let t0 = first.t;
    let duration_s = last.t - t0;

    let mut by_id: BTreeMap<(bool, u32), Vec<&Frame>> = BTreeMap::new();
    for f in frames {
        by_id.entry((f.extended, f.id)).or_default().push(f);
    }
    let ids = by_id
        .into_iter()
        .map(|((extended, id), fs)| id_stats(id, extended, &fs, duration_s))
        .collect();

    let gaps = frames
        .windows(2)
        .filter(|w| w[1].t - w[0].t > gap_threshold_s)
        .map(|w| Gap {
            at_s: w[0].t - t0,
            len_s: w[1].t - w[0].t,
        })
        .collect();

    Census {
        duration_s,
        frames: frames.len(),
        ids,
        gaps,
    }
}

fn id_stats(id: u32, extended: bool, fs: &[&Frame], duration_s: f64) -> IdStats {
    let mut periods: Vec<f64> = fs.windows(2).map(|w| (w[1].t - w[0].t) * 1000.0).collect();
    let jitter_ms = std_dev(&periods);
    periods.sort_by(f64::total_cmp);
    let median_period_ms = periods.get(periods.len() / 2).copied().unwrap_or(0.0);

    let lengths = fs.iter().map(|f| f.data.len()).collect();
    let distinct_payloads = fs
        .iter()
        .map(|f| f.data.as_slice())
        .collect::<BTreeSet<_>>()
        .len();
    let max_len = fs.iter().map(|f| f.data.len()).max().unwrap_or(0);
    let changing_bytes = (0..max_len)
        .filter(|&k| {
            fs.iter()
                .filter_map(|f| f.data.get(k))
                .collect::<BTreeSet<_>>()
                .len()
                > 1
        })
        .collect();

    IdStats {
        id,
        extended,
        count: fs.len(),
        hz: if duration_s > 0.0 {
            fs.len() as f64 / duration_s
        } else {
            0.0
        },
        median_period_ms,
        jitter_ms,
        lengths,
        distinct_payloads,
        changing_bytes,
        first: fs.first().map(|f| f.data.clone()).unwrap_or_default(),
        last: fs.last().map(|f| f.data.clone()).unwrap_or_default(),
    }
}

fn std_dev(xs: &[f64]) -> f64 {
    if xs.len() < 2 {
        return 0.0;
    }
    let mean = xs.iter().sum::<f64>() / xs.len() as f64;
    (xs.iter().map(|x| (x - mean).powi(2)).sum::<f64>() / xs.len() as f64).sqrt()
}

#[cfg(test)]
#[allow(clippy::unwrap_used)]
mod tests {
    use super::*;

    fn f(t: f64, id: u32, data: &[u8]) -> Frame {
        Frame {
            t,
            id,
            extended: false,
            fd: false,
            data: data.to_vec(),
        }
    }

    #[test]
    fn rates_periods_changing_bytes_and_gaps() {
        let mut frames = Vec::new();
        for k in 0..100 {
            let t = k as f64 * 0.01;
            frames.push(f(t, 0x201, &[0, (k % 3) as u8, 7]));
            if k % 4 == 0 {
                frames.push(f(t + 0.001, 0x420, &[1, 2]));
            }
        }
        // A 3 s silence, then one more frame.
        frames.push(f(3.99 + 0.001, 0x201, &[0, 0, 7]));
        let c = census(&frames, 1.0);
        assert_eq!(c.frames, 126);
        assert_eq!(c.ids.len(), 2);
        let a = &c.ids[0];
        assert_eq!(a.id, 0x201);
        assert_eq!(a.count, 101);
        assert!((a.median_period_ms - 10.0).abs() < 1e-6);
        assert_eq!(a.changing_bytes, [1]);
        assert_eq!(a.distinct_payloads, 3);
        assert_eq!(a.lengths, BTreeSet::from([3]));
        let b = &c.ids[1];
        assert_eq!((b.id, b.count, b.distinct_payloads), (0x420, 25, 1));
        assert!(b.changing_bytes.is_empty());
        assert!((b.median_period_ms - 40.0).abs() < 1e-6);
        assert_eq!(c.gaps.len(), 1);
        // Last frame before it: 0x201 at 0.99 s; next at 3.991 s.
        assert!((c.gaps[0].len_s - 3.001).abs() < 1e-6);
        assert!((c.gaps[0].at_s - 0.99).abs() < 1e-6);
    }

    #[test]
    fn empty_log() {
        let c = census(&[], 1.0);
        assert_eq!((c.frames, c.ids.len(), c.gaps.len()), (0, 0, 0));
    }
}
