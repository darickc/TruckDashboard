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
        art_lines_per_tick: 50,
        art_repeat: Duration::from_millis(300),
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
    let task = tokio::spawn(serve(
        pi,
        rx,
        Units::Metric,
        timing(),
        |_| {},
        move |m| l2.lock().unwrap().push(m),
    ));

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
    let task = tokio::spawn(serve(pi, rx, Units::Imperial, timing(), |_| {}, |_| {}));
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
    let call = lines.next_line().await.unwrap().unwrap();
    assert!(
        first
            .iter()
            .chain([&call])
            .any(|l| l.starts_with("P1 none*")),
        "{first:?} {call}"
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
        .skip_while(|l| l.starts_with("N1") || l.starts_with("M1") || l.starts_with("P1"))
        .filter(|l| l.starts_with("N1") || l.starts_with("M1") || l.starts_with("P1"))
        .collect();
    assert!(after.is_empty(), "nothing old: {late:?}");
    drop(tx);
    task.abort();
}

#[tokio::test]
async fn the_cover_goes_out_paced_and_again_after_a_while() {
    use knob_link::art::{Art, CHUNK, lines as art_lines, none_line};
    use knob_link::link::Cover;
    let pixels: Vec<u8> = (0..1000u32).map(|i| (i % 251) as u8).collect();
    let crc = knob_link::art::crc32(&pixels);
    let art = Arc::new(Art {
        id: crc,
        w: 10,
        h: 50,
        pixels,
        crc,
    });
    let want = art_lines(&art);
    assert_eq!(want.len(), 1 + 1000usize.div_ceil(CHUNK));
    let (pi, dial) = tokio::io::duplex(1 << 16);
    let (tx, rx) = watch::channel(Latest {
        cover: Cover::Some(Arc::clone(&art)),
        ..Default::default()
    });
    let mut t = timing();
    t.art_lines_per_tick = 3;
    let task = tokio::spawn(serve(pi, rx, Units::Imperial, t, |_| {}, |_| {}));
    let mut lines = BufReader::new(dial).lines();
    let mut next_art = async || loop {
        let l = lines.next_line().await.unwrap().unwrap();
        if l.starts_with("A1 ") {
            return (Instant::now(), l);
        }
    };
    // Every line, in order, at most three per period.
    let mut got = Vec::new();
    let mut times = Vec::new();
    for _ in 0..want.len() {
        let (at, l) = next_art().await;
        assert!(ok_checksum(&l));
        got.push(l);
        times.push(at);
    }
    assert_eq!(got, want);
    assert!(
        times[want.len() - 1].duration_since(times[0]) >= Duration::from_millis(40),
        "paced over at least three periods"
    );
    // And again after art_repeat (300 ms), from its begin.
    let (_, again) = next_art().await;
    assert_eq!(again, want[0]);
    // A track without a picture: "none" (after what's queued).
    tx.send_modify(|l| l.cover = Cover::None);
    let mut seen_none = false;
    for _ in 0..want.len() + 2 {
        let (_, l) = next_art().await;
        if l == none_line() {
            seen_none = true;
            break;
        }
    }
    assert!(seen_none);
    task.abort();
}

#[tokio::test]
async fn no_cover_lines_until_audio_manager_says() {
    let (pi, dial) = tokio::io::duplex(8192);
    let (_tx, rx) = watch::channel(Latest::default());
    let task = tokio::spawn(serve(pi, rx, Units::Imperial, timing(), |_| {}, |_| {}));
    let mut lines = BufReader::new(dial).lines();
    for _ in 0..5 {
        let l = tokio::time::timeout(Duration::from_millis(500), lines.next_line())
            .await
            .unwrap()
            .unwrap()
            .unwrap();
        assert!(!l.starts_with("A1 "), "{l}");
    }
    task.abort();
}

#[tokio::test]
async fn a_call_button_reaches_audio_manager_only_for_the_call_shown() {
    use f250_proto::audio::v1 as audio;
    use knob_link::frame::with_checksum;
    use knob_link::pages::CallCommand;
    let ringing = |state: audio::CallState| audio::WatchAudioResponse {
        phone: Some(audio::Phone::default()),
        calls: Some(audio::Calls {
            available: true,
            call: Some(audio::Call {
                id: 42,
                state: state.into(),
                name: "Test Caller".into(),
                ..Default::default()
            }),
            ..Default::default()
        }),
        ..Default::default()
    };
    let (pi, dial) = tokio::io::duplex(1 << 16);
    let (tx, rx) = watch::channel(Latest {
        audio: Some((Instant::now(), ringing(audio::CallState::Incoming))),
        ..Default::default()
    });
    let sent = Arc::new(Mutex::new(Vec::<CallCommand>::new()));
    let logs = Arc::new(Mutex::new(Vec::<String>::new()));
    let (s2, l2) = (Arc::clone(&sent), Arc::clone(&logs));
    let task = tokio::spawn(serve(
        pi,
        rx,
        Units::Imperial,
        timing(),
        move |c| s2.lock().unwrap().push(c),
        move |m| l2.lock().unwrap().push(m),
    ));
    let (_dial_rd, mut dial_wr) = tokio::io::split(dial);
    // Answer while it rings: sent.
    dial_wr
        .write_all(format!("{}\n", with_checksum("K1 answer")).as_bytes())
        .await
        .unwrap();
    tokio::time::sleep(Duration::from_millis(50)).await;
    assert_eq!(*sent.lock().unwrap(), vec![CallCommand::Answer(42)]);
    // The phone answered meanwhile: a Decline is not sent, and says why.
    tx.send_modify(|l| l.audio = Some((Instant::now(), ringing(audio::CallState::Active))));
    dial_wr
        .write_all(format!("{}\n", with_checksum("K1 decline")).as_bytes())
        .await
        .unwrap();
    tokio::time::sleep(Duration::from_millis(50)).await;
    assert_eq!(sent.lock().unwrap().len(), 1);
    assert!(
        logs.lock()
            .unwrap()
            .iter()
            .any(|l| l.contains("not sent: the call is CALL_STATE_ACTIVE")),
        "{:?}",
        logs.lock().unwrap()
    );
    // End during it: sent.
    dial_wr
        .write_all(format!("{}\n", with_checksum("K1 end")).as_bytes())
        .await
        .unwrap();
    tokio::time::sleep(Duration::from_millis(50)).await;
    assert_eq!(
        *sent.lock().unwrap(),
        vec![CallCommand::Answer(42), CallCommand::HangUp(42)]
    );
    // audio-manager gone quiet: nothing is sent on old news.
    tokio::time::sleep(Duration::from_millis(150)).await;
    dial_wr
        .write_all(format!("{}\n", with_checksum("K1 end")).as_bytes())
        .await
        .unwrap();
    tokio::time::sleep(Duration::from_millis(50)).await;
    assert_eq!(sent.lock().unwrap().len(), 2);
    task.abort();
}
