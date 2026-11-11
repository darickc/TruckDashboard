//! The `can-monitor` binary on synthetic captures written to disk: a bounded
//! capture's parts read from its folder, CSV, and the two-capture diff.

use std::path::{Path, PathBuf};
use std::process::Command;

struct Dir(PathBuf);

impl Drop for Dir {
    fn drop(&mut self) {
        let _ = std::fs::remove_dir_all(&self.0);
    }
}

fn dir(name: &str) -> Dir {
    let d = std::env::temp_dir().join(format!("canmon-{name}-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&d);
    std::fs::create_dir_all(&d).expect("dir");
    Dir(d)
}

/// `secs` of 201 at 100 Hz and 440 at 50 Hz from `t0`, 440's byte 0 = `b0`.
fn capture(t0: f64, secs: f64, b0: u8) -> String {
    let mut lines = Vec::new();
    for i in 0..(secs * 100.0).round() as u32 {
        let t = f64::from(i) / 100.0;
        lines.push(format!("({:.6}) can0 201#00{:02X}0000", t0 + t, i % 200));
        if i % 2 == 0 {
            lines.push(format!(
                "({:.6}) can0 440#{b0:02X}0000000000000{:X}",
                t0 + t + 0.001,
                i % 16
            ));
        }
    }
    lines.join("\n") + "\n"
}

fn run(args: &[&str]) -> (bool, String, String) {
    let o = Command::new(env!("CARGO_BIN_EXE_can-monitor"))
        .args(args)
        .output()
        .expect("runs");
    (
        o.status.success(),
        String::from_utf8_lossy(&o.stdout).into_owned(),
        String::from_utf8_lossy(&o.stderr).into_owned(),
    )
}

fn p(path: &Path) -> &str {
    path.to_str().expect("utf-8 path")
}

#[test]
fn a_folder_of_parts_reads_as_one_capture() {
    let d = dir("parts");
    let text = capture(1000.0, 4.0, 0x01);
    let lines: Vec<&str> = text.lines().collect();
    let (one, two) = lines.split_at(lines.len() / 2);
    std::fs::write(d.0.join("candump-part-00000.log"), one.join("\n") + "\n").expect("w");
    std::fs::write(d.0.join("candump-part-00001.log"), two.join("\n") + "\n").expect("w");
    std::fs::write(d.0.join("session.txt"), "not a log\n").expect("w");
    let (ok, out, err) = run(&["census", p(&d.0)]);
    assert!(ok, "{err}");
    assert!(err.contains("2 files read as one capture"), "{err}");
    assert!(out.contains(&format!("{} frames", lines.len())), "{out}");
    assert!(out.contains("no silence"), "{out}");

    let (ok, _, err) = run(&["census", p(&d.0.join("missing"))]);
    assert!(!ok);
    assert!(err.contains("missing"), "{err}");
    let empty = dir("empty");
    let (ok, _, err) = run(&["census", p(&empty.0)]);
    assert!(!ok && err.contains("no candump*.log"), "{err}");
}

#[test]
fn csv_of_frames() {
    let d = dir("csv");
    let f = d.0.join("candump-1.log");
    std::fs::write(&f, capture(1000.0, 0.1, 0x01)).expect("w");
    let (ok, out, err) = run(&["csv", p(&f), "--ids", "440"]);
    assert!(ok, "{err}");
    let rows: Vec<&str> = out.lines().collect();
    assert!(rows[0].starts_with("t_s,epoch_s,id,"));
    assert_eq!(rows.len(), 1 + 5, "{out}");
    assert!(rows[1].contains(",440,0,0,8,01"), "{}", rows[1]);
    assert!(err.contains("5 rows"), "{err}");
}

#[test]
fn diff_finds_the_flipped_bit() {
    let d = dir("diff");
    let a = d.0.join("a.log");
    let b = d.0.join("b.log");
    std::fs::write(&a, capture(1000.0, 5.0, 0x01)).expect("w");
    std::fs::write(&b, capture(2000.0, 5.0, 0x11)).expect("w");
    let (ok, out, err) = run(&["diff", p(&a), p(&b)]);
    assert!(ok, "{err}");
    assert!(out.contains("Bits that flip (1):"), "{out}");
    assert!(
        out.contains("440 byte 0 bit 4  set in   0% of A, 100% of B  (mask 10)"),
        "{out}"
    );
    assert!(out.contains("no value in common"), "{out}");
    assert!(
        out.contains("1 IDs in both with nothing to report"),
        "{out}"
    );
    assert!(out.contains("candidate only"), "{out}");
    let (ok, _, err) = run(&["diff", p(&a), p(&b), "--bit-threshold", "2"]);
    assert!(!ok && err.contains("0 to 1"), "{err}");
}
