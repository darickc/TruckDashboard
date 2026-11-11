//! camera-manager: shows the camera the policy picks in a window of its
//! own, which agl-compositor keeps inside the dashboard's activation area
//! ([ADR-0009](../../../docs/architecture/adr/0009-camera-rendering.md),
//! [ADR-0026](../../../docs/architecture/adr/0026-camera-manager-interfaces.md)),
//! records the front and rear cameras like a dashcam
//! ([ADR-0027](../../../docs/architecture/adr/0027-front-and-rear-recording.md)),
//! and serves `f250.camera.v1` so the dashboard can draw around it.
//!
//! - [`config`]: the command line.
//! - [`media`]: how a camera is captured, display and recording branches.
//! - [`pipeline`]: display through `gst-launch-1.0` children (no recording).
//! - `gst` (feature `gstreamer`): in-process GStreamer, both branches from
//!   one capture.
//! - [`drive`]: the recordings on the data drive: retention, saved clips,
//!   the run counter.
//! - [`manager`]: the control loop around `crates/camera-policy`.
//! - [`server`]: the gRPC service.
//!
//! Status: `[SIM]`. The loop's tests run against a fake `gst-launch` and a
//! fake media; the GStreamer media's tests run real pipelines from
//! `videotestsrc` in Linux (`make linux-test`). Nothing reads reverse or
//! speed from the gateway yet (automatic reverse and the speed limit are off
//! by default). Recording `[BENCH]` 2026-11-10 on the Pi with two webcams
//! onto a tmpfs in the data drive's place (bench-log); no real drive yet.

pub mod config;
pub mod drive;
#[cfg(feature = "gstreamer")]
pub mod gst;
pub mod manager;
pub mod media;
pub mod pipeline;
pub mod server;
