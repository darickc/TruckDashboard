//! Says so when audio that should be playing is left unlinked (bench-log
//! 2026-11-15, ADR-0045 amendment 2026-11-15 item 3).
//!
//! WirePlumber's policy instance links every stream. On the bench Pi it once
//! stopped linking any new stream for hours: a Lua error in one of its event
//! hooks left the hook unfinished, and WirePlumber runs one event at a time.
//! The cause is fixed (the backported linking scripts in
//! agl/rootfs/usr/local/share/wireplumber), but a wedge like it is silent: the
//! music or the call just isn't heard. So audio-manager checks, while it
//! knows something should be linked, and puts the problem on the screen and
//! in the log.
//!
//! What should be linked, and only then (AGL's role policy corks, that is
//! unlinks, lower-priority streams, so an unlinked stream is often right):
//! - during an active call, the phone's two hands-free streams;
//! - while the phone streams music and no call is up, no prompt is being
//!   said and no ring tone plays, the phone's music stream.
//!
//! A stream that isn't there isn't a linking problem (the phone may keep a
//! call's audio): only streams that exist are checked.
//!
//! Status: matching and timing tested on pw-dump output shaped like the
//! bench Pi's [SIM]; the watch on the Pi [BENCH] (bench-log 2026-11-15).

use std::collections::HashMap;
use std::path::PathBuf;
use std::sync::Arc;
use std::time::Duration;

use tokio::time::Instant;

use crate::manager::Manager;

/// How long a stream may stay unlinked before it is a problem. WirePlumber
/// links a new stream within a second on the bench.
pub const UNLINKED_AFTER: Duration = Duration::from_secs(6);
/// How often to look while something should be linked.
pub const EVERY: Duration = Duration::from_secs(2);

/// The phone (its Bluetooth address) whose streams should be linked now.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct Expected {
    /// A call is active on this phone: its hands-free streams.
    pub call: Option<String>,
    /// This phone streams music, with nothing above it: its music stream.
    pub music: Option<String>,
}

impl Expected {
    pub fn is_empty(&self) -> bool {
        self.call.is_none() && self.music.is_none()
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Kind {
    Call,
    Music,
}

/// One stream that should be linked, as pw-dump shows it.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Watched {
    pub name: String,
    pub kind: Kind,
    pub linked: bool,
}

/// The streams `want` names in `pw-dump`'s JSON, and whether each has a
/// link. Unparseable output gives none (nothing is claimed).
pub fn watched(dump: &str, want: &Expected) -> Vec<Watched> {
    let Ok(serde_json::Value::Array(objects)) = serde_json::from_str::<serde_json::Value>(dump)
    else {
        return Vec::new();
    };
    let mut linked = std::collections::HashSet::new();
    for o in &objects {
        if o.get("type").and_then(|t| t.as_str()) == Some("PipeWire:Interface:Link") {
            for k in ["/info/output-node-id", "/info/input-node-id"] {
                if let Some(id) = o.pointer(k).and_then(serde_json::Value::as_u64) {
                    linked.insert(id);
                }
            }
        }
    }
    let mut out = Vec::new();
    for o in &objects {
        if o.get("type").and_then(|t| t.as_str()) != Some("PipeWire:Interface:Node") {
            continue;
        }
        let (Some(id), Some(props)) = (
            o.get("id").and_then(serde_json::Value::as_u64),
            o.pointer("/info/props"),
        ) else {
            continue;
        };
        let s = |k: &str| props.get(k).and_then(|v| v.as_str()).unwrap_or("");
        if !s("media.class").starts_with("Stream/") || s("node.name").is_empty() {
            continue;
        }
        let addr = s("api.bluez5.address");
        let profile = s("api.bluez5.profile");
        let is = |a: &Option<String>| a.as_deref().is_some_and(|a| a.eq_ignore_ascii_case(addr));
        let kind = if profile.starts_with("headset") && is(&want.call) {
            Kind::Call
        } else if profile.starts_with("a2dp") && is(&want.music) {
            Kind::Music
        } else {
            continue;
        };
        out.push(Watched {
            name: s("node.name").to_string(),
            kind,
            linked: linked.contains(&id),
        });
    }
    out
}

/// Remembers since when each stream has been unlinked.
#[derive(Debug, Default)]
pub struct Tracker {
    since: HashMap<String, Instant>,
}

/// A stream left unlinked: for the screen and for the log.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Problem {
    pub screen: String,
    pub log: String,
}

impl Tracker {
    /// The problem as of `now`, if a stream in `seen` has been unlinked for
    /// `after` or longer. Streams no longer seen, or linked, start over.
    pub fn update(&mut self, now: Instant, seen: &[Watched], after: Duration) -> Option<Problem> {
        self.since
            .retain(|name, _| seen.iter().any(|w| &w.name == name && !w.linked));
        let mut worst: Option<(&Watched, Duration)> = None;
        for w in seen.iter().filter(|w| !w.linked) {
            let for_ =
                now.saturating_duration_since(*self.since.entry(w.name.clone()).or_insert(now));
            if for_ >= after && worst.is_none_or(|(_, d)| for_ > d) {
                worst = Some((w, for_));
            }
        }
        let (w, for_) = worst?;
        let what = match w.kind {
            Kind::Call => "The call's audio isn't connected",
            Kind::Music => "The phone's music isn't reaching the speakers",
        };
        Some(Problem {
            screen: format!(
                "{what}: the audio system left it unlinked. Restarting the head unit fixes it."
            ),
            log: format!(
                "{} has had no link for {} s: WirePlumber's policy instance may have stopped \
                 linking (systemctl restart wireplumber@policy)",
                w.name,
                for_.as_secs()
            ),
        })
    }
}

/// Looks every [`EVERY`] while the manager expects something linked, and
/// tells it what it finds. pw-dump only runs then.
pub async fn watch(manager: Arc<Manager>, pw_dump: PathBuf) {
    let mut tracker = Tracker::default();
    loop {
        tokio::time::sleep(EVERY).await;
        if manager.stopping() {
            return;
        }
        let want = manager.routing_expectation();
        if want.is_empty() {
            tracker = Tracker::default();
            manager.set_routing_problem(None);
            continue;
        }
        match crate::call_audio::run_cmd(&pw_dump, &[]).await {
            Ok(dump) => {
                let seen = watched(&dump, &want);
                let p = tracker.update(Instant::now(), &seen, UNLINKED_AFTER);
                manager.set_routing_problem(p);
            }
            // Can't look: nothing is claimed either way.
            Err(e) => eprintln!("[audio] audio routing check: {e}"),
        }
    }
}

#[cfg(test)]
#[allow(clippy::unwrap_used)]
mod tests {
    use super::*;

    const ADDR: &str = "B0:DE:31:1E:55:96";

    fn node(id: u64, name: &str, class: &str, profile: &str) -> String {
        format!(
            r#"{{"id":{id},"type":"PipeWire:Interface:Node","info":{{"props":{{"node.name":"{name}","media.class":"{class}","api.bluez5.address":"{ADDR}","api.bluez5.profile":"{profile}"}}}}}}"#
        )
    }

    fn link(out: u64, inp: u64) -> String {
        format!(
            r#"{{"id":900,"type":"PipeWire:Interface:Link","info":{{"output-node-id":{out},"output-port-id":1,"input-node-id":{inp},"input-port-id":2,"state":"paused","error":null}}}}"#
        )
    }

    /// Shaped like the bench Pi's pw-dump during a call (2026-11-15): the
    /// voice linked to AGL's Communication loopback, the input to the phone
    /// not linked.
    fn dump() -> String {
        format!(
            "[{},{},{},{},{}]",
            node(
                120,
                "bluez_input.B0_DE_31_1E_55_96.2",
                "Stream/Output/Audio",
                "a2dp-source"
            ),
            node(
                121,
                "bluez_input.B0_DE_31_1E_55_96.0",
                "Stream/Output/Audio",
                "headset-audio-gateway"
            ),
            node(
                122,
                "bluez_output.B0_DE_31_1E_55_96.1",
                "Stream/Input/Audio",
                "headset-audio-gateway"
            ),
            r#"{"id":170,"type":"PipeWire:Interface:Node","info":{"props":{"node.name":"input.loopback.sink.role.communication","media.class":"Audio/Sink"}}}"#,
            link(121, 170),
        )
    }

    #[test]
    fn a_call_watches_the_hands_free_streams_only() {
        let want = Expected {
            call: Some(ADDR.to_ascii_lowercase()),
            music: None,
        };
        assert_eq!(
            watched(&dump(), &want),
            vec![
                Watched {
                    name: "bluez_input.B0_DE_31_1E_55_96.0".into(),
                    kind: Kind::Call,
                    linked: true
                },
                Watched {
                    name: "bluez_output.B0_DE_31_1E_55_96.1".into(),
                    kind: Kind::Call,
                    linked: false
                },
            ]
        );
    }

    #[test]
    fn music_watches_the_music_stream_only() {
        let want = Expected {
            call: None,
            music: Some(ADDR.into()),
        };
        let w = watched(&dump(), &want);
        assert_eq!(w.len(), 1);
        assert_eq!((w[0].kind, w[0].linked), (Kind::Music, false));
        // Another phone's streams are never watched.
        let other = Expected {
            call: Some("11:22:33:44:55:66".into()),
            music: Some("11:22:33:44:55:66".into()),
        };
        assert!(watched(&dump(), &other).is_empty());
        assert!(watched(&dump(), &Expected::default()).is_empty());
        assert!(watched("not json", &want).is_empty());
    }

    fn w(name: &str, linked: bool) -> Watched {
        Watched {
            name: name.into(),
            kind: Kind::Call,
            linked,
        }
    }

    #[tokio::test(start_paused = true)]
    async fn a_problem_only_after_the_stream_stays_unlinked() {
        let mut t = Tracker::default();
        let t0 = Instant::now();
        let after = Duration::from_secs(6);
        assert_eq!(t.update(t0, &[w("a", false)], after), None, "just appeared");
        assert_eq!(
            t.update(t0 + Duration::from_secs(5), &[w("a", false)], after),
            None
        );
        let p = t
            .update(t0 + Duration::from_secs(6), &[w("a", false)], after)
            .unwrap();
        assert!(
            p.screen.starts_with("The call's audio isn't connected"),
            "{p:?}"
        );
        assert!(p.log.starts_with("a has had no link for 6 s"), "{p:?}");
        // Linked again: over at once, and the time starts over.
        assert_eq!(
            t.update(t0 + Duration::from_secs(7), &[w("a", true)], after),
            None
        );
        assert_eq!(
            t.update(t0 + Duration::from_secs(8), &[w("a", false)], after),
            None
        );
        assert!(
            t.update(t0 + Duration::from_secs(14), &[w("a", false)], after)
                .is_some()
        );
        // Gone: forgotten.
        assert_eq!(t.update(t0 + Duration::from_secs(15), &[], after), None);
        assert_eq!(
            t.update(t0 + Duration::from_secs(16), &[w("a", false)], after),
            None
        );
    }

    #[tokio::test(start_paused = true)]
    async fn a_linked_stream_is_never_a_problem() {
        let mut t = Tracker::default();
        let t0 = Instant::now();
        for s in 0..20 {
            assert_eq!(
                t.update(t0 + Duration::from_secs(s), &[w("a", true)], UNLINKED_AFTER),
                None
            );
        }
    }

    #[tokio::test(start_paused = true)]
    async fn music_says_music() {
        let mut t = Tracker::default();
        let t0 = Instant::now();
        let m = [Watched {
            name: "m".into(),
            kind: Kind::Music,
            linked: false,
        }];
        t.update(t0, &m, UNLINKED_AFTER);
        let p = t.update(t0 + UNLINKED_AFTER, &m, UNLINKED_AFTER).unwrap();
        assert!(
            p.screen
                .starts_with("The phone's music isn't reaching the speakers")
        );
    }
}
