//! audio-manager (Phase 6.1, ADR-0039): Bluetooth audio from a phone
//! (A2DP sink through PipeWire, AVRCP now playing and controls through
//! BlueZ, a pairing window opened from the dashboard) and the speakers'
//! PipeWire filter-chain for the DAC8x (crossover, fader, balance, sub
//! level; ADR-0014). Serves `f250.audio.v1`.
//!
//! Phone calls (ADR-0045, phase 1): the connected phone's calls through
//! PipeWire's Telephony service, answered, declined and hung up from the
//! dashboard, with the music paused and prompts skipped during a call
//! (`calls.rs`, `telephony.rs`, `sim_calls.rs`). Only with a call
//! microphone configured; the call audio path itself is the bench's (S3).
//! Phase 2: dialling, and the phone's contacts and recent calls over PBAP
//! (`phonebook.rs`).
//!
//! Audio left unlinked by WirePlumber is put on the screen and in the log
//! (`routing.rs`, bench-log 2026-11-15).

pub mod backend;
pub mod bluez;
pub mod call_audio;
pub mod calls;
pub mod cover_art;
pub mod dsp;
pub mod knob;
pub mod manager;
pub mod model;
pub mod objects;
pub mod pairing;
pub mod phonebook;
pub mod prompts;
pub mod ring;
pub mod routing;
pub mod runner;
pub mod server;
pub mod sim;
pub mod sim_calls;
pub mod telephony;
pub mod voice;
pub mod volume;
