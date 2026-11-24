//! Writes frames to the dial and reads its lines (ADR-0044 decision 7).
//! Generic over the port, so the tests run it over an in-memory pipe.

use std::collections::{HashMap, VecDeque};
use std::sync::Arc;
use std::time::Duration;

use f250_proto::audio::v1 as audio;
use f250_proto::nav::v1 as nav;
use f250_proto::vehicle::v1 as pb;
use tokio::io::{AsyncBufReadExt, AsyncRead, AsyncWrite, AsyncWriteExt, BufReader};
use tokio::sync::watch;
use tokio::time::Instant;

use crate::art::{self, Art};
use crate::frame::{self, FromDial, Units};
use crate::pages;

/// What the gateway, navigation and audio-manager said last, and when it
/// arrived.
#[derive(Debug, Clone, Default)]
pub struct Latest {
    pub defs: HashMap<String, pb::SignalDefinition>,
    /// Bumped when `defs` changes: the config frame goes out again at once.
    pub defs_gen: u64,
    pub snapshot: Option<(Instant, pb::Snapshot)>,
    /// The guidance and, once fetched, its route.
    pub guidance: Option<(Instant, nav::Guidance)>,
    pub route: Option<nav::Route>,
    pub audio: Option<(Instant, audio::WatchAudioResponse)>,
    /// The cover of the track playing, made ready for the dial.
    pub cover: Cover,
}

/// What the dial's media page shows behind it.
#[derive(Debug, Clone, Default)]
pub enum Cover {
    /// audio-manager hasn't said (or isn't followed): nothing is sent.
    #[default]
    Unknown,
    /// No picture for this track (or no phone): `A1 none`.
    None,
    Some(Arc<Art>),
}

#[derive(Debug, Clone, Copy)]
pub struct Timing {
    /// A data frame this often.
    pub period: Duration,
    /// The config frame this often (and on opening).
    pub config_every: Duration,
    /// A snapshot older than this isn't sent: the dial goes stale on its own.
    pub snapshot_max_age: Duration,
    /// Guidance or audio older than this isn't sent: the dial's page then
    /// says it has no data (navigation and audio-manager answer at least once
    /// a second).
    pub page_max_age: Duration,
    /// A cover's lines go out at most this many per period, so the dial's
    /// serial buffer keeps up while it draws.
    pub art_lines_per_tick: usize,
    /// The cover is sent again this often (the dial skips a picture it
    /// already shows; one it missed comes back).
    pub art_repeat: Duration,
}

impl Default for Timing {
    fn default() -> Timing {
        Timing {
            period: Duration::from_millis(250),
            config_every: Duration::from_secs(5),
            snapshot_max_age: Duration::from_secs(2),
            page_max_age: Duration::from_secs(3),
            // 32 lines of ~225 bytes every 250 ms: ~29 kB/s, a 180 x 180
            // cover in about 3.5 s.
            art_lines_per_tick: 32,
            art_repeat: Duration::from_secs(15),
        }
    }
}

/// Serves one opened port until it fails. Returns why.
pub async fn serve<P>(
    port: P,
    mut latest: watch::Receiver<Latest>,
    units: Units,
    timing: Timing,
    log: impl Fn(String),
) -> String
where
    P: AsyncRead + AsyncWrite + Unpin,
{
    let (rd, mut wr) = tokio::io::split(port);
    let mut lines = BufReader::new(rd).lines();
    let mut tick = tokio::time::interval(timing.period);
    tick.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Delay);
    let mut next_config = Instant::now();
    let mut sent_gen: Option<u64> = None;
    let mut seq: u32 = 0;
    // The cover's lines still to send, and what was last queued and when
    // (Some(id) for a picture, None for "none").
    let mut art_queue: VecDeque<String> = VecDeque::new();
    let mut art_sent: Option<(Option<u32>, Instant)> = None;
    loop {
        tokio::select! {
            _ = tick.tick() => {
                let now = Instant::now();
                let mut out = String::new();
                {
                    let l = latest.borrow_and_update();
                    if now >= next_config || sent_gen != Some(l.defs_gen) {
                        sent_gen = Some(l.defs_gen);
                        out.push_str(&frame::config_line(&l.defs, units));
                        out.push('\n');
                        next_config = now + timing.config_every;
                    }
                    if let Some((at, snap)) = &l.snapshot
                        && now.duration_since(*at) <= timing.snapshot_max_age
                    {
                        seq = seq.wrapping_add(1);
                        out.push_str(&frame::data_line(seq, snap, units));
                        out.push('\n');
                    }
                    if let Some((at, g)) = &l.guidance
                        && now.duration_since(*at) <= timing.page_max_age
                    {
                        out.push_str(&pages::nav_line(g, l.route.as_ref(), units));
                        out.push('\n');
                    }
                    if let Some((at, a)) = &l.audio
                        && now.duration_since(*at) <= timing.page_max_age
                    {
                        out.push_str(&pages::media_line(a));
                        out.push('\n');
                        out.push_str(&pages::call_line(a));
                        out.push('\n');
                    }
                    let want = match &l.cover {
                        Cover::Unknown => None,
                        Cover::None => Some(None),
                        Cover::Some(a) => Some(Some(Arc::clone(a))),
                    };
                    if let Some(want) = want {
                        let id = want.as_ref().map(|a| a.id);
                        let due = match art_sent {
                            None => true,
                            Some((sent, at)) => {
                                sent != id
                                    || (art_queue.is_empty()
                                        && now.duration_since(at) >= timing.art_repeat)
                            }
                        };
                        if due {
                            art_queue.clear();
                            match &want {
                                Some(a) => art_queue.extend(art::lines(a)),
                                None => art_queue.push_back(art::none_line()),
                            }
                            art_sent = Some((id, now));
                        }
                    }
                }
                for l in art_queue.drain(..timing.art_lines_per_tick.min(art_queue.len())) {
                    out.push_str(&l);
                    out.push('\n');
                }
                if !out.is_empty()
                    && let Err(e) = wr.write_all(out.as_bytes()).await
                {
                    return format!("write: {e}");
                }
            }
            line = lines.next_line() => match line {
                Ok(Some(l)) => match frame::from_dial(&l) {
                    FromDial::Hello(h) => log(format!("dial: {h}")),
                    FromDial::Log(m) => log(format!("dial says: {m}")),
                    FromDial::Other(o) if o.trim().is_empty() => {}
                    FromDial::Other(o) => log(format!("dial sent something else: {o:?}")),
                },
                Ok(None) => return "the dial closed the port".into(),
                Err(e) => return format!("read: {e}"),
            },
        }
    }
}

/// The dial's serial port: `fixed` if given, else the first entry in
/// `by_id` (normally /dev/serial/by-id) whose name has "F-250_knob" (the
/// firmware's USB product name; udev puts it in the link's name).
pub fn find_port(
    fixed: Option<&std::path::Path>,
    by_id: &std::path::Path,
) -> Option<std::path::PathBuf> {
    if let Some(p) = fixed {
        return p.exists().then(|| p.to_path_buf());
    }
    let mut found: Vec<_> = std::fs::read_dir(by_id)
        .ok()?
        .filter_map(Result::ok)
        .map(|e| e.path())
        .filter(|p| {
            p.file_name()
                .and_then(|n| n.to_str())
                .is_some_and(|n| n.contains("F-250_knob"))
        })
        .collect();
    found.sort();
    found.into_iter().next()
}
