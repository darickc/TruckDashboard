//! The systemd notify protocol for the head unit's daemons, and a watchdog
//! that only sends keep-alives while the daemon is making progress.
//!
//! A `Type=notify` unit with `WatchdogSec=` gets two environment variables
//! from systemd (`sd_notify(3)`, `systemd.service(5)`):
//!
//! - `NOTIFY_SOCKET`: a datagram socket, a path (`/run/systemd/notify`) or an
//!   abstract name (`@…`, Linux only). Messages are `KEY=VALUE` lines.
//! - `WATCHDOG_USEC` (and `WATCHDOG_PID`): send `WATCHDOG=1` at least this
//!   often, or systemd kills and restarts the service. Keep-alives go out at
//!   half the interval, as `sd_watchdog_enabled(3)` recommends.
//!
//! Outside systemd (a dev Mac, `make pi-run`) neither variable is set and
//! every call is a no-op, so the daemons run unchanged.
//!
//! A timer alone would keep a hung daemon alive. [`run_watchdog`] instead
//! withholds the keep-alive unless the daemon's own loop has called
//! [`Heartbeat::beat`] since the last one, so a stuck control loop gets
//! restarted.
//!
//! Status: the protocol is tested against a local socket `[SIM]`.

use std::ffi::OsString;
use std::io;
use std::os::unix::net::UnixDatagram;
use std::path::PathBuf;
use std::sync::Arc;
use std::sync::atomic::{AtomicU64, Ordering};
use std::time::Duration;

#[derive(Debug, Clone, PartialEq, Eq)]
enum Target {
    Path(PathBuf),
    /// Abstract socket name, without the leading `@`.
    #[cfg(target_os = "linux")]
    Abstract(Vec<u8>),
}

/// A connection to systemd's notify socket, or a no-op when not run by systemd.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Notifier {
    target: Option<Target>,
    watchdog: Option<Duration>,
    problem: Option<String>,
}

impl Notifier {
    /// From `NOTIFY_SOCKET`, `WATCHDOG_USEC` and `WATCHDOG_PID`.
    pub fn from_env() -> Self {
        let var = |k: &str| std::env::var(k).ok();
        Self::from_vars(
            std::env::var_os("NOTIFY_SOCKET"),
            var("WATCHDOG_USEC").as_deref(),
            var("WATCHDOG_PID").as_deref(),
            std::process::id(),
        )
    }

    /// A notifier that does nothing (tests, or a daemon run by hand).
    pub fn disabled() -> Self {
        Self {
            target: None,
            watchdog: None,
            problem: None,
        }
    }

    /// The parsing behind [`Notifier::from_env`], with the values passed in.
    pub fn from_vars(
        notify_socket: Option<OsString>,
        watchdog_usec: Option<&str>,
        watchdog_pid: Option<&str>,
        own_pid: u32,
    ) -> Self {
        let mut n = Self::disabled();
        let Some(socket) = notify_socket.filter(|s| !s.is_empty()) else {
            return n;
        };
        match parse_target(socket) {
            Ok(t) => n.target = Some(t),
            Err(problem) => {
                n.problem = Some(problem);
                return n;
            }
        }
        let for_us = match watchdog_pid {
            None => true,
            Some(pid) => pid.trim().parse::<u32>().ok() == Some(own_pid),
        };
        match watchdog_usec.map(|u| u.trim().parse::<u64>()) {
            None => {}
            Some(Ok(0)) => {}
            Some(Ok(usec)) if for_us => n.watchdog = Some(Duration::from_micros(usec)),
            Some(Ok(_)) => {} // the watchdog is another process's
            Some(Err(_)) => {
                n.problem = Some(format!(
                    "WATCHDOG_USEC={:?} is not a number; the watchdog is off",
                    watchdog_usec.unwrap_or_default()
                ));
            }
        }
        n
    }

    /// True when run by systemd with a notify socket.
    pub fn enabled(&self) -> bool {
        self.target.is_some()
    }

    /// Why notifications are off or incomplete, for the daemon's log.
    pub fn problem(&self) -> Option<&str> {
        self.problem.as_deref()
    }

    /// The unit's `WatchdogSec`, if it has one.
    pub fn watchdog_timeout(&self) -> Option<Duration> {
        self.watchdog
    }

    /// How often to send keep-alives: half the watchdog timeout.
    pub fn watchdog_period(&self) -> Option<Duration> {
        self.watchdog.map(|w| (w / 2).max(Duration::from_millis(1)))
    }

    /// `READY=1`, with a one-line status for `systemctl status`.
    pub fn ready(&self, status: &str) -> io::Result<()> {
        self.send(&format!("READY=1\nSTATUS={}", one_line(status)))
    }

    pub fn status(&self, status: &str) -> io::Result<()> {
        self.send(&format!("STATUS={}", one_line(status)))
    }

    pub fn stopping(&self) -> io::Result<()> {
        self.send("STOPPING=1")
    }

    /// `WATCHDOG=1`. Prefer [`run_watchdog`], which checks for progress first.
    pub fn watchdog(&self) -> io::Result<()> {
        if self.watchdog.is_none() {
            return Ok(());
        }
        self.send("WATCHDOG=1")
    }

    /// Sends one datagram. Ok and nothing sent when not run by systemd.
    pub fn send(&self, message: &str) -> io::Result<()> {
        let Some(target) = &self.target else {
            return Ok(());
        };
        let socket = UnixDatagram::unbound()?;
        let sent = match target {
            Target::Path(path) => socket.send_to(message.as_bytes(), path)?,
            #[cfg(target_os = "linux")]
            Target::Abstract(name) => {
                use std::os::linux::net::SocketAddrExt;
                let addr = std::os::unix::net::SocketAddr::from_abstract_name(name)?;
                socket.send_to_addr(message.as_bytes(), &addr)?
            }
        };
        if sent != message.len() {
            return Err(io::Error::new(
                io::ErrorKind::WriteZero,
                format!("sent {sent} of {} bytes", message.len()),
            ));
        }
        Ok(())
    }
}

fn parse_target(socket: OsString) -> Result<Target, String> {
    match socket.as_encoded_bytes().first() {
        Some(b'/') => Ok(Target::Path(PathBuf::from(socket))),
        #[cfg(target_os = "linux")]
        Some(b'@') => Ok(Target::Abstract(socket.as_encoded_bytes()[1..].to_vec())),
        _ => Err(format!(
            "NOTIFY_SOCKET={socket:?} is not a socket path this build supports; \
             systemd notifications are off"
        )),
    }
}

fn one_line(s: &str) -> String {
    s.replace(['\n', '\r'], " ")
}

/// Progress counter a daemon's main loop bumps; cheap to clone and share.
#[derive(Debug, Clone, Default)]
pub struct Heartbeat(Arc<AtomicU64>);

impl Heartbeat {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn beat(&self) {
        self.0.fetch_add(1, Ordering::Relaxed);
    }

    pub fn count(&self) -> u64 {
        self.0.load(Ordering::Relaxed)
    }
}

/// Whether a [`Heartbeat`] has beaten since the last check.
#[derive(Debug)]
pub struct Progress {
    heartbeat: Heartbeat,
    seen: u64,
}

impl Progress {
    pub fn new(heartbeat: Heartbeat) -> Self {
        let seen = heartbeat.count();
        Self { heartbeat, seen }
    }

    /// True if it beat at least once since the previous call (or since `new`).
    pub fn advanced(&mut self) -> bool {
        let now = self.heartbeat.count();
        let advanced = now != self.seen;
        self.seen = now;
        advanced
    }
}

/// Sends `WATCHDOG=1` every [`Notifier::watchdog_period`], but only after the
/// heartbeat has advanced since the previous one. Returns at once when the
/// unit has no watchdog. `name` prefixes the log lines (`[gateway] …`).
///
/// A loop that stalls longer than the period misses one keep-alive; one that
/// stays stuck for the whole `WatchdogSec` is killed and restarted by systemd.
#[cfg(feature = "tokio")]
pub async fn run_watchdog(notifier: Notifier, heartbeat: Heartbeat, name: &'static str) {
    let Some(period) = notifier.watchdog_period() else {
        return;
    };
    let mut progress = Progress::new(heartbeat);
    let mut ticker = tokio::time::interval(period);
    ticker.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Delay);
    ticker.tick().await; // the first tick is immediate
    let mut stalled = false;
    loop {
        ticker.tick().await;
        if progress.advanced() {
            if stalled {
                eprintln!("[{name}] watchdog: making progress again; keep-alives resumed");
                stalled = false;
            }
            if let Err(e) = notifier.watchdog() {
                eprintln!("[{name}] watchdog: keep-alive not sent: {e}");
            }
        } else if !stalled {
            stalled = true;
            eprintln!(
                "[{name}] watchdog: no progress in {} ms; keep-alive withheld, \
                 systemd restarts the service if it stays stuck",
                period.as_millis()
            );
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::path::Path;

    fn sock_path(tag: &str) -> PathBuf {
        // Short: macOS limits socket paths to 104 bytes.
        std::env::temp_dir().join(format!("sdn-{}-{tag}.sock", std::process::id()))
    }

    fn listener(path: &Path) -> UnixDatagram {
        let _ = std::fs::remove_file(path);
        let rx = UnixDatagram::bind(path).expect("bind");
        rx.set_nonblocking(true).expect("nonblocking");
        rx
    }

    fn recv(rx: &UnixDatagram) -> Option<String> {
        let mut buf = [0u8; 512];
        rx.recv(&mut buf)
            .ok()
            .map(|n| String::from_utf8_lossy(&buf[..n]).into_owned())
    }

    fn notifier_for(path: &Path, usec: Option<&str>) -> Notifier {
        Notifier::from_vars(Some(path.as_os_str().to_owned()), usec, None, 1)
    }

    #[test]
    fn no_socket_means_disabled_and_silent() {
        let n = Notifier::from_vars(None, Some("30000000"), None, 1);
        assert!(!n.enabled());
        assert_eq!(n.watchdog_period(), None);
        assert!(n.ready("x").is_ok());
        assert!(n.watchdog().is_ok());
        assert_eq!(n.problem(), None);
        let empty = Notifier::from_vars(Some(OsString::new()), None, None, 1);
        assert!(!empty.enabled());
    }

    #[test]
    fn path_socket_with_watchdog() {
        let n = Notifier::from_vars(
            Some("/run/systemd/notify".into()),
            Some("60000000"),
            None,
            7,
        );
        assert!(n.enabled());
        assert_eq!(n.watchdog_timeout(), Some(Duration::from_secs(60)));
        assert_eq!(n.watchdog_period(), Some(Duration::from_secs(30)));
    }

    #[test]
    fn watchdog_pid_must_be_ours() {
        let ours = Notifier::from_vars(Some("/n".into()), Some("2000000"), Some("42"), 42);
        assert_eq!(ours.watchdog_period(), Some(Duration::from_secs(1)));
        let theirs = Notifier::from_vars(Some("/n".into()), Some("2000000"), Some("41"), 42);
        assert_eq!(theirs.watchdog_period(), None);
        assert!(theirs.enabled(), "READY etc. still go out");
        let junk = Notifier::from_vars(Some("/n".into()), Some("2000000"), Some("x"), 42);
        assert_eq!(junk.watchdog_period(), None);
    }

    #[test]
    fn zero_or_bad_watchdog_usec_is_off() {
        let zero = Notifier::from_vars(Some("/n".into()), Some("0"), None, 1);
        assert_eq!(zero.watchdog_period(), None);
        assert_eq!(zero.problem(), None);
        let bad = Notifier::from_vars(Some("/n".into()), Some("30s"), None, 1);
        assert_eq!(bad.watchdog_period(), None);
        assert!(bad.problem().is_some_and(|p| p.contains("WATCHDOG_USEC")));
    }

    #[test]
    fn unsupported_socket_is_reported_not_used() {
        let n = Notifier::from_vars(Some("vsock:2:1234".into()), Some("1000000"), None, 1);
        assert!(!n.enabled());
        assert!(n.problem().is_some_and(|p| p.contains("vsock")));
        assert_eq!(n.watchdog_period(), None);
    }

    #[cfg(target_os = "linux")]
    #[test]
    fn abstract_socket_name() {
        let n = Notifier::from_vars(Some("@/org/test/notify".into()), None, None, 1);
        assert_eq!(
            n.target,
            Some(Target::Abstract(b"/org/test/notify".to_vec()))
        );
    }

    #[cfg(target_os = "linux")]
    #[test]
    fn sends_to_an_abstract_socket() {
        use std::os::linux::net::SocketAddrExt;
        let name = format!("f250-sdn-test-{}", std::process::id());
        let addr =
            std::os::unix::net::SocketAddr::from_abstract_name(name.as_bytes()).expect("addr");
        let rx = UnixDatagram::bind_addr(&addr).expect("bind");
        rx.set_nonblocking(true).expect("nonblocking");
        let n = Notifier::from_vars(Some(format!("@{name}").into()), None, None, 1);
        n.stopping().expect("send");
        assert_eq!(recv(&rx).as_deref(), Some("STOPPING=1"));
    }

    #[test]
    fn messages_on_the_wire() {
        let path = sock_path("wire");
        let rx = listener(&path);
        let n = notifier_for(&path, Some("1000000"));
        n.ready("listening on\nunix:/run/f250/vehicle.sock")
            .expect("ready");
        assert_eq!(
            recv(&rx).as_deref(),
            Some("READY=1\nSTATUS=listening on unix:/run/f250/vehicle.sock")
        );
        n.status("ok").expect("status");
        assert_eq!(recv(&rx).as_deref(), Some("STATUS=ok"));
        n.watchdog().expect("watchdog");
        assert_eq!(recv(&rx).as_deref(), Some("WATCHDOG=1"));
        n.stopping().expect("stopping");
        assert_eq!(recv(&rx).as_deref(), Some("STOPPING=1"));
        let _ = std::fs::remove_file(&path);
    }

    #[test]
    fn no_watchdog_configured_sends_no_keepalive() {
        let path = sock_path("nowd");
        let rx = listener(&path);
        let n = notifier_for(&path, None);
        n.watchdog().expect("no-op");
        assert_eq!(recv(&rx), None);
        let _ = std::fs::remove_file(&path);
    }

    #[test]
    fn missing_socket_is_an_error_not_a_panic() {
        let n = notifier_for(&sock_path("absent"), None);
        assert!(n.ready("x").is_err());
    }

    #[test]
    fn progress_follows_the_heartbeat() {
        let hb = Heartbeat::new();
        hb.beat(); // before Progress::new: not counted
        let mut p = Progress::new(hb.clone());
        assert!(!p.advanced());
        hb.beat();
        hb.beat();
        assert!(p.advanced());
        assert!(!p.advanced(), "each beat counts once");
        let shared = hb.clone();
        shared.beat();
        assert!(p.advanced(), "clones share the counter");
    }

    #[cfg(feature = "tokio")]
    #[tokio::test(start_paused = true)]
    async fn keepalives_only_while_progressing() {
        let path = sock_path("loop");
        let rx = listener(&path);
        // WatchdogSec=2 s, so a keep-alive check every second.
        let n = notifier_for(&path, Some("2000000"));
        let hb = Heartbeat::new();
        let task = tokio::spawn(run_watchdog(n, hb.clone(), "test"));
        let step = || async {
            tokio::time::sleep(Duration::from_millis(1000)).await;
            tokio::task::yield_now().await;
        };
        tokio::task::yield_now().await;

        hb.beat();
        step().await;
        assert_eq!(recv(&rx).as_deref(), Some("WATCHDOG=1"));

        step().await; // no beat in this period
        assert_eq!(recv(&rx), None);
        step().await;
        assert_eq!(recv(&rx), None);

        hb.beat();
        step().await;
        assert_eq!(recv(&rx).as_deref(), Some("WATCHDOG=1"), "resumes");
        task.abort();
        let _ = std::fs::remove_file(&path);
    }

    #[cfg(feature = "tokio")]
    #[tokio::test]
    async fn returns_at_once_without_a_watchdog() {
        run_watchdog(Notifier::disabled(), Heartbeat::new(), "test").await;
    }
}
