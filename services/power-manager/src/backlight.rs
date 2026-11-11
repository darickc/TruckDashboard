//! The panel's backlight in sysfs (`/sys/class/backlight/<name>`), written
//! by a thread of its own ([ADR-0028](../../../docs/architecture/adr/0028-day-night-and-backlight.md)
//! decision 6).
//!
//! The original 7" display's backlight is an I2C regulator
//! (`rpi_panel_attiny_regulator`, `10-0045` on the Pi 5 with AGL 22.0.1,
//! `max_brightness` 255; bench-log 2026-11-06). A write goes over I2C, so a
//! sick bus could make it slow or hang: the writes happen on a thread that
//! nothing waits for, and the power key never shares a thread with them.
//!
//! The device is found at runtime, never hard-coded. Write access comes from
//! a udev rule (`60-f250-backlight.rules`: group f250, `g+w` on
//! `brightness`).

use std::path::{Path, PathBuf};
use std::sync::mpsc::{self, RecvTimeoutError};
use std::time::{Duration, Instant};

use daylight::brightness::Ramp;

/// One backlight device.
#[derive(Debug, Clone)]
pub struct Device {
    name: String,
    dir: PathBuf,
    max: u32,
}

impl Device {
    /// `name` under `<sysfs>/class/backlight`, or the first there (sorted by
    /// name) when `name` is `None`.
    pub fn find(sysfs: &Path, name: Option<&str>) -> Result<Device, String> {
        let class = sysfs.join("class/backlight");
        let name = match name {
            Some(n) => n.to_string(),
            None => {
                let mut names: Vec<String> = std::fs::read_dir(&class)
                    .map_err(|e| format!("no backlight: {}: {e}", class.display()))?
                    .filter_map(|e| e.ok())
                    .map(|e| e.file_name().to_string_lossy().into_owned())
                    .collect();
                names.sort();
                names
                    .into_iter()
                    .next()
                    .ok_or_else(|| format!("no backlight device in {}", class.display()))?
            }
        };
        let dir = class.join(&name);
        let max = read_u32(&dir.join("max_brightness"))
            .map_err(|e| format!("backlight {name}: max_brightness: {e}"))?;
        if max == 0 {
            return Err(format!("backlight {name}: max_brightness is 0"));
        }
        Ok(Device { name, dir, max })
    }

    pub fn name(&self) -> &str {
        &self.name
    }

    pub fn max(&self) -> u32 {
        self.max
    }

    pub fn brightness(&self) -> Result<u32, String> {
        read_u32(&self.dir.join("brightness"))
    }

    pub fn write(&self, raw: u32) -> Result<(), String> {
        let path = self.dir.join("brightness");
        std::fs::write(&path, format!("{}\n", raw.min(self.max)))
            .map_err(|e| format!("can't write {}: {e}", path.display()))
    }
}

fn read_u32(path: &Path) -> Result<u32, String> {
    let text = std::fs::read_to_string(path).map_err(|e| e.to_string())?;
    text.trim()
        .parse()
        .map_err(|_| format!("not a number: {:?}", text.trim()))
}

/// What the writer thread reports.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Report {
    /// The ramp finished at this value.
    At(u32),
    /// A write failed; the ramp stopped. The next target tries again.
    Failed(String),
}

/// Sends targets to the writer thread. Dropping it ends the thread.
#[derive(Debug, Clone)]
pub struct Writer {
    tx: mpsc::Sender<u32>,
}

impl Writer {
    /// Starts the thread. Each target ramps over `ramp` from wherever the
    /// backlight is, in steps of `step`; a new target mid-ramp starts a new
    /// ramp from there. `report` runs on the thread.
    pub fn spawn<R>(device: Device, ramp: Duration, step: Duration, report: R) -> Writer
    where
        R: Fn(Report) + Send + 'static,
    {
        let (tx, rx) = mpsc::channel::<u32>();
        std::thread::spawn(move || write_loop(&device, &rx, ramp, step, &report));
        Writer { tx }
    }

    /// The level to ramp to. Never waits.
    pub fn set(&self, raw: u32) {
        let _ = self.tx.send(raw);
    }
}

fn write_loop<R: Fn(Report)>(
    device: &Device,
    rx: &mpsc::Receiver<u32>,
    ramp: Duration,
    step: Duration,
    report: &R,
) {
    // Where the backlight is now (systemd-backlight restored it at boot);
    // full if it can't be read, so the first ramp never starts from dark.
    let mut current = device.brightness().unwrap_or(device.max());
    let mut next = None;
    loop {
        let target = match next.take() {
            Some(t) => t,
            None => match rx.recv() {
                Ok(t) => t,
                Err(_) => return,
            },
        };
        let target = latest(rx, target).min(device.max());
        let r = Ramp::new(current, target, ramp);
        let start = Instant::now();
        loop {
            let elapsed = start.elapsed();
            let v = r.at(elapsed);
            if v != current {
                if let Err(e) = device.write(v) {
                    report(Report::Failed(e));
                    // Assume nothing about where it is; read it if possible.
                    current = device.brightness().unwrap_or(current);
                    break;
                }
                current = v;
            }
            if r.done(elapsed) {
                report(Report::At(current));
                break;
            }
            match rx.recv_timeout(step) {
                Ok(t) => {
                    next = Some(t);
                    break;
                }
                Err(RecvTimeoutError::Timeout) => {}
                Err(RecvTimeoutError::Disconnected) => return,
            }
        }
    }
}

/// The newest target waiting, or `t`.
fn latest(rx: &mpsc::Receiver<u32>, mut t: u32) -> u32 {
    while let Ok(n) = rx.try_recv() {
        t = n;
    }
    t
}

#[cfg(test)]
#[allow(clippy::unwrap_used, clippy::expect_used)]
mod tests {
    use super::*;
    use std::sync::{Arc, Mutex};

    struct Fake {
        root: PathBuf,
    }

    impl Fake {
        fn new(devices: &[(&str, &str, &str)]) -> Fake {
            let root = std::env::temp_dir().join(format!(
                "f250-backlight-{}-{:?}",
                std::process::id(),
                std::thread::current().id()
            ));
            let _ = std::fs::remove_dir_all(&root);
            for (name, max, now) in devices {
                let d = root.join("class/backlight").join(name);
                std::fs::create_dir_all(&d).unwrap();
                std::fs::write(d.join("max_brightness"), format!("{max}\n")).unwrap();
                std::fs::write(d.join("brightness"), format!("{now}\n")).unwrap();
            }
            Fake { root }
        }

        fn brightness(&self, name: &str) -> String {
            std::fs::read_to_string(
                self.root
                    .join("class/backlight")
                    .join(name)
                    .join("brightness"),
            )
            .unwrap()
            .trim()
            .to_string()
        }
    }

    impl Drop for Fake {
        fn drop(&mut self) {
            let _ = std::fs::remove_dir_all(&self.root);
        }
    }

    #[test]
    fn finds_the_first_device_or_the_named_one() {
        let f = Fake::new(&[("10-0045", "255", "200"), ("0-aaaa", "100", "50")]);
        let d = Device::find(&f.root, None).unwrap();
        assert_eq!((d.name(), d.max()), ("0-aaaa", 100));
        let d = Device::find(&f.root, Some("10-0045")).unwrap();
        assert_eq!((d.name(), d.max()), ("10-0045", 255));
        assert_eq!(d.brightness().unwrap(), 200);
        assert!(Device::find(&f.root, Some("nope")).is_err());
    }

    #[test]
    fn no_backlight_is_an_error_not_a_panic() {
        let f = Fake::new(&[]);
        assert!(
            Device::find(&f.root, None)
                .unwrap_err()
                .contains("no backlight")
        );
        let f = Fake::new(&[("bad", "0", "0")]);
        assert!(Device::find(&f.root, None).unwrap_err().contains("is 0"));
        let f = Fake::new(&[("bad", "x", "0")]);
        assert!(
            Device::find(&f.root, None)
                .unwrap_err()
                .contains("not a number")
        );
    }

    fn collect() -> (Arc<Mutex<Vec<Report>>>, impl Fn(Report) + Send + 'static) {
        let reports = Arc::new(Mutex::new(Vec::new()));
        let r = reports.clone();
        (reports, move |rep| r.lock().unwrap().push(rep))
    }

    fn wait_for(reports: &Arc<Mutex<Vec<Report>>>, n: usize) -> Vec<Report> {
        let start = Instant::now();
        while start.elapsed() < Duration::from_secs(5) {
            if reports.lock().unwrap().len() >= n {
                break;
            }
            std::thread::sleep(Duration::from_millis(5));
        }
        reports.lock().unwrap().clone()
    }

    #[test]
    fn ramps_to_the_target_and_reports() {
        let f = Fake::new(&[("bl", "255", "255")]);
        let d = Device::find(&f.root, None).unwrap();
        let (reports, report) = collect();
        let w = Writer::spawn(
            d,
            Duration::from_millis(100),
            Duration::from_millis(10),
            report,
        );
        w.set(102);
        assert_eq!(wait_for(&reports, 1), vec![Report::At(102)]);
        assert_eq!(f.brightness("bl"), "102");
    }

    #[test]
    fn a_new_target_mid_ramp_wins() {
        let f = Fake::new(&[("bl", "255", "255")]);
        let d = Device::find(&f.root, None).unwrap();
        let (reports, report) = collect();
        let w = Writer::spawn(
            d,
            Duration::from_millis(300),
            Duration::from_millis(10),
            report,
        );
        w.set(26);
        std::thread::sleep(Duration::from_millis(50));
        w.set(200);
        let got = wait_for(&reports, 1);
        assert_eq!(got, vec![Report::At(200)]);
        assert_eq!(f.brightness("bl"), "200");
    }

    #[test]
    fn never_writes_above_max() {
        let f = Fake::new(&[("bl", "100", "10")]);
        let d = Device::find(&f.root, None).unwrap();
        let (reports, report) = collect();
        let w = Writer::spawn(d, Duration::ZERO, Duration::from_millis(10), report);
        w.set(5000);
        assert_eq!(wait_for(&reports, 1), vec![Report::At(100)]);
    }

    #[test]
    fn a_failed_write_is_reported() {
        let f = Fake::new(&[("bl", "255", "255")]);
        let d = Device::find(&f.root, None).unwrap();
        // The brightness file becomes a directory: every write fails.
        let file = f.root.join("class/backlight/bl/brightness");
        std::fs::remove_file(&file).unwrap();
        std::fs::create_dir(&file).unwrap();
        let (reports, report) = collect();
        let w = Writer::spawn(d, Duration::ZERO, Duration::from_millis(10), report);
        w.set(10);
        let got = wait_for(&reports, 1);
        assert!(
            matches!(&got[0], Report::Failed(e) if e.contains("can't write")),
            "{got:?}"
        );
    }
}
