//! The recorder binary under a stand-in for systemd (f250-recorder.service:
//! `Type=notify`, `WatchdogSec=`), with no gateway running. It must report
//! READY, say it isn't recording, and keep sending keep-alives while its
//! reconnect loop runs. [SIM]: a local datagram socket, no systemd.

#![allow(clippy::unwrap_used)]

use std::os::unix::net::UnixDatagram;
use std::process::{Child, Command, Stdio};
use std::time::{Duration, Instant};

struct Killed(Child);
impl Drop for Killed {
    fn drop(&mut self) {
        let _ = self.0.kill();
        let _ = self.0.wait();
    }
}

#[test]
fn ready_status_and_keepalives_without_a_gateway() {
    let dir = std::env::temp_dir().join(format!("rec-notify-{}", std::process::id()));
    std::fs::create_dir_all(&dir).unwrap();
    let notify = dir.join("n.sock");
    let _ = std::fs::remove_file(&notify);
    let rx = UnixDatagram::bind(&notify).unwrap();
    rx.set_read_timeout(Some(Duration::from_millis(100)))
        .unwrap();

    let child = Command::new(env!("CARGO_BIN_EXE_recorder"))
        .args([
            "run",
            "--gateway",
            &format!("unix:{}", dir.join("absent.sock").display()),
            "--db",
            &dir.join("t.sqlite").display().to_string(),
        ])
        .env("NOTIFY_SOCKET", &notify)
        // Keep-alive check every 3 s; the reconnect loop beats every 2 s.
        .env("WATCHDOG_USEC", "6000000")
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .spawn()
        .unwrap();
    let _child = Killed(child);

    let deadline = Instant::now() + Duration::from_secs(15);
    let mut got: Vec<String> = Vec::new();
    let mut buf = [0u8; 1024];
    while Instant::now() < deadline && !got.iter().any(|m| m == "WATCHDOG=1") {
        if let Ok(n) = rx.recv(&mut buf) {
            got.push(String::from_utf8_lossy(&buf[..n]).into_owned());
        }
    }
    assert!(got[0].starts_with("READY=1\nSTATUS=session "), "{got:?}");
    assert!(
        got.iter()
            .any(|m| m.starts_with("STATUS=") && m.contains("not recording")),
        "{got:?}"
    );
    assert!(got.iter().any(|m| m == "WATCHDOG=1"), "{got:?}");
    let _ = std::fs::remove_dir_all(&dir);
}
