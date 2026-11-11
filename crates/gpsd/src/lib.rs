//! gpsd for the head unit (Phase 6.4, ADR-0030).
//!
//! gpsd owns the GNSS receiver; this crate reads what gpsd says and keeps
//! the truck's position honestly:
//!
//! - [`report`] parses gpsd's JSON reports (gpsd_json(5)): the `TPV` fix,
//!   `SKY` satellites, and `DEVICES`/`DEVICE` (is a receiver there?).
//! - [`tracker`] turns them into a [`tracker::Position`]: the status (no
//!   gpsd, no receiver, receiver silent, no fix, 2D, 3D), the last good fix
//!   and its age. A fix older than the stale limit is reported stale, never
//!   as current (CLAUDE.md rule 4).
//! - [`time`] reads gpsd's UTC timestamps.
//!
//! The test vectors in `tests/data/` are gpsd 3.27.5's own output, the
//! version in the AGL 22.0.1 image, fed synthetic NMEA over UDP on the Mac
//! [SIM]. No receiver has been chosen yet (H11), so a real receiver's output
//! (u-blox binary messages, gpsd's other drivers) is UNVERIFIED.

pub mod report;
pub mod time;
pub mod tracker;

/// What a client sends gpsd to get JSON reports from every receiver.
pub const WATCH: &str = "?WATCH={\"enable\":true,\"json\":true}\n";

/// gpsd's default port on the loopback interface.
pub const DEFAULT_ADDR: &str = "127.0.0.1:2947";
