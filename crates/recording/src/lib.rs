//! Front and rear recording, the parts that decide
//! ([ADR-0027](../../../docs/architecture/adr/0027-front-and-rear-recording.md)):
//!
//! - [`segment`]: segment names, carrying the wall time only when the clock
//!   was trusted (decision 10)
//! - [`settings`]: the retention settings and their recommendations
//!   (decision 7)
//! - [`retention`]: which recordings to delete, oldest first, never a
//!   segment being written or a saved clip (decision 7)
//! - [`protect`]: "save clip", and the minutes before an unclean stop
//!   (decision 8)
//! - [`store`]: the files on the data drive, the run counter and the
//!   clean-stop marker
//!
//! Everything but [`store`] is pure: inputs in, decisions out, so the tests
//! need no clock and no drive. The drive's free space comes from the caller.
//! Recording itself (GStreamer, decision 2) is camera-manager's and isn't
//! built yet.
//!
//! Status: `[SIM]`, unit and filesystem tests only.

pub mod protect;
pub mod retention;
pub mod segment;
pub mod settings;
pub mod store;
