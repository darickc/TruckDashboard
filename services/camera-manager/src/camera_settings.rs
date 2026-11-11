//! Camera assignment and recording set from the dashboard
//! ([ADR-0029](../../../docs/architecture/adr/0029-settings-screen.md)).
//!
//! - [`Saved`]: the file in camera-manager's state directory
//!   (`/var/lib/f250-camera/settings`). Once it exists it replaces the
//!   `/etc/default/f250` cameras and `RECORD_CAMERAS` as a whole (decision 4).
//! - [`effective`]: what camera-manager runs with: the saved settings or the
//!   command line's, recording only where it is allowed (the data drive,
//!   decision 5) and only for front and rear cameras that have a device.
//! - [`scan`]: the cameras plugged in now, by USB port, labelled with the
//!   camera's model.
//!
//! ```text
//! front=/dev/v4l/by-path/platform-xhci-hcd.0-usb-0:1:1.0-video-index0
//! left=
//! right=
//! rear=/dev/v4l/by-path/platform-xhci-hcd.1-usb-0:2:1.0-video-index0
//! record=front,rear
//! ```

use std::path::{Path, PathBuf};

use camera_policy::Camera;
use f250_proto::camera::v1 as pb;

use crate::config::camera_name;
use crate::manager::pb_camera;

/// The four cameras in the order the API lists them.
pub const ORDER: [Camera; 4] = [Camera::Front, Camera::Left, Camera::Right, Camera::Rear];

/// Settings saved from the dashboard.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct Saved {
    /// Cameras with a device; one not listed has none.
    pub cameras: Vec<(Camera, String)>,
    /// Front and/or rear.
    pub record: Vec<Camera>,
}

fn camera_from_name(s: &str) -> Option<Camera> {
    match s {
        "front" => Some(Camera::Front),
        "left" => Some(Camera::Left),
        "right" => Some(Camera::Right),
        "rear" => Some(Camera::Rear),
        _ => None,
    }
}

/// A device path the settings accept: absolute, under `/dev` (or the test
/// root), no whitespace, no `..`.
pub fn check_device(device: &str) -> Result<(), String> {
    if device.chars().any(char::is_whitespace) {
        return Err(format!("{device:?} has a space in it"));
    }
    if !device.starts_with('/') || device.split('/').any(|p| p == "..") {
        return Err(format!("{device:?} isn't an absolute device path"));
    }
    Ok(())
}

impl Saved {
    /// Checks the settings: good devices, no device shared by two cameras,
    /// only front and rear recorded.
    pub fn check(&self) -> Result<(), String> {
        let mut seen: Vec<(&str, Camera)> = Vec::new();
        for (c, d) in &self.cameras {
            check_device(d).map_err(|e| format!("{} camera: {e}", camera_name(*c)))?;
            if let Some((_, other)) = seen.iter().find(|(dev, _)| *dev == d.as_str()) {
                return Err(format!(
                    "the {} and {} cameras can't both be {d}",
                    camera_name(*other),
                    camera_name(*c)
                ));
            }
            seen.push((d, *c));
        }
        for c in &self.record {
            if !matches!(c, Camera::Front | Camera::Rear) {
                return Err(format!(
                    "only front and rear can record, not {}",
                    camera_name(*c)
                ));
            }
        }
        Ok(())
    }

    pub fn device(&self, c: Camera) -> Option<&str> {
        self.cameras
            .iter()
            .find(|(x, _)| *x == c)
            .map(|(_, d)| d.as_str())
    }

    pub fn parse(text: &str) -> Result<Saved, String> {
        let mut s = Saved::default();
        for (i, line) in text.lines().enumerate() {
            let line = line.trim();
            if line.is_empty() || line.starts_with('#') {
                continue;
            }
            let (k, v) = line
                .split_once('=')
                .ok_or_else(|| format!("line {}: not key=value", i + 1))?;
            let (k, v) = (k.trim(), v.trim());
            if k == "record" {
                for name in v.split(',').map(str::trim).filter(|n| !n.is_empty()) {
                    let c = camera_from_name(name)
                        .ok_or_else(|| format!("line {}: unknown camera {name:?}", i + 1))?;
                    if !s.record.contains(&c) {
                        s.record.push(c);
                    }
                }
            } else {
                let c = camera_from_name(k)
                    .ok_or_else(|| format!("line {}: unknown setting {k:?}", i + 1))?;
                s.cameras.retain(|(x, _)| *x != c);
                if !v.is_empty() {
                    s.cameras.push((c, v.to_string()));
                }
            }
        }
        s.check()?;
        Ok(s)
    }

    pub fn format(&self) -> String {
        let mut out = String::from(
            "# camera-manager's camera settings, saved from the dashboard (ADR-0029).\n\
             # They replace /etc/default/f250's CAMERA_* and RECORD_CAMERAS.\n",
        );
        for c in ORDER {
            out.push_str(&format!(
                "{}={}\n",
                camera_name(c),
                self.device(c).unwrap_or("")
            ));
        }
        let record: Vec<&str> = ORDER
            .into_iter()
            .filter(|c| self.record.contains(c))
            .map(camera_name)
            .collect();
        out.push_str(&format!("record={}\n", record.join(",")));
        out
    }

    /// From the API's request.
    pub fn from_pb(cameras: &[pb::CameraAssignment], record: &[i32]) -> Result<Saved, String> {
        let mut s = Saved::default();
        for a in cameras {
            let c =
                camera_from_pb(a.camera).ok_or("a camera must be front, left, right or rear")?;
            s.cameras.retain(|(x, _)| *x != c);
            let d = a.device.trim();
            if !d.is_empty() {
                s.cameras.push((c, d.to_string()));
            }
        }
        for v in record {
            let c = camera_from_pb(*v).ok_or("record: unknown camera")?;
            if !s.record.contains(&c) {
                s.record.push(c);
            }
        }
        s.check()?;
        Ok(s)
    }
}

pub fn camera_from_pb(v: i32) -> Option<Camera> {
    match pb::Camera::try_from(v).ok()? {
        pb::Camera::Front => Some(Camera::Front),
        pb::Camera::Left => Some(Camera::Left),
        pb::Camera::Right => Some(Camera::Right),
        pb::Camera::Rear => Some(Camera::Rear),
        pb::Camera::Unspecified => None,
    }
}

/// Reads the saved settings: `Ok(None)` when there are none, `Err` when
/// the file is there but bad (then the command line's are used).
pub fn load(path: &Path) -> Result<Option<Saved>, String> {
    match std::fs::read_to_string(path) {
        Ok(text) => Saved::parse(&text)
            .map(Some)
            .map_err(|e| format!("{}: {e}", path.display())),
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => Ok(None),
        Err(e) => Err(format!("{}: {e}", path.display())),
    }
}

/// Writes the file whole (temporary, synced, renamed).
pub fn save(path: &Path, s: &Saved) -> Result<(), String> {
    use std::io::Write;
    let tmp = path.with_extension("new");
    let write = || -> std::io::Result<()> {
        if let Some(dir) = path.parent() {
            std::fs::create_dir_all(dir)?;
        }
        let mut f = std::fs::File::create(&tmp)?;
        f.write_all(s.format().as_bytes())?;
        f.sync_all()?;
        std::fs::rename(&tmp, path)
    };
    write().map_err(|e| format!("can't save {}: {e}", path.display()))
}

/// Removes the saved settings ("Use /etc/default/f250").
pub fn forget(path: &Path) -> Result<(), String> {
    match std::fs::remove_file(path) {
        Ok(()) => Ok(()),
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => Ok(()),
        Err(e) => Err(format!("can't remove {}: {e}", path.display())),
    }
}

/// What camera-manager runs with.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Effective {
    pub cameras: Vec<(Camera, String)>,
    pub record: Vec<Camera>,
    pub source: pb::SettingsSource,
}

/// The saved settings if there are any, else the command line's. Recording
/// only when allowed, and only for front and rear cameras with a device.
pub fn effective(
    cli_cameras: &[(Camera, String)],
    cli_record: &[Camera],
    saved: Option<&Saved>,
    recording_allowed: bool,
) -> Effective {
    let (cameras, record, source) = match saved {
        Some(s) => (
            s.cameras.clone(),
            s.record.clone(),
            pb::SettingsSource::Screen,
        ),
        None => {
            // The last --camera for a name wins, as config::Settings::device.
            let mut cams: Vec<(Camera, String)> = Vec::new();
            for (c, d) in cli_cameras {
                cams.retain(|(x, _)| x != c);
                cams.push((*c, d.clone()));
            }
            (cams, cli_record.to_vec(), pb::SettingsSource::Defaults)
        }
    };
    let record = if recording_allowed {
        record
            .into_iter()
            .filter(|c| matches!(c, Camera::Front | Camera::Rear))
            .filter(|c| cameras.iter().any(|(x, _)| x == c))
            .collect()
    } else {
        Vec::new()
    };
    Effective {
        cameras,
        record,
        source,
    }
}

impl Effective {
    /// For `GetCameraSettings`. `wanted`: the cameras the settings ask to
    /// record, before the data-drive and device rules: the screen shows the
    /// driver's choice, and `recording_unavailable` says why nothing records.
    pub fn to_pb(&self, wanted: &[Camera], recording_unavailable: &str) -> pb::CameraSettings {
        pb::CameraSettings {
            cameras: ORDER
                .into_iter()
                .map(|c| pb::CameraAssignment {
                    camera: pb_camera(c) as i32,
                    device: self
                        .cameras
                        .iter()
                        .find(|(x, _)| *x == c)
                        .map(|(_, d)| d.clone())
                        .unwrap_or_default(),
                })
                .collect(),
            record: ORDER
                .into_iter()
                .filter(|c| wanted.contains(c))
                .map(|c| pb_camera(c) as i32)
                .collect(),
            source: self.source as i32,
            recording_unavailable: recording_unavailable.to_string(),
        }
    }
}

/// A camera plugged in now.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Device {
    pub path: PathBuf,
    pub label: String,
}

/// The capture devices under `<dev>/v4l/by-path` (`*-video-index0`: the
/// capture node; a UVC camera's other index is metadata), each labelled
/// with the `by-id` name that points at the same device, sorted by path.
/// Nothing (not an error) when there is no `v4l` directory: no camera has
/// ever been plugged in.
pub fn scan(dev: &Path) -> Vec<Device> {
    let entries = |dir: &Path| -> Vec<(String, Option<PathBuf>)> {
        std::fs::read_dir(dir)
            .map(|rd| {
                rd.filter_map(Result::ok)
                    .map(|e| {
                        let name = e.file_name().to_string_lossy().into_owned();
                        (name, std::fs::canonicalize(e.path()).ok())
                    })
                    .filter(|(n, _)| n.ends_with("-video-index0"))
                    .collect()
            })
            .unwrap_or_default()
    };
    let by_path = dev.join("v4l/by-path");
    let ids = entries(&dev.join("v4l/by-id"));
    let mut out: Vec<Device> = entries(&by_path)
        .into_iter()
        .map(|(name, target)| {
            let label = target
                .as_ref()
                .and_then(|t| ids.iter().find(|(_, it)| it.as_ref() == Some(t)))
                .map(|(n, _)| model_label(n))
                .unwrap_or_default();
            Device {
                path: by_path.join(&name),
                label,
            }
        })
        .collect();
    out.sort_by(|a, b| a.path.cmp(&b.path));
    out
}

/// `usb-046d_0825_ABCD1234-video-index0` → `046d_0825_ABCD1234`: the
/// vendor, product and serial udev put in the name.
fn model_label(by_id: &str) -> String {
    by_id
        .strip_prefix("usb-")
        .unwrap_or(by_id)
        .strip_suffix("-video-index0")
        .unwrap_or(by_id)
        .to_string()
}

#[cfg(test)]
#[allow(clippy::unwrap_used, clippy::expect_used)]
mod tests {
    use super::*;

    const P0: &str = "/dev/v4l/by-path/platform-xhci-hcd.0-usb-0:1:1.0-video-index0";
    const P1: &str = "/dev/v4l/by-path/platform-xhci-hcd.1-usb-0:2:1.0-video-index0";

    #[test]
    fn round_trips() {
        let s = Saved {
            cameras: vec![(Camera::Rear, P1.into()), (Camera::Front, P0.into())],
            record: vec![Camera::Rear, Camera::Front],
        };
        let text = s.format();
        assert!(text.contains(&format!(
            "front={P0}\nleft=\nright=\nrear={P1}\nrecord=front,rear\n"
        )));
        let back = Saved::parse(&text).unwrap();
        assert_eq!(back.device(Camera::Front), Some(P0));
        assert_eq!(back.device(Camera::Rear), Some(P1));
        assert_eq!(back.device(Camera::Left), None);
        assert_eq!(back.record.len(), 2);
    }

    #[test]
    fn bad_settings_are_refused() {
        for (text, why) in [
            ("front=/dev/video0\nrear=/dev/video0\n", "can't both be"),
            ("left=dev/video0\n", "absolute"),
            ("left=/dev/../etc/passwd\n", "absolute"),
            ("left=/dev/video 0\n", "space"),
            ("record=left\n", "only front and rear"),
            ("record=top\n", "unknown camera"),
            ("top=/dev/video0\n", "unknown setting"),
            ("junk\n", "key=value"),
        ] {
            let e = Saved::parse(text).expect_err(text);
            assert!(e.contains(why), "{text:?}: {e}");
        }
    }

    #[test]
    fn from_the_api() {
        let s = Saved::from_pb(
            &[
                pb::CameraAssignment {
                    camera: pb::Camera::Rear as i32,
                    device: P1.into(),
                },
                pb::CameraAssignment {
                    camera: pb::Camera::Left as i32,
                    device: " ".into(),
                },
            ],
            &[pb::Camera::Rear as i32],
        )
        .unwrap();
        assert_eq!(s.cameras, vec![(Camera::Rear, P1.to_string())]);
        assert_eq!(s.record, vec![Camera::Rear]);
        assert!(Saved::from_pb(&[pb::CameraAssignment::default()], &[]).is_err());
        assert!(Saved::from_pb(&[], &[pb::Camera::Right as i32]).is_err());
    }

    #[test]
    fn saved_settings_replace_the_command_line_and_recording_follows_the_rules() {
        let cli = vec![
            (Camera::Rear, "/dev/video0".to_string()),
            (Camera::Rear, "/dev/video4".to_string()),
        ];
        let e = effective(&cli, &[Camera::Rear], None, true);
        assert_eq!(e.cameras, vec![(Camera::Rear, "/dev/video4".to_string())]);
        assert_eq!(e.record, vec![Camera::Rear]);
        assert_eq!(e.source, pb::SettingsSource::Defaults);

        let saved = Saved {
            cameras: vec![(Camera::Front, P0.into())],
            record: vec![Camera::Front, Camera::Rear],
        };
        let e = effective(&cli, &[Camera::Rear], Some(&saved), true);
        assert_eq!(e.cameras, vec![(Camera::Front, P0.to_string())]);
        assert_eq!(e.record, vec![Camera::Front], "rear has no device");
        assert_eq!(e.source, pb::SettingsSource::Screen);

        let e = effective(&cli, &[Camera::Rear], Some(&saved), false);
        assert!(e.record.is_empty(), "no data drive: nothing records");

        let p = e.to_pb(&saved.record, "no data drive");
        assert_eq!(p.cameras.len(), 4);
        assert_eq!(p.cameras[0].device, P0);
        assert_eq!(p.cameras[3].device, "");
        assert_eq!(
            p.record,
            vec![pb::Camera::Front as i32, pb::Camera::Rear as i32],
            "the driver's choice is shown"
        );
        assert_eq!(p.recording_unavailable, "no data drive");
    }

    #[test]
    fn files_load_save_and_forget() {
        let dir = std::env::temp_dir().join(format!("cm-settings-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        let path = dir.join("state/settings");
        assert_eq!(load(&path).unwrap(), None);
        let s = Saved {
            cameras: vec![(Camera::Left, P0.into())],
            record: vec![],
        };
        save(&path, &s).unwrap();
        assert_eq!(load(&path).unwrap(), Some(s));
        std::fs::write(&path, "left=relative\n").unwrap();
        assert!(load(&path).is_err());
        forget(&path).unwrap();
        forget(&path).unwrap();
        assert_eq!(load(&path).unwrap(), None);
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn scans_cameras_by_port_with_their_model() {
        let dev = std::env::temp_dir().join(format!("cm-dev-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dev);
        std::fs::create_dir_all(dev.join("v4l/by-path")).unwrap();
        std::fs::create_dir_all(dev.join("v4l/by-id")).unwrap();
        for n in ["video0", "video1", "video2", "video3"] {
            std::fs::write(dev.join(n), "").unwrap();
        }
        let link = |dir: &str, name: &str, target: &str| {
            std::os::unix::fs::symlink(dev.join(target), dev.join("v4l").join(dir).join(name))
                .unwrap();
        };
        link("by-path", "platform-x-usb-0:2:1.0-video-index0", "video2");
        link("by-path", "platform-x-usb-0:2:1.0-video-index1", "video3");
        link("by-path", "platform-x-usb-0:1:1.0-video-index0", "video0");
        link("by-path", "platform-x-usb-0:1:1.0-video-index1", "video1");
        link("by-id", "usb-046d_0825_ABC-video-index0", "video0");
        let found = scan(&dev);
        assert_eq!(found.len(), 2, "{found:?}");
        assert!(
            found[0]
                .path
                .ends_with("platform-x-usb-0:1:1.0-video-index0")
        );
        assert_eq!(found[0].label, "046d_0825_ABC");
        assert!(
            found[1]
                .path
                .ends_with("platform-x-usb-0:2:1.0-video-index0")
        );
        assert_eq!(found[1].label, "");
        assert!(scan(&dev.join("nothing")).is_empty());
        let _ = std::fs::remove_dir_all(&dev);
    }
}
