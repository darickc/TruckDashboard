//! ELM327/STN response parsing primitives.
//!
//! Port of `firmware/esp32/lib/ObdCore/src/ElmParser.{h,cpp}`.
//!
//! The adapter is configured with `ATE0` (no echo), `ATL0` (no linefeeds),
//! `ATS0` (no spaces) and `ATH1` (headers on). With those settings a CAN data
//! line on an 11-bit-ID protocol looks like:
//!
//! ```text
//! 7E804410C1AF8
//! ^^^            3 hex chars: CAN ID (0x7E8)
//!    ^^          ISO-TP PCI byte (0x04 = single frame, 4 data bytes)
//!      ^^^^^^^^  data: 41 0C 1A F8 (positive response to 01 0C)
//! ```
//!
//! Multi-byte responses (more than 7 data bytes) arrive as ISO 15765-2
//! (ISO-TP) first frame (PCI `1L LL`) plus consecutive frames (PCI `2N`),
//! possibly interleaved from several ECUs. [`IsoTpReassembler`] groups frames
//! by CAN ID.
//!
//! Everything here is pure logic: no I/O, no clock.

/// Longest line the accumulator keeps (the C++ buffer was 96 bytes including
/// the terminator). Longer lines are truncated; classification rejects them.
pub const MAX_LINE_LEN: usize = 95;

/// Most data bytes one line may carry (the C++ `Frame::data` size). An ATH1
/// CAN frame carries at most 8.
pub const MAX_FRAME_BYTES: usize = 16;

/// Largest ISO-TP message the reassembler accepts: the 12-bit length field's
/// maximum.
pub const MAX_ISOTP_PAYLOAD: usize = 4095;

/// How many senders may have a multi-frame message in flight at once. 11-bit
/// OBD response IDs span 0x7E8..=0x7EF, so eight covers every physical
/// responder.
pub const MAX_REASSEMBLY_SLOTS: usize = 8;

// ---------------------------------------------------------------------------
// Line accumulation
// ---------------------------------------------------------------------------

/// What one byte fed to a [`LineAccumulator`] produced.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum AccEvent {
    /// Byte consumed, nothing complete yet.
    None,
    /// A complete non-empty line is available via [`LineAccumulator::line`].
    Line,
    /// The `>` prompt was seen (any partial line is discarded).
    Prompt,
}

/// Splits the adapter's byte stream into lines.
///
/// ELM output is `\r`-delimited (`ATL0` disables `\n`); the `>` prompt arrives
/// *without* a terminator, so it is reported as its own event.
#[derive(Debug, Default, Clone)]
pub struct LineAccumulator {
    buf: String,
    line: String,
}

impl LineAccumulator {
    /// A new, empty accumulator.
    pub fn new() -> Self {
        Self::default()
    }

    /// Feed one received byte.
    pub fn feed(&mut self, byte: u8) -> AccEvent {
        match byte {
            b'>' => {
                // The prompt normally follows a '\r', so the buffer is empty;
                // a partial line before it is discarded.
                self.clear();
                AccEvent::Prompt
            }
            b'\r' | b'\n' => {
                if self.buf.is_empty() {
                    return AccEvent::None; // blank lines / CRLF pairs
                }
                self.line = std::mem::take(&mut self.buf);
                AccEvent::Line
            }
            0 => AccEvent::None, // the ELM can emit NULs at reset
            b => {
                if self.buf.len() < MAX_LINE_LEN {
                    // Latin-1 mapping keeps every byte representable without
                    // failing on invalid UTF-8; non-ASCII never classifies as
                    // anything but Unknown anyway.
                    self.buf.push(char::from(b));
                }
                AccEvent::None
            }
        }
    }

    /// The most recently completed line (valid after [`AccEvent::Line`]).
    pub fn line(&self) -> &str {
        &self.line
    }

    /// Length of the partial line being accumulated.
    pub fn pending_len(&self) -> usize {
        self.buf.len()
    }

    /// Drop any partial and completed line.
    pub fn clear(&mut self) {
        self.buf.clear();
        self.line.clear();
    }
}

// ---------------------------------------------------------------------------
// Line classification
// ---------------------------------------------------------------------------

/// What kind of line the adapter sent.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum LineClass {
    /// Looks like a hex data line (possibly with a CAN ID).
    HexData,
    /// `OK`.
    Ok,
    /// `NO DATA`: request sent, no ECU answered.
    NoData,
    /// `STOPPED`: the adapter aborted (a character arrived mid-request).
    Stopped,
    /// `SEARCHING...`: protocol auto-detect in progress.
    Searching,
    /// `CAN ERROR`.
    CanError,
    /// `BUFFER FULL`.
    BufferFull,
    /// `UNABLE TO CONNECT`.
    UnableToConnect,
    /// `?` or any `...ERROR` variant.
    Error,
    /// Unsolicited STN chatter: `ACT ALERT`, `LV RESET`, `LP ALERT`,
    /// `SLEEPING`, `WAKE...`.
    Ignorable,
    /// Anything else (banners, unrecognised text).
    Unknown,
}

/// Classify one adapter line.
pub fn classify_line(line: &str) -> LineClass {
    if line.is_empty() {
        return LineClass::Unknown;
    }
    let starts = |p: &str| line.starts_with(p);
    if line == "OK" {
        return LineClass::Ok;
    }
    if starts("NO DATA") || starts("NODATA") {
        return LineClass::NoData;
    }
    if starts("STOPPED") {
        return LineClass::Stopped;
    }
    if starts("SEARCHING") {
        return LineClass::Searching;
    }
    if starts("CAN ERROR") || starts("CANERROR") {
        return LineClass::CanError;
    }
    if starts("BUFFER FULL") || starts("BUFFERFULL") {
        return LineClass::BufferFull;
    }
    if starts("UNABLE TO CONNECT") || starts("UNABLETOCONNECT") {
        return LineClass::UnableToConnect;
    }
    if line == "?" || line.contains("ERROR") {
        return LineClass::Error;
    }
    // Unsolicited STN11xx (OBDLink) chatter: power management, voltage events.
    if starts("ACT ALERT")
        || starts("LV RESET")
        || starts("LP ALERT")
        || starts("SLEEPING")
        || starts("WAKE")
    {
        return LineClass::Ignorable;
    }

    // Hex data line? Spaces between digits are tolerated (in case ATS0 is
    // not active).
    let mut hex_chars = 0usize;
    for b in line.bytes() {
        if b == b' ' {
            continue;
        }
        if hex_nibble(b).is_none() {
            return LineClass::Unknown;
        }
        hex_chars += 1;
    }
    if hex_chars >= 2 {
        LineClass::HexData
    } else {
        LineClass::Unknown
    }
}

// ---------------------------------------------------------------------------
// Hex utilities
// ---------------------------------------------------------------------------

/// Remove every space (defensive: `ATS0` is set, but not relied on).
pub fn strip_spaces(s: &str) -> String {
    s.chars().filter(|&c| c != ' ').collect()
}

/// 0..=15 for a hex digit, `None` otherwise.
pub fn hex_nibble(c: u8) -> Option<u8> {
    match c {
        b'0'..=b'9' => Some(c - b'0'),
        b'A'..=b'F' => Some(c - b'A' + 10),
        b'a'..=b'f' => Some(c - b'a' + 10),
        _ => None,
    }
}

/// True if every byte of `s` is a hex digit (vacuously true for "").
pub fn is_hex_string(s: &str) -> bool {
    s.bytes().all(|b| hex_nibble(b).is_some())
}

/// Decode pairs of hex characters into bytes.
///
/// `None` on empty input, odd length, invalid characters, or more than
/// `max_out` bytes (the C++ version returned 0 in all those cases).
pub fn hex_to_bytes(s: &str, max_out: usize) -> Option<Vec<u8>> {
    let b = s.as_bytes();
    if b.is_empty() || !b.len().is_multiple_of(2) || b.len() / 2 > max_out {
        return None;
    }
    let (pairs, _) = b.as_chunks::<2>();
    pairs
        .iter()
        .map(|&[hi, lo]| Some((hex_nibble(hi)? << 4) | hex_nibble(lo)?))
        .collect()
}

// ---------------------------------------------------------------------------
// Data-line framing
// ---------------------------------------------------------------------------

/// One data line, split into CAN ID (when headers are on) and bytes.
#[derive(Debug, Clone, PartialEq, Eq, Default)]
pub struct Frame {
    /// 11-bit CAN ID, or `None` when the line had no header (ATH0 style).
    pub can_id: Option<u16>,
    /// Data bytes, including the ISO-TP PCI byte when `can_id` is `Some`.
    pub data: Vec<u8>,
}

/// Parse a space-stripped hex data line into a frame.
///
/// Odd-length lines are a 3-hex-char 11-bit CAN ID followed by data (`ATH1` on
/// an 11-bit CAN protocol). Even-length lines are raw payload with no header
/// (`ATH0` style). `None` on malformed input.
///
/// 29-bit headers are not parsed: this truck's HS-CAN diagnostic responses use
/// 11-bit IDs (7E8..7EF), confirmed by `ATDPN` → `A6` in VERIFICATION_LOG.md.
pub fn parse_data_line(line: &str) -> Option<Frame> {
    let b = line.as_bytes();
    if b.len() < 2 {
        return None;
    }
    let mut can_id = None;
    let mut data_start = 0;
    if !b.len().is_multiple_of(2) {
        if b.len() < 5 {
            return None;
        }
        let n0 = hex_nibble(b[0])?;
        let n1 = hex_nibble(b[1])?;
        let n2 = hex_nibble(b[2])?;
        can_id = Some((u16::from(n0) << 8) | (u16::from(n1) << 4) | u16::from(n2));
        data_start = 3;
    }
    let data = hex_to_bytes(line.get(data_start..)?, MAX_FRAME_BYTES)?;
    Some(Frame { can_id, data })
}

// ---------------------------------------------------------------------------
// ISO-TP reassembly
// ---------------------------------------------------------------------------

/// A complete ISO-TP message.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct IsoTpMessage {
    /// Sender's CAN ID; `None` for a headerless line.
    pub source: Option<u16>,
    /// The reassembled payload (PCI bytes removed).
    pub data: Vec<u8>,
}

#[derive(Debug, Clone)]
struct Slot {
    source: u16,
    buf: Vec<u8>,
    expected: usize,
    next_seq: u8,
}

/// ISO 15765-2 reassembler, keyed by sender CAN ID.
///
/// Single frames complete immediately. A first frame opens a slot for its
/// sender; consecutive frames are appended only to their own sender's slot,
/// so interleaved multi-frame answers from several ECUs all complete.
/// Headerless frames are treated as already-complete payloads. Flow-control
/// frames (PCI 3) are adapter-internal and ignored.
#[derive(Debug, Default, Clone)]
pub struct IsoTpReassembler {
    slots: Vec<Slot>,
}

impl IsoTpReassembler {
    /// A new reassembler with nothing in flight.
    pub fn new() -> Self {
        Self::default()
    }

    /// Abandon every in-flight message.
    pub fn reset(&mut self) {
        self.slots.clear();
    }

    /// Number of senders with a multi-frame message in flight.
    pub fn in_flight(&self) -> usize {
        self.slots.len()
    }

    fn drop_slot(&mut self, source: u16) {
        self.slots.retain(|s| s.source != source);
    }

    /// Feed one frame. Returns the message it completed, if any.
    pub fn feed(&mut self, f: &Frame) -> Option<IsoTpMessage> {
        let first = *f.data.first()?;
        let Some(id) = f.can_id else {
            // ATH0-style line: the adapter already stripped header and PCI.
            return Some(IsoTpMessage {
                source: None,
                data: f.data.clone(),
            });
        };

        match first >> 4 {
            0x0 => {
                // Single frame: low nibble = payload length (1..=7).
                let dl = usize::from(first & 0x0F);
                if dl == 0 || dl > 7 || dl > f.data.len() - 1 {
                    return None;
                }
                // A new message from this sender supersedes any partial one.
                self.drop_slot(id);
                Some(IsoTpMessage {
                    source: Some(id),
                    data: f.data[1..=dl].to_vec(),
                })
            }
            0x1 => {
                // First frame: 12-bit total length, 6 payload bytes here.
                let total = (usize::from(first & 0x0F) << 8) | usize::from(*f.data.get(1)?);
                if !(8..=MAX_ISOTP_PAYLOAD).contains(&total) || f.data.len() < 8 {
                    return None; // total <= 7 must use a single frame
                }
                self.drop_slot(id);
                if self.slots.len() >= MAX_REASSEMBLY_SLOTS {
                    return None; // more concurrent senders than OBD allows
                }
                self.slots.push(Slot {
                    source: id,
                    buf: f.data[2..8].to_vec(),
                    expected: total,
                    next_seq: 1,
                });
                None
            }
            0x2 => {
                // Consecutive frame: only for a sender with a slot open.
                let idx = self.slots.iter().position(|s| s.source == id)?;
                let slot = &mut self.slots[idx];
                if (first & 0x0F) != (slot.next_seq & 0x0F) {
                    // Sequence error: abandon this sender's reassembly.
                    self.slots.remove(idx);
                    return None;
                }
                slot.next_seq = slot.next_seq.wrapping_add(1);
                let remaining = slot.expected - slot.buf.len();
                let chunk = (f.data.len() - 1).min(remaining);
                slot.buf.extend_from_slice(&f.data[1..=chunk]);
                if slot.buf.len() >= slot.expected {
                    let done = self.slots.remove(idx);
                    return Some(IsoTpMessage {
                        source: Some(done.source),
                        data: done.buf,
                    });
                }
                None
            }
            // Flow control (0x3) is adapter-internal; anything else is noise.
            _ => None,
        }
    }
}

// ---------------------------------------------------------------------------
// ATRV
// ---------------------------------------------------------------------------

/// Parse an `ATRV` reply such as `12.4V` into volts.
///
/// Accepts an optional trailing `V`/`v` and surrounding whitespace. Only ASCII
/// digits and at most one `.` are accepted, so `inf`/`NaN` and other text are
/// rejected rather than turned into a number.
pub fn parse_voltage(line: &str) -> Option<f32> {
    let t = line.trim();
    let t = t
        .strip_suffix('V')
        .or_else(|| t.strip_suffix('v'))
        .unwrap_or(t)
        .trim_end();
    if !t.bytes().any(|b| b.is_ascii_digit())
        || !t.bytes().all(|b| b.is_ascii_digit() || b == b'.')
        || t.bytes().filter(|&b| b == b'.').count() > 1
    {
        return None;
    }
    t.parse::<f32>().ok().filter(|v| v.is_finite())
}

#[cfg(test)]
#[allow(clippy::unwrap_used, clippy::expect_used)]
mod tests {
    use super::*;

    fn feed_all(acc: &mut LineAccumulator, s: &str) -> Vec<String> {
        let mut lines = Vec::new();
        for b in s.bytes() {
            if acc.feed(b) == AccEvent::Line {
                lines.push(acc.line().to_owned());
            }
        }
        lines
    }

    // C++: test_accumulator_cr_terminated_lines
    #[test]
    fn accumulator_cr_terminated_lines() {
        let mut acc = LineAccumulator::new();
        let mut ev = AccEvent::None;
        for b in "OK\r".bytes() {
            ev = acc.feed(b);
        }
        assert_eq!(ev, AccEvent::Line);
        assert_eq!(acc.line(), "OK");
    }

    // C++: test_accumulator_prompt_event
    #[test]
    fn accumulator_prompt_event() {
        let mut acc = LineAccumulator::new();
        assert_eq!(acc.feed(b'>'), AccEvent::Prompt);
    }

    // C++: test_accumulator_blank_lines_swallowed
    #[test]
    fn accumulator_blank_lines_swallowed() {
        let mut acc = LineAccumulator::new();
        assert_eq!(acc.feed(b'\r'), AccEvent::None);
        assert_eq!(acc.feed(b'\n'), AccEvent::None);
        assert_eq!(acc.feed(b'\r'), AccEvent::None);
    }

    // C++: test_accumulator_crlf_and_multiple_lines
    #[test]
    fn accumulator_crlf_and_multiple_lines() {
        let mut acc = LineAccumulator::new();
        let lines = feed_all(&mut acc, "ELM327 v1.4b\r\nOK\r\n");
        assert_eq!(lines, ["ELM327 v1.4b", "OK"]);
    }

    #[test]
    fn accumulator_prompt_discards_partial_line_and_nuls_are_ignored() {
        let mut acc = LineAccumulator::new();
        assert!(feed_all(&mut acc, "PART\0IAL").is_empty());
        assert_eq!(acc.pending_len(), 7);
        assert_eq!(acc.feed(b'>'), AccEvent::Prompt);
        assert_eq!(acc.pending_len(), 0);
    }

    #[test]
    fn accumulator_truncates_overlong_lines() {
        let mut acc = LineAccumulator::new();
        let long = "A".repeat(200) + "\r";
        let lines = feed_all(&mut acc, &long);
        assert_eq!(lines.len(), 1);
        assert_eq!(lines[0].len(), MAX_LINE_LEN);
    }

    // C++: test_classify_statuses
    #[test]
    fn classify_statuses() {
        assert_eq!(classify_line("OK"), LineClass::Ok);
        assert_eq!(classify_line("NO DATA"), LineClass::NoData);
        assert_eq!(classify_line("STOPPED"), LineClass::Stopped);
        assert_eq!(classify_line("SEARCHING..."), LineClass::Searching);
        assert_eq!(classify_line("CAN ERROR"), LineClass::CanError);
        assert_eq!(classify_line("BUFFER FULL"), LineClass::BufferFull);
        assert_eq!(
            classify_line("UNABLE TO CONNECT"),
            LineClass::UnableToConnect
        );
        assert_eq!(classify_line("?"), LineClass::Error);
        assert_eq!(classify_line("ACT ALERT"), LineClass::Ignorable);
        assert_eq!(classify_line("LV RESET"), LineClass::Ignorable);
        assert_eq!(classify_line("ELM327 v1.4b"), LineClass::Unknown);
    }

    #[test]
    fn classify_remaining_stn_chatter_and_variants() {
        assert_eq!(classify_line("LP ALERT"), LineClass::Ignorable);
        assert_eq!(classify_line("SLEEPING"), LineClass::Ignorable);
        assert_eq!(classify_line("WAKE UP"), LineClass::Ignorable);
        assert_eq!(classify_line("NODATA"), LineClass::NoData);
        assert_eq!(classify_line("CANERROR"), LineClass::CanError);
        assert_eq!(classify_line("BUFFERFULL"), LineClass::BufferFull);
        assert_eq!(classify_line("UNABLETOCONNECT"), LineClass::UnableToConnect);
        assert_eq!(classify_line("BUS INIT: ...ERROR"), LineClass::Error);
        assert_eq!(classify_line(""), LineClass::Unknown);
        assert_eq!(classify_line("A"), LineClass::Unknown);
        // ATDPN on this truck answers "A6": hex-shaped, so it must only ever be
        // read in raw mode (see the client's raw passthrough).
        assert_eq!(classify_line("A6"), LineClass::HexData);
        assert_eq!(classify_line("12.4V"), LineClass::Unknown);
    }

    // C++: test_classify_hex_data
    #[test]
    fn classify_hex_data() {
        assert_eq!(classify_line("7E804410C1AF8"), LineClass::HexData);
        assert_eq!(classify_line("41 0C 1A F8"), LineClass::HexData);
        assert_eq!(classify_line("41 0C 1A FX"), LineClass::Unknown);
    }

    // C++: test_hex_to_bytes
    #[test]
    fn hex_to_bytes_cases() {
        let out = hex_to_bytes("410C1AF8", 8).unwrap();
        assert_eq!(out.len(), 4);
        assert_eq!(out[0], 0x41);
        assert_eq!(out[3], 0xF8);
        assert_eq!(hex_to_bytes("410C1", 8), None); // odd length
        assert_eq!(hex_to_bytes("41ZZ", 8), None); // invalid chars
        assert_eq!(hex_to_bytes("0102030405060708FF", 8), None); // overflow
        assert_eq!(hex_to_bytes("", 8), None);
    }

    // C++: test_strip_spaces
    #[test]
    fn strip_spaces_removes_all_spaces() {
        assert_eq!(strip_spaces("41 0C 1A F8"), "410C1AF8");
    }

    #[test]
    fn hex_nibble_and_is_hex_string() {
        assert_eq!(hex_nibble(b'0'), Some(0));
        assert_eq!(hex_nibble(b'f'), Some(15));
        assert_eq!(hex_nibble(b'F'), Some(15));
        assert_eq!(hex_nibble(b'G'), None);
        assert!(is_hex_string("7E8"));
        assert!(!is_hex_string("7EG"));
    }

    // C++: test_parse_data_line_with_header
    #[test]
    fn parse_data_line_with_header() {
        let f = parse_data_line("7E804410C1AF8").unwrap();
        assert_eq!(f.can_id, Some(0x7E8));
        assert_eq!(f.data.len(), 5);
        assert_eq!(f.data[0], 0x04); // PCI
        assert_eq!(f.data[1], 0x41);
    }

    // C++: test_parse_data_line_headerless
    #[test]
    fn parse_data_line_headerless() {
        let f = parse_data_line("410C1AF8").unwrap();
        assert_eq!(f.can_id, None);
        assert_eq!(f.data.len(), 4);
        assert_eq!(f.data[0], 0x41);
    }

    // C++: test_parse_data_line_malformed
    #[test]
    fn parse_data_line_malformed() {
        assert_eq!(parse_data_line("4"), None);
        assert_eq!(parse_data_line(""), None);
        assert_eq!(parse_data_line("XYZ12"), None);
        assert_eq!(parse_data_line("7E8"), None); // header, no data
    }

    // C++: test_isotp_single_frame
    #[test]
    fn isotp_single_frame() {
        let mut r = IsoTpReassembler::new();
        let m = r.feed(&parse_data_line("7E804410C1AF8").unwrap()).unwrap();
        assert_eq!(m.data, [0x41, 0x0C, 0x1A, 0xF8]);
        assert_eq!(m.source, Some(0x7E8));
    }

    // C++: test_isotp_multi_frame
    #[test]
    fn isotp_multi_frame() {
        // 8-byte payload: 62 13 46 AA BB CC DD EE.
        let mut r = IsoTpReassembler::new();
        assert_eq!(
            r.feed(&parse_data_line("7E81008621346AABBCC").unwrap()),
            None
        );
        let m = r.feed(&parse_data_line("7E821DDEE").unwrap()).unwrap();
        assert_eq!(m.data, [0x62, 0x13, 0x46, 0xAA, 0xBB, 0xCC, 0xDD, 0xEE]);
    }

    // C++: test_isotp_interleaved_ecu_ignored
    #[test]
    fn isotp_interleaved_ecu_ignored() {
        let mut r = IsoTpReassembler::new();
        assert_eq!(
            r.feed(&parse_data_line("7E81008621346AABBCC").unwrap()),
            None
        );
        // Consecutive frame from the WRONG ECU (no slot open): ignored.
        assert_eq!(r.feed(&parse_data_line("7E92100FF").unwrap()), None);
        let m = r.feed(&parse_data_line("7E821DDEE").unwrap()).unwrap();
        assert_eq!(m.data.len(), 8);
        assert_eq!(m.data[7], 0xEE);
    }

    // C++: test_isotp_sequence_error_abandons
    #[test]
    fn isotp_sequence_error_abandons() {
        let mut r = IsoTpReassembler::new();
        assert_eq!(
            r.feed(&parse_data_line("7E81008621346AABBCC").unwrap()),
            None
        );
        assert_eq!(r.feed(&parse_data_line("7E822DDEE").unwrap()), None); // seq 2, expected 1
        assert_eq!(r.in_flight(), 0);
        // The correct frame can no longer complete anything.
        assert_eq!(r.feed(&parse_data_line("7E821DDEE").unwrap()), None);
    }

    // C++: test_isotp_headerless_passthrough
    #[test]
    fn isotp_headerless_passthrough() {
        let mut r = IsoTpReassembler::new();
        let m = r.feed(&parse_data_line("410C1AF8").unwrap()).unwrap();
        assert_eq!(m.source, None);
        assert_eq!(m.data.len(), 4);
        assert_eq!(m.data[0], 0x41);
    }

    #[test]
    fn isotp_two_senders_interleaved_both_complete() {
        // Grouped by CAN ID: 7E9's single frame arriving in the middle of 7E8's
        // multi-frame message must not abandon it (the C++ single-slot version
        // did).
        let mut r = IsoTpReassembler::new();
        assert_eq!(
            r.feed(&parse_data_line("7E81009621674AABBCC").unwrap()),
            None
        );
        let neg = r.feed(&parse_data_line("7E9037F2231").unwrap()).unwrap();
        assert_eq!(neg.source, Some(0x7E9));
        assert_eq!(neg.data, [0x7F, 0x22, 0x31]);
        let m = r.feed(&parse_data_line("7E821DDEEFF").unwrap()).unwrap();
        assert_eq!(m.source, Some(0x7E8));
        assert_eq!(
            m.data,
            [0x62, 0x16, 0x74, 0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0xFF]
        );
    }

    #[test]
    fn isotp_rejects_bad_single_and_first_frames() {
        let mut r = IsoTpReassembler::new();
        assert_eq!(r.feed(&parse_data_line("7E800410C").unwrap()), None); // dl 0
        assert_eq!(r.feed(&parse_data_line("7E805410C").unwrap()), None); // dl > bytes
        assert_eq!(
            r.feed(&parse_data_line("7E81007621346AABBCC").unwrap()),
            None
        ); // total < 8
        assert_eq!(r.in_flight(), 0);
        assert_eq!(r.feed(&parse_data_line("7E830000000").unwrap()), None); // flow control
    }

    #[test]
    fn isotp_three_frame_message_and_padding() {
        // 15-byte message: FF (6) + CF1 (7) + CF2 (2 of 7, rest padding).
        let mut r = IsoTpReassembler::new();
        assert_eq!(
            r.feed(&parse_data_line("7E8100F490201314731").unwrap()),
            None
        );
        assert_eq!(
            r.feed(&parse_data_line("7E82132333435363738").unwrap()),
            None
        );
        let m = r
            .feed(&parse_data_line("7E8223940AAAAAAAAAA").unwrap())
            .unwrap();
        assert_eq!(m.data.len(), 15);
        assert_eq!(m.data[..3], [0x49, 0x02, 0x01]);
        assert_eq!(m.data[14], 0x40);
    }

    #[test]
    fn voltage_parsing() {
        assert_eq!(parse_voltage("12.4V"), Some(12.4));
        assert_eq!(parse_voltage(" 13.9V "), Some(13.9));
        assert_eq!(parse_voltage("12.4"), Some(12.4));
        assert_eq!(parse_voltage("12v"), Some(12.0));
        assert_eq!(parse_voltage("V"), None);
        assert_eq!(parse_voltage(""), None);
        assert_eq!(parse_voltage("?"), None);
        assert_eq!(parse_voltage("infV"), None);
        assert_eq!(parse_voltage("NaN"), None);
        assert_eq!(parse_voltage("-1.0V"), None);
        assert_eq!(parse_voltage("1.2.3V"), None);
        assert_eq!(parse_voltage("ELM327 v1.4b"), None);
    }
}
