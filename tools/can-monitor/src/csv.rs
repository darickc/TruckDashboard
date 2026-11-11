//! CSV export, for a spreadsheet or a plotting tool.
//!
//! - [`frames`]: one row per data frame, with each byte in its own column.
//! - [`pid_samples`]: one row per decoded PID answer, all signals in time
//!   order, with the definition's provenance on every row so an
//!   `IMPORTED_UNVERIFIED` formula is never mistaken for a verified one.
//!
//! Times are given twice: seconds since the capture's first frame, and the
//! Pi's wall clock (which may be wrong before network time; see
//! session.txt's clock line).

use std::collections::BTreeSet;
use std::io::{self, Write};

use crate::candump::Frame;
use crate::pids::PidReport;

/// The widest classic CAN frame; FD frames' extra bytes are only in `data`.
const BYTE_COLUMNS: usize = 8;

fn hex(data: &[u8]) -> String {
    data.iter().map(|b| format!("{b:02X}")).collect()
}

fn id_text(id: u32, extended: bool) -> String {
    if extended {
        format!("{id:08X}")
    } else {
        format!("{id:03X}")
    }
}

/// Writes the frames (only `ids`, when given). `t0`: the capture's first
/// frame time. Returns the rows written.
pub fn frames(
    out: &mut impl Write,
    frames: &[Frame],
    t0: f64,
    ids: Option<&BTreeSet<u32>>,
) -> io::Result<usize> {
    write!(out, "t_s,epoch_s,id,extended,fd,len,data")?;
    for i in 0..BYTE_COLUMNS {
        write!(out, ",b{i}")?;
    }
    writeln!(out)?;
    let mut n = 0;
    for f in frames {
        if ids.is_some_and(|s| !s.contains(&f.id)) {
            continue;
        }
        write!(
            out,
            "{:.6},{:.6},{},{},{},{},{}",
            f.t - t0,
            f.t,
            id_text(f.id, f.extended),
            u8::from(f.extended),
            u8::from(f.fd),
            f.data.len(),
            hex(&f.data)
        )?;
        for i in 0..BYTE_COLUMNS {
            match f.data.get(i) {
                Some(b) => write!(out, ",{b}")?,
                None => write!(out, ",")?,
            }
        }
        writeln!(out)?;
        n += 1;
    }
    Ok(n)
}

/// Writes every decoded PID answer (only `signals`, when given), in time
/// order. Returns the rows written.
pub fn pid_samples(
    out: &mut impl Write,
    report: &PidReport,
    t0: f64,
    signals: Option<&BTreeSet<String>>,
) -> io::Result<usize> {
    writeln!(out, "t_s,epoch_s,signal,responder,value,unit,provenance")?;
    let mut rows: Vec<(f64, &str, u32, f64, &str, String)> = Vec::new();
    for s in &report.series {
        if signals.is_some_and(|w| !w.contains(&s.signal)) {
            continue;
        }
        let prov = s.provenance.to_string();
        for x in &s.samples {
            rows.push((x.t, &s.signal, s.responder, x.value, &s.unit, prov.clone()));
        }
    }
    rows.sort_by(|a, b| a.0.total_cmp(&b.0).then(a.1.cmp(b.1)));
    for (t, signal, responder, value, unit, prov) in &rows {
        writeln!(
            out,
            "{:.6},{t:.6},{signal},{responder:03X},{value},{},{prov}",
            t - t0,
            quote(unit)
        )?;
    }
    Ok(rows.len())
}

/// A field quoted if it holds a comma, quote or newline (RFC 4180).
fn quote(s: &str) -> String {
    if s.contains([',', '"', '\n']) {
        format!("\"{}\"", s.replace('"', "\"\""))
    } else {
        s.to_string()
    }
}

#[cfg(test)]
#[allow(clippy::unwrap_used)]
mod tests {
    use super::*;
    use crate::pids::{Sample, Series};
    use f250_telemetry::Provenance;

    fn frame(t: f64, id: u32, data: &[u8]) -> Frame {
        Frame {
            t,
            id,
            extended: id > 0x7FF,
            fd: false,
            data: data.to_vec(),
        }
    }

    #[test]
    fn frames_one_row_each_with_byte_columns() {
        let fs = [
            frame(100.0, 0x201, &[0x00, 0x3F, 0xFF]),
            frame(100.5, 0x420, &[1]),
            frame(101.0, 0x18DA_F110, &[0xAB; 8]),
        ];
        let mut out = Vec::new();
        assert_eq!(frames(&mut out, &fs, 100.0, None).unwrap(), 3);
        let text = String::from_utf8(out).unwrap();
        let lines: Vec<_> = text.lines().collect();
        assert_eq!(
            lines[0],
            "t_s,epoch_s,id,extended,fd,len,data,b0,b1,b2,b3,b4,b5,b6,b7"
        );
        assert_eq!(
            lines[1],
            "0.000000,100.000000,201,0,0,3,003FFF,0,63,255,,,,,"
        );
        assert_eq!(lines[3].split(',').nth(2), Some("18DAF110"));
        assert_eq!(lines[3].split(',').count(), 15);

        let only: BTreeSet<u32> = [0x420].into_iter().collect();
        let mut out = Vec::new();
        assert_eq!(frames(&mut out, &fs, 100.0, Some(&only)).unwrap(), 1);
        assert!(
            String::from_utf8(out)
                .unwrap()
                .contains("0.500000,100.500000,420,")
        );
    }

    #[test]
    fn pid_samples_in_time_order_with_provenance() {
        let report = PidReport {
            series: vec![
                Series {
                    signal: "rpm".into(),
                    responder: 0x7E8,
                    unit: "rpm".into(),
                    provenance: Provenance::Sae,
                    samples: vec![
                        Sample {
                            t: 10.2,
                            value: 700.0,
                        },
                        Sample {
                            t: 10.6,
                            value: 710.0,
                        },
                    ],
                },
                Series {
                    signal: "eot".into(),
                    responder: 0x7E8,
                    unit: "°C".into(),
                    provenance: Provenance::ImportedUnverified,
                    samples: vec![Sample {
                        t: 10.4,
                        value: 88.5,
                    }],
                },
            ],
            ..PidReport::default()
        };
        let mut out = Vec::new();
        assert_eq!(pid_samples(&mut out, &report, 10.0, None).unwrap(), 3);
        let text = String::from_utf8(out).unwrap();
        let lines: Vec<_> = text.lines().collect();
        assert_eq!(
            lines[0],
            "t_s,epoch_s,signal,responder,value,unit,provenance"
        );
        assert!(
            lines[1].starts_with("0.200000,10.200000,rpm,7E8,700,rpm,"),
            "{}",
            lines[1]
        );
        assert!(lines[2].contains(",eot,7E8,88.5,°C,"), "{}", lines[2]);
        assert!(lines[2].ends_with(&Provenance::ImportedUnverified.to_string()));

        let only: BTreeSet<String> = ["eot".to_string()].into_iter().collect();
        let mut out = Vec::new();
        assert_eq!(
            pid_samples(&mut out, &report, 10.0, Some(&only)).unwrap(),
            1
        );
    }

    #[test]
    fn quotes_only_when_needed() {
        assert_eq!(quote("kPa"), "kPa");
        assert_eq!(quote("a,b"), "\"a,b\"");
        assert_eq!(quote("say \"hi\""), "\"say \"\"hi\"\"\"");
    }
}
