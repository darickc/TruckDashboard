//! Command-line configuration. Every time and limit here is an example
//! default, not a measured requirement.

use std::time::Duration;

use camera_policy::Camera;
use clap::Parser;

/// The bench pipeline's source caps (bench-log 2026-11-09): the webcam's
/// MJPEG at 640x480, 30 fps, decoded on the CPU.
pub const DEFAULT_CAPS: &str = "image/jpeg,width=640,height=480,framerate=30/1 ! jpegdec";

#[derive(Parser, Debug, Clone)]
#[command(
    name = "camera-manager",
    about = "Shows the camera the policy picks, as a gst-launch pipeline with a window of its own \
             (ADR-0009, ADR-0026), and serves f250.camera.v1"
)]
pub struct Config {
    /// Where to serve the API: unix:PATH or tcp:HOST:PORT (development).
    #[arg(long, default_value = "unix:/tmp/f250/camera.sock")]
    pub listen: String,

    /// A camera and its V4L2 device, e.g. rear=/dev/v4l/by-id/usb-...-video-index0.
    /// Names: left, right, rear. Repeat for each camera. A camera with no
    /// device shows as unavailable when chosen.
    #[arg(long = "camera", value_name = "NAME=DEVICE", value_parser = parse_camera)]
    pub cameras: Vec<(Camera, String)>,

    /// Caps and decoder after v4l2src.
    #[arg(long, default_value = DEFAULT_CAPS)]
    pub caps: String,

    /// The video sink: the window the compositor places in the dashboard's
    /// activation area.
    #[arg(long, default_value = "waylandsink")]
    pub sink: String,

    /// The program that runs a pipeline. Tests point this at a fake.
    #[arg(long, default_value = "gst-launch-1.0")]
    pub gst_launch: String,

    /// A live camera with no frame for this long is unavailable: its
    /// pipeline is stopped so no frozen frame stays on screen.
    #[arg(long, default_value_t = 1000)]
    pub frame_timeout_ms: u64,

    /// A starting pipeline with no first frame after this long is
    /// unavailable. The bench webcam took 0.62 s.
    #[arg(long, default_value_t = 5000)]
    pub start_timeout_ms: u64,

    /// First wait before restarting a failed pipeline; it doubles on each
    /// failure up to --restart-max-ms.
    #[arg(long, default_value_t = 1000)]
    pub restart_min_ms: u64,

    #[arg(long, default_value_t = 10_000)]
    pub restart_max_ms: u64,
}

impl Config {
    pub fn settings(&self) -> Settings {
        Settings {
            cameras: self.cameras.clone(),
            caps: self.caps.clone(),
            sink: self.sink.clone(),
            gst_launch: self.gst_launch.clone(),
            frame_timeout: Duration::from_millis(self.frame_timeout_ms),
            start_timeout: Duration::from_millis(self.start_timeout_ms),
            restart_min: Duration::from_millis(self.restart_min_ms),
            restart_max: Duration::from_millis(self.restart_max_ms.max(self.restart_min_ms)),
            policy: camera_policy::Config::default(),
        }
    }
}

/// What the manager needs, separate from argument parsing so tests can
/// build it directly.
#[derive(Debug, Clone)]
pub struct Settings {
    pub cameras: Vec<(Camera, String)>,
    pub caps: String,
    pub sink: String,
    pub gst_launch: String,
    pub frame_timeout: Duration,
    pub start_timeout: Duration,
    pub restart_min: Duration,
    pub restart_max: Duration,
    /// Automatic reverse and the speed limit stay off (their defaults):
    /// camera-manager doesn't read the gateway yet (ADR-0026 decision 5).
    pub policy: camera_policy::Config,
}

impl Settings {
    pub fn device(&self, camera: Camera) -> Option<&str> {
        self.cameras
            .iter()
            .rev() // the last --camera for a name wins
            .find(|(c, _)| *c == camera)
            .map(|(_, d)| d.as_str())
    }
}

pub fn camera_name(c: Camera) -> &'static str {
    match c {
        Camera::Left => "left",
        Camera::Right => "right",
        Camera::Rear => "rear",
    }
}

fn parse_camera(s: &str) -> Result<(Camera, String), String> {
    let (name, device) = s
        .split_once('=')
        .ok_or_else(|| format!("expected NAME=DEVICE, got {s:?}"))?;
    let camera = match name {
        "left" => Camera::Left,
        "right" => Camera::Right,
        "rear" => Camera::Rear,
        _ => return Err(format!("unknown camera {name:?}: use left, right or rear")),
    };
    if device.is_empty() {
        return Err(format!("no device for {name}"));
    }
    Ok((camera, device.to_string()))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_cameras_and_rejects_bad_ones() {
        let c = Config::try_parse_from([
            "camera-manager",
            "--camera",
            "rear=/dev/video0",
            "--camera",
            "left=/dev/video2",
        ])
        .expect("valid");
        let s = c.settings();
        assert_eq!(s.device(Camera::Rear), Some("/dev/video0"));
        assert_eq!(s.device(Camera::Left), Some("/dev/video2"));
        assert_eq!(s.device(Camera::Right), None);

        for bad in ["front=/dev/video0", "rear", "rear="] {
            assert!(
                Config::try_parse_from(["camera-manager", "--camera", bad]).is_err(),
                "{bad} accepted"
            );
        }
    }

    #[test]
    fn last_device_for_a_camera_wins_and_backoff_max_is_at_least_min() {
        let c = Config::try_parse_from([
            "camera-manager",
            "--camera",
            "rear=/dev/video0",
            "--camera",
            "rear=/dev/video4",
            "--restart-min-ms",
            "3000",
            "--restart-max-ms",
            "100",
        ])
        .expect("valid");
        let s = c.settings();
        assert_eq!(s.device(Camera::Rear), Some("/dev/video4"));
        assert_eq!(s.restart_max, Duration::from_millis(3000));
    }

    #[test]
    fn defaults_are_the_bench_pipeline_and_auto_reverse_off() {
        let s = Config::try_parse_from(["camera-manager"])
            .expect("valid")
            .settings();
        assert_eq!(s.caps, DEFAULT_CAPS);
        assert_eq!(s.sink, "waylandsink");
        assert!(!s.policy.auto_reverse);
        assert_eq!(s.policy.manual_max_speed_kph, None);
    }
}
