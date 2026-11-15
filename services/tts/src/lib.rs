//! The spoken directions' voice (ADR-0048).
//!
//! Piper takes about 1.4 s to load a voice on the Pi 5 and then about a
//! quarter of the speech's length to say it (bench, 2026-11-15), so
//! `tts serve` loads it once and keeps it: `speak-prompt` asks for each
//! prompt over a unix socket (`tts say`) and plays the WAV it gets back, as
//! it plays Flite's. With no service, `speak-prompt` falls back to Flite.
//!
//! - [`wav`]: 16-bit PCM WAV from Piper's float samples.
//! - [`server`]: the socket protocol and the loop, over any [`server::Engine`].
//! - [`piper`]: the engine, libpiper loaded at run time (the one place with
//!   unsafe code).
//!
//! The protocol: the client sends the text (UTF-8, at most
//! [`server::MAX_TEXT`] bytes) and shuts down its write side; the server
//! answers with a complete WAV and closes. Any failure closes the connection
//! with nothing sent, and the client reports it.

pub mod piper;
pub mod server;
pub mod wav;
