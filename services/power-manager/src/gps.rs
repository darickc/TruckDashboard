//! The sun's location and clock from GPS (ADR-0028 amendment, 2026-11-14).
//!
//! power-manager follows navigation's `f250.nav.v1` `WatchPosition` (it never
//! talks to gpsd itself) and takes two things from it:
//!
//! - **Where the truck is.** The latest fix, current or not: the sun needs
//!   only roughly where the truck is (0.1° of longitude moves sunset by
//!   24 s), and a truck is never far from its last fix. The position is
//!   saved to 0.1° whenever it has moved that far, so a restart without a
//!   fix (a garage) still knows. In order: this run's GPS fix, the saved
//!   one, the configured `DISPLAY_LATITUDE/LONGITUDE`, nothing.
//! - **The time,** when the system clock isn't synchronized (no network,
//!   no RTC cell yet, H20). Only from a *current*, real fix with a UTC time
//!   from 2026 on, carried forward with the monotonic clock. The system
//!   clock is never changed (power-manager has no `CAP_SYS_TIME`, and
//!   setting it belongs to whatever keeps time). In order: the system clock
//!   while it is synchronized, GPS time, the system clock when the
//!   configuration says to trust it, nothing.
//!
//! The simulated receiver is never the truck: its positions are ignored
//! unless `--gps-accept-simulated` (development), and its time never.
//!
//! [`GpsInput`] is the logic, with no I/O and no clock of its own;
//! [`follow`] is the task that feeds it.

use std::path::Path;
use std::time::{Duration, Instant};

use daylight::Location;
use daylight::decide::EARLIEST_PLAUSIBLE_UNIX;
use f250_proto::nav::v1 as nav;
use f250_proto::power::v1 as pb;
use hyper_util::rt::TokioIo;
use nav::position_service_client::PositionServiceClient;
use tokio::sync::watch;
use tonic::transport::{Channel, Endpoint, Uri};

/// A saved position is rewritten only once the truck is this far from it
/// (degrees, either axis), so a parked truck's jitter never writes.
pub const SAVE_STEP_DEG: f64 = 0.1;

/// Where the location came from.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum LocationSource {
    None,
    Gps,
    GpsSaved,
    Configured,
    GpsSimulated,
}

impl LocationSource {
    pub fn to_pb(self) -> pb::LocationSource {
        match self {
            LocationSource::None => pb::LocationSource::None,
            LocationSource::Gps => pb::LocationSource::Gps,
            LocationSource::GpsSaved => pb::LocationSource::GpsSaved,
            LocationSource::Configured => pb::LocationSource::Configured,
            LocationSource::GpsSimulated => pb::LocationSource::GpsSimulated,
        }
    }

    pub fn describe(self) -> &'static str {
        match self {
            LocationSource::None => "no location",
            LocationSource::Gps => "GPS position",
            LocationSource::GpsSaved => "saved GPS position",
            LocationSource::Configured => "configured location",
            LocationSource::GpsSimulated => "SIMULATED GPS position",
        }
    }
}

/// The location for the sun, and where it came from.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Located {
    pub location: Option<Location>,
    pub source: LocationSource,
    /// How old the fix is (GPS and GpsSimulated only).
    pub age: Option<Duration>,
}

#[derive(Debug, Clone, Copy, PartialEq)]
struct Live {
    location: Location,
    simulated: bool,
    /// The fix's age when it arrived, and when that was.
    age: Duration,
    at: Instant,
}

/// UTC from a GPS fix, pinned to the monotonic clock.
#[derive(Debug, Clone, Copy, PartialEq)]
struct GpsTime {
    unix: f64,
    at: Instant,
}

/// What navigation has said, and the saved position.
#[derive(Debug, Clone)]
pub struct GpsInput {
    accept_simulated: bool,
    live: Option<Live>,
    saved: Option<Location>,
    time: Option<GpsTime>,
}

impl GpsInput {
    /// `saved`: the position kept from an earlier run, if any.
    pub fn new(saved: Option<Location>, accept_simulated: bool) -> Self {
        Self {
            accept_simulated,
            live: None,
            saved,
            time: None,
        }
    }

    /// Takes one position from navigation, received at `at`. Returns a
    /// position to save when the truck has moved [`SAVE_STEP_DEG`] from the
    /// saved one (rounded to 0.1°; never a simulated one).
    pub fn position(&mut self, p: &nav::Position, at: Instant) -> Option<Location> {
        let fix = p.fix.as_ref()?;
        if p.simulated && !self.accept_simulated {
            return None;
        }
        let Ok(location) = Location::new(fix.latitude_deg, fix.longitude_deg) else {
            return None;
        };
        let age = Duration::from_millis(fix.age_ms);
        self.live = Some(Live {
            location,
            simulated: p.simulated,
            age,
            at,
        });
        if let (false, true, true, Some(ms)) =
            (p.simulated, p.current, has_fix(p.status), fix.utc_time_ms)
        {
            let unix = ms as f64 / 1000.0 + age.as_secs_f64();
            if unix.is_finite() && unix >= EARLIEST_PLAUSIBLE_UNIX {
                self.time = Some(GpsTime { unix, at });
            }
        }
        if p.simulated {
            return None;
        }
        let moved = match self.saved {
            None => true,
            Some(s) => {
                (s.latitude_deg() - location.latitude_deg()).abs() >= SAVE_STEP_DEG
                    || (s.longitude_deg() - location.longitude_deg()).abs() >= SAVE_STEP_DEG
            }
        };
        if !moved {
            return None;
        }
        let rounded = Location::new(
            round_tenth(location.latitude_deg()),
            round_tenth(location.longitude_deg()),
        )
        .ok()?;
        self.saved = Some(rounded);
        Some(rounded)
    }

    /// The location for the sun at `now`, falling back to `configured`.
    pub fn locate(&self, configured: Option<Location>, now: Instant) -> Located {
        if let Some(l) = self.live {
            return Located {
                location: Some(l.location),
                source: if l.simulated {
                    LocationSource::GpsSimulated
                } else {
                    LocationSource::Gps
                },
                age: Some(l.age + now.saturating_duration_since(l.at)),
            };
        }
        if let Some(s) = self.saved {
            return Located {
                location: Some(s),
                source: LocationSource::GpsSaved,
                age: None,
            };
        }
        Located {
            location: configured,
            source: if configured.is_some() {
                LocationSource::Configured
            } else {
                LocationSource::None
            },
            age: None,
        }
    }

    /// UTC at `now` from the last GPS time, if there has been one.
    pub fn utc_now(&self, now: Instant) -> Option<f64> {
        self.time
            .map(|t| t.unix + now.saturating_duration_since(t.at).as_secs_f64())
    }
}

fn has_fix(status: i32) -> bool {
    matches!(
        nav::FixStatus::try_from(status),
        Ok(nav::FixStatus::Fix2d | nav::FixStatus::Fix3d)
    )
}

fn round_tenth(v: f64) -> f64 {
    (v * 10.0).round() / 10.0
}

/// The saved position file: `latitude=` and `longitude=` lines.
pub fn format_location(l: Location) -> String {
    format!(
        "# power-manager: the last GPS position, to 0.1 degrees, for the sun\n\
         # after a restart without a fix (ADR-0028). Delete it to forget it.\n\
         latitude={:.1}\nlongitude={:.1}\n",
        l.latitude_deg(),
        l.longitude_deg()
    )
}

/// Parses [`format_location`]'s output. `Err` says why it can't be used.
pub fn parse_location(text: &str) -> Result<Location, String> {
    let (mut lat, mut lon) = (None, None);
    for line in text.lines().map(str::trim) {
        if line.is_empty() || line.starts_with('#') {
            continue;
        }
        let Some((k, v)) = line.split_once('=') else {
            return Err(format!("{line:?} isn't key=value"));
        };
        let v: f64 = v
            .trim()
            .parse()
            .map_err(|_| format!("{} {:?} isn't a number", k.trim(), v.trim()))?;
        match k.trim() {
            "latitude" => lat = Some(v),
            "longitude" => lon = Some(v),
            other => return Err(format!("unknown key {other:?}")),
        }
    }
    match (lat, lon) {
        (Some(lat), Some(lon)) => Location::new(lat, lon),
        _ => Err("latitude and longitude are both needed".into()),
    }
}

/// Reads the saved position. Missing: `None` with no note; damaged: `None`
/// and a note (it is rewritten at the next fix).
pub fn load_location(path: &Path) -> (Option<Location>, Option<String>) {
    match std::fs::read_to_string(path) {
        Ok(text) => match parse_location(&text) {
            Ok(l) => (Some(l), None),
            Err(e) => (None, Some(format!("{}: {e}: ignored", path.display()))),
        },
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => (None, None),
        Err(e) => (None, Some(format!("{}: {e}: ignored", path.display()))),
    }
}

/// Writes the saved position whole (temporary file, synced, renamed).
pub fn save_location(path: &Path, l: Location) -> Result<(), String> {
    use std::io::Write;
    let tmp = path.with_extension("new");
    let write = || -> std::io::Result<()> {
        let mut f = std::fs::File::create(&tmp)?;
        f.write_all(format_location(l).as_bytes())?;
        f.sync_all()?;
        std::fs::rename(&tmp, path)
    };
    write().map_err(|e| format!("can't save {}: {e}", path.display()))
}

/// How long connecting and the first answer may take.
const CALL_TIMEOUT: Duration = Duration::from_secs(5);
/// navigation sends at least once a second; this long without a message and
/// the stream is dropped and opened again.
const SILENCE: Duration = Duration::from_secs(10);
/// Between attempts.
const RETRY: Duration = Duration::from_secs(5);

fn channel(endpoint: &str) -> Result<Channel, String> {
    if let Some(path) = endpoint.strip_prefix("unix:") {
        let path = path.to_string();
        Ok(Endpoint::from_static("http://localhost")
            .connect_timeout(CALL_TIMEOUT)
            .connect_with_connector_lazy(tower::service_fn(move |_: Uri| {
                let path = path.clone();
                async move {
                    tokio::net::UnixStream::connect(path)
                        .await
                        .map(TokioIo::new)
                }
            })))
    } else if let Some(addr) = endpoint.strip_prefix("tcp:") {
        Ok(Endpoint::try_from(format!("http://{addr}"))
            .map_err(|e| format!("bad --navigation {endpoint}: {e}"))?
            .connect_timeout(CALL_TIMEOUT)
            .connect_lazy())
    } else {
        Err(format!(
            "--navigation must start with unix: or tcp:, got {endpoint}"
        ))
    }
}

/// Follows navigation's positions into `out` (each with when it arrived),
/// reconnecting for ever. A missing navigation is logged once per reason;
/// the display goes on with what it had.
pub async fn follow(endpoint: String, out: watch::Sender<Option<(nav::Position, Instant)>>) {
    let channel = match channel(&endpoint) {
        Ok(c) => c,
        Err(e) => {
            eprintln!("[power-manager] display: {e}: no GPS");
            return;
        }
    };
    let mut last = String::new();
    loop {
        let why = follow_once(PositionServiceClient::new(channel.clone()), &out).await;
        if why != last {
            eprintln!(
                "[power-manager] display: navigation ({endpoint}): {why}; retrying every {} s",
                RETRY.as_secs()
            );
            last = why;
        }
        tokio::time::sleep(RETRY).await;
    }
}

async fn follow_once(
    mut client: PositionServiceClient<Channel>,
    out: &watch::Sender<Option<(nav::Position, Instant)>>,
) -> String {
    let mut stream = match tokio::time::timeout(
        CALL_TIMEOUT,
        client.watch_position(nav::WatchPositionRequest {}),
    )
    .await
    {
        Ok(Ok(r)) => r.into_inner(),
        Ok(Err(e)) => return format!("WatchPosition: {}", e.message()),
        Err(_) => return "WatchPosition: no answer".into(),
    };
    let mut announced = false;
    loop {
        match tokio::time::timeout(SILENCE, stream.message()).await {
            Err(_) => return format!("no position in {} s", SILENCE.as_secs()),
            Ok(Err(e)) => return format!("stream: {}", e.message()),
            Ok(Ok(None)) => return "navigation ended the stream".into(),
            Ok(Ok(Some(m))) => {
                if !announced {
                    eprintln!("[power-manager] display: following navigation's positions");
                    announced = true;
                }
                if let Some(p) = m.position {
                    out.send_replace(Some((p, Instant::now())));
                }
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn pos(lat: f64, lon: f64, status: nav::FixStatus, current: bool) -> nav::Position {
        nav::Position {
            status: status as i32,
            fix: Some(nav::Fix {
                latitude_deg: lat,
                longitude_deg: lon,
                age_ms: 200,
                utc_time_ms: Some(1_794_423_600_000),
                ..Default::default()
            }),
            current,
            stale_after_ms: 3000,
            source: "gpsd 3.27.5: /dev/ttyACM0".into(),
            ..Default::default()
        }
    }

    fn loc(lat: f64, lon: f64) -> Location {
        Location::new(lat, lon).expect("valid")
    }

    #[test]
    fn nothing_but_configuration_before_a_fix() {
        let g = GpsInput::new(None, false);
        let t = Instant::now();
        let l = g.locate(Some(loc(39.7, -105.0)), t);
        assert_eq!(l.source, LocationSource::Configured);
        assert_eq!(l.location, Some(loc(39.7, -105.0)));
        let l = g.locate(None, t);
        assert_eq!(l.source, LocationSource::None);
        assert_eq!(l.location, None);
        assert_eq!(g.utc_now(t), None);
    }

    #[test]
    fn a_fix_beats_the_saved_position_which_beats_the_configured_one() {
        let t = Instant::now();
        let mut g = GpsInput::new(Some(loc(38.0, -97.0)), false);
        let l = g.locate(Some(loc(39.7, -105.0)), t);
        assert_eq!(l.source, LocationSource::GpsSaved);
        assert_eq!(l.location, Some(loc(38.0, -97.0)));

        g.position(&pos(37.69, -97.34, nav::FixStatus::Fix3d, true), t);
        let l = g.locate(Some(loc(39.7, -105.0)), t + Duration::from_secs(5));
        assert_eq!(l.source, LocationSource::Gps);
        assert_eq!(l.location, Some(loc(37.69, -97.34)));
        assert_eq!(l.age, Some(Duration::from_millis(5200)));
    }

    #[test]
    fn a_lost_fix_keeps_the_last_position_with_its_age() {
        let t = Instant::now();
        let mut g = GpsInput::new(None, false);
        g.position(&pos(37.69, -97.34, nav::FixStatus::Fix3d, true), t);
        // Navigation still sends the last fix, no longer current.
        let mut lost = pos(37.69, -97.34, nav::FixStatus::NoFix, false);
        lost.fix.as_mut().expect("fix").age_ms = 60_000;
        g.position(&lost, t + Duration::from_secs(60));
        let l = g.locate(None, t + Duration::from_secs(61));
        assert_eq!(l.source, LocationSource::Gps);
        assert_eq!(l.age, Some(Duration::from_secs(61)));
        // No fix at all from the receiver: nothing changes.
        let none = nav::Position {
            status: nav::FixStatus::Unavailable as i32,
            ..Default::default()
        };
        assert_eq!(g.position(&none, t + Duration::from_secs(62)), None);
        assert_eq!(g.locate(None, t).location, Some(loc(37.69, -97.34)));
    }

    #[test]
    fn saves_only_after_moving_a_tenth_of_a_degree() {
        let t = Instant::now();
        let mut g = GpsInput::new(None, false);
        assert_eq!(
            g.position(&pos(37.6871, -97.3301, nav::FixStatus::Fix3d, true), t),
            Some(loc(37.7, -97.3))
        );
        // Jitter, and a drive of a few km: not saved again.
        for (lat, lon) in [(37.6873, -97.3299), (37.75, -97.25), (37.65, -97.39)] {
            assert_eq!(
                g.position(&pos(lat, lon, nav::FixStatus::Fix3d, true), t),
                None
            );
        }
        // 0.1° north of the saved 37.7.
        assert_eq!(
            g.position(&pos(37.81, -97.33, nav::FixStatus::Fix3d, true), t),
            Some(loc(37.8, -97.3))
        );
        // A saved position from an earlier run counts the same way.
        let mut g = GpsInput::new(Some(loc(37.8, -97.3)), false);
        assert_eq!(
            g.position(&pos(37.84, -97.31, nav::FixStatus::Fix2d, true), t),
            None
        );
    }

    #[test]
    fn time_only_from_a_current_real_fix_from_2026_on() {
        let t = Instant::now();
        let mut g = GpsInput::new(None, false);
        // Not current: position yes, time no.
        g.position(&pos(37.69, -97.34, nav::FixStatus::Fix3d, false), t);
        assert_eq!(g.utc_now(t), None);
        // A current fix without a fix status (shouldn't happen): no time.
        g.position(&pos(37.69, -97.34, nav::FixStatus::ReceiverSilent, true), t);
        assert_eq!(g.utc_now(t), None);
        // A receiver that thinks it is 2019 (a week rollover): no time.
        let mut old = pos(37.69, -97.34, nav::FixStatus::Fix3d, true);
        old.fix.as_mut().expect("fix").utc_time_ms = Some(1_560_000_000_000);
        g.position(&old, t);
        assert_eq!(g.utc_now(t), None);
        // A fix without a time: none.
        let mut untimed = pos(37.69, -97.34, nav::FixStatus::Fix3d, true);
        untimed.fix.as_mut().expect("fix").utc_time_ms = None;
        g.position(&untimed, t);
        assert_eq!(g.utc_now(t), None);

        g.position(&pos(37.69, -97.34, nav::FixStatus::Fix3d, true), t);
        // The fix's time plus its age, then the monotonic clock.
        assert_eq!(g.utc_now(t), Some(1_794_423_600.2));
        let later = g.utc_now(t + Duration::from_secs(3600)).expect("time");
        assert!((later - 1_794_427_200.2).abs() < 1e-6, "{later}");
        // A later fix that goes stale doesn't take the time away.
        g.position(&pos(37.69, -97.34, nav::FixStatus::NoFix, false), t);
        assert!(g.utc_now(t).is_some());
    }

    #[test]
    fn the_simulated_receiver_is_never_the_truck() {
        let t = Instant::now();
        let mut sim = pos(37.69, -97.34, nav::FixStatus::Fix3d, true);
        sim.simulated = true;
        sim.source = "simulated".into();

        let mut g = GpsInput::new(None, false);
        assert_eq!(g.position(&sim, t), None);
        assert_eq!(
            g.locate(Some(loc(39.7, -105.0)), t).source,
            LocationSource::Configured
        );
        assert_eq!(g.utc_now(t), None);

        // Development: its position, labelled, but never its time or a save.
        let mut g = GpsInput::new(None, true);
        assert_eq!(g.position(&sim, t), None);
        let l = g.locate(None, t);
        assert_eq!(l.source, LocationSource::GpsSimulated);
        assert_eq!(l.location, Some(loc(37.69, -97.34)));
        assert_eq!(g.utc_now(t), None);
    }

    #[test]
    fn a_nonsense_fix_is_ignored() {
        let t = Instant::now();
        let mut g = GpsInput::new(None, false);
        assert_eq!(
            g.position(&pos(91.0, 0.0, nav::FixStatus::Fix3d, true), t),
            None
        );
        assert_eq!(
            g.position(&pos(f64::NAN, 0.0, nav::FixStatus::Fix3d, true), t),
            None
        );
        assert_eq!(g.locate(None, t).source, LocationSource::None);
        assert_eq!(g.utc_now(t), None);
    }

    #[test]
    fn the_saved_file_round_trips_and_survives_damage() {
        let text = format_location(loc(37.7, -97.3));
        assert!(text.contains("latitude=37.7\n"), "{text}");
        assert!(text.contains("longitude=-97.3\n"), "{text}");
        assert_eq!(parse_location(&text), Ok(loc(37.7, -97.3)));
        assert!(parse_location("latitude=37.7\n").is_err());
        assert!(parse_location("latitude=north\nlongitude=1\n").is_err());
        assert!(parse_location("latitude=95\nlongitude=1\n").is_err());
        assert!(parse_location("altitude=3\n").is_err());

        let dir = std::env::temp_dir().join(format!("f250-gps-{}", std::process::id()));
        std::fs::create_dir_all(&dir).expect("dir");
        let path = dir.join("location");
        let _ = std::fs::remove_file(&path);
        assert_eq!(load_location(&path), (None, None));
        save_location(&path, loc(37.7, -97.3)).expect("save");
        assert_eq!(load_location(&path), (Some(loc(37.7, -97.3)), None));
        std::fs::write(&path, "garbage").expect("write");
        let (l, note) = load_location(&path);
        assert_eq!(l, None);
        assert!(note.expect("note").contains("ignored"));
        assert!(save_location(&dir.join("missing/location"), loc(1.0, 1.0)).is_err());
        let _ = std::fs::remove_dir_all(&dir);
    }
}
