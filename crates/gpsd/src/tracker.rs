//! The truck's position from gpsd's reports, honestly.
//!
//! Time is a monotonic [`Duration`] from any origin the caller picks (its
//! start), so a GPS or RTC clock jump can't make an old fix look new.
//!
//! - **Status** says what gpsd and the receiver are doing now: gpsd
//!   unreachable, no receiver, a receiver that has gone quiet, no fix, or a
//!   2D/3D fix. It comes from the newest `TPV` while that is younger than
//!   the stale limit.
//! - **The last good fix** is kept whatever happens next, with its age, and
//!   is [`Position::current`] only while the status is a fix and the fix is
//!   younger than the stale limit. Otherwise it may be shown only as "last
//!   known", with its age (CLAUDE.md rule 4).
//! - NMEA receivers make gpsd send one `TPV` per sentence, and some lack
//!   the course or speed (see the test vectors). A missing field keeps its
//!   previous value only while that value is itself younger than the stale
//!   limit, and keeps its own age, so carrying it over can never make it
//!   look newer than it is.

use std::collections::BTreeSet;
use std::time::Duration;

use crate::report::{Mode, Report, Tpv};
use crate::time::parse_utc_ms;

/// An example: tune once a receiver is fitted (H11). Receivers report at
/// 1 Hz or faster, so three missed cycles.
pub const DEFAULT_STALE_AFTER: Duration = Duration::from_secs(3);

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Status {
    /// gpsd isn't reachable (or hasn't been reached yet).
    Unavailable,
    /// gpsd is running but has no receiver.
    NoReceiver,
    /// gpsd has a receiver but no `TPV` within the stale limit.
    ReceiverSilent,
    /// The receiver is talking but has no fix.
    NoFix,
    Fix2d,
    Fix3d,
}

impl Status {
    pub fn is_fix(self) -> bool {
        matches!(self, Status::Fix2d | Status::Fix3d)
    }
}

/// A value and when it was reported.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Timed {
    pub value: f64,
    pub at: Duration,
}

#[derive(Debug, Clone, PartialEq)]
pub struct Fix {
    pub mode: Mode,
    pub lat: f64,
    pub lon: f64,
    /// When the position was reported.
    pub at: Duration,
    /// Above mean sea level; 3D fixes only.
    pub alt_msl_m: Option<Timed>,
    pub speed_mps: Option<Timed>,
    /// Degrees from true north.
    pub track_deg: Option<Timed>,
    pub eph_m: Option<Timed>,
    /// The receiver's UTC time for this fix, ms since the Unix epoch.
    pub utc_ms: Option<i64>,
    /// gpsd's name for the receiver.
    pub device: Option<String>,
}

/// What the tracker says at one instant.
#[derive(Debug, Clone, PartialEq)]
pub struct Position {
    pub status: Status,
    /// The last good fix, current or not.
    pub fix: Option<Fix>,
    /// Its age now.
    pub fix_age: Option<Duration>,
    /// The fix is current: a fix status and younger than the stale limit.
    pub current: bool,
    pub satellites_used: Option<u32>,
    pub satellites_visible: Option<u32>,
    /// The receivers gpsd has open.
    pub receivers: Vec<String>,
    pub gpsd_release: Option<String>,
    /// Why there is no current fix, for the screen and the log. Empty while
    /// there is one.
    pub detail: String,
}

#[derive(Debug, Clone)]
pub struct Tracker {
    stale_after: Duration,
    connected: bool,
    unavailable_because: String,
    release: Option<String>,
    devices: BTreeSet<String>,
    last_tpv: Option<(Mode, bool, Duration)>, // mode, had a position, when
    fix: Option<Fix>,
    used: Option<(u32, Duration)>,
    visible: Option<(u32, Duration)>,
}

impl Tracker {
    pub fn new(stale_after: Duration) -> Self {
        Tracker {
            stale_after,
            connected: false,
            unavailable_because: "not connected to gpsd yet".to_string(),
            release: None,
            devices: BTreeSet::new(),
            last_tpv: None,
            fix: None,
            used: None,
            visible: None,
        }
    }

    pub fn stale_after(&self) -> Duration {
        self.stale_after
    }

    /// Connected to gpsd (or the simulation started).
    pub fn connected(&mut self) {
        self.connected = true;
        self.unavailable_because.clear();
        self.devices.clear();
        self.last_tpv = None;
        self.used = None;
        self.visible = None;
    }

    /// Lost gpsd. The last fix is kept, and ages.
    pub fn disconnected(&mut self, why: &str) {
        self.connected = false;
        self.unavailable_because = why.to_string();
        self.devices.clear();
        self.last_tpv = None;
        self.used = None;
        self.visible = None;
    }

    pub fn report(&mut self, report: &Report, now: Duration) {
        match report {
            Report::Version { release, .. } => self.release = Some(release.clone()),
            Report::Devices(list) => {
                self.devices = list
                    .iter()
                    .filter(|d| d.active())
                    .map(|d| d.path.clone())
                    .collect();
            }
            Report::Device(d) if d.active() => {
                self.devices.insert(d.path.clone());
            }
            Report::Device(d) => {
                self.devices.remove(&d.path);
            }
            Report::Tpv(t) => self.tpv(t, now),
            Report::Sky(s) => {
                if let Some(n) = s.used {
                    self.used = Some((n, now));
                }
                if let Some(n) = s.visible {
                    self.visible = Some((n, now));
                }
            }
            Report::Error(_) | Report::Other(_) => {}
        }
    }

    fn tpv(&mut self, t: &Tpv, now: Duration) {
        let has_position = t.has_position();
        self.last_tpv = Some((t.mode(), has_position, now));
        if let Some(device) = &t.device {
            // A receiver that reports is there, whatever DEVICES said.
            self.devices.insert(device.clone());
        }
        let (Some(lat), Some(lon)) = (t.lat, t.lon) else {
            return;
        };
        if !has_position {
            return;
        }
        let prev = self.fix.take();
        let fresh = |f: Option<Timed>| f.filter(|f| now.saturating_sub(f.at) <= self.stale_after);
        let field = |new: Option<f64>, old: Option<Timed>| match new {
            Some(value) => Some(Timed { value, at: now }),
            None => fresh(old),
        };
        let mode = t.mode();
        self.fix = Some(Fix {
            mode,
            lat,
            lon,
            at: now,
            alt_msl_m: if mode == Mode::Fix3d {
                field(t.alt_msl_m, prev.as_ref().and_then(|p| p.alt_msl_m))
            } else {
                None
            },
            speed_mps: field(t.speed_mps, prev.as_ref().and_then(|p| p.speed_mps)),
            track_deg: field(
                t.track_deg.filter(|v| (0.0..=360.0).contains(v)),
                prev.as_ref().and_then(|p| p.track_deg),
            ),
            eph_m: field(t.eph_m, prev.as_ref().and_then(|p| p.eph_m)),
            utc_ms: t.time.as_deref().and_then(parse_utc_ms),
            device: t.device.clone(),
        });
    }

    pub fn position(&self, now: Duration) -> Position {
        let recent = |at: Duration| now.saturating_sub(at) <= self.stale_after;
        let status = if !self.connected {
            Status::Unavailable
        } else {
            match self.last_tpv {
                Some((mode, has_position, at)) if recent(at) => match mode {
                    Mode::Fix3d if has_position => Status::Fix3d,
                    Mode::Fix2d if has_position => Status::Fix2d,
                    _ => Status::NoFix,
                },
                _ if !self.devices.is_empty() => Status::ReceiverSilent,
                _ => Status::NoReceiver,
            }
        };
        let fix_age = self.fix.as_ref().map(|f| now.saturating_sub(f.at));
        let current = status.is_fix() && fix_age.is_some_and(|a| a <= self.stale_after);
        let count = |c: Option<(u32, Duration)>| {
            if self.connected {
                c.filter(|(_, at)| recent(*at)).map(|(n, _)| n)
            } else {
                None
            }
        };
        let detail = match status {
            _ if current => String::new(),
            Status::Unavailable => format!("gpsd unavailable: {}", self.unavailable_because),
            Status::NoReceiver => "gpsd has no GPS receiver".to_string(),
            // last_tpv is cleared on (re)connecting.
            Status::ReceiverSilent if self.last_tpv.is_none() => {
                "waiting for the GPS receiver's first report".to_string()
            }
            Status::ReceiverSilent => format!(
                "the GPS receiver has sent nothing for over {} s",
                self.stale_after.as_secs()
            ),
            Status::NoFix => "no GPS fix yet (needs a view of the sky)".to_string(),
            // A fix status with an old fix can't happen; say so if it does.
            Status::Fix2d | Status::Fix3d => "the fix is stale".to_string(),
        };
        Position {
            status,
            fix: self.fix.clone(),
            fix_age,
            current,
            satellites_used: count(self.used),
            satellites_visible: count(self.visible),
            receivers: self.devices.iter().cloned().collect(),
            gpsd_release: self.release.clone(),
            detail,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::report::Device;

    const STALE: Duration = DEFAULT_STALE_AFTER;

    fn s(secs: f64) -> Duration {
        Duration::from_secs_f64(secs)
    }

    fn tpv(mode: u8, lat: Option<f64>, track: Option<f64>) -> Report {
        Report::Tpv(Tpv {
            device: Some("/dev/ttyACM0".to_string()),
            mode: Some(match mode {
                3 => Mode::Fix3d,
                2 => Mode::Fix2d,
                1 => Mode::NoFix,
                _ => Mode::Unknown,
            }),
            time: Some("2026-11-11T18:00:06.000Z".to_string()),
            lat,
            lon: lat.map(|_| -98.5),
            alt_msl_m: Some(560.0),
            speed_mps: Some(10.0),
            track_deg: track,
            eph_m: Some(5.0),
        })
    }

    fn devices(paths: &[&str]) -> Report {
        Report::Devices(
            paths
                .iter()
                .map(|p| Device {
                    path: (*p).to_string(),
                    activated: Some("2026-11-11T17:46:13.026Z".to_string()),
                    driver: None,
                })
                .collect(),
        )
    }

    fn connected() -> Tracker {
        let mut t = Tracker::new(STALE);
        t.connected();
        t
    }

    #[test]
    fn unavailable_until_connected() {
        let t = Tracker::new(STALE);
        let p = t.position(s(0.0));
        assert_eq!(p.status, Status::Unavailable);
        assert!(!p.current);
        assert!(p.fix.is_none());
        assert!(p.detail.contains("not connected"));
    }

    #[test]
    fn connected_without_a_receiver() {
        let mut t = connected();
        t.report(&devices(&[]), s(0.0));
        assert_eq!(t.position(s(0.1)).status, Status::NoReceiver);
    }

    #[test]
    fn a_receiver_with_no_reports_yet_is_silent() {
        let mut t = connected();
        t.report(&devices(&["/dev/ttyACM0"]), s(0.0));
        let p = t.position(s(0.1));
        assert_eq!(p.status, Status::ReceiverSilent);
        assert_eq!(p.receivers, vec!["/dev/ttyACM0".to_string()]);
        assert!(p.detail.contains("first report"), "{}", p.detail);
    }

    #[test]
    fn no_fix_then_3d_then_2d() {
        let mut t = connected();
        t.report(&devices(&["/dev/ttyACM0"]), s(0.0));
        t.report(&tpv(1, None, None), s(1.0));
        let p = t.position(s(1.0));
        assert_eq!(p.status, Status::NoFix);
        assert!(!p.current);

        t.report(&tpv(3, Some(39.8), Some(45.0)), s(2.0));
        let p = t.position(s(2.5));
        assert_eq!(p.status, Status::Fix3d);
        assert!(p.current);
        assert!(p.detail.is_empty());
        let f = p.fix.expect("fix");
        assert_eq!((f.lat, f.lon), (39.8, -98.5));
        assert_eq!(f.alt_msl_m.map(|a| a.value), Some(560.0));
        assert_eq!(f.track_deg.map(|a| a.value), Some(45.0));
        assert_eq!(f.utc_ms, Some(1_794_420_006_000));
        assert_eq!(p.fix_age, Some(s(0.5)));

        t.report(&tpv(2, Some(39.9), Some(46.0)), s(3.0));
        let p = t.position(s(3.0));
        assert_eq!(p.status, Status::Fix2d);
        assert!(p.current);
        assert_eq!(p.fix.expect("fix").alt_msl_m, None, "no altitude in 2D");
    }

    #[test]
    fn losing_the_fix_keeps_the_last_one_as_stale() {
        let mut t = connected();
        t.report(&tpv(3, Some(39.8), Some(45.0)), s(1.0));
        t.report(&tpv(1, None, None), s(2.0));
        let p = t.position(s(2.0));
        assert_eq!(p.status, Status::NoFix);
        assert!(!p.current, "a fix after losing it is never current");
        assert_eq!(p.fix.expect("last fix").lat, 39.8);
        assert_eq!(p.fix_age, Some(s(1.0)));
    }

    #[test]
    fn a_fix_goes_stale_when_reports_stop() {
        let mut t = connected();
        t.report(&tpv(3, Some(39.8), Some(45.0)), s(1.0));
        assert!(
            t.position(s(1.0) + STALE).current,
            "at the limit: still current"
        );
        let p = t.position(s(1.0) + STALE + s(0.001));
        assert!(!p.current);
        assert_eq!(
            p.status,
            Status::ReceiverSilent,
            "the TPV's device is a receiver"
        );
        assert!(p.detail.contains("sent nothing"));
    }

    #[test]
    fn losing_gpsd_keeps_the_last_fix_as_stale() {
        let mut t = connected();
        t.report(&devices(&["/dev/ttyACM0"]), s(0.0));
        t.report(&tpv(3, Some(39.8), Some(45.0)), s(1.0));
        t.disconnected("connection refused");
        let p = t.position(s(1.5));
        assert_eq!(p.status, Status::Unavailable);
        assert!(!p.current);
        assert!(p.receivers.is_empty());
        assert_eq!(p.fix.expect("last fix").lat, 39.8);
        assert_eq!(p.detail, "gpsd unavailable: connection refused");
        // Back: still not current until a new fix.
        t.connected();
        let p = t.position(s(2.0));
        assert_eq!(p.status, Status::NoReceiver);
        assert!(!p.current);
    }

    #[test]
    fn a_receiver_unplugged() {
        let mut t = connected();
        t.report(&devices(&["/dev/ttyACM0"]), s(0.0));
        t.report(
            &Report::Device(Device {
                path: "/dev/ttyACM0".to_string(),
                activated: None,
                driver: None,
            }),
            s(1.0),
        );
        assert_eq!(t.position(s(1.0)).status, Status::NoReceiver);
    }

    #[test]
    fn a_missing_course_carries_over_only_while_fresh() {
        let mut t = connected();
        t.report(&tpv(3, Some(39.8), Some(45.0)), s(1.0));
        t.report(&tpv(3, Some(39.81), None), s(2.0));
        let f = t.position(s(2.0)).fix.expect("fix");
        assert_eq!(
            f.track_deg,
            Some(Timed {
                value: 45.0,
                at: s(1.0)
            }),
            "carried, with its own age"
        );
        // Carried again after its own limit: dropped, not renewed.
        t.report(&tpv(3, Some(39.82), None), s(1.0) + STALE + s(0.5));
        assert_eq!(t.position(s(5.0)).fix.expect("fix").track_deg, None);
    }

    #[test]
    fn a_fix_mode_without_a_position_is_no_fix() {
        let mut t = connected();
        t.report(&tpv(3, None, None), s(1.0));
        let p = t.position(s(1.0));
        assert_eq!(p.status, Status::NoFix);
        assert!(p.fix.is_none());
    }

    #[test]
    fn satellite_counts_expire() {
        let mut t = connected();
        t.report(
            &Report::Sky(crate::report::Sky {
                device: None,
                visible: Some(8),
                used: Some(6),
            }),
            s(1.0),
        );
        // A short SKY: used only; visible keeps its value.
        t.report(
            &Report::Sky(crate::report::Sky {
                device: None,
                visible: None,
                used: Some(7),
            }),
            s(2.0),
        );
        let p = t.position(s(2.0));
        assert_eq!(
            (p.satellites_used, p.satellites_visible),
            (Some(7), Some(8))
        );
        let p = t.position(s(2.0) + STALE + s(0.1));
        assert_eq!((p.satellites_used, p.satellites_visible), (None, None));
    }
}
