//! How a camera is captured: the seam between the control loop
//! ([`crate::manager`]) and GStreamer.
//!
//! One [`Capture`] per camera, at most. It has up to two branches
//! (ADR-0027 decision 2):
//!
//! - **display**: decodes and shows the picture in its own window
//!   (`waylandsink`), only while the camera is on screen;
//! - **record**: the camera's own MJPEG or H.264, as it comes, into Matroska
//!   segments on the data drive, while the camera is set to record.
//!
//! Two implementations:
//!
//! - [`crate::pipeline`] (`gst-launch-1.0` children, ADR-0026 decision 3):
//!   display only. It is what a build without GStreamer's development files
//!   has (the Mac), and `--media launch` in a build with them.
//! - `crate::gst` (feature `gstreamer`): in-process gstreamer-rs, both
//!   branches from one capture with a `tee`, frames counted by pad probes.
//!
//! The tests drive the loop through a fake of their own.

use std::future::Future;
use std::path::PathBuf;
use std::pin::Pin;
use std::sync::Arc;
use std::time::Duration;

use camera_policy::Camera;
use tokio::sync::mpsc;

/// Which branch of a capture an event is about.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Branch {
    Display,
    Record,
}

/// What a capture reports. `generation` tells a stopped capture's late
/// events from the current one's.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Event {
    /// A buffer passed the branch's counting point.
    Frame { generation: u64, branch: Branch },
    /// The recording branch opened a new segment file.
    SegmentOpened { generation: u64, path: PathBuf },
    /// The recording branch finished a segment file: it is complete and
    /// closed (a cut segment never gets this).
    SegmentClosed { generation: u64, path: PathBuf },
    /// The capture ended or failed. `detail` is the last error, if any.
    Ended { generation: u64, detail: String },
}

impl Event {
    pub fn generation(&self) -> u64 {
        match self {
            Event::Frame { generation, .. }
            | Event::SegmentOpened { generation, .. }
            | Event::SegmentClosed { generation, .. }
            | Event::Ended { generation, .. } => *generation,
        }
    }
}

/// Names each new segment, from GStreamer's streaming thread: the path of
/// the file to open next.
pub type NextSegment = Arc<dyn Fn() -> PathBuf + Send + Sync>;

/// The recording branch.
#[derive(Clone)]
pub struct RecordSpec {
    /// Segment length (`RECORD_SEGMENT_S`).
    pub segment: Duration,
    /// The muxer closes a cluster at least this often, so each second on the
    /// drive is complete data (ADR-0027 decision 5).
    pub cluster: Duration,
    pub next_segment: NextSegment,
}

impl std::fmt::Debug for RecordSpec {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("RecordSpec")
            .field("segment", &self.segment)
            .field("cluster", &self.cluster)
            .finish_non_exhaustive()
    }
}

/// One capture to start.
#[derive(Debug, Clone)]
pub struct CaptureSpec {
    pub camera: Camera,
    pub device: String,
    /// `--caps`: the camera's caps, then the decoder for the display branch,
    /// e.g. `image/jpeg,width=640,height=480,framerate=30/1 ! jpegdec`.
    /// See [`split_caps`].
    pub caps: String,
    /// The display branch's sink (`waylandsink`).
    pub sink: String,
    /// Start with the display branch.
    pub display: bool,
    /// Start with the recording branch.
    pub record: Option<RecordSpec>,
    pub generation: u64,
}

pub type StopFuture = Pin<Box<dyn Future<Output = bool> + Send>>;

/// A running capture. Dropping it without [`Capture::stop`] tears it down
/// without finishing the segment being written.
pub trait Capture: Send {
    fn generation(&self) -> u64;
    /// Adds or removes the display branch (its window) while the recording
    /// branch keeps running. Only meaningful on a recording capture.
    fn set_display(&mut self, on: bool) -> Result<(), String>;
    /// Stops it. A recording capture gets an end-of-stream first, so its
    /// last segment is finished (ADR-0027 decision 4). Resolves to `true`
    /// when everything finished cleanly, `false` when it had to be cut off.
    fn stop(self: Box<Self>) -> StopFuture;
}

/// Starts captures.
pub trait Media: Send {
    /// Why this media can't record, or `Ok` if it can.
    fn can_record(&self) -> Result<(), String>;
    fn start(
        &mut self,
        spec: CaptureSpec,
        events: mpsc::Sender<Event>,
    ) -> Result<Box<dyn Capture>, String>;
}

/// What the camera sends, from the first part of `--caps`.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Encoding {
    Mjpeg,
    H264,
    /// Raw video or anything else: shown, never recorded (decision 3).
    Other,
}

/// Splits `--caps` into the camera's caps (what the `tee` and the recording
/// see) and the display branch's decoder chain (empty if none):
/// `image/jpeg,width=640 ! jpegdec` → (`image/jpeg,width=640`, `jpegdec`).
pub fn split_caps(caps: &str) -> (&str, &str) {
    match caps.split_once('!') {
        Some((camera, decode)) => (camera.trim(), decode.trim()),
        None => (caps.trim(), ""),
    }
}

/// What the camera's caps say it sends.
pub fn encoding(camera_caps: &str) -> Encoding {
    let media = camera_caps.split(',').next().unwrap_or("").trim();
    match media {
        "image/jpeg" => Encoding::Mjpeg,
        "video/x-h264" => Encoding::H264,
        _ => Encoding::Other,
    }
}

/// Why a camera with these caps can't be recorded, if it can't
/// (ADR-0027 decision 3: record what the camera sends; raw isn't recorded).
pub fn recordable(caps: &str) -> Result<Encoding, String> {
    let (camera, _) = split_caps(caps);
    match encoding(camera) {
        Encoding::Other => Err(format!(
            "the camera's caps ({camera}) aren't MJPEG or H.264: raw video isn't recorded"
        )),
        e => Ok(e),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn caps_split_into_camera_and_decoder() {
        assert_eq!(
            split_caps("image/jpeg,width=640,height=480,framerate=30/1 ! jpegdec"),
            ("image/jpeg,width=640,height=480,framerate=30/1", "jpegdec")
        );
        assert_eq!(
            split_caps("video/x-h264,width=1280 ! h264parse ! avdec_h264"),
            ("video/x-h264,width=1280", "h264parse ! avdec_h264")
        );
        assert_eq!(split_caps("video/x-raw"), ("video/x-raw", ""));
    }

    #[test]
    fn only_mjpeg_and_h264_are_recorded() {
        assert_eq!(recordable("image/jpeg ! jpegdec"), Ok(Encoding::Mjpeg));
        assert_eq!(
            recordable("video/x-h264,stream-format=byte-stream ! avdec_h264"),
            Ok(Encoding::H264)
        );
        let e = recordable("video/x-raw,format=YUY2").expect_err("raw");
        assert!(e.contains("raw video isn't recorded"), "{e}");
    }
}
