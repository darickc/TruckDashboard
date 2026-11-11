//! Command-line configuration. Every time and limit here is an example
//! default, not a measured requirement.
//!
//! Recording's retention settings (`RECORD_MAX_AGE_DAYS` and the rest,
//! ADR-0027 decision 7) come from the environment, as the unit's
//! `EnvironmentFile=/etc/default/f250` sets them; absent ones keep the 512 GB
//! drive's recommendations (`crates/recording`).

use std::collections::HashMap;
use std::path::PathBuf;
use std::time::Duration;

use camera_policy::Camera;
use clap::{Parser, ValueEnum};

use crate::drive::{Clock, SystemClock};

/// Where recordings go: on the data drive (ADR-0027 decision 6).
pub const DEFAULT_RECORD_DIR: &str = "/var/lib/f250/storage/video";

/// The bench pipeline's source caps (bench-log 2026-11-09): the webcam's
/// MJPEG at 640x480, 30 fps, decoded on the CPU.
pub const DEFAULT_CAPS: &str = "image/jpeg,width=640,height=480,framerate=30/1 ! jpegdec";

#[derive(Parser, Debug, Clone)]
#[command(
    name = "camera-manager",
    about = "Shows the camera the policy picks in a window of its own (ADR-0009, ADR-0026), records \
             front and rear (ADR-0027), and serves f250.camera.v1. Retention settings come from the \
             RECORD_* environment variables (/etc/default/f250)"
)]
pub struct Config {
    /// Where to serve the API: unix:PATH or tcp:HOST:PORT (development).
    #[arg(long, default_value = "unix:/tmp/f250/camera.sock")]
    pub listen: String,

    /// A camera and its V4L2 device, e.g.
    /// rear=/dev/v4l/by-path/platform-...-usb-0:1:1.0-video-index0 (by-path
    /// follows the USB port, so identical cameras stay apart). Names: front,
    /// left, right, rear. Repeat for each camera. A camera with no
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

    /// How pipelines run. gstreamer: in-process, one capture per camera,
    /// recording front and rear (needs the `gstreamer` build). launch: a
    /// gst-launch-1.0 child for the camera on screen; no recording.
    #[arg(long, value_enum, default_value_t = MediaChoice::default())]
    pub media: MediaChoice,

    /// Cameras to record, comma-separated (RECORD_CAMERAS): front, rear.
    /// Empty: recording is off.
    #[arg(long, value_name = "CAMERAS", default_value = "", value_parser = parse_record)]
    pub record: RecordCameras,

    /// Where recordings go. Only ever on the data drive.
    #[arg(long, default_value = DEFAULT_RECORD_DIR)]
    pub record_dir: PathBuf,

    /// The data drive's mount point: nothing is recorded unless it is
    /// mounted, so the SD card is never used (ADR-0027 decision 6). Empty:
    /// not checked (development only).
    #[arg(long, default_value = "/var/lib/f250/storage")]
    pub record_drive: String,

    /// Whether segment names carry the wall time: ntp trusts the clock
    /// while the system says it is synchronized (timedatectl's
    /// NTPSynchronized, or systemd-timesyncd's flag file); trusted and
    /// untrusted are for development (ADR-0027 decision 10).
    #[arg(long, value_enum, default_value_t = ClockChoice::Ntp)]
    pub clock: ClockChoice,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, ValueEnum)]
pub enum MediaChoice {
    Gstreamer,
    Launch,
}

impl Default for MediaChoice {
    fn default() -> Self {
        if cfg!(feature = "gstreamer") {
            MediaChoice::Gstreamer
        } else {
            MediaChoice::Launch
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, ValueEnum)]
pub enum ClockChoice {
    Ntp,
    Trusted,
    Untrusted,
}

#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct RecordCameras(pub Vec<Camera>);

impl Config {
    /// The manager's settings. `env`: the RECORD_* variables.
    pub fn settings_with(&self, env: &HashMap<String, String>) -> Result<Settings, String> {
        let recording = if self.record.0.is_empty() {
            None
        } else {
            Some(RecordingConfig {
                cameras: self.record.0.clone(),
                root: self.record_dir.clone(),
                mount: (!self.record_drive.trim().is_empty())
                    .then(|| PathBuf::from(self.record_drive.trim())),
                settings: recording::settings::Settings::from_vars(env)?,
                clock: match self.clock {
                    ClockChoice::Ntp => Clock::System(SystemClock::default()),
                    ClockChoice::Trusted => Clock::Trusted,
                    ClockChoice::Untrusted => Clock::Untrusted,
                },
            })
        };
        Ok(Settings {
            recording,
            ..self.settings()
        })
    }

    /// The manager's settings, recording off.
    pub fn settings(&self) -> Settings {
        Settings {
            recording: None,
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
    /// `None`: recording is off.
    pub recording: Option<RecordingConfig>,
}

/// Front and rear recording (ADR-0027).
#[derive(Debug, Clone)]
pub struct RecordingConfig {
    /// Front and/or rear, never left or right (decision 1).
    pub cameras: Vec<Camera>,
    pub root: PathBuf,
    /// The data drive's mount point; `None`: not checked.
    pub mount: Option<PathBuf>,
    pub settings: recording::settings::Settings,
    pub clock: Clock,
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
        Camera::Front => "front",
    }
}

fn parse_record(s: &str) -> Result<RecordCameras, String> {
    let mut out = Vec::new();
    for name in s.split(',').map(str::trim).filter(|n| !n.is_empty()) {
        let c = match name {
            "front" => Camera::Front,
            "rear" => Camera::Rear,
            "left" | "right" => {
                return Err(format!(
                    "{name}: only front and rear are recorded (ADR-0027 decision 1)"
                ));
            }
            _ => return Err(format!("unknown camera {name:?}: use front and/or rear")),
        };
        if !out.contains(&c) {
            out.push(c);
        }
    }
    Ok(RecordCameras(out))
}

fn parse_camera(s: &str) -> Result<(Camera, String), String> {
    let (name, device) = s
        .split_once('=')
        .ok_or_else(|| format!("expected NAME=DEVICE, got {s:?}"))?;
    let camera = match name {
        "left" => Camera::Left,
        "right" => Camera::Right,
        "rear" => Camera::Rear,
        "front" => Camera::Front,
        _ => {
            return Err(format!(
                "unknown camera {name:?}: use front, left, right or rear"
            ));
        }
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
            "--camera",
            "front=/dev/video4",
        ])
        .expect("valid");
        let s = c.settings();
        assert_eq!(s.device(Camera::Front), Some("/dev/video4"));
        assert_eq!(s.device(Camera::Rear), Some("/dev/video0"));
        assert_eq!(s.device(Camera::Left), Some("/dev/video2"));
        assert_eq!(s.device(Camera::Right), None);

        for bad in ["top=/dev/video0", "rear", "rear="] {
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
    fn record_takes_front_and_rear_only() {
        let c = Config::try_parse_from(["camera-manager", "--record", "rear, front,rear"])
            .expect("valid");
        assert_eq!(c.record.0, vec![Camera::Rear, Camera::Front]);
        for bad in ["left", "front,right", "top"] {
            assert!(
                Config::try_parse_from(["camera-manager", "--record", bad]).is_err(),
                "{bad} accepted"
            );
        }
        let off = Config::try_parse_from(["camera-manager"]).expect("valid");
        assert!(off.record.0.is_empty());
        assert!(
            off.settings_with(&HashMap::new())
                .expect("valid")
                .recording
                .is_none()
        );
    }

    #[test]
    fn recording_settings_come_from_the_environment_and_bad_ones_are_errors() {
        let c = Config::try_parse_from([
            "camera-manager",
            "--record",
            "front,rear",
            "--record-dir",
            "/tmp/v",
            "--record-drive",
            "",
            "--clock",
            "untrusted",
        ])
        .expect("valid");
        let env: HashMap<String, String> = [("RECORD_MAX_AGE_DAYS".to_string(), "7".to_string())]
            .into_iter()
            .collect();
        let r = c.settings_with(&env).expect("valid").recording.expect("on");
        assert_eq!(r.settings.max_age_days, 7);
        assert_eq!(r.settings.segment_s, 60, "the recommendation");
        assert_eq!(r.mount, None);
        assert_eq!(r.clock, Clock::Untrusted);
        let bad: HashMap<String, String> = [("RECORD_SYNC_S".to_string(), "0".to_string())]
            .into_iter()
            .collect();
        let e = c.settings_with(&bad).expect_err("bad");
        assert!(e.starts_with("RECORD_SYNC_S"), "{e}");
        let d = Config::try_parse_from(["camera-manager", "--record", "front"]).expect("valid");
        let r = d
            .settings_with(&HashMap::new())
            .expect("valid")
            .recording
            .expect("on");
        assert_eq!(r.root, PathBuf::from(DEFAULT_RECORD_DIR));
        assert_eq!(r.mount, Some(PathBuf::from("/var/lib/f250/storage")));
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
