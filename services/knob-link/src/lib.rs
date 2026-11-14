//! knob-link (ADR-0044): reads vehicle-gateway's snapshots and writes the
//! knob display's frames to its USB serial port. The dial never talks to the
//! truck (CLAUDE.md rule 5); its knob reaches audio-manager as a USB HID
//! device, not through here.

pub mod frame;
pub mod link;
pub mod pages;
