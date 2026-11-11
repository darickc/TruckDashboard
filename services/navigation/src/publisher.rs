//! Source events → the tracker → `f250.nav.v1.Position`, published on every
//! event and once a second so ages move and a fix goes stale on time even
//! when gpsd says nothing.

use std::time::Duration;

use f250_proto::nav::v1 as pb;
use f250_sd_notify::Heartbeat;
use gpsd::tracker::{Position, Status, Tracker};
use tokio::sync::{mpsc, watch};

use crate::source::Event;

pub const TICK: Duration = Duration::from_secs(1);

#[derive(Debug, Clone)]
pub struct PublisherConfig {
    pub stale_after: Duration,
    pub simulated: bool,
    pub tick: Duration,
}

pub fn status_to_pb(s: Status) -> pb::FixStatus {
    match s {
        Status::Unavailable => pb::FixStatus::Unavailable,
        Status::NoReceiver => pb::FixStatus::NoReceiver,
        Status::ReceiverSilent => pb::FixStatus::ReceiverSilent,
        Status::NoFix => pb::FixStatus::NoFix,
        Status::Fix2d => pb::FixStatus::Fix2d,
        Status::Fix3d => pb::FixStatus::Fix3d,
    }
}

fn ms(d: Duration) -> u64 {
    u64::try_from(d.as_millis()).unwrap_or(u64::MAX)
}

/// Where it comes from, for the screen.
pub fn source_label(p: &Position, simulated: bool) -> String {
    if simulated {
        return "simulated".to_string();
    }
    let gpsd = match &p.gpsd_release {
        Some(r) => format!("gpsd {r}"),
        None => "gpsd".to_string(),
    };
    if p.receivers.is_empty() {
        gpsd
    } else {
        format!("{gpsd}: {}", p.receivers.join(", "))
    }
}

pub fn to_pb(p: &Position, simulated: bool, stale_after: Duration) -> pb::Position {
    pb::Position {
        status: status_to_pb(p.status) as i32,
        fix: p.fix.as_ref().map(|f| pb::Fix {
            latitude_deg: f.lat,
            longitude_deg: f.lon,
            age_ms: p.fix_age.map_or(0, ms),
            altitude_msl_m: f.alt_msl_m.map(|v| v.value),
            speed_mps: f.speed_mps.map(|v| v.value),
            track_deg: f.track_deg.map(|v| v.value),
            horizontal_error_m: f.eph_m.map(|v| v.value),
            utc_time_ms: f.utc_ms,
        }),
        current: p.current,
        stale_after_ms: ms(stale_after),
        satellites_used: p.satellites_used,
        satellites_visible: p.satellites_visible,
        source: source_label(p, simulated),
        simulated,
        detail: p.detail.clone(),
    }
}

/// Runs until the source's channel closes.
pub async fn run(
    cfg: PublisherConfig,
    mut rx: mpsc::Receiver<Event>,
    out: watch::Sender<pb::Position>,
    heartbeat: Option<Heartbeat>,
) {
    let start = tokio::time::Instant::now();
    let mut tracker = Tracker::new(cfg.stale_after);
    let mut tick = tokio::time::interval(cfg.tick);
    let mut logged: Option<(Status, bool, String)> = None;
    loop {
        tokio::select! {
            _ = tick.tick() => {
                if let Some(h) = &heartbeat {
                    h.beat();
                }
            }
            event = rx.recv() => match event {
                None => return,
                Some(Event::Connected) => tracker.connected(),
                Some(Event::Disconnected(why)) => tracker.disconnected(&why),
                Some(Event::Report(r)) => tracker.report(&r, start.elapsed()),
            },
        }
        let p = tracker.position(start.elapsed());
        let key = (p.status, p.current, p.detail.clone());
        if logged.as_ref() != Some(&key) {
            eprintln!(
                "[navigation] {:?}{} ({}){}",
                p.status,
                if p.current { ", current" } else { "" },
                source_label(&p, cfg.simulated),
                if p.detail.is_empty() {
                    String::new()
                } else {
                    format!(": {}", p.detail)
                }
            );
            logged = Some(key);
        }
        out.send_replace(to_pb(&p, cfg.simulated, cfg.stale_after));
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use gpsd::report::{Mode, Report, Tpv};

    #[test]
    fn a_current_fix_and_a_stale_one() {
        let mut t = Tracker::new(Duration::from_secs(3));
        t.connected();
        t.report(
            &Report::Version {
                release: "3.27.5".to_string(),
                proto_major: 3,
                proto_minor: 16,
            },
            Duration::ZERO,
        );
        t.report(
            &Report::Tpv(Tpv {
                device: Some("/dev/ttyACM0".to_string()),
                mode: Some(Mode::Fix2d),
                lat: Some(39.8),
                lon: Some(-98.5),
                speed_mps: Some(12.5),
                ..Tpv::default()
            }),
            Duration::from_secs(1),
        );
        let p = to_pb(
            &t.position(Duration::from_millis(1500)),
            false,
            Duration::from_secs(3),
        );
        assert_eq!(p.status, pb::FixStatus::Fix2d as i32);
        assert!(p.current);
        assert!(!p.simulated);
        assert_eq!(p.source, "gpsd 3.27.5: /dev/ttyACM0");
        assert_eq!(p.stale_after_ms, 3000);
        let f = p.fix.expect("fix");
        assert_eq!(
            (f.latitude_deg, f.longitude_deg, f.age_ms),
            (39.8, -98.5, 500)
        );
        assert_eq!(f.speed_mps, Some(12.5));
        assert_eq!(f.track_deg, None);
        assert_eq!(f.altitude_msl_m, None);

        let p = to_pb(
            &t.position(Duration::from_secs(10)),
            false,
            Duration::from_secs(3),
        );
        assert!(!p.current);
        assert_eq!(p.status, pb::FixStatus::ReceiverSilent as i32);
        assert_eq!(p.fix.expect("kept").age_ms, 9000);
        assert!(!p.detail.is_empty());
    }

    #[test]
    fn simulated_is_labelled() {
        let t = Tracker::new(Duration::from_secs(3));
        let p = to_pb(&t.position(Duration::ZERO), true, Duration::from_secs(3));
        assert!(p.simulated);
        assert_eq!(p.source, "simulated");
        assert_eq!(p.status, pb::FixStatus::Unavailable as i32);
        assert!(p.fix.is_none());
    }
}
