//! The real power-manager binary with the 5-way switch on a FIFO (evdev
//! events written by the test) and its API on a unix socket: short and long
//! presses, learning, saving and resetting the directions (ADR-0051). No
//! camera-manager or audio-manager runs, so presses say they weren't sent.
//! `[SIM]`.

use std::io::Write;
use std::path::{Path, PathBuf};
use std::process::{Child, Command, Stdio};
use std::time::{Duration, Instant};

use f250_proto::power::v1 as pb;
use hyper_util::rt::TokioIo;
use pb::switch_service_client::SwitchServiceClient;
use pb::watch_switch_response::Event;
use tonic::transport::{Channel, Endpoint, Uri};

struct Run {
    child: Child,
    root: PathBuf,
}

impl Drop for Run {
    fn drop(&mut self) {
        let _ = self.child.kill();
        let _ = self.child.wait();
        let _ = std::fs::remove_dir_all(&self.root);
    }
}

fn start(name: &str) -> Run {
    // Short: unix socket paths are limited to about 100 bytes.
    let root = std::env::temp_dir().join(format!("pm-{name}-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&root);
    std::fs::create_dir_all(root.join("sys")).expect("fake sysfs");
    let fifo = root.join("switch");
    let made = Command::new("mkfifo").arg(&fifo).status().expect("mkfifo");
    assert!(made.success());
    let sock = root.join("p.sock");
    let child = Command::new(env!("CARGO_BIN_EXE_power-manager"))
        .arg("--sysfs")
        .arg(root.join("sys"))
        .arg("--backlight=none")
        .arg("--display-listen")
        .arg(format!("unix:{}", sock.display()))
        .arg("--switch-device")
        .arg(&fifo)
        .arg("--switch-state")
        .arg(root.join("mapping"))
        .arg("--switch-debounce-ms=10")
        .arg("--switch-long-press-ms=300")
        .arg("--dry-run")
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .spawn()
        .expect("power-manager starts");
    Run { child, root }
}

async fn connect(root: &Path) -> SwitchServiceClient<Channel> {
    let sock = root.join("p.sock");
    let deadline = Instant::now() + Duration::from_secs(10);
    while !sock.exists() {
        assert!(Instant::now() < deadline, "no socket at {}", sock.display());
        tokio::time::sleep(Duration::from_millis(20)).await;
    }
    let channel = Endpoint::from_static("http://localhost")
        .connect_with_connector(tower::service_fn(move |_: Uri| {
            let sock = sock.clone();
            async move {
                tokio::net::UnixStream::connect(sock)
                    .await
                    .map(TokioIo::new)
            }
        }))
        .await
        .expect("connects");
    SwitchServiceClient::new(channel)
}

/// Writes evdev key events into the FIFO, as the kernel would.
struct Switch(std::fs::File);

impl Switch {
    fn open(root: &Path) -> Switch {
        // Opening blocks until power-manager's reader opens the other end.
        Switch(
            std::fs::OpenOptions::new()
                .write(true)
                .open(root.join("switch"))
                .expect("fifo"),
        )
    }

    fn key(&mut self, code: u16, down: bool) {
        let mut raw = [0u8; f250_evdev::EVENT_SIZE];
        raw[16..18].copy_from_slice(&f250_evdev::EV_KEY.to_ne_bytes());
        raw[18..20].copy_from_slice(&code.to_ne_bytes());
        raw[20..24].copy_from_slice(&i32::from(down).to_ne_bytes());
        self.0.write_all(&raw).expect("write");
        self.0.flush().expect("flush");
    }

    async fn press(&mut self, code: u16, hold: Duration) {
        self.key(code, true);
        tokio::time::sleep(hold).await;
        self.key(code, false);
    }
}

type Events = tonic::Streaming<pb::WatchSwitchResponse>;

async fn next_event(s: &mut Events) -> Event {
    tokio::time::timeout(Duration::from_secs(5), s.message())
        .await
        .expect("an event within 5 s")
        .expect("stream ok")
        .expect("a message")
        .event
        .expect("event set")
}

async fn until_state(s: &mut Events, f: impl Fn(&pb::SwitchState) -> bool) -> pb::SwitchState {
    loop {
        if let Event::State(st) = next_event(s).await
            && f(&st)
        {
            return st;
        }
    }
}

/// The last report of the next press: the first event says what it will do,
/// a second one (same seq) what became of it.
async fn until_press(s: &mut Events, done: impl Fn(&pb::Press) -> bool) -> pb::Press {
    loop {
        if let Event::Press(p) = next_event(s).await
            && done(&p)
        {
            return p;
        }
    }
}

fn role_of(st: &pb::SwitchState, wire: pb::Wire) -> pb::Role {
    st.wires
        .iter()
        .find(|w| w.wire() == wire)
        .map_or(pb::Role::Unspecified, |w| w.role())
}

const F13: u16 = 183;
const F15: u16 = 185;
const F16: u16 = 186;

#[tokio::test]
async fn presses_learning_and_saving_the_directions() {
    let run = start("switch");
    let mut client = connect(&run.root).await;
    let mut s = client
        .watch_switch(pb::WatchSwitchRequest {})
        .await
        .expect("watch")
        .into_inner();
    let mut sw = Switch::open(&run.root);
    let st = until_state(&mut s, |st| st.wires.iter().all(|w| w.present)).await;
    assert!(st.default_mapping && !st.learning);
    assert_eq!((st.long_press_ms, st.learning_timeout_s), (300, 60));
    assert_eq!(role_of(&st, pb::Wire::F16), pb::Role::Up);
    assert_eq!(st.wires[0].pin, "BCM12, pin 32");

    // Short: media, not sent here (no audio-manager).
    sw.press(F16, Duration::from_millis(50)).await;
    let p = until_press(&mut s, |p| p.result.contains("not sent")).await;
    assert_eq!(
        (p.wire(), p.role(), p.kind()),
        (pb::Wire::F16, pb::Role::Up, pb::PressKind::Short)
    );
    assert_eq!(p.result, "volume up: not sent: no audio-manager");

    // Long: a camera, said as soon as it is held long enough.
    sw.key(F15, true);
    let p = until_press(&mut s, |p| p.result.contains("not sent")).await;
    assert_eq!((p.role(), p.kind()), (pb::Role::Down, pb::PressKind::Long));
    assert_eq!(p.result, "rear camera: not sent: no camera-manager");
    sw.key(F15, false);

    // Learning: reported, not sent.
    let r = client
        .set_learning(pb::SetLearningRequest {
            on: true,
            source: "test".into(),
        })
        .await
        .expect("learning")
        .into_inner();
    assert!(r.state.expect("state").learning);
    sw.press(F13, Duration::from_millis(50)).await;
    let p = until_press(&mut s, |_| true).await;
    assert_eq!(
        (p.wire(), p.result.as_str()),
        (pb::Wire::F13, "learning: not sent")
    );

    // A mapping with a direction twice is refused.
    let wire_roles = |roles: [pb::Role; 5]| -> Vec<pb::WireRole> {
        [
            pb::Wire::F13,
            pb::Wire::F14,
            pb::Wire::F15,
            pb::Wire::F16,
            pb::Wire::F17,
        ]
        .into_iter()
        .zip(roles)
        .map(|(w, r)| pb::WireRole {
            wire: w as i32,
            role: r as i32,
        })
        .collect()
    };
    use pb::Role::{Down, Left, Press, Right, Up};
    let bad = client
        .set_mapping(pb::SetMappingRequest {
            wires: wire_roles([Up, Up, Left, Right, Press]),
            source: "test".into(),
        })
        .await
        .expect("set")
        .into_inner();
    assert!(!bad.saved && bad.detail.contains("up is on 2"), "{bad:?}");
    assert!(bad.state.expect("state").learning, "still learning");

    // Mounted turned a quarter: saved, learning off, and F13 is now Up.
    let ok = client
        .set_mapping(pb::SetMappingRequest {
            wires: wire_roles([Up, Down, Left, Right, Press]),
            source: "test".into(),
        })
        .await
        .expect("set")
        .into_inner();
    assert!(ok.saved, "{ok:?}");
    let st = ok.state.expect("state");
    assert!(!st.learning && !st.default_mapping);
    assert_eq!(role_of(&st, pb::Wire::F13), pb::Role::Up);
    let file = std::fs::read_to_string(run.root.join("mapping")).expect("saved");
    assert!(
        file.contains("F13 up\n") && file.contains("F16 right\n"),
        "{file}"
    );
    sw.press(F13, Duration::from_millis(50)).await;
    let p = until_press(&mut s, |p| p.result.contains("not sent")).await;
    assert_eq!(
        (p.role(), p.result.as_str()),
        (pb::Role::Up, "volume up: not sent: no audio-manager")
    );

    // Reset: the default again, saved.
    let r = client
        .reset_mapping(pb::ResetMappingRequest {
            source: "test".into(),
        })
        .await
        .expect("reset")
        .into_inner();
    assert!(r.saved && r.state.expect("state").default_mapping);
    let file = std::fs::read_to_string(run.root.join("mapping")).expect("saved");
    assert!(file.contains("F16 up\n"), "{file}");
}
