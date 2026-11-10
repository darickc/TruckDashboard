//! One camera pipeline: a `gst-launch-1.0` child process (ADR-0026).
//!
//! An `identity` element just before the sink reports every buffer on
//! stdout when `gst-launch` runs with `-v`; each such line counts as a frame.
//! That output format is UNVERIFIED on the Pi's GStreamer 1.28.5: check it on
//! the bench before trusting the frame count.

use std::process::Stdio;
use std::sync::{Arc, Mutex};

use tokio::io::{AsyncBufReadExt, BufReader};
use tokio::process::{Child, Command};
use tokio::sync::mpsc;

/// The `identity` element's name in the pipeline.
pub const FRAME_ELEMENT: &str = "f250_frames";

/// What `gst-launch -v` prints for each buffer through the identity element.
pub const FRAME_MARK: &str = "f250_frames: last-message = chain";

/// What a running pipeline reports. `generation` tells a stopped pipeline's
/// late events from the current one's.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Event {
    Frame {
        generation: u64,
    },
    /// The process ended (or closed its output). `detail` is the last
    /// error line it printed, if any.
    Ended {
        generation: u64,
        detail: String,
    },
}

/// `gst-launch` arguments for one camera:
/// `-v v4l2src device=DEV ! CAPS ! videoconvert ! identity ... ! SINK`.
/// `caps` and `sink` may hold several elements joined by `!`.
pub fn args(device: &str, caps: &str, sink: &str) -> Vec<String> {
    let mut a: Vec<String> = vec!["-v".into(), "v4l2src".into(), format!("device={device}")];
    for part in [caps, "videoconvert"] {
        a.push("!".into());
        a.extend(part.split_whitespace().map(String::from));
    }
    a.push("!".into());
    a.extend([
        "identity".into(),
        format!("name={FRAME_ELEMENT}"),
        "silent=false".into(),
    ]);
    a.push("!".into());
    a.extend(sink.split_whitespace().map(String::from));
    a
}

/// A running pipeline. Dropping it kills the process.
#[derive(Debug)]
pub struct Running {
    child: Child,
    pub generation: u64,
}

impl Running {
    /// Starts `program args`, reporting frames and the end on `events`.
    pub fn spawn(
        program: &str,
        args: &[String],
        generation: u64,
        events: mpsc::Sender<Event>,
    ) -> std::io::Result<Running> {
        let mut child = Command::new(program)
            .args(args)
            .stdin(Stdio::null())
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .kill_on_drop(true)
            .spawn()?;
        let last_error = Arc::new(Mutex::new(String::new()));

        if let Some(stderr) = child.stderr.take() {
            let last_error = last_error.clone();
            tokio::spawn(async move {
                let mut lines = BufReader::new(stderr).lines();
                while let Ok(Some(line)) = lines.next_line().await {
                    let line = line.trim();
                    if line.is_empty() {
                        continue;
                    }
                    eprintln!("[camera] gst: {line}");
                    if let Ok(mut e) = last_error.lock() {
                        *e = line.to_string();
                    }
                }
            });
        }

        if let Some(stdout) = child.stdout.take() {
            tokio::spawn(async move {
                let mut lines = BufReader::new(stdout).lines();
                let mut last_error_out = String::new();
                while let Ok(Some(line)) = lines.next_line().await {
                    if line.contains(FRAME_MARK) {
                        if events.send(Event::Frame { generation }).await.is_err() {
                            return; // the manager is gone
                        }
                    } else if line.starts_with("ERROR") || line.contains("Could not") {
                        // gst-launch prints its own failures on stdout.
                        eprintln!("[camera] gst: {}", line.trim());
                        last_error_out = line.trim().to_string();
                    }
                }
                // stdout closed: the process ended (or is about to). Give
                // stderr a moment to deliver its last line.
                tokio::time::sleep(std::time::Duration::from_millis(50)).await;
                let mut detail = last_error.lock().map(|e| e.clone()).unwrap_or_default();
                if detail.is_empty() {
                    detail = last_error_out;
                }
                if detail.is_empty() {
                    detail = "the pipeline ended".into();
                }
                let _ = events.send(Event::Ended { generation, detail }).await;
            });
        }

        Ok(Running { child, generation })
    }

    /// Kills the process and waits for it, so its window is gone.
    pub async fn stop(mut self) {
        let _ = self.child.start_kill();
        let _ = self.child.wait().await;
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn builds_the_bench_pipeline() {
        let a = args(
            "/dev/video0",
            "image/jpeg,width=640,height=480,framerate=30/1 ! jpegdec",
            "waylandsink",
        );
        assert_eq!(
            a.join(" "),
            "-v v4l2src device=/dev/video0 ! image/jpeg,width=640,height=480,framerate=30/1 \
             ! jpegdec ! videoconvert ! identity name=f250_frames silent=false ! waylandsink"
        );
    }

    #[test]
    fn device_with_odd_characters_stays_one_argument() {
        let a = args(
            "/dev/v4l/by-id/usb-046d_0804-video-index0",
            "x",
            "fakesink sync=false",
        );
        assert_eq!(a[2], "device=/dev/v4l/by-id/usb-046d_0804-video-index0");
        assert_eq!(a.last().map(String::as_str), Some("sync=false"));
    }

    #[test]
    fn frame_mark_matches_gst_launch_v_output() {
        // The classic gst-launch -v line for identity silent=false. Its exact
        // text on 1.28.5 is UNVERIFIED (see the module docs).
        let line = "/GstPipeline:pipeline0/GstIdentity:f250_frames: last-message = chain   \
                    ******* (f250_frames:sink) (614400 bytes, dts: none, pts: 0:00:00.0333)";
        assert!(line.contains(FRAME_MARK));
        assert!(
            !"/GstPipeline:pipeline0/GstVideoConvert:videoconvert0.GstPad:src: caps = video/x-raw"
                .contains(FRAME_MARK)
        );
    }
}
