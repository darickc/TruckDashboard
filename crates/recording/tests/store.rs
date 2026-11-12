//! The on-drive store with real files in a temporary directory. `[SIM]`.

use std::fs;
use std::path::PathBuf;

use recording::retention::{Drive, plan};
use recording::segment::SegmentName;
use recording::settings::Settings;
use recording::store::{Previous, Store};

fn temp(test: &str) -> PathBuf {
    let dir = std::env::temp_dir().join(format!("f250-rec-{test}-{}", std::process::id()));
    let _ = fs::remove_dir_all(&dir);
    dir
}

fn name(camera: &str, boot: u32, seq: u32) -> SegmentName {
    SegmentName {
        camera: camera.into(),
        boot,
        seq,
        wall: None,
    }
}

fn write(store: &Store, n: &SegmentName, bytes: usize) {
    let dir = store.camera_dir(&n.camera).expect("dir");
    fs::write(dir.join(n.file_name()), vec![0u8; bytes]).expect("write");
}

#[test]
fn runs_count_up_and_remember_whether_the_last_one_stopped_cleanly() {
    let root = temp("runs");
    let store = Store::open(&root).expect("open");

    let r1 = store.start_run().expect("run 1");
    assert_eq!((r1.boot, r1.previous), (1, None));
    store.mark_clean_stop(1).expect("mark");

    let r2 = store.start_run().expect("run 2");
    assert_eq!(r2.boot, 2);
    assert_eq!(
        r2.previous,
        Some(Previous {
            boot: 1,
            clean: true
        })
    );
    // Run 2 never marks a clean stop (power cut).

    let r3 = Store::open(&root)
        .expect("reopen")
        .start_run()
        .expect("run 3");
    assert_eq!(
        r3.previous,
        Some(Previous {
            boot: 2,
            clean: false
        })
    );

    // A stale marker from an older run doesn't make the last one clean.
    store.mark_clean_stop(1).expect("old marker");
    let r4 = store.start_run().expect("run 4");
    assert_eq!(
        r4.previous,
        Some(Previous {
            boot: 3,
            clean: false
        })
    );
    fs::remove_dir_all(&root).ok();
}

#[test]
fn a_damaged_run_counter_is_an_error_not_a_restart_from_one() {
    let root = temp("damaged");
    let store = Store::open(&root).expect("open");
    fs::write(root.join(".state/boot"), "garbage").expect("write");
    let e = store.start_run().expect_err("must not reuse run numbers");
    assert!(e.to_string().contains("not a number"), "{e}");
    fs::remove_dir_all(&root).ok();
}

#[test]
fn scan_finds_segments_and_reports_strays_without_touching_them() {
    let root = temp("scan");
    let store = Store::open(&root).expect("open");
    write(&store, &name("front", 1, 0), 10);
    write(&store, &name("rear", 1, 0), 20);
    fs::write(
        store.camera_dir("front").expect("dir").join("notes.txt"),
        "x",
    )
    .expect("stray");
    fs::write(root.join("README"), "x").expect("stray");
    fs::create_dir_all(root.join("Bad")).expect("stray dir");

    let scan = store.scan().expect("scan");
    let mut got: Vec<(String, u64, bool)> = scan
        .segments
        .iter()
        .map(|g| (g.name.to_string(), g.bytes, g.protected))
        .collect();
    got.sort();
    assert_eq!(
        got,
        [
            ("front/b00001-s000000.mkv".to_string(), 10, false),
            ("rear/b00001-s000000.mkv".to_string(), 20, false),
        ]
    );
    assert_eq!(scan.ignored.len(), 3, "{:?}", scan.ignored);
    assert!(root.join("README").exists());
    fs::remove_dir_all(&root).ok();
}

#[test]
fn protecting_moves_a_clip_where_retention_never_looks() {
    let root = temp("protect");
    let store = Store::open(&root).expect("open");
    let n = name("front", 1, 0);
    write(&store, &n, 100);
    store.protect(&n).expect("protect");
    assert!(!store.path(&n, false).exists());
    assert!(store.path(&n, true).exists());
    assert_eq!(
        store.path(&n, true),
        root.join("protected/front/b00001-s000000.mkv")
    );

    let scan = store.scan().expect("scan");
    assert_eq!(scan.protected_bytes(), 100);
    // Even with no free space and a tiny size limit, nothing is planned for
    // deletion, and the drive problem is reported.
    let s = Settings {
        max_bytes: 1,
        ..Settings::default()
    };
    let p = plan(&scan.segments, &[], Drive { free_bytes: 0 }, None, &s);
    assert!(p.delete.is_empty());
    assert!(p.problem.is_some());
    fs::remove_dir_all(&root).ok();
}

#[test]
fn applying_a_plan_deletes_only_recordings_and_tolerates_ones_already_gone() {
    let root = temp("apply");
    let store = Store::open(&root).expect("open");
    for i in 0..3 {
        write(&store, &name("rear", 1, i), 1000);
    }
    let scan = store.scan().expect("scan");
    let s = Settings {
        max_bytes: 1500,
        min_free_bytes: 0,
        ..Settings::default()
    };
    let p = plan(
        &scan.segments,
        &[],
        Drive {
            free_bytes: 1 << 40,
        },
        None,
        &s,
    );
    assert_eq!(p.delete.len(), 2);
    fs::remove_file(store.path(&name("rear", 1, 0), false)).expect("someone else deleted it");
    assert!(store.apply(&p).is_empty());
    let left: Vec<String> = store
        .scan()
        .expect("scan")
        .segments
        .iter()
        .map(|g| g.name.to_string())
        .collect();
    assert_eq!(left, ["rear/b00001-s000002.mkv"]);
    fs::remove_dir_all(&root).ok();
}

#[test]
fn camera_names_cannot_escape_the_store() {
    let root = temp("names");
    let store = Store::open(&root).expect("open");
    for bad in ["../etc", "protected", "", "Front", "front/x"] {
        assert!(store.camera_dir(bad).is_err(), "{bad:?}");
    }
    fs::remove_dir_all(&root).ok();
}

#[test]
fn an_existing_store_is_read_without_creating_anything() {
    let root = temp("existing");
    fs::create_dir_all(root.join("front")).expect("mkdir");
    fs::write(
        root.join("front").join(name("front", 3, 1).file_name()),
        b"abc",
    )
    .expect("write");
    let store = Store::existing(&root);
    let scan = store.scan().expect("scan without protected/");
    assert_eq!(scan.segments.len(), 1);
    assert_eq!(scan.segments[0].bytes, 3);
    assert!(!root.join("protected").exists(), "nothing created");
    assert!(!root.join(".state").exists(), "nothing created");
    assert!(Store::existing(root.join("missing")).scan().is_err());
}
