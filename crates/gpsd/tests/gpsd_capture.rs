//! gpsd 3.27.5's own output, captured on the Mac from synthetic NMEA
//! [SIM]: `tests/data/README.md` says how. Replayed through the parser and
//! the tracker, 0.25 s per line.

use std::time::Duration;

use gpsd::report::Report;
use gpsd::tracker::{DEFAULT_STALE_AFTER, Status, Tracker};

const CAPTURE: &str = include_str!("data/gpsd-3.27.5-nmea-udp.jsonl");

#[test]
fn every_line_parses() {
    for (n, line) in CAPTURE.lines().enumerate() {
        let r = Report::parse(line);
        assert!(r.is_ok(), "line {}: {r:?}", n + 1);
        assert!(!matches!(r, Ok(Report::Error(_))), "line {}", n + 1);
    }
}

#[test]
fn replay_goes_no_fix_3d_2d_no_fix() {
    let mut t = Tracker::new(DEFAULT_STALE_AFTER);
    t.connected();
    let mut statuses: Vec<Status> = Vec::new();
    let mut now = Duration::ZERO;
    let mut max_used = 0;
    for line in CAPTURE.lines() {
        let report = Report::parse(line).expect("parses");
        t.report(&report, now);
        let p = t.position(now);
        if statuses.last() != Some(&p.status) {
            statuses.push(p.status);
        }
        if p.status.is_fix() {
            assert!(p.current, "a fresh fix is current");
        }
        max_used = max_used.max(p.satellites_used.unwrap_or(0));
        now += Duration::from_millis(250);
    }
    assert_eq!(
        statuses,
        [
            Status::NoReceiver,     // VERSION, before DEVICES
            Status::ReceiverSilent, // DEVICES, before the first TPV
            Status::NoFix,
            Status::Fix3d,
            Status::Fix2d,
            Status::NoFix,
        ]
    );
    assert_eq!(max_used, 8);

    let p = t.position(now);
    assert!(!p.current, "no fix at the end");
    let fix = p.fix.expect("the last fix is kept");
    assert_eq!((fix.lat, fix.lon), (39.8299, -98.5779));
    assert_eq!(p.gpsd_release.as_deref(), Some("3.27.5"));
    assert_eq!(p.receivers, vec!["udp://127.0.0.1:5948".to_string()]);
}
