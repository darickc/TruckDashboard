//! audio-manager (Phase 6.1, ADR-0039): Bluetooth audio from a phone
//! (A2DP sink through PipeWire, AVRCP now playing and controls through
//! BlueZ, a pairing window opened from the dashboard) and the speakers'
//! PipeWire filter-chain for the DAC8x (crossover, fader, balance, sub
//! level; ADR-0014). Serves `f250.audio.v1`.
//!
//! Not here yet: DAC mute sequencing (6.2) and the volume knob (6.3); the
//! manager's settings and the filter-chain are where they will attach.

pub mod backend;
pub mod bluez;
pub mod dsp;
pub mod manager;
pub mod model;
pub mod objects;
pub mod pairing;
pub mod runner;
pub mod server;
pub mod sim;
