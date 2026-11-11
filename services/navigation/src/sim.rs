//! A simulated receiver for development: drives a loop at a steady speed and
//! sends gpsd-shaped reports, so the tracker, the API and the dashboard run
//! exactly as they would with gpsd. Optional outages (no fix, as in a
//! tunnel) exercise the stale path. Its position is labelled simulated all
//! the way to the screen.

use std::time::Duration;

use gpsd::report::{Device, Mode, Report, Sky, Tpv};
use tokio::sync::mpsc;

use crate::source::Event;

/// An arbitrary loop near Lebanon, Kansas (the geographic centre of the
/// contiguous United States). Not a road: straight lines between corners.
pub const DEFAULT_LOOP: &[(f64, f64)] = &[
    (39.8097, -98.5556),
    (39.8097, -98.5000),
    (39.8500, -98.5000),
    (39.8500, -98.5556),
];

pub const DEVICE: &str = "simulated";

#[derive(Debug, Clone)]
pub struct SimConfig {
    /// Closed loop of (latitude, longitude) corners, at least two.
    pub corners: Vec<(f64, f64)>,
    pub speed_mps: f64,
    /// How often a report is sent.
    pub period: Duration,
    /// Every this long, lose the fix for `outage_for`.
    pub outage_every: Option<Duration>,
    pub outage_for: Duration,
}

impl Default for SimConfig {
    fn default() -> Self {
        SimConfig {
            corners: DEFAULT_LOOP.to_vec(),
            speed_mps: 80.0 / 3.6,
            period: Duration::from_secs(1),
            outage_every: None,
            outage_for: Duration::from_secs(10),
        }
    }
}

const EARTH_RADIUS_M: f64 = 6_371_008.8;

/// Great-circle distance, metres.
pub fn distance_m(a: (f64, f64), b: (f64, f64)) -> f64 {
    let (la1, lo1) = (a.0.to_radians(), a.1.to_radians());
    let (la2, lo2) = (b.0.to_radians(), b.1.to_radians());
    let h = ((la2 - la1) / 2.0).sin().powi(2)
        + la1.cos() * la2.cos() * ((lo2 - lo1) / 2.0).sin().powi(2);
    2.0 * EARTH_RADIUS_M * h.sqrt().asin()
}

/// Initial bearing from `a` to `b`, degrees clockwise from true north.
pub fn bearing_deg(a: (f64, f64), b: (f64, f64)) -> f64 {
    let (la1, la2) = (a.0.to_radians(), b.0.to_radians());
    let dlo = (b.1 - a.1).to_radians();
    let y = dlo.sin() * la2.cos();
    let x = la1.cos() * la2.sin() - la1.sin() * la2.cos() * dlo.cos();
    y.atan2(x).to_degrees().rem_euclid(360.0)
}

/// Where the simulated truck is after `elapsed`: (lat, lon, course).
/// Linear between corners, fine over a few kilometres.
pub fn along(cfg: &SimConfig, elapsed: Duration) -> (f64, f64, f64) {
    let n = cfg.corners.len();
    let legs: Vec<f64> = (0..n)
        .map(|i| distance_m(cfg.corners[i], cfg.corners[(i + 1) % n]))
        .collect();
    let total: f64 = legs.iter().sum();
    let mut d = (cfg.speed_mps * elapsed.as_secs_f64()).rem_euclid(total.max(1.0));
    for (i, leg) in legs.iter().enumerate() {
        let (a, b) = (cfg.corners[i], cfg.corners[(i + 1) % n]);
        if d <= *leg || i == n - 1 {
            let f = if *leg > 0.0 { (d / leg).min(1.0) } else { 0.0 };
            return (
                a.0 + (b.0 - a.0) * f,
                a.1 + (b.1 - a.1) * f,
                bearing_deg(a, b),
            );
        }
        d -= leg;
    }
    (cfg.corners[0].0, cfg.corners[0].1, 0.0)
}

pub fn in_outage(cfg: &SimConfig, elapsed: Duration) -> bool {
    match cfg.outage_every {
        Some(every) if !every.is_zero() => {
            let into = elapsed.as_secs_f64() % every.as_secs_f64();
            elapsed >= every && into < cfg.outage_for.as_secs_f64()
        }
        _ => false,
    }
}

/// The report the simulated receiver sends at `elapsed`.
pub fn tpv_at(cfg: &SimConfig, elapsed: Duration) -> Tpv {
    if in_outage(cfg, elapsed) {
        return Tpv {
            device: Some(DEVICE.to_string()),
            mode: Some(Mode::NoFix),
            ..Tpv::default()
        };
    }
    let (lat, lon, track) = along(cfg, elapsed);
    Tpv {
        device: Some(DEVICE.to_string()),
        mode: Some(Mode::Fix3d),
        time: None,
        lat: Some(lat),
        lon: Some(lon),
        alt_msl_m: Some(560.0),
        speed_mps: Some(cfg.speed_mps),
        track_deg: Some(track),
        eph_m: Some(4.0),
    }
}

/// Runs until `tx` closes.
pub async fn run(cfg: SimConfig, tx: mpsc::Sender<Event>) {
    let device = Device {
        path: DEVICE.to_string(),
        activated: Some("simulated".to_string()),
        driver: Some("simulated".to_string()),
    };
    for e in [
        Event::Connected,
        Event::Report(Report::Devices(vec![device])),
    ] {
        if tx.send(e).await.is_err() {
            return;
        }
    }
    let start = tokio::time::Instant::now();
    let mut tick = tokio::time::interval(cfg.period);
    loop {
        tick.tick().await;
        let elapsed = start.elapsed();
        let tpv = tpv_at(&cfg, elapsed);
        let fixed = tpv.has_position();
        let sky = Sky {
            device: Some(DEVICE.to_string()),
            visible: Some(12),
            used: Some(if fixed { 9 } else { 0 }),
        };
        for r in [Report::Tpv(tpv), Report::Sky(sky)] {
            if tx.send(Event::Report(r)).await.is_err() {
                return;
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn distance_and_bearing() {
        // One degree of latitude is about 111.2 km.
        let d = distance_m((39.0, -98.0), (40.0, -98.0));
        assert!((d - 111_195.0).abs() < 50.0, "{d}");
        assert!((bearing_deg((39.0, -98.0), (40.0, -98.0)) - 0.0).abs() < 1e-9);
        assert!((bearing_deg((40.0, -98.0), (39.0, -98.0)) - 180.0).abs() < 1e-9);
        let east = bearing_deg((39.8, -98.6), (39.8, -98.5));
        assert!((east - 90.0).abs() < 0.1, "{east}");
    }

    #[test]
    fn drives_the_loop() {
        let cfg = SimConfig::default();
        let (lat, lon, track) = along(&cfg, Duration::ZERO);
        assert_eq!((lat, lon), cfg.corners[0]);
        assert!((track - 90.0).abs() < 0.1, "first leg heads east: {track}");
        // Halfway along the first leg.
        let leg = distance_m(cfg.corners[0], cfg.corners[1]);
        let t = Duration::from_secs_f64(leg / 2.0 / cfg.speed_mps);
        let (_, lon, _) = along(&cfg, t);
        assert!((lon - (-98.5278)).abs() < 1e-3, "{lon}");
        // Second leg heads north.
        let t = Duration::from_secs_f64((leg + 100.0) / cfg.speed_mps);
        let (_, _, track) = along(&cfg, t);
        assert!(track.abs() < 0.1 || (track - 360.0).abs() < 0.1, "{track}");
        // Round the loop and back to the start.
        let total: f64 = (0..4)
            .map(|i| distance_m(cfg.corners[i], cfg.corners[(i + 1) % 4]))
            .sum();
        let (lat, lon, _) = along(&cfg, Duration::from_secs_f64(total / cfg.speed_mps));
        assert!((lat - cfg.corners[0].0).abs() < 1e-6 && (lon - cfg.corners[0].1).abs() < 1e-6);
    }

    #[test]
    fn outages_lose_the_fix() {
        let cfg = SimConfig {
            outage_every: Some(Duration::from_secs(60)),
            outage_for: Duration::from_secs(10),
            ..SimConfig::default()
        };
        assert!(
            tpv_at(&cfg, Duration::from_secs(5)).has_position(),
            "none before the first"
        );
        assert!(!tpv_at(&cfg, Duration::from_secs(65)).has_position());
        assert!(tpv_at(&cfg, Duration::from_secs(71)).has_position());
        assert!(!tpv_at(&cfg, Duration::from_secs(125)).has_position());
        assert!(tpv_at(&SimConfig::default(), Duration::from_secs(65)).has_position());
    }
}
