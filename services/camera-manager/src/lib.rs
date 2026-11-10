//! camera-manager: shows the camera the policy picks, as a `gst-launch-1.0`
//! pipeline whose `waylandsink` window agl-compositor keeps inside the
//! dashboard's activation area ([ADR-0009](../../../docs/architecture/adr/0009-camera-rendering.md),
//! [ADR-0026](../../../docs/architecture/adr/0026-camera-manager-interfaces.md)),
//! and serves `f250.camera.v1` so the dashboard can draw around it.
//!
//! - [`config`]: the command line.
//! - [`pipeline`]: one `gst-launch` child process and its frame count.
//! - [`manager`]: the control loop around `crates/camera-policy`.
//! - [`server`]: the gRPC service.
//!
//! Status: `[SIM]`. The tests run the loop against a fake `gst-launch`.
//! Counting frames from `gst-launch -v` output is UNVERIFIED on the Pi, and
//! nothing reads reverse or speed from the gateway yet (automatic reverse
//! and the speed limit are off by default).

pub mod config;
pub mod manager;
pub mod pipeline;
pub mod server;
