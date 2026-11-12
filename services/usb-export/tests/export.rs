//! The exporter end to end with directories standing in for the data drive
//! and the stick (stickfs::DirFs). `[SIM]`: no stick is mounted.

use std::fs;
use std::path::{Path, PathBuf};
use std::sync::Arc;
use std::sync::atomic::{AtomicBool, Ordering};
use std::time::{Duration, Instant};

use f250_proto::export::v1 as pb;
use usb_export::copy::{self, FOLDER, Failure, Outcome, Ref};
use usb_export::exporter::{Config, Exporter};
use usb_export::stickfs::DirFs;
use usb_export::sticks::{self, Found};

const MB: usize = 1 << 20;

fn temp(test: &str) -> PathBuf {
    let dir = std::env::temp_dir().join(format!("f250-export-{test}-{}", std::process::id()));
    let _ = fs::remove_dir_all(&dir);
    fs::create_dir_all(&dir).expect("temp");
    dir
}

/// A recording of `len` bytes, its content telling it apart.
fn record(video: &Path, rel: &str, len: usize) -> Vec<u8> {
    let path = video.join(rel);
    fs::create_dir_all(path.parent().expect("parent")).expect("mkdir");
    let data: Vec<u8> = (0..len)
        .map(|i| (i % 251) as u8 ^ rel.len() as u8)
        .collect();
    fs::write(&path, &data).expect("write");
    // Old enough not to count as being written.
    let old = std::time::SystemTime::now() - Duration::from_secs(600);
    fs::File::options()
        .write(true)
        .open(&path)
        .and_then(|f| f.set_modified(old))
        .expect("mtime");
    data
}

fn r(camera: &str, file: &str, protected: bool) -> Ref {
    Ref {
        camera: camera.into(),
        file_name: file.into(),
        protected,
    }
}

struct Bench {
    video: PathBuf,
    stick: PathBuf,
    fs: Arc<DirFs>,
    exporter: Arc<Exporter>,
}

fn bench(test: &str) -> Bench {
    let root = temp(test);
    let video = root.join("video");
    let stick = root.join("stick");
    fs::create_dir_all(&video).expect("video");
    fs::create_dir_all(&stick).expect("stick");
    let dirs = Arc::new(DirFs::new());
    dirs.add("sdz1", &stick);
    let present = dirs.clone();
    let exporter = Exporter::new(
        Config {
            video_root: video.clone(),
            drive: None,
            map_lock: root.join("no-map-import.lock"),
            writing_window: Duration::from_secs(15),
        },
        dirs.clone(),
        Box::new(move || {
            use usb_export::stickfs::StickFs;
            if !present.present("sdz1") {
                return Vec::new();
            }
            vec![Found {
                device: "sdz1".into(),
                filesystem: "exfat".into(),
                label: "STICK".into(),
                model: "Test Stick".into(),
                size_bytes: 32_000_000_000,
                read_only: false,
            }]
        }),
    );
    Bench {
        video,
        stick,
        fs: dirs,
        exporter,
    }
}

fn wait_done(e: &Exporter) -> pb::Copy {
    let start = Instant::now();
    loop {
        let c = e.status().copy.expect("copy");
        let state = pb::CopyState::try_from(c.state).expect("state");
        if matches!(
            state,
            pb::CopyState::Done | pb::CopyState::Failed | pb::CopyState::Cancelled
        ) {
            return c;
        }
        assert!(
            start.elapsed() < Duration::from_secs(20),
            "copy never finished: {c:?}"
        );
        std::thread::sleep(Duration::from_millis(5));
    }
}

fn stick_role(e: &Exporter) -> pb::StickRole {
    let s = e.status();
    pb::StickRole::try_from(s.sticks.first().expect("a stick").role).expect("role")
}

#[test]
fn recordings_are_copied_complete_and_the_drive_is_left_as_it_was() {
    let b = bench("copy");
    let front = record(
        &b.video,
        "front/b00003-s000001-20261112T045215Z.mkv",
        3 * MB + 17,
    );
    let clip = record(&b.video, "protected/rear/b00002-s000004.mkv", MB);
    record(&b.video, "front/b00003-s000002-20261112T045315Z.mkv", 10);
    b.exporter.poll();
    assert_eq!(stick_role(&b.exporter), pb::StickRole::Export);
    assert!(b.fs.mounts().is_empty(), "checked, then unmounted");

    let list = b.exporter.list();
    assert_eq!(list.recordings.len(), 3);
    assert_eq!(
        list.recordings[0].file_name, "b00002-s000004.mkv",
        "oldest run first"
    );
    assert!(list.recordings[0].protected);
    assert_eq!(list.recordings[1].wall_time, 1_794_459_135);

    let started = b.exporter.start(
        "sdz1",
        &[
            r("front", "b00003-s000001-20261112T045215Z.mkv", false),
            r("rear", "b00002-s000004.mkv", true),
        ],
        "test",
    );
    assert!(started.started, "{}", started.detail);
    let c = wait_done(&b.exporter);
    assert_eq!(c.state, pb::CopyState::Done as i32, "{}", c.detail);
    assert!(c.safe_to_unplug);
    assert_eq!((c.files_total, c.files_done, c.files_skipped), (2, 2, 0));
    assert_eq!(c.bytes_done, c.bytes_total);
    assert_eq!(c.bytes_total, (4 * MB + 17) as u64);
    assert!(c.detail.contains("Copied 2 recordings"), "{}", c.detail);
    assert!(b.fs.mounts().is_empty(), "unmounted when done");

    let out = b.stick.join(FOLDER);
    assert_eq!(
        fs::read(out.join("front/b00003-s000001-20261112T045215Z.mkv")).expect("front"),
        front
    );
    assert_eq!(
        fs::read(out.join("protected/rear/b00002-s000004.mkv")).expect("clip"),
        clip
    );
    assert!(
        !out.join("front/b00003-s000002-20261112T045315Z.mkv")
            .exists(),
        "only what was chosen"
    );
    // Copy only: every recording is still on the drive.
    assert_eq!(b.exporter.list().recordings.len(), 3);
    assert_eq!(
        fs::read(b.video.join("front/b00003-s000001-20261112T045215Z.mkv")).expect("src"),
        front
    );
    let leftovers: Vec<_> = walk(&out)
        .into_iter()
        .filter(|p| p.to_string_lossy().ends_with(".part"))
        .collect();
    assert!(leftovers.is_empty(), "{leftovers:?}");

    // Again: everything is already there.
    let again = b
        .exporter
        .start("sdz1", &[r("rear", "b00002-s000004.mkv", true)], "test");
    assert!(again.started && again.id > started.id);
    let c = wait_done(&b.exporter);
    assert_eq!((c.state, c.files_skipped), (pb::CopyState::Done as i32, 1));
    assert!(c.detail.contains("already there"), "{}", c.detail);
}

fn walk(dir: &Path) -> Vec<PathBuf> {
    let mut out = Vec::new();
    for e in fs::read_dir(dir).into_iter().flatten().flatten() {
        if e.path().is_dir() {
            out.extend(walk(&e.path()));
        } else {
            out.push(e.path());
        }
    }
    out
}

#[test]
fn a_full_stick_is_refused_before_anything_is_written() {
    let b = bench("full");
    record(&b.video, "front/b00001-s000000.mkv", 2 * MB);
    b.fs.set_free(MB as u64);
    b.exporter.poll();
    assert!(
        b.exporter
            .start("sdz1", &[r("front", "b00001-s000000.mkv", false)], "test")
            .started
    );
    let c = wait_done(&b.exporter);
    assert_eq!(c.state, pb::CopyState::Failed as i32);
    assert!(c.detail.contains("Not enough room"), "{}", c.detail);
    assert!(c.safe_to_unplug && b.fs.mounts().is_empty());
    assert!(
        walk(&b.stick).is_empty(),
        "nothing written: {:?}",
        walk(&b.stick)
    );
}

#[test]
fn a_read_only_stick_says_so() {
    let b = bench("ro");
    record(&b.video, "front/b00001-s000000.mkv", 100);
    b.fs.set_read_only(true);
    b.exporter.poll();
    assert!(
        b.exporter
            .start("sdz1", &[r("front", "b00001-s000000.mkv", false)], "test")
            .started
    );
    let c = wait_done(&b.exporter);
    assert_eq!(c.state, pb::CopyState::Failed as i32);
    assert!(c.detail.contains("read-only"), "{}", c.detail);
    assert!(c.safe_to_unplug && b.fs.mounts().is_empty());
}

#[test]
fn a_stick_pulled_mid_copy_keeps_the_finished_files_and_says_so() {
    let b = bench("pulled");
    record(&b.video, "front/b00001-s000000.mkv", 3 * MB);
    record(&b.video, "front/b00001-s000001.mkv", 3 * MB);
    b.exporter.poll();
    // One check at mount... then one per MiB: gone during the second file.
    b.fs.pull_after("sdz1", 5);
    let refs = [
        r("front", "b00001-s000000.mkv", false),
        r("front", "b00001-s000001.mkv", false),
    ];
    assert!(b.exporter.start("sdz1", &refs, "test").started);
    let c = wait_done(&b.exporter);
    assert_eq!(c.state, pb::CopyState::Failed as i32);
    assert!(c.detail.contains("removed during the copy"), "{}", c.detail);
    assert!(c.detail.contains("1 of 2"), "{}", c.detail);
    assert!(c.safe_to_unplug, "it's out already");
    let out = b.stick.join(FOLDER).join("front");
    assert_eq!(
        fs::metadata(out.join("b00001-s000000.mkv"))
            .expect("first")
            .len(),
        3 * MB as u64
    );
    assert!(
        !out.join("b00001-s000001.mkv").exists(),
        "never a half file under its real name"
    );

    // Gone from the list at the next look, and a copy to it is refused.
    b.exporter.poll();
    assert!(b.exporter.status().sticks.is_empty());
    let refused = b.exporter.start("sdz1", &refs, "test");
    assert!(
        !refused.started && refused.detail.contains("isn't plugged in"),
        "{}",
        refused.detail
    );
}

#[test]
fn a_map_stick_is_left_to_the_map_import() {
    let b = bench("map");
    fs::create_dir_all(b.stick.join("f250")).expect("mkdir");
    fs::write(b.stick.join("f250/map.pmtiles"), b"PMTiles").expect("map");
    record(&b.video, "front/b00001-s000000.mkv", 100);
    b.exporter.poll();
    assert_eq!(stick_role(&b.exporter), pb::StickRole::Map);
    let refused = b
        .exporter
        .start("sdz1", &[r("front", "b00001-s000000.mkv", false)], "test");
    assert!(
        !refused.started && refused.detail.contains("map stick"),
        "{}",
        refused.detail
    );
    assert!(b.fs.mounts().is_empty());
}

#[test]
fn copies_wait_for_a_map_import_and_for_each_other() {
    let b = bench("busy");
    record(&b.video, "front/b00001-s000000.mkv", 100);
    b.exporter.poll();
    let refused = b
        .exporter
        .start("sdz9", &[r("front", "b00001-s000000.mkv", false)], "test");
    assert!(!refused.started);
    let unknown = b
        .exporter
        .start("sdz1", &[r("front", "b00009-s000000.mkv", false)], "test");
    assert!(
        !unknown.started && unknown.detail.contains("isn't on the data drive"),
        "{}",
        unknown.detail
    );
    assert!(!b.exporter.cancel(), "nothing to cancel");
}

#[test]
fn the_newest_recording_still_being_written_is_marked_and_refused() {
    let b = bench("writing");
    record(&b.video, "front/b00001-s000000.mkv", 100);
    fs::write(b.video.join("front/b00001-s000001.mkv"), b"live").expect("write");
    let list = b.exporter.list();
    let writing: Vec<_> = list.recordings.iter().map(|r| r.being_written).collect();
    assert_eq!(writing, [false, true]);
    b.exporter.poll();
    let refused = b
        .exporter
        .start("sdz1", &[r("front", "b00001-s000001.mkv", false)], "test");
    assert!(
        !refused.started && refused.detail.contains("still being recorded"),
        "{}",
        refused.detail
    );
}

#[test]
fn no_drive_means_no_recordings_and_says_why() {
    let root = temp("nodrive");
    let e = Exporter::new(
        Config {
            video_root: root.join("video"),
            drive: Some(root.clone()), // a plain directory, not a mount point
            map_lock: root.join("lock"),
            writing_window: Duration::from_secs(15),
        },
        Arc::new(DirFs::new()),
        Box::new(Vec::new),
    );
    let list = e.list();
    assert!(
        !list.drive_mounted && list.problem.contains("isn't mounted"),
        "{list:?}"
    );
}

#[test]
fn a_cancelled_copy_stops_between_chunks_and_leaves_no_partial_file() {
    let root = temp("cancel");
    let (video, stick) = (root.join("video"), root.join("stick"));
    record(&video, "front/b00001-s000000.mkv", MB);
    record(&video, "front/b00001-s000001.mkv", 3 * MB);
    let scan = recording::store::Store::existing(&video)
        .scan()
        .expect("scan");
    let items = copy::resolve(
        &scan.segments,
        &Default::default(),
        &[
            r("front", "b00001-s000000.mkv", false),
            r("front", "b00001-s000001.mkv", false),
        ],
    )
    .expect("items");
    let plan = copy::plan(items, &stick, u64::MAX, 0).expect("plan");
    let cancel = AtomicBool::new(false);
    let (outcome, p) = copy::run(&plan, &video, &stick, &cancel, &|| true, &mut |p| {
        // Cancel once the second file has started.
        if p.files_done == 1 {
            cancel.store(true, Ordering::SeqCst);
        }
    });
    assert_eq!(outcome, Outcome::Cancelled);
    assert_eq!((p.files_done, p.bytes_done), (1, MB as u64));
    assert_eq!(walk(&stick).len(), 1, "{:?}", walk(&stick));
}

#[test]
fn fat_sticks_refuse_files_over_4_gib_and_room_is_counted_after_skips() {
    let root = temp("plan");
    let (video, stick) = (root.join("video"), root.join("stick"));
    record(&video, "rear/b00001-s000000.mkv", 1000);
    record(&video, "rear/b00001-s000001.mkv", 2000);
    let scan = recording::store::Store::existing(&video)
        .scan()
        .expect("scan");
    let both = [
        r("rear", "b00001-s000000.mkv", false),
        r("rear", "b00001-s000001.mkv", false),
    ];
    let items = copy::resolve(&scan.segments, &Default::default(), &both).expect("items");
    assert_eq!(
        copy::plan(items.clone(), &stick, u64::MAX, 1500),
        Err(Failure::TooBig {
            file: "b00001-s000001.mkv".into(),
            max: 1500
        })
    );
    // The bigger one already there: only the smaller needs room.
    record(&stick.join(FOLDER), "rear/b00001-s000001.mkv", 2000);
    let plan = copy::plan(items.clone(), &stick, 1000 + copy::SPARE_BYTES, 1500).expect("fits");
    assert_eq!(
        (plan.already.clone(), plan.to_copy),
        (vec![false, true], 1000)
    );
    assert!(matches!(
        copy::plan(items, &stick, 999, 0),
        Err(Failure::Full { .. })
    ));
}

#[cfg(unix)]
#[test]
fn sticks_are_found_on_usb_only_with_their_filesystems() {
    use std::os::unix::fs::symlink;
    let root = temp("sysfs");
    let devices = root.join("devices");
    let usb_disk =
        devices.join("platform/xhci-hcd.1/usb3/3-1/3-1:1.0/host0/target0:0:0/0:0:0:0/block/sda");
    let usb_part = usb_disk.join("sda1");
    let raw =
        devices.join("platform/xhci-hcd.1/usb3/3-2/3-2:1.0/host1/target1:0:0/1:0:0:0/block/sdb");
    let nvme = devices.join("platform/pcie/nvme/nvme0/nvme0n1");
    let nvme_part = nvme.join("nvme0n1p1");
    for (dir, dev, size, ro) in [
        (&usb_disk, "8:0", "62521344", "0"),
        (&usb_part, "8:1", "62519296", "1"),
        (&raw, "8:16", "2048", "0"),
        (&nvme, "259:0", "1000215216", "0"),
        (&nvme_part, "259:1", "1000212480", "0"),
    ] {
        fs::create_dir_all(dir).expect("mkdir");
        fs::write(dir.join("dev"), format!("{dev}\n")).expect("dev");
        fs::write(dir.join("size"), size).expect("size");
        fs::write(dir.join("ro"), ro).expect("ro");
    }
    fs::write(usb_part.join("partition"), "1").expect("partition");
    fs::write(nvme_part.join("partition"), "1").expect("partition");
    let class = root.join("class/block");
    fs::create_dir_all(&class).expect("class");
    for (name, target) in [
        ("sda", &usb_disk),
        ("sda1", &usb_part),
        ("sdb", &raw),
        ("nvme0n1", &nvme),
        ("nvme0n1p1", &nvme_part),
    ] {
        symlink(target, class.join(name)).expect("symlink");
    }
    let udev = root.join("udev");
    fs::create_dir_all(&udev).expect("udev");
    fs::write(
        udev.join("b8:0"),
        "E:ID_BUS=usb\nE:ID_VENDOR=SanDisk\nE:ID_MODEL=Ultra_Fit\nE:ID_PART_TABLE_TYPE=dos\n",
    )
    .expect("udev");
    fs::write(
        udev.join("b8:1"),
        "E:ID_FS_TYPE=exfat\nE:ID_FS_USAGE=filesystem\nE:ID_FS_LABEL=TRUCK\n",
    )
    .expect("udev");
    fs::write(udev.join("b8:16"), "E:ID_BUS=usb\nE:ID_MODEL=Blank\n").expect("udev");
    fs::write(
        udev.join("b259:1"),
        "E:ID_FS_TYPE=ext4\nE:ID_FS_USAGE=filesystem\n",
    )
    .expect("udev");

    let found = sticks::scan(&sticks::Paths {
        sys_block: class,
        udev_data: udev,
    });
    assert_eq!(
        found,
        [
            Found {
                device: "sda1".into(),
                filesystem: "exfat".into(),
                label: "TRUCK".into(),
                model: "SanDisk Ultra Fit".into(),
                size_bytes: 62_519_296 * 512,
                read_only: true,
            },
            Found {
                device: "sdb".into(),
                filesystem: String::new(),
                label: String::new(),
                model: "Blank".into(),
                size_bytes: 2048 * 512,
                read_only: false,
            },
        ]
    );
}

#[test]
fn an_unformatted_or_foreign_stick_is_unusable_with_a_reason() {
    let root = temp("unusable");
    for (fs_type, want) in [("", "No filesystem"), ("ntfs", "(ntfs) isn't supported")] {
        let e = Exporter::new(
            Config {
                video_root: root.clone(),
                drive: None,
                map_lock: root.join("lock"),
                writing_window: Duration::from_secs(15),
            },
            Arc::new(DirFs::new()),
            Box::new(move || {
                vec![Found {
                    device: "sdy".into(),
                    filesystem: fs_type.into(),
                    label: String::new(),
                    model: String::new(),
                    size_bytes: 1,
                    read_only: false,
                }]
            }),
        );
        e.poll();
        let s = &e.status().sticks[0];
        assert_eq!(s.role, pb::StickRole::Unusable as i32);
        assert!(s.detail.contains(want), "{}", s.detail);
    }
}
