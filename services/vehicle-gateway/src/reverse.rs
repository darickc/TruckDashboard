//! Reverse from the truck's broadcast `230` byte 0 (ADR-0046, ADR-0024
//! decision 4), heard passively.
//!
//! - [`decode`]: one frame's byte 0. `10` is reverse; the other values seen
//!   on the truck (`F0` P, `F1` N, `01`–`06` forward) are not; anything else
//!   is unknown, never "not engaged" (VERIFICATION_LOG 2026-11-08 lever test
//!   and 2026-11-10 drive).
//! - [`Tracker`]: the last decoded frame and its age; stale after
//!   `stale_after` (the broadcast arrives about 31 times a second).
//! - [`run`]: the reader task. It opens the interface **receive-only**:
//!   [`FrameReader`] has no way to send, the kernel filter passes only `230`,
//!   and it never changes the interface's mode. It works with the interface
//!   listen-only (f250-can-auto's first state) as well as active, and doesn't
//!   need `--transmit` (ADR-0007: listening is the default).
//!
//! Status: `[SIM]`. The decoder's values are `[TRUCK]` (VERIFICATION_LOG);
//! this code has run against test vectors only.

use std::future::Future;
use std::io;
use std::pin::Pin;
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

use tokio::sync::watch;

/// The broadcast that carries the gear lever (CAN_CENSUS, VERIFICATION_LOG).
pub const REVERSE_ID: u16 = 0x230;

/// Byte 0 of `230` in reverse.
const REVERSE: u8 = 0x10;

/// The other values byte 0 took on the truck, none of them reverse: P, N,
/// and the forward gears' low nibble (2026-11-10: `01`, `02`, `03`, `05`,
/// `06` driving; `04` never seen, accepted as a forward gear between them).
const NOT_REVERSE: [u8; 8] = [0xF0, 0xF1, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06];

/// Default: how long without a `230` frame before reverse is unknown.
pub const DEFAULT_STALE_AFTER: Duration = Duration::from_millis(500);

/// How long the reader waits before opening the interface again.
const REOPEN_AFTER: Duration = Duration::from_secs(1);

/// What one frame says.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Decoded {
    Engaged,
    NotEngaged,
    /// A byte 0 the truck has never sent: unknown, not "not engaged".
    Undocumented(u8),
    /// No data bytes.
    Empty,
}

/// Decodes `230`'s data bytes.
pub fn decode(data: &[u8]) -> Decoded {
    match data.first() {
        None => Decoded::Empty,
        Some(&REVERSE) => Decoded::Engaged,
        Some(b) if NOT_REVERSE.contains(b) => Decoded::NotEngaged,
        Some(&b) => Decoded::Undocumented(b),
    }
}

/// Reverse as the API reports it.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum State {
    Unknown,
    NotEngaged,
    Engaged,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Report {
    pub state: State,
    /// Since the last frame decoded; `None` before the first.
    pub age: Option<Duration>,
    pub detail: String,
}

/// The last frame and the reader's last problem. Times are `Duration`s since
/// an arbitrary origin, passed in (no clock inside).
#[derive(Debug, Clone)]
pub struct Tracker {
    stale_after: Duration,
    interface: String,
    last: Option<(Decoded, Duration)>,
    problem: Option<String>,
}

impl Tracker {
    pub fn new(interface: &str, stale_after: Duration) -> Self {
        Tracker {
            stale_after,
            interface: interface.to_string(),
            last: None,
            problem: None,
        }
    }

    /// A `230` frame's data at `now`. Returns whether the state changed.
    pub fn on_frame(&mut self, data: &[u8], now: Duration) -> bool {
        let before = self.report(now).state;
        self.last = Some((decode(data), now));
        self.problem = None;
        self.report(now).state != before
    }

    /// The reader can't read (the interface is down, gone, or failed).
    pub fn on_problem(&mut self, why: String, now: Duration) -> bool {
        let before = self.report(now).state;
        self.problem = Some(why);
        self.report(now).state != before
    }

    pub fn report(&self, now: Duration) -> Report {
        let age = self.last.map(|(_, at)| now.saturating_sub(at));
        let unknown = |detail: String| Report {
            state: State::Unknown,
            age,
            detail,
        };
        let Some((decoded, at)) = self.last else {
            return unknown(match &self.problem {
                Some(p) => format!("no 230 frame yet: {p}"),
                None => format!("no 230 frame yet on {}", self.interface),
            });
        };
        let age_now = now.saturating_sub(at);
        if age_now > self.stale_after {
            return unknown(match &self.problem {
                Some(p) => format!("no 230 frame for {}: {p}", seconds(age_now)),
                None => format!("no 230 frame for {}", seconds(age_now)),
            });
        }
        match decoded {
            Decoded::Engaged => Report {
                state: State::Engaged,
                age,
                detail: "230 byte 0 = 10".into(),
            },
            Decoded::NotEngaged => Report {
                state: State::NotEngaged,
                age,
                detail: "230 byte 0 not 10".into(),
            },
            Decoded::Undocumented(b) => unknown(format!(
                "230 byte 0 = {b:02X}: a value never seen on the truck"
            )),
            Decoded::Empty => unknown("230 frame with no data".into()),
        }
    }
}

fn seconds(d: Duration) -> String {
    format!("{:.1} s", d.as_secs_f64())
}

/// Shared between the reader task and the API's streams.
#[derive(Clone)]
pub struct Feed {
    origin: Instant,
    tracker: Option<Arc<Mutex<Tracker>>>,
    /// Without a reader: why reverse is always unknown.
    absent: String,
    changed: watch::Receiver<u64>,
}

impl Feed {
    /// No broadcast reader (the simulator, or the MX+ alone: ADR-0024
    /// decision 4).
    pub fn absent(why: &str) -> Self {
        let (_tx, rx) = watch::channel(0);
        Feed {
            origin: Instant::now(),
            tracker: None,
            absent: why.to_string(),
            changed: rx,
        }
    }

    pub fn report(&self) -> Report {
        match &self.tracker {
            None => Report {
                state: State::Unknown,
                age: None,
                detail: self.absent.clone(),
            },
            Some(t) => match t.lock() {
                Ok(t) => t.report(self.origin.elapsed()),
                Err(_) => Report {
                    state: State::Unknown,
                    age: None,
                    detail: "reverse reader failed".into(),
                },
            },
        }
    }

    /// Changes when the state changes.
    pub fn changes(&self) -> watch::Receiver<u64> {
        self.changed.clone()
    }
}

pub type BoxFuture<'a, T> = Pin<Box<dyn Future<Output = T> + Send + 'a>>;

/// A receive-only source of `230` frames' data bytes. There is deliberately
/// no send.
pub trait FrameReader: Send {
    fn recv(&mut self) -> BoxFuture<'_, io::Result<Vec<u8>>>;
}

/// Opens (or re-opens) the reader.
pub type Opener =
    Arc<dyn Fn() -> BoxFuture<'static, io::Result<Box<dyn FrameReader>>> + Send + Sync>;

/// Starts the reader task and returns its feed.
pub fn spawn(interface: &str, stale_after: Duration, opener: Opener) -> Feed {
    let origin = Instant::now();
    let tracker = Arc::new(Mutex::new(Tracker::new(interface, stale_after)));
    let (tx, rx) = watch::channel(0u64);
    tokio::spawn(run(
        interface.to_string(),
        origin,
        tracker.clone(),
        tx,
        opener,
    ));
    Feed {
        origin,
        tracker: Some(tracker),
        absent: String::new(),
        changed: rx,
    }
}

/// Reads frames until the process ends; reopens after any error. Logs each
/// change of state and each problem once.
pub async fn run(
    interface: String,
    origin: Instant,
    tracker: Arc<Mutex<Tracker>>,
    changed: watch::Sender<u64>,
    opener: Opener,
) {
    let mut last_logged: Option<String> = None;
    let note = |tracker: &Arc<Mutex<Tracker>>, f: &dyn Fn(&mut Tracker, Duration) -> bool| {
        let mut flipped = false;
        let mut report = None;
        if let Ok(mut t) = tracker.lock() {
            let now = origin.elapsed();
            flipped = f(&mut t, now);
            report = Some(t.report(now));
        }
        (flipped, report)
    };
    let mut log = |r: Option<Report>| {
        if let Some(r) = r {
            let line = format!("{:?}: {}", r.state, r.detail);
            if last_logged.as_deref() != Some(line.as_str()) {
                eprintln!("[gateway] reverse: {line}");
                last_logged = Some(line);
            }
        }
    };
    loop {
        match opener().await {
            Err(e) => {
                let (flipped, r) = note(&tracker, &|t, now| {
                    t.on_problem(format!("{interface}: {e}"), now)
                });
                if flipped {
                    changed.send_modify(|g| *g += 1);
                }
                log(r);
            }
            Ok(mut reader) => loop {
                match reader.recv().await {
                    Ok(data) => {
                        let (flipped, r) = note(&tracker, &|t, now| t.on_frame(&data, now));
                        if flipped {
                            changed.send_modify(|g| *g += 1);
                            log(r);
                        }
                    }
                    Err(e) => {
                        let (flipped, r) = note(&tracker, &|t, now| {
                            t.on_problem(format!("{interface}: {e}"), now)
                        });
                        if flipped {
                            changed.send_modify(|g| *g += 1);
                        }
                        log(r);
                        break;
                    }
                }
            },
        }
        tokio::time::sleep(REOPEN_AFTER).await;
    }
}

/// The real reader: a raw SocketCAN socket that only receives `230`.
#[cfg(target_os = "linux")]
pub mod socket {
    use super::*;
    use socketcan::tokio::CanSocket;
    use socketcan::{CanFilter, CanFrame, EmbeddedFrame, Id, SocketOptions};

    struct Reader(CanSocket);

    impl FrameReader for Reader {
        fn recv(&mut self) -> BoxFuture<'_, io::Result<Vec<u8>>> {
            Box::pin(async move {
                loop {
                    // The filter can also pass an extended ID ending in 230.
                    if let CanFrame::Data(d) = self.0.read_frame().await? {
                        if let Id::Standard(id) = d.id() {
                            if id.as_raw() == REVERSE_ID {
                                return Ok(d.data().to_vec());
                            }
                        }
                    }
                }
            })
        }
    }

    /// Opens `interface` with a kernel filter for standard ID `230` only. The
    /// socket is never written to.
    pub fn opener(interface: String) -> Opener {
        Arc::new(move || {
            let interface = interface.clone();
            Box::pin(async move {
                let sock = CanSocket::open(&interface)?;
                sock.set_filters(&[CanFilter::new(u32::from(REVERSE_ID), 0x7FF)])?;
                sock.set_error_filter_drop_all()?;
                Ok(Box::new(Reader(sock)) as Box<dyn FrameReader>)
            })
        })
    }
}

/// Not Linux: SocketCAN doesn't exist; opening always fails, honestly.
#[cfg(not(target_os = "linux"))]
pub mod socket {
    use super::*;

    pub fn opener(interface: String) -> Opener {
        Arc::new(move || {
            let interface = interface.clone();
            Box::pin(async move {
                Err(io::Error::new(
                    io::ErrorKind::Unsupported,
                    format!("SocketCAN ({interface}) is Linux-only"),
                ))
            })
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const MS: fn(u64) -> Duration = Duration::from_millis;

    #[test]
    fn decodes_every_value_seen_on_the_truck() {
        // VERIFICATION_LOG 2026-11-08 (lever) and 2026-11-10 (drive).
        assert_eq!(decode(&[0x10, 0, 0, 0, 0, 0, 0, 0]), Decoded::Engaged);
        for b in [0xF0, 0xF1, 0x01, 0x02, 0x03, 0x05, 0x06] {
            assert_eq!(decode(&[b, 0xFF]), Decoded::NotEngaged, "{b:02X}");
        }
    }

    #[test]
    fn an_unseen_value_or_no_data_is_not_a_decision() {
        for b in [0x00, 0x11, 0x20, 0x07, 0xF2, 0xFF] {
            assert_eq!(decode(&[b]), Decoded::Undocumented(b), "{b:02X}");
        }
        assert_eq!(decode(&[]), Decoded::Empty);
    }

    #[test]
    fn unknown_until_the_first_frame() {
        let t = Tracker::new("can0", MS(500));
        let r = t.report(MS(10_000));
        assert_eq!(r.state, State::Unknown);
        assert_eq!(r.age, None);
        assert_eq!(r.detail, "no 230 frame yet on can0");
    }

    #[test]
    fn follows_the_frames_and_reports_changes() {
        let mut t = Tracker::new("can0", MS(500));
        assert!(t.on_frame(&[0xF0], MS(0)), "unknown → not engaged");
        assert!(!t.on_frame(&[0xF0], MS(32)));
        assert!(t.on_frame(&[0x10], MS(64)), "→ engaged");
        let r = t.report(MS(100));
        assert_eq!(r.state, State::Engaged);
        assert_eq!(r.age, Some(MS(36)));
        assert!(t.on_frame(&[0x01], MS(128)), "→ not engaged");
        assert_eq!(t.report(MS(130)).state, State::NotEngaged);
    }

    #[test]
    fn a_silent_bus_is_unknown_never_not_engaged() {
        let mut t = Tracker::new("can0", MS(500));
        t.on_frame(&[0x10], MS(0));
        assert_eq!(t.report(MS(500)).state, State::Engaged, "at the limit");
        let r = t.report(MS(501));
        assert_eq!(r.state, State::Unknown);
        assert_eq!(r.detail, "no 230 frame for 0.5 s");
        assert_eq!(r.age, Some(MS(501)));
        t.on_frame(&[0xF0], MS(600));
        assert_eq!(t.report(MS(600)).state, State::NotEngaged);
    }

    #[test]
    fn an_undocumented_value_makes_it_unknown() {
        let mut t = Tracker::new("can0", MS(500));
        t.on_frame(&[0xF0], MS(0));
        assert!(t.on_frame(&[0x42], MS(30)));
        let r = t.report(MS(30));
        assert_eq!(r.state, State::Unknown);
        assert!(r.detail.contains("42"), "{}", r.detail);
    }

    #[test]
    fn a_reader_problem_shows_once_the_frames_go_stale() {
        let mut t = Tracker::new("can0", MS(500));
        t.on_frame(&[0x10], MS(0));
        // The last frame is still fresh: reverse holds for now.
        assert!(!t.on_problem("can0: Network is down".into(), MS(10)));
        assert_eq!(t.report(MS(10)).state, State::Engaged);
        let r = t.report(MS(900));
        assert_eq!(r.state, State::Unknown);
        assert_eq!(r.detail, "no 230 frame for 0.9 s: can0: Network is down");
    }

    #[test]
    fn the_brief_pass_through_r_into_p_is_reported_as_it_comes() {
        // 2026-11-10 +1350 s: F1, 10, F0 for 0.1 s each. The gateway reports
        // it; camera-policy's debounce (rev_debounce) decides what to show.
        let mut t = Tracker::new("can0", MS(500));
        let states: Vec<_> = [(0xF1, 0), (0x10, 100), (0xF0, 200)]
            .iter()
            .map(|&(b, at)| {
                t.on_frame(&[b], MS(at));
                t.report(MS(at)).state
            })
            .collect();
        assert_eq!(
            states,
            [State::NotEngaged, State::Engaged, State::NotEngaged]
        );
    }

    #[test]
    fn without_a_reader_it_says_why() {
        let f = Feed::absent("--transport sim: no CAN broadcast to read");
        let r = f.report();
        assert_eq!(r.state, State::Unknown);
        assert_eq!(r.detail, "--transport sim: no CAN broadcast to read");
    }

    struct Script(std::collections::VecDeque<io::Result<Vec<u8>>>);

    impl FrameReader for Script {
        fn recv(&mut self) -> BoxFuture<'_, io::Result<Vec<u8>>> {
            Box::pin(async move {
                match self.0.pop_front() {
                    Some(r) => r,
                    None => std::future::pending().await,
                }
            })
        }
    }

    #[tokio::test]
    async fn the_reader_task_feeds_the_tracker_and_signals_changes() {
        let opener: Opener = Arc::new(|| {
            Box::pin(async {
                Ok(
                    Box::new(Script(vec![Ok(vec![0xF0]), Ok(vec![0x10])].into()))
                        as Box<dyn FrameReader>,
                )
            })
        });
        let feed = spawn("can0", MS(500), opener);
        let mut changes = feed.changes();
        tokio::time::timeout(Duration::from_secs(2), async {
            while feed.report().state != State::Engaged {
                let _ = changes.changed().await;
            }
        })
        .await
        .unwrap_or_else(|_| panic!("never engaged: {:?}", feed.report()));
    }

    #[tokio::test]
    async fn an_interface_that_wont_open_is_unknown_with_the_reason() {
        let opener: Opener = Arc::new(|| {
            Box::pin(async { Err(io::Error::new(io::ErrorKind::NotFound, "No such device")) })
        });
        let feed = spawn("can9", MS(500), opener);
        tokio::time::timeout(Duration::from_secs(2), async {
            while !feed.report().detail.contains("No such device") {
                tokio::time::sleep(MS(10)).await;
            }
        })
        .await
        .unwrap_or_else(|_| panic!("{:?}", feed.report()));
        assert_eq!(feed.report().state, State::Unknown);
        assert_eq!(
            feed.report().detail,
            "no 230 frame yet: can9: No such device"
        );
    }
}
