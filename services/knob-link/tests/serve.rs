//! The serial loop over an in-memory pipe: the config frame first, data
//! frames while the gateway is current, none once it goes quiet (the dial
//! then goes stale by itself), the dial's lines logged, and a closed port
//! ending it.

#![allow(clippy::unwrap_used)]

use std::collections::HashMap;
use std::sync::{Arc, Mutex};
use std::time::Duration;

use f250_proto::vehicle::v1 as pb;
use knob_link::frame::{Units, checksum};
use knob_link::link::{Latest, Timing, find_port, serve};
use tokio::io::{AsyncBufReadExt, AsyncWriteExt, BufReader};
use tokio::sync::watch;
use tokio::time::Instant;

fn timing() -> Timing {
    Timing {
        period: Duration::from_millis(20),
        config_every: Duration::from_millis(200),
        snapshot_max_age: Duration::from_millis(100),
        page_max_age: Duration::from_millis(100),
    }
}

fn snap(speed: f64) -> pb::Snapshot {
    pb::Snapshot {
        samples: vec![pb::Sample {
            signal_id: "speed".into(),
            validity: pb::Validity::Valid.into(),
            value: Some(speed),
            ..Default::default()
        }],
        ..Default::default()
    }
}

fn ok_checksum(line: &str) -> bool {
    line.rsplit_once('*')
        .is_some_and(|(b, cs)| u8::from_str_radix(cs, 16).ok() == Some(checksum(b)))
}

#[tokio::test]
async fn frames_follow_the_gateway_and_stop_when_it_goes_quiet() {
    let (pi, dial) = tokio::io::duplex(4096);
    let (tx, rx) = watch::channel(Latest {
        defs: HashMap::new(),
        defs_gen: 0,
        snapshot: Some((Instant::now(), snap(100.0))),
        ..Default::default()
    });
    let logs = Arc::new(Mutex::new(Vec::<String>::new()));
    let l2 = Arc::clone(&logs);
    let task = tokio::spawn(serve(pi, rx, Units::Metric, timing(), move |m| {
        l2.lock().unwrap().push(m)
    }));

    let (dial_rd, mut dial_wr) = tokio::io::split(dial);
    let mut lines = BufReader::new(dial_rd).lines();
    let first = lines.next_line().await.unwrap().unwrap();
    assert!(
        first.starts_with("C1 spd:kmh:0:160:u "),
        "config first: {first}"
    );
    assert!(ok_checksum(&first));
    let data = lines.next_line().await.unwrap().unwrap();
    assert!(data.starts_with("D1 1 live spd:c:100 fuel:n"), "{data}");
    assert!(ok_checksum(&data));
    let next = lines.next_line().await.unwrap().unwrap();
    assert!(next.starts_with("D1 2 "), "sequence counts: {next}");

    // The definitions arrive: the config frame goes out again at once, now
    // trusting speed (SAE).
    tx.send_modify(|l| {
        l.defs = HashMap::from([(
            "speed".to_string(),
            pb::SignalDefinition {
                id: "speed".into(),
                provenance: pb::Provenance::Sae.into(),
                ..Default::default()
            },
        )]);
        l.defs_gen += 1;
    });
    let mut cfg = None;
    for _ in 0..5 {
        let l = lines.next_line().await.unwrap().unwrap();
        if l.starts_with("C1 ") {
            cfg = Some(l);
            break;
        }
    }
    assert!(
        cfg.unwrap().starts_with("C1 spd:kmh:0:160:v "),
        "resent with the definitions"
    );

    // The dial's hello and log.
    let hello = format!(
        "H1 knob-display 0.1.0*{:02X}\n",
        checksum("H1 knob-display 0.1.0")
    );
    dial_wr.write_all(hello.as_bytes()).await.unwrap();
    dial_wr.write_all(b"# frames: 2 data\n").await.unwrap();

    // The gateway goes quiet: after snapshot_max_age, no more data frames
    // (config frames go on).
    tokio::time::sleep(Duration::from_millis(150)).await;
    let mut seen = Vec::new();
    let until = Instant::now() + Duration::from_millis(300);
    while Instant::now() < until {
        if let Ok(Ok(Some(l))) =
            tokio::time::timeout(Duration::from_millis(50), lines.next_line()).await
        {
            seen.push(l);
        }
    }
    assert!(seen.iter().any(|l| l.starts_with("C1 ")), "{seen:?}");
    let late_data = seen
        .iter()
        .skip_while(|l| l.starts_with("D1 "))
        .filter(|l| l.starts_with("D1 "))
        .count();
    assert_eq!(late_data, 0, "no data once the snapshot is old: {seen:?}");

    // It comes back.
    tx.send_modify(|l| l.snapshot = Some((Instant::now(), snap(50.0))));
    let mut back = None;
    for _ in 0..20 {
        let l = lines.next_line().await.unwrap().unwrap();
        if l.starts_with("D1 ") {
            back = Some(l);
            break;
        }
    }
    assert!(back.unwrap().contains(" spd:c:50 "));

    {
        let logs = logs.lock().unwrap();
        assert!(
            logs.contains(&"dial: knob-display 0.1.0".to_string()),
            "{logs:?}"
        );
        assert!(
            logs.contains(&"dial says: frames: 2 data".to_string()),
            "{logs:?}"
        );
    }

    // The dial unplugged: the loop ends and says why.
    drop(lines);
    drop(dial_wr);
    let why = tokio::time::timeout(Duration::from_secs(2), task)
        .await
        .unwrap()
        .unwrap();
    assert!(why.contains("closed") || why.starts_with("write"), "{why}");
}

#[test]
fn finds_the_dial_by_its_usb_name() {
    let dir = std::env::temp_dir().join(format!("f250-knob-byid-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).unwrap();
    assert_eq!(find_port(None, &dir), None);
    std::fs::write(dir.join("usb-OBDLink_MX-if00"), "").unwrap();
    assert_eq!(find_port(None, &dir), None, "another serial device");
    let dial = dir.join("usb-TruckDashboard_F-250_knob_0123-if00");
    std::fs::write(&dial, "").unwrap();
    assert_eq!(find_port(None, &dir), Some(dial.clone()));
    // A fixed device: used if it exists.
    assert_eq!(find_port(Some(&dial), &dir), Some(dial.clone()));
    assert_eq!(find_port(Some(&dir.join("nope")), &dir), None);
    let _ = std::fs::remove_dir_all(&dir);
}

#[tokio::test]
async fn nav_and_media_frames_only_while_they_are_fresh() {
    use f250_proto::audio::v1 as audio;
    use f250_proto::nav::v1 as nav;
    let (pi, dial) = tokio::io::duplex(8192);
    let (tx, rx) = watch::channel(Latest {
        guidance: Some((
            Instant::now(),
            nav::Guidance {
                state: nav::RouteState::Routing.into(),
                ..Default::default()
            },
        )),
        audio: Some((Instant::now(), audio::WatchAudioResponse::default())),
        ..Default::default()
    });
    let task = tokio::spawn(serve(pi, rx, Units::Imperial, timing(), |_| {}));
    let mut lines = BufReader::new(dial).lines();
    let mut first = Vec::new();
    for _ in 0..3 {
        first.push(lines.next_line().await.unwrap().unwrap());
    }
    // No snapshot: no D1, but the pages' frames.
    assert!(
        first.iter().any(|l| l.starts_with("N1 route*")),
        "{first:?}"
    );
    assert!(
        first.iter().any(|l| l.starts_with("M1 none -*")),
        "{first:?}"
    );
    assert!(first.iter().all(|l| ok_checksum(l)));
    assert!(!first.iter().any(|l| l.starts_with("D1 ")));
    // Both go quiet: after page_max_age, neither is sent.
    tokio::time::sleep(Duration::from_millis(150)).await;
    let mut late = Vec::new();
    let until = Instant::now() + Duration::from_millis(250);
    while Instant::now() < until {
        if let Ok(Ok(Some(l))) =
            tokio::time::timeout(Duration::from_millis(50), lines.next_line()).await
        {
            late.push(l);
        }
    }
    let after: Vec<_> = late
        .iter()
        .skip_while(|l| l.starts_with("N1") || l.starts_with("M1"))
        .filter(|l| l.starts_with("N1") || l.starts_with("M1"))
        .collect();
    assert!(after.is_empty(), "nothing old: {late:?}");
    drop(tx);
    task.abort();
}
