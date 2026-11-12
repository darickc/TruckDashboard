//! `usb-export`: copies dashcam recordings from the data drive to a USB
//! stick plugged into the head unit, for the dashboard (ADR-0037).
//!
//! - [`sticks`]: finding USB sticks in sysfs and udev's database
//! - [`stickfs`]: mounting them (only while checking or copying), free space
//! - [`copy`]: which recordings, whether they fit, and the copy
//! - [`exporter`]: the state the API serves: sticks, roles, the copy
//! - [`server`]: the `f250.export.v1` API
//!
//! Copy only: the data drive is read, never changed. Status: `[SIM]`.

pub mod copy;
pub mod exporter;
pub mod server;
pub mod stickfs;
pub mod sticks;
