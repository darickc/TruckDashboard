//! Retention rules (ADR-0027 decision 7). `[SIM]`.

use recording::retention::{Drive, Plan, Problem, Reason, Segment, plan};
use recording::segment::SegmentName;
use recording::settings::Settings;

const GB: u64 = 1_000_000_000;
const DAY: u64 = 86_400;
/// 2026-11-10 14:30 UTC.
const NOW: u64 = 1_794_321_000;

fn seg(camera: &str, boot: u32, seq: u32, wall: Option<u64>, gb: u64) -> Segment {
    Segment {
        name: SegmentName {
            camera: camera.into(),
            boot,
            seq,
            wall,
        },
        bytes: gb * GB,
        protected: false,
    }
}

fn protected(mut s: Segment) -> Segment {
    s.protected = true;
    s
}

/// Small numbers so the arithmetic is easy to follow.
fn settings() -> Settings {
    Settings {
        max_age_days: 14,
        max_bytes: 100 * GB,
        min_free_bytes: 10 * GB,
        protected_max_bytes: 20 * GB,
        max_segments: 0,
        ..Settings::default()
    }
}

fn names(p: &Plan) -> Vec<String> {
    p.delete.iter().map(|(n, _)| n.to_string()).collect()
}

fn reasons(p: &Plan) -> Vec<Reason> {
    p.delete.iter().map(|(_, r)| *r).collect()
}

const ROOMY: Drive = Drive {
    free_bytes: 500 * GB,
};

#[test]
fn nothing_to_do_under_every_limit() {
    let segs = [
        seg("front", 1, 0, Some(NOW - DAY), 10),
        seg("rear", 1, 0, Some(NOW - DAY), 10),
    ];
    let p = plan(&segs, &[], ROOMY, Some(NOW), &settings());
    assert!(p.delete.is_empty());
    assert_eq!(p.recording_bytes_after, 20 * GB);
    assert_eq!(p.problem, None);
}

#[test]
fn old_segments_go_and_take_untrusted_older_ones_with_them() {
    let segs = [
        seg("front", 1, 0, None, 1), // clock untrusted, recorded before b2
        seg("front", 2, 0, Some(NOW - 20 * DAY), 1), // too old
        seg("front", 2, 1, None, 1), // clock lost mid-run? still after b2s0
        seg("front", 3, 0, Some(NOW - 13 * DAY), 1), // young enough
        seg("front", 3, 1, None, 1),
    ];
    let p = plan(&segs, &[], ROOMY, Some(NOW), &settings());
    assert_eq!(
        names(&p),
        [
            "front/b00001-s000000.mkv",
            &format!("front/{}", segs[1].name.file_name())
        ]
    );
    assert_eq!(reasons(&p), [Reason::Age, Reason::Age]);
}

#[test]
fn an_untrusted_clock_now_deletes_nothing_by_age() {
    let segs = [seg("rear", 1, 0, Some(NOW - 100 * DAY), 1)];
    let p = plan(&segs, &[], ROOMY, None, &settings());
    assert!(p.delete.is_empty(), "a wrong clock must not delete by age");
}

#[test]
fn a_clock_that_jumped_forward_only_deletes_by_its_own_trusted_segments() {
    // A segment stamped in the "future" (the clock was wrong then) is never
    // old; it doesn't drag older segments out early either.
    let segs = [
        seg("rear", 1, 0, Some(NOW + 300 * DAY), 1),
        seg("rear", 2, 0, Some(NOW - DAY), 1),
    ];
    let p = plan(&segs, &[], ROOMY, Some(NOW), &settings());
    assert!(p.delete.is_empty());
}

#[test]
fn age_limit_off_keeps_old_video() {
    let s = Settings {
        max_age_days: 0,
        ..settings()
    };
    let segs = [seg("rear", 1, 0, Some(NOW - 400 * DAY), 1)];
    assert!(plan(&segs, &[], ROOMY, Some(NOW), &s).delete.is_empty());
}

#[test]
fn size_limit_deletes_oldest_first_across_cameras() {
    // 6 × 20 GB = 120 GB against a 100 GB limit: the oldest one goes.
    let segs: Vec<Segment> = (0..3)
        .flat_map(|i| [seg("front", 1, i, None, 20), seg("rear", 1, i, None, 20)])
        .collect();
    let p = plan(&segs, &[], ROOMY, Some(NOW), &settings());
    assert_eq!(names(&p), ["front/b00001-s000000.mkv"]);
    assert_eq!(reasons(&p), [Reason::Size]);
    assert_eq!(p.recording_bytes_after, 100 * GB);
}

#[test]
fn the_segment_being_written_counts_but_is_never_deleted() {
    let segs = [seg("front", 1, 0, None, 60), seg("front", 1, 1, None, 60)];
    let writing = [segs[1].name.clone()];
    let p = plan(&segs, &writing, ROOMY, Some(NOW), &settings());
    assert_eq!(names(&p), ["front/b00001-s000000.mkv"]);
    assert_eq!(
        p.recording_bytes_after,
        60 * GB,
        "the written one is still counted"
    );

    // Only the writing one left, still over the limit: nothing to delete,
    // and it isn't a drive problem.
    let one = [seg("front", 1, 1, None, 150)];
    let p = plan(&one, &[one[0].name.clone()], ROOMY, Some(NOW), &settings());
    assert!(p.delete.is_empty());
    assert_eq!(p.problem, None);
}

#[test]
fn saved_clips_are_never_deleted_and_dont_count_toward_the_size_limit() {
    let segs = [
        protected(seg("front", 1, 0, Some(NOW - 300 * DAY), 90)),
        seg("front", 2, 0, None, 50),
    ];
    let p = plan(&segs, &[], ROOMY, Some(NOW), &settings());
    assert!(p.delete.is_empty());
    assert_eq!(p.recording_bytes_after, 50 * GB);
}

#[test]
fn free_space_deletes_until_the_minimum_is_back() {
    let segs = [
        seg("front", 1, 0, None, 3),
        seg("rear", 1, 0, None, 3),
        seg("front", 1, 1, None, 3),
        seg("rear", 1, 1, None, 3),
    ];
    // 4 GB free, 10 GB minimum: two 3 GB segments give 10.
    let p = plan(
        &segs,
        &[],
        Drive { free_bytes: 4 * GB },
        Some(NOW),
        &settings(),
    );
    assert_eq!(
        names(&p),
        ["front/b00001-s000000.mkv", "rear/b00001-s000000.mkv"]
    );
    assert_eq!(reasons(&p), [Reason::FreeSpace, Reason::FreeSpace]);
    assert_eq!(p.free_bytes_after, 10 * GB);
    assert_eq!(p.problem, None);
}

#[test]
fn a_drive_full_of_saved_clips_stops_recording_instead_of_deleting_them() {
    let segs = [
        protected(seg("front", 1, 0, None, 5)),
        seg("front", 2, 0, None, 1),
        seg("front", 2, 1, None, 1),
    ];
    let writing = [segs[2].name.clone()];
    let p = plan(
        &segs,
        &writing,
        Drive { free_bytes: 2 * GB },
        Some(NOW),
        &settings(),
    );
    assert_eq!(
        names(&p),
        ["front/b00002-s000000.mkv"],
        "the only deletable one"
    );
    assert_eq!(
        p.problem,
        Some(Problem::DriveFull {
            free_bytes: 3 * GB,
            min_free_bytes: 10 * GB
        })
    );
}

#[test]
fn segment_count_per_camera() {
    let s = Settings {
        max_segments: 2,
        ..settings()
    };
    let segs: Vec<Segment> = (0..4)
        .flat_map(|i| [seg("front", 1, i, None, 1), seg("rear", 1, i, None, 1)])
        .chain([seg("rear", 1, 4, None, 1)])
        .collect();
    let writing = [segs.last().map(|g| g.name.clone()).expect("one")];
    let p = plan(&segs, &writing, ROOMY, Some(NOW), &s);
    // front: 4 → 2; rear: 5 (one writing) → 2.
    assert_eq!(
        names(&p),
        [
            "front/b00001-s000000.mkv",
            "rear/b00001-s000000.mkv",
            "front/b00001-s000001.mkv",
            "rear/b00001-s000001.mkv",
            "rear/b00001-s000002.mkv",
        ]
    );
    assert!(reasons(&p).iter().all(|r| *r == Reason::Count));
}

#[test]
fn each_segment_is_listed_once_with_the_first_rule_that_caught_it() {
    let segs = [
        seg("front", 1, 0, Some(NOW - 30 * DAY), 60),
        seg("front", 2, 0, Some(NOW - DAY), 60),
        seg("front", 2, 1, Some(NOW), 60),
    ];
    let p = plan(
        &segs,
        &[segs[2].name.clone()],
        Drive { free_bytes: 0 },
        Some(NOW),
        &settings(),
    );
    assert_eq!(reasons(&p), [Reason::Age, Reason::Size]);
    assert_eq!(p.delete.len(), 2);
}

#[test]
fn a_simulated_month_never_breaks_the_limits() {
    // Two cameras, 2 h of driving a day, 1 GB per minute-segment pair
    // (0.5 GB each), retention after every minute; the drive starts with
    // 400 GB free. Invariants checked every step.
    let s = Settings {
        max_age_days: 14,
        max_bytes: 250 * GB,
        min_free_bytes: 50 * GB,
        ..Settings::default()
    };
    let half = GB / 2;
    let mut on_drive: Vec<Segment> = Vec::new();
    let mut free = 400 * GB;
    let start = NOW - 30 * DAY;
    for day in 0..30u64 {
        let boot = day as u32 + 1;
        for minute in 0..120u32 {
            let t = start + day * DAY + u64::from(minute) * 60;
            for cam in ["front", "rear"] {
                on_drive.push(Segment {
                    name: SegmentName {
                        camera: cam.into(),
                        boot,
                        seq: minute,
                        wall: Some(t),
                    },
                    bytes: half,
                    protected: false,
                });
                free -= half;
            }
            let writing: Vec<SegmentName> = on_drive
                .iter()
                .rev()
                .take(2)
                .map(|g| g.name.clone())
                .collect();
            let p = plan(&on_drive, &writing, Drive { free_bytes: free }, Some(t), &s);
            assert_eq!(p.problem, None, "day {day} minute {minute}");
            for (name, _) in &p.delete {
                assert!(!writing.contains(name));
                let i = on_drive
                    .iter()
                    .position(|g| &g.name == name)
                    .expect("exists");
                free += on_drive.remove(i).bytes;
            }
            let used: u64 = on_drive.iter().map(|g| g.bytes).sum();
            assert!(used <= s.max_bytes, "day {day}: {used} used");
            assert!(free >= s.min_free_bytes, "day {day}: {free} free");
            let oldest = on_drive
                .iter()
                .filter_map(|g| g.name.wall)
                .min()
                .expect("some");
            assert!(
                t - oldest <= 14 * DAY + 60,
                "day {day}: kept {} s",
                t - oldest
            );
        }
    }
    // 14 days × 120 GB/day of driving would be 1680 GB; the size limit
    // (250 GB) decided, so about two days are kept.
    let kept: u64 = on_drive.iter().map(|g| g.bytes).sum();
    assert!(kept > 240 * GB && kept <= 250 * GB, "{kept}");
}
