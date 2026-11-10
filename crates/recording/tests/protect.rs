//! Saved clips and the minutes before an unclean stop (ADR-0027
//! decision 8). `[SIM]`.

use recording::protect::{ClipError, after_unclean_stop, fits, save_clip};
use recording::retention::Segment;
use recording::segment::SegmentName;
use recording::settings::Settings;

const GB: u64 = 1_000_000_000;

fn seg(camera: &str, boot: u32, seq: u32, gb: u64) -> Segment {
    Segment {
        name: SegmentName {
            camera: camera.into(),
            boot,
            seq,
            wall: None,
        },
        bytes: gb * GB,
        protected: false,
    }
}

fn names(v: &[SegmentName]) -> Vec<String> {
    v.iter().map(|n| n.to_string()).collect()
}

/// 10 minutes of front and rear in run 3, minute 10 being written.
fn ten_minutes() -> (Vec<Segment>, Vec<SegmentName>) {
    let segs: Vec<Segment> = (0..=10)
        .flat_map(|i| [seg("front", 3, i, 1), seg("rear", 3, i, 1)])
        .collect();
    let writing = vec![segs[20].name.clone(), segs[21].name.clone()];
    (segs, writing)
}

#[test]
fn save_clip_keeps_two_minutes_before_and_asks_for_the_rest_as_they_finish() {
    let (segs, writing) = ten_minutes();
    let s = Settings::default(); // 120 s before, 60 s after, 60 s segments
    let p = save_clip(&segs, &writing, 0, &s).expect("fits");
    assert_eq!(
        names(&p.protect_now),
        [
            "front/b00003-s000008.mkv",
            "rear/b00003-s000008.mkv",
            "front/b00003-s000009.mkv",
            "rear/b00003-s000009.mkv",
        ]
    );
    // The segment being written, then one more, per camera.
    assert_eq!(
        p.protect_next,
        [("front".to_string(), 2), ("rear".to_string(), 2)]
    );
}

#[test]
fn save_clip_early_in_a_run_takes_what_there_is() {
    let segs = [seg("front", 1, 0, 1), seg("front", 1, 1, 1)];
    let p = save_clip(&segs, &[segs[1].name.clone()], 0, &Settings::default()).expect("fits");
    assert_eq!(names(&p.protect_now), ["front/b00001-s000000.mkv"]);
}

#[test]
fn save_clip_skips_segments_already_saved() {
    let (mut segs, writing) = ten_minutes();
    segs[18].protected = true; // front s9 already saved
    let p = save_clip(&segs, &writing, 0, &Settings::default()).expect("fits");
    assert!(!names(&p.protect_now).contains(&"front/b00003-s000009.mkv".to_string()));
    assert!(names(&p.protect_now).contains(&"front/b00003-s000008.mkv".to_string()));
}

#[test]
fn a_full_cap_refuses_the_save_instead_of_deleting_old_clips() {
    let (segs, writing) = ten_minutes();
    let s = Settings {
        protected_max_bytes: 25 * GB,
        ..Settings::default()
    };
    // 4 finished (4 GB) + 4 estimated to come (4 GB) = 8 GB; 20 GB used.
    match save_clip(&segs, &writing, 20 * GB, &s) {
        Err(ClipError::CapFull {
            need_bytes,
            free_bytes,
        }) => {
            assert_eq!(need_bytes, 8 * GB);
            assert_eq!(free_bytes, 5 * GB);
        }
        other => panic!("{other:?}"),
    }
    assert!(
        save_clip(&segs, &writing, 17 * GB, &s).is_ok(),
        "exactly fits"
    );
    assert!(fits(17 * GB, 8 * GB, &s));
    assert!(!fits(17 * GB, 8 * GB + 1, &s));
}

#[test]
fn nothing_recording_means_nothing_to_save() {
    let (segs, _) = ten_minutes();
    assert_eq!(
        save_clip(&segs, &[], 0, &Settings::default()),
        Err(ClipError::NotRecording)
    );
}

#[test]
fn an_unclean_stop_protects_the_last_minutes_of_the_run_before() {
    // Run 3 was cut off after minute 10; run 4 is starting.
    let (mut segs, _) = ten_minutes();
    segs.push(seg("front", 2, 50, 1)); // an older run: untouched
    let p = after_unclean_stop(&segs, 3, 0, &Settings::default()); // 5 min → 6 segments each
    let mut got = names(&p.protect);
    got.sort();
    let mut want: Vec<String> = (5..=10)
        .flat_map(|i| {
            [
                format!("front/b00003-s{i:06}.mkv"),
                format!("rear/b00003-s{i:06}.mkv"),
            ]
        })
        .collect();
    want.sort();
    assert_eq!(got, want);
    assert!(p.skipped.is_empty());
    // Newest first.
    assert_eq!(p.protect[0].seq, 10);
}

#[test]
fn when_the_cap_is_short_the_minutes_closest_to_the_stop_win() {
    let (segs, _) = ten_minutes();
    let s = Settings {
        protected_max_bytes: 4 * GB,
        ..Settings::default()
    };
    let p = after_unclean_stop(&segs, 3, 0, &s);
    assert_eq!(
        names(&p.protect),
        [
            "rear/b00003-s000010.mkv",
            "front/b00003-s000010.mkv",
            "rear/b00003-s000009.mkv",
            "front/b00003-s000009.mkv",
        ]
    );
    assert_eq!(
        p.skipped.len(),
        8,
        "the other 4 per camera are reported, not protected"
    );
}

#[test]
fn unclean_protection_off_or_nothing_from_that_run() {
    let (segs, _) = ten_minutes();
    let off = Settings {
        unclean_protect_min: 0,
        ..Settings::default()
    };
    let p = after_unclean_stop(&segs, 3, 0, &off);
    assert!(p.protect.is_empty() && p.skipped.is_empty());
    let p = after_unclean_stop(&segs, 7, 0, &Settings::default());
    assert!(p.protect.is_empty() && p.skipped.is_empty());
}
