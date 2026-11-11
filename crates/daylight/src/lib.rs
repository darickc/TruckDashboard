//! Day or night for the head unit's display, and how bright the backlight is
//! ([ADR-0028](../../../docs/architecture/adr/0028-day-night-and-backlight.md)).
//!
//! There is no illumination wire and no light sensor, so the automatic input
//! is the sun: its elevation from the wall clock and a configured location
//! ([`sun`]). [`decide`] turns that and the driver's choice (Auto, Day,
//! Night) into a [`Mode`], and says honestly when Auto can't run: no
//! location, or a clock that can't be believed. [`brightness`] maps the
//! driver's per-mode levels onto the backlight, never below a floor, and
//! ramps between them. [`prefs`] is the small file power-manager keeps them
//! in.
//!
//! Everything here is pure: no clock, no files, no sysfs. power-manager does
//! the I/O.
//!
//! Status: `[SIM]`. The sun's elevation is checked against an independent
//! implementation of NOAA's solar calculator and against published sunrise
//! times; every threshold is an example value.

pub mod brightness;
pub mod decide;
pub mod prefs;
pub mod sun;

pub use decide::{Basis, Choice, DayNight, Decision, Mode, SunState, Thresholds, Unavailable};
pub use sun::Location;
