//! OBD traffic on the wire: requests from a tester (the MX+ or the gateway)
//! and the modules' single-frame answers, decoded with the signal registry.
//!
//! Only formulas from `shared/signals` are used, never a formula of this
//! tool's own. Each series carries the definition's provenance, so an
//! `IMPORTED_UNVERIFIED` formula is visible as such.

use std::collections::{BTreeMap, BTreeSet};

use f250_telemetry::registry::Protocol;
use f250_telemetry::{Provenance, Registry};

use crate::candump::Frame;

/// Functional request ID.
pub const FUNCTIONAL_ID: u32 = 0x7DF;

pub fn is_request_id(id: u32) -> bool {
    id == FUNCTIONAL_ID || (0x7E0..=0x7E7).contains(&id)
}

pub fn is_response_id(id: u32) -> bool {
    (0x7E8..=0x7EF).contains(&id)
}

#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Sample {
    pub t: f64,
    pub value: f64,
}

#[derive(Debug, Clone, PartialEq)]
pub struct Series {
    pub signal: String,
    pub responder: u32,
    pub unit: String,
    pub provenance: Provenance,
    pub samples: Vec<Sample>,
}

#[derive(Debug, Clone, Default, PartialEq)]
pub struct PidReport {
    /// One per (signal, responder), sorted.
    pub series: Vec<Series>,
    pub requests: usize,
    /// Request payloads seen (service + PID/DID), with counts.
    pub request_payloads: BTreeMap<Vec<u8>, usize>,
    /// Bytes after the request payload in an 8-byte request frame.
    pub request_pads: BTreeSet<u8>,
    pub answers: usize,
    /// Negative responses (`7F`), keyed by (responder, service, NRC).
    pub negatives: BTreeMap<(u32, u8, u8), usize>,
    /// First or consecutive frames of multi-frame answers (not decoded).
    pub multi_frame: usize,
    /// Positive single-frame answers that no registry signal claims.
    pub unmatched: BTreeMap<Vec<u8>, usize>,
    pub decode_errors: usize,
}

/// The payload of an ISO-TP single frame, if `data` is one.
fn single_frame(data: &[u8]) -> Option<&[u8]> {
    let pci = *data.first()?;
    let len = usize::from(pci & 0x0F);
    (pci >> 4 == 0 && len > 0)
        .then(|| data.get(1..1 + len))
        .flatten()
}

pub fn decode(frames: &[Frame], registry: &Registry) -> PidReport {
    let mut report = PidReport::default();
    let defs: Vec<_> = registry
        .iter()
        .filter(|d| !d.is_computed())
        .filter(|d| {
            d.request
                .as_ref()
                .is_some_and(|r| r.protocol == Protocol::Iso15765)
        })
        .filter(|d| d.response.is_some() && d.decode.is_some())
        .collect();
    let mut series: BTreeMap<(String, u32), Series> = BTreeMap::new();

    for f in frames.iter().filter(|f| !f.extended) {
        if is_request_id(f.id) {
            report.requests += 1;
            if let Some(p) = single_frame(&f.data) {
                *report.request_payloads.entry(p.to_vec()).or_default() += 1;
                report.request_pads.extend(&f.data[1 + p.len()..]);
            }
            continue;
        }
        if !is_response_id(f.id) {
            continue;
        }
        report.answers += 1;
        let Some(payload) = single_frame(&f.data) else {
            if f.data.first().is_some_and(|pci| matches!(pci >> 4, 1 | 2)) {
                report.multi_frame += 1;
            }
            continue;
        };
        if payload[0] == 0x7F {
            if let [_, sid, nrc, ..] = *payload {
                *report.negatives.entry((f.id, sid, nrc)).or_default() += 1;
            }
            continue;
        }
        let mut claimed = false;
        for def in &defs {
            let (Some(req), Some(spec)) = (&def.request, &def.response) else {
                continue;
            };
            let Some(rest) = payload.strip_prefix(spec.expect.as_slice()) else {
                continue;
            };
            if req.rx_id.is_some_and(|rx| rx != f.id) {
                continue;
            }
            claimed = true;
            match def.decode_payload(rest, &|_| None) {
                Ok(value) => series
                    .entry((def.id.clone(), f.id))
                    .or_insert_with(|| Series {
                        signal: def.id.clone(),
                        responder: f.id,
                        unit: def.unit.to_string(),
                        provenance: def.provenance,
                        samples: Vec::new(),
                    })
                    .samples
                    .push(Sample { t: f.t, value }),
                Err(_) => report.decode_errors += 1,
            }
        }
        if !claimed {
            let key = payload[..payload.len().min(3)].to_vec();
            *report.unmatched.entry(key).or_default() += 1;
        }
    }
    report.series = series.into_values().collect();
    report
}

#[cfg(test)]
#[allow(clippy::unwrap_used)]
mod tests {
    use super::*;

    fn registry() -> Registry {
        Registry::load_dir(concat!(env!("CARGO_MANIFEST_DIR"), "/../../shared/signals")).unwrap()
    }

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
    fn decodes_answers_with_the_registry_per_responder() {
        let frames = [
            f(
                0.00,
                0x7DF,
                &[0x02, 0x01, 0x0C, 0x55, 0x55, 0x55, 0x55, 0x55],
            ),
            // 0x0C4E / 4 = 787.5 rpm (SAE formula from sae.yaml).
            f(0.02, 0x7E8, &[0x04, 0x41, 0x0C, 0x0C, 0x4E, 0, 0, 0]),
            f(0.03, 0x7E9, &[0x04, 0x41, 0x0C, 0x0C, 0x50, 0, 0, 0]),
            f(0.10, 0x201, &[0x03, 0x13]),
        ];
        let r = decode(&frames, &registry());
        assert_eq!(r.requests, 1);
        assert_eq!(r.request_payloads.get(&vec![0x01, 0x0C]), Some(&1));
        assert_eq!(r.request_pads, BTreeSet::from([0x55]));
        assert_eq!(r.answers, 2);
        assert_eq!(r.series.len(), 2);
        let pcm = &r.series[0];
        assert_eq!((pcm.signal.as_str(), pcm.responder), ("rpm", 0x7E8));
        assert_eq!(pcm.provenance, Provenance::Sae);
        assert_eq!(
            pcm.samples,
            [Sample {
                t: 0.02,
                value: 787.5
            }]
        );
        assert_eq!(r.series[1].responder, 0x7E9);
        assert_eq!(r.series[1].samples[0].value, 788.0);
    }

    #[test]
    fn pinned_responder_negatives_multi_frame_and_unmatched() {
        let frames = [
            // EOT is pinned to the PCM (rx_id 0x7E8): the TCM's refusal and a
            // TCM positive (hypothetical) are not EOT.
            f(1.0, 0x7E9, &[0x03, 0x7F, 0x22, 0x12, 0, 0, 0, 0]),
            f(1.1, 0x7E9, &[0x05, 0x62, 0x13, 0x10, 0x26, 0x91, 0, 0]),
            f(1.2, 0x7E8, &[0x05, 0x62, 0x13, 0x10, 0x26, 0x91, 0, 0]),
            // A first frame (VIN) and a PID nobody defines.
            f(
                1.3,
                0x7E8,
                &[0x10, 0x14, 0x49, 0x02, 0x01, 0x31, 0x46, 0x54],
            ),
            f(1.4, 0x7E8, &[0x03, 0x41, 0x99, 0x00, 0, 0, 0, 0]),
        ];
        let r = decode(&frames, &registry());
        assert_eq!(r.negatives.get(&(0x7E9, 0x22, 0x12)), Some(&1));
        assert_eq!(r.multi_frame, 1);
        assert_eq!(r.unmatched.get(&vec![0x41, 0x99, 0x00]), Some(&1));
        let eot: Vec<_> = r.series.iter().filter(|s| s.signal == "eot").collect();
        assert_eq!(eot.len(), 1);
        assert_eq!(eot[0].responder, 0x7E8);
        // ((0x26*256)+0x91)/100 - 40 = 58.73, the 2026-11-03 capture.
        assert!((eot[0].samples[0].value - 58.73).abs() < 1e-9);
    }

    #[test]
    fn single_frame_pci() {
        assert_eq!(
            single_frame(&[0x02, 0x41, 0x0D, 0]),
            Some(&[0x41, 0x0D][..])
        );
        assert_eq!(single_frame(&[0x00, 1]), None);
        assert_eq!(single_frame(&[0x10, 0x14, 1, 2]), None);
        assert_eq!(single_frame(&[0x07, 1, 2]), None); // claims 7 bytes, has 2
        assert_eq!(single_frame(&[]), None);
    }
}
