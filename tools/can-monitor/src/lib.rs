//! Offline analysis of `candump -l` logs from the truck's HS-CAN (Phase 4.2).
//!
//! - [`candump`]: parses the log.
//! - [`census`]: per-ID rates, periods, changing bytes, and silences.
//! - [`pids`]: OBD answers on the wire (`7E8`–`7EF`), decoded with the
//!   signal registry (`shared/signals`), plus what the tester sent.
//! - [`correlate`]: fits broadcast byte fields against a decoded PID.
//!
//! The intended capture is listen-only, with the MX+ polling through a
//! Y-splitter: its requests and the modules' answers are frames on the same
//! bus, so they land in the same log as the broadcasts with the same clock
//! (docs/diagnostics/CAN_CENSUS.md). Nothing here touches a bus.
//!
//! A good fit makes a broadcast field a **candidate**. It becomes a decoder
//! only after Stage B corroboration and a VERIFICATION_LOG.md entry.

pub mod candump;
pub mod census;
pub mod correlate;
pub mod pids;
