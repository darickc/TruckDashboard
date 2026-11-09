//! `candump -l` log lines: `(1793981271.350104) can0 201#00003FFF00000080`.
//!
//! - 3 hex digits: 11-bit ID. 8 hex digits: 29-bit ID, or an error frame when
//!   the `CAN_ERR_FLAG` bit (`0x20000000`) is set.
//! - `ID#R` is a remote frame. `ID##<flags><data>` is CAN FD.

use std::io::BufRead;

/// `CAN_ERR_FLAG` from `linux/can.h`.
pub const CAN_ERR_FLAG: u32 = 0x2000_0000;

#[derive(Debug, Clone, PartialEq)]
pub struct Frame {
    /// Seconds since the Unix epoch (the Pi's receive time).
    pub t: f64,
    pub id: u32,
    pub extended: bool,
    pub fd: bool,
    pub data: Vec<u8>,
}

#[derive(Debug, Clone, PartialEq)]
pub enum Record {
    Data(Frame),
    Remote {
        t: f64,
        id: u32,
    },
    /// Error frame: the error class bits (ID without the flag) and its data.
    Error {
        t: f64,
        class: u32,
        data: Vec<u8>,
    },
}

#[derive(Debug, Default)]
pub struct Log {
    pub frames: Vec<Frame>,
    pub remote: usize,
    pub errors: Vec<(f64, u32)>,
    /// Lines that didn't parse, with their line number (1-based).
    pub bad_lines: Vec<(usize, String)>,
}

impl Log {
    /// Seconds from the first to the last record, 0 if fewer than two frames.
    pub fn duration(&self) -> f64 {
        match (self.frames.first(), self.frames.last()) {
            (Some(a), Some(b)) => b.t - a.t,
            _ => 0.0,
        }
    }
}

/// Parses one line. Blank lines give `Ok(None)`.
pub fn parse_line(line: &str) -> Result<Option<Record>, String> {
    let line = line.trim();
    if line.is_empty() {
        return Ok(None);
    }
    let mut parts = line.split_whitespace();
    let (Some(ts), Some(_iface), Some(frame), None) =
        (parts.next(), parts.next(), parts.next(), parts.next())
    else {
        return Err("expected '(time) iface ID#DATA'".into());
    };
    let t: f64 = ts
        .strip_prefix('(')
        .and_then(|s| s.strip_suffix(')'))
        .ok_or("timestamp not in parentheses")?
        .parse()
        .map_err(|_| "bad timestamp")?;
    let (id_hex, rest) = frame.split_once('#').ok_or("no '#'")?;
    let raw_id = u32::from_str_radix(id_hex, 16).map_err(|_| "bad ID")?;
    let extended = match id_hex.len() {
        3 => false,
        8 => true,
        _ => return Err(format!("ID '{id_hex}' is neither 3 nor 8 hex digits")),
    };
    if extended && raw_id & CAN_ERR_FLAG != 0 {
        return Ok(Some(Record::Error {
            t,
            class: raw_id & !CAN_ERR_FLAG,
            data: hex(rest)?,
        }));
    }
    if rest.starts_with('R') {
        return Ok(Some(Record::Remote { t, id: raw_id }));
    }
    let (fd, data) = match rest.strip_prefix('#') {
        // CAN FD: one hex digit of flags, then the data.
        Some(fd) => (true, hex(fd.get(1..).ok_or("CAN FD frame without flags")?)?),
        None => (false, hex(rest)?),
    };
    Ok(Some(Record::Data(Frame {
        t,
        id: raw_id,
        extended,
        fd,
        data,
    })))
}

fn hex(s: &str) -> Result<Vec<u8>, String> {
    // Byte-index slicing below needs ASCII; a corrupted line may not be.
    if !s.is_ascii() {
        return Err("non-ASCII data".into());
    }
    if !s.len().is_multiple_of(2) {
        return Err("odd number of hex digits".into());
    }
    (0..s.len())
        .step_by(2)
        .map(|i| u8::from_str_radix(&s[i..i + 2], 16).map_err(|_| format!("bad hex '{s}'")))
        .collect()
}

/// Reads a whole log. Bad lines are kept, not fatal: a capture cut off
/// mid-line still gives everything before it.
pub fn read_log(reader: impl BufRead) -> std::io::Result<Log> {
    let mut log = Log::default();
    for (n, line) in reader.lines().enumerate() {
        let line = line?;
        match parse_line(&line) {
            Ok(Some(Record::Data(f))) => log.frames.push(f),
            Ok(Some(Record::Remote { .. })) => log.remote += 1,
            Ok(Some(Record::Error { t, class, .. })) => log.errors.push((t, class)),
            Ok(None) => {}
            Err(e) => log.bad_lines.push((n + 1, format!("{e}: {line}"))),
        }
    }
    Ok(log)
}

#[cfg(test)]
#[allow(clippy::unwrap_used)]
mod tests {
    use super::*;

    #[test]
    fn standard_frame() {
        let r = parse_line("(1793981271.350104) can0 201#00003FFF00000080").unwrap();
        let Some(Record::Data(f)) = r else {
            panic!("{r:?}")
        };
        assert_eq!(f.id, 0x201);
        assert!(!f.extended && !f.fd);
        assert_eq!(f.data, [0, 0, 0x3F, 0xFF, 0, 0, 0, 0x80]);
        assert!((f.t - 1793981271.350104).abs() < 1e-6);
    }

    #[test]
    fn extended_remote_error_fd_and_empty() {
        let Some(Record::Data(f)) = parse_line("(1.0) can0 18DAF110#0102").unwrap() else {
            panic!()
        };
        assert!(f.extended);
        assert_eq!(f.id, 0x18DA_F110);
        assert_eq!(
            parse_line("(1.0) can0 7DF#R").unwrap(),
            Some(Record::Remote { t: 1.0, id: 0x7DF })
        );
        assert_eq!(
            parse_line("(2.5) can0 20000080#0000000000000000").unwrap(),
            Some(Record::Error {
                t: 2.5,
                class: 0x80,
                data: vec![0; 8]
            })
        );
        let Some(Record::Data(f)) = parse_line("(1.0) can0 123##1AABB").unwrap() else {
            panic!()
        };
        assert!(f.fd);
        assert_eq!(f.data, [0xAA, 0xBB]);
        let Some(Record::Data(f)) = parse_line("(1.0) can0 123#").unwrap() else {
            panic!()
        };
        assert!(f.data.is_empty());
        assert_eq!(parse_line("   ").unwrap(), None);
    }

    #[test]
    fn malformed_lines_are_errors() {
        for bad in [
            "1.0 can0 123#00",
            "(x) can0 123#00",
            "(1.0) can0 12#00",
            "(1.0) can0 123#0",
            "(1.0) can0 123#ZZ",
            "(1.0) can0 12300",
            "(1.0) can0 123#00 extra",
            "(1.0) can0 123#0\u{e9}0",
        ] {
            assert!(parse_line(bad).is_err(), "{bad}");
        }
    }

    #[test]
    fn read_log_keeps_going_past_bad_lines() {
        let text =
            "(1.0) can0 201#00\n(1.5) can0 20000004#0000000000000000\ngarbage\n(2.0) can0 201#01\n";
        let log = read_log(text.as_bytes()).unwrap();
        assert_eq!(log.frames.len(), 2);
        assert_eq!(log.errors, [(1.5, 4)]);
        assert_eq!(log.bad_lines.len(), 1);
        assert_eq!(log.bad_lines[0].0, 3);
        assert!((log.duration() - 1.0).abs() < 1e-9);
    }
}
