//! The gateway binary under a stand-in for systemd: NOTIFY_SOCKET and
//! WATCHDOG_USEC set, as `Type=notify` + `WatchdogSec=` would (f250-gateway.service).
//! [SIM]: simulated transport, a local datagram socket, no systemd.

#![allow(clippy::unwrap_used)]

use std::os::unix::net::UnixDatagram;
use std::path::PathBuf;
use std::process::{Child, Command, Stdio};
use std::time::{Duration, Instant};

struct Killed(Child);
impl Drop for Killed {
    fn drop(&mut self) {
        let _ = self.0.kill();
        let _ = self.0.wait();
    }
}

fn recv_until(rx: &UnixDatagram, within: Duration, want: &str) -> Vec<String> {
    let deadline = Instant::now() + within;
    let mut got = Vec::new();
    let mut buf = [0u8; 1024];
    while Instant::now() < deadline {
        if let Ok(n) = rx.recv(&mut buf) {
            let msg = String::from_utf8_lossy(&buf[..n]).into_owned();
            let done = msg.lines().any(|l| l == want);
            got.push(msg);
            if done {
                break;
            }
        }
    }
    got
}

#[test]
fn ready_after_bind_then_keepalives() {
    let dir = std::env::temp_dir().join(format!("gw-notify-{}", std::process::id()));
    std::fs::create_dir_all(&dir).unwrap();
    let notify = dir.join("n.sock");
    let vehicle = dir.join("v.sock");
    let _ = std::fs::remove_file(&notify);
    let rx = UnixDatagram::bind(&notify).unwrap();
    rx.set_read_timeout(Some(Duration::from_millis(100)))
        .unwrap();

    let root = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../..");
    let child = Command::new(env!("CARGO_BIN_EXE_vehicle-gateway"))
        .current_dir(&root)
        .args(["--listen", &format!("unix:{}", vehicle.display())])
        .env("NOTIFY_SOCKET", &notify)
        .env("WATCHDOG_USEC", "2000000") // keep-alive check every second
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .spawn()
        .unwrap();
    let _child = Killed(child);

    let got = recv_until(&rx, Duration::from_secs(20), "READY=1");
    let ready = got.last().expect("no notification at all");
    assert!(ready.contains("READY=1"), "{got:?}");
    assert!(
        ready.contains(&format!("STATUS=listening on unix:{}", vehicle.display())),
        "{ready}"
    );
    assert!(vehicle.exists(), "READY before the socket was bound");

    // The simulated control loop runs, so keep-alives follow.
    let got = recv_until(&rx, Duration::from_secs(5), "WATCHDOG=1");
    assert!(got.iter().any(|m| m == "WATCHDOG=1"), "{got:?}");
    let _ = std::fs::remove_dir_all(&dir);
}
