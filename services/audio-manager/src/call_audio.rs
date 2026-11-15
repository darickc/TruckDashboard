//! The call's audio path (ADR-0045 decision 3, first cut): while a call is
//! up, the call microphone feeds the phone and the phone's voice goes to the
//! speakers.
//!
//! With the head unit in the hands-free role, PipeWire 1.6.8 shows the
//! phone's call audio as two **streams** on the phone's `audio-gateway`
//! device, made when the call starts (bench Pi with the owner's Z Fold8,
//! 2026-11-14): the phone's voice, `media.class` `Stream/Output/Audio`
//! (`bluez_input.<address>.0`), and the way to the phone,
//! `Stream/Input/Audio` (`bluez_output.<address>.1`), both with
//! `api.bluez5.profile` "headset-audio-gateway" and `api.bluez5.address`.
//! The phone's music is a stream too, with an "a2dp-…" profile, and is never
//! taken. WirePlumber links streams like any application's: the voice to
//! the default sink (AGL's Communication role), the phone's input from the
//! default source. audio-manager pins them with `target.object` in
//! WirePlumber's default metadata: the input to the call microphone (the
//! default source could be a camera's), the voice to `--call-speaker` when
//! one is named.
//!
//! The call audio link (SCO) opens only once these streams run, that is
//! once they are linked: on the bench, with no sink at all (no DAC yet), the
//! transport stayed "pending" for a whole call and nothing was heard.
//!
//! Echo cancellation is outside this service: on the image, `--call-mic` is
//! the source of f250-echo-cancel.service's WebRTC canceller
//! (`f250.call-aec`, ADR-0045 amendment 2026-11-14b), pinned like any
//! microphone. Status:
//! the stream matching is tested on pw-dump output shaped like the bench's
//! [SIM]; `target.object` pinning is UNVERIFIED until a bench call with a
//! sink.

use std::path::PathBuf;
use std::process::Stdio;
use std::sync::Mutex;
use std::time::Duration;

/// How long to look for the call's streams after a call starts.
const FIND_FOR: Duration = Duration::from_secs(60);
const FIND_EVERY: Duration = Duration::from_millis(500);

/// A PipeWire node: its id (the metadata's subject) and `node.name`.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Node {
    pub id: u64,
    pub name: String,
}

/// The phone's hands-free streams.
#[derive(Debug, Clone, PartialEq, Eq, Default)]
pub struct PhoneStreams {
    /// The phone's voice, played into the graph.
    pub voice: Option<Node>,
    /// To the phone, captured from the graph (the microphone).
    pub to_phone: Option<Node>,
}

/// `address`'s hands-free streams in `pw-dump`'s JSON. Music (A2DP) and
/// other phones' are left out. Devices' nodes (`Audio/Source`,
/// `Audio/Sink`), which the other hands-free role would make, are taken the
/// same way.
pub fn phone_streams(dump: &str, address: &str) -> PhoneStreams {
    let mut out = PhoneStreams::default();
    let Ok(serde_json::Value::Array(objects)) = serde_json::from_str::<serde_json::Value>(dump)
    else {
        return out;
    };
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
        if !s("api.bluez5.address").eq_ignore_ascii_case(address)
            || !s("api.bluez5.profile").starts_with("headset")
            || s("node.name").is_empty()
        {
            continue;
        }
        let node = Node {
            id,
            name: s("node.name").to_string(),
        };
        match s("media.class") {
            "Stream/Output/Audio" | "Audio/Source" => out.voice = Some(node),
            "Stream/Input/Audio" | "Audio/Sink" => out.to_phone = Some(node),
            _ => {}
        }
    }
    out
}

/// The `pw-metadata` command lines that pin the streams: the input to the
/// phone to `mic`, the phone's voice to `speaker` when named (else
/// WirePlumber's choice).
pub fn pins(mic: &str, speaker: Option<&str>, s: &PhoneStreams) -> Vec<Vec<String>> {
    let mut out = Vec::new();
    if let Some(n) = &s.to_phone {
        out.push(vec![n.id.to_string(), "target.object".into(), mic.into()]);
    }
    if let (Some(n), Some(sp)) = (&s.voice, speaker) {
        out.push(vec![n.id.to_string(), "target.object".into(), sp.into()]);
    }
    out
}

/// Runs a PipeWire tool (pw-dump, pw-metadata) for at most 3 s: its output.
pub async fn run_cmd(program: &std::path::Path, args: &[String]) -> Result<String, String> {
    let out = tokio::time::timeout(
        Duration::from_secs(3),
        tokio::process::Command::new(program)
            .args(args)
            .stdin(Stdio::null())
            .output(),
    )
    .await
    .map_err(|_| format!("{}: no answer in 3 s", program.display()))?
    .map_err(|e| format!("{}: {e}", program.display()))?;
    if !out.status.success() {
        return Err(format!(
            "{}: {} {}",
            program.display(),
            out.status,
            String::from_utf8_lossy(&out.stderr).trim()
        ));
    }
    Ok(String::from_utf8_lossy(&out.stdout).into_owned())
}

/// Starts and stops the call's audio path.
pub trait CallAudio: Send + Sync {
    /// A call is up on `address`'s phone.
    fn start(&self, address: &str);
    /// No call any more.
    fn stop(&self);
}

/// No call audio here (calls off, or the simulation).
pub struct NoCallAudio;

impl CallAudio for NoCallAudio {
    fn start(&self, _: &str) {}
    fn stop(&self) {}
}

pub struct PwCallAudio {
    pub mic: String,
    pub speaker: Option<String>,
    pub pw_dump: PathBuf,
    pub pw_metadata: PathBuf,
    task: Mutex<Option<tokio::task::JoinHandle<()>>>,
}

impl PwCallAudio {
    pub fn new(
        mic: String,
        speaker: Option<String>,
        pw_dump: PathBuf,
        pw_metadata: PathBuf,
    ) -> PwCallAudio {
        PwCallAudio {
            mic,
            speaker,
            pw_dump,
            pw_metadata,
            task: Mutex::new(None),
        }
    }

    /// Finds the phone's streams, then pins them once.
    async fn run(
        address: String,
        mic: String,
        speaker: Option<String>,
        pw_dump: PathBuf,
        pw_metadata: PathBuf,
    ) {
        let until = tokio::time::Instant::now() + FIND_FOR;
        let streams = loop {
            if let Ok(d) = run_cmd(&pw_dump, &[]).await {
                let s = phone_streams(&d, &address);
                if s.voice.is_some() && s.to_phone.is_some() {
                    break s;
                }
            }
            if tokio::time::Instant::now() >= until {
                eprintln!(
                    "[audio] call audio: the phone's hands-free streams didn't appear in {} s",
                    FIND_FOR.as_secs()
                );
                return;
            }
            tokio::time::sleep(FIND_EVERY).await;
        };
        for args in pins(&mic, speaker.as_deref(), &streams) {
            if let Err(e) = run_cmd(&pw_metadata, &args).await {
                eprintln!("[audio] call audio: pinning {}: {e}", args[0]);
            }
        }
        eprintln!(
            "[audio] call audio: {} → phone ({}), phone ({}) → {}",
            mic,
            streams.to_phone.as_ref().map_or("?", |n| n.name.as_str()),
            streams.voice.as_ref().map_or("?", |n| n.name.as_str()),
            speaker.as_deref().unwrap_or("WirePlumber's choice")
        );
    }
}

impl CallAudio for PwCallAudio {
    fn start(&self, address: &str) {
        let mut task = self
            .task
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        if let Some(t) = task.take() {
            t.abort();
        }
        *task = Some(tokio::spawn(Self::run(
            address.to_string(),
            self.mic.clone(),
            self.speaker.clone(),
            self.pw_dump.clone(),
            self.pw_metadata.clone(),
        )));
    }

    fn stop(&self) {
        // The streams go with the call; only a search still running stops.
        if let Some(t) = self
            .task
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .take()
        {
            t.abort();
        }
    }
}

#[cfg(test)]
#[allow(clippy::unwrap_used)]
mod tests {
    use super::*;

    const ADDR: &str = "B0:DE:31:1E:55:96";

    fn node(id: u64, name: &str, class: &str, addr: &str, profile: &str) -> String {
        format!(
            r#"{{"id":{id},"type":"PipeWire:Interface:Node","info":{{"props":{{"node.name":"{name}","media.class":"{class}","api.bluez5.address":"{addr}","api.bluez5.profile":"{profile}"}}}}}}"#
        )
    }

    /// Shaped like the bench Pi's pw-dump during a call (2026-11-14).
    #[test]
    fn finds_the_phones_hands_free_streams_only() {
        let dump = format!(
            "[{},{},{},{},{},{}]",
            r#"{"id":0,"type":"PipeWire:Interface:Core","info":{}}"#,
            node(
                120,
                "bluez_input.B0_DE_31_1E_55_96.2",
                "Stream/Output/Audio",
                ADDR,
                "a2dp-source"
            ),
            node(
                121,
                "bluez_input.B0_DE_31_1E_55_96.0",
                "Stream/Output/Audio",
                ADDR,
                "headset-audio-gateway"
            ),
            node(
                122,
                "bluez_output.B0_DE_31_1E_55_96.1",
                "Stream/Input/Audio",
                ADDR,
                "headset-audio-gateway"
            ),
            node(
                130,
                "bluez_input.other",
                "Stream/Output/Audio",
                "11:22:33:44:55:66",
                "headset-audio-gateway"
            ),
            r#"{"id":9,"type":"PipeWire:Interface:Node","info":{"props":{"node.name":"alsa_input.mic","media.class":"Audio/Source"}}}"#,
        );
        assert_eq!(
            phone_streams(&dump, &ADDR.to_ascii_lowercase()),
            PhoneStreams {
                voice: Some(Node {
                    id: 121,
                    name: "bluez_input.B0_DE_31_1E_55_96.0".into()
                }),
                to_phone: Some(Node {
                    id: 122,
                    name: "bluez_output.B0_DE_31_1E_55_96.1".into()
                }),
            }
        );
        assert_eq!(phone_streams(&dump, "11:22:33:44:55:66").to_phone, None);
        assert_eq!(phone_streams("not json", ADDR), PhoneStreams::default());
        // The other role's device nodes are taken the same way.
        let dev = format!(
            "[{},{}]",
            node(5, "v", "Audio/Source", ADDR, "headset-head-unit"),
            node(6, "p", "Audio/Sink", ADDR, "headset-head-unit")
        );
        assert_eq!(phone_streams(&dev, ADDR).to_phone.unwrap().id, 6);
    }

    #[test]
    fn the_pins() {
        let s = PhoneStreams {
            voice: Some(Node {
                id: 121,
                name: "v".into(),
            }),
            to_phone: Some(Node {
                id: 122,
                name: "p".into(),
            }),
        };
        assert_eq!(
            pins("mic", None, &s),
            vec![vec!["122", "target.object", "mic"]],
            "the voice is WirePlumber's choice without a speaker"
        );
        assert_eq!(
            pins("mic", Some("dac"), &s)[1],
            vec!["121", "target.object", "dac"]
        );
    }
}
