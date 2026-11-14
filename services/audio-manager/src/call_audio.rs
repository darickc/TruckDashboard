//! The call's audio path (ADR-0045 decision 3, first cut): while a call is
//! up, the microphone goes to the phone and the phone's voice to the
//! speakers, through two `pw-loopback`s audio-manager runs and stops.
//!
//! PipeWire's bluez5 plugin makes the call's nodes when the phone opens its
//! call audio (SCO): a source (the phone's voice) and a sink (to the phone),
//! each with `api.bluez5.address` and `api.bluez5.profile` (PipeWire 1.6.8
//! `spa/plugins/bluez5/bluez5-device.c`: "headset-head-unit" or
//! "headset-audio-gateway" for hands-free, "a2dp-…" for music). They are
//! found in `pw-dump`'s output by the phone's address and a `headset`
//! profile, so the music nodes are never taken; their `node.name`s are the
//! loopbacks' targets.
//!
//! No echo cancellation yet (WebRTC isn't in the image: spike S3), and the
//! voice goes to the default sink unless `--call-speaker` names one.
//! Status: the matching is tested on hand-written `pw-dump` output [SIM];
//! the loopbacks on the Pi are UNVERIFIED until a bench call.

use std::path::PathBuf;
use std::process::Stdio;
use std::sync::Mutex;
use std::time::Duration;

/// How long to look for the call's nodes after a call starts (the phone
/// opens its call audio when it rings in-band or the call connects).
const FIND_FOR: Duration = Duration::from_secs(60);
const FIND_EVERY: Duration = Duration::from_millis(500);

/// The phone's hands-free nodes: its voice (a source) and the way to it (a
/// sink), by `node.name`.
#[derive(Debug, Clone, PartialEq, Eq, Default)]
pub struct PhoneNodes {
    pub voice: Option<String>,
    pub to_phone: Option<String>,
}

/// `address`'s hands-free nodes in `pw-dump`'s JSON. Music (A2DP) nodes and
/// other phones' are left out.
pub fn phone_nodes(dump: &str, address: &str) -> PhoneNodes {
    let mut out = PhoneNodes::default();
    let Ok(serde_json::Value::Array(objects)) = serde_json::from_str::<serde_json::Value>(dump)
    else {
        return out;
    };
    for o in &objects {
        if o.get("type").and_then(|t| t.as_str()) != Some("PipeWire:Interface:Node") {
            continue;
        }
        let Some(props) = o.pointer("/info/props") else {
            continue;
        };
        let s = |k: &str| props.get(k).and_then(|v| v.as_str()).unwrap_or("");
        if !s("api.bluez5.address").eq_ignore_ascii_case(address)
            || !s("api.bluez5.profile").starts_with("headset")
        {
            continue;
        }
        let name = s("node.name");
        if name.is_empty() {
            continue;
        }
        match s("media.class") {
            "Audio/Source" => out.voice = Some(name.to_string()),
            "Audio/Sink" => out.to_phone = Some(name.to_string()),
            _ => {}
        }
    }
    out
}

/// The two `pw-loopback` command lines: the microphone to the phone, and
/// the phone's voice to `speaker` (None: the default sink). Mono both ways:
/// hands-free audio is one channel (CVSD or mSBC).
pub fn loopbacks(mic: &str, speaker: Option<&str>, n: &PhoneNodes) -> Vec<Vec<String>> {
    let mut out = Vec::new();
    let mono = ["-c", "1", "-m", "[ MONO ]"];
    if let Some(to_phone) = &n.to_phone {
        let mut a: Vec<String> = vec!["-n".into(), "f250-call-mic".into()];
        a.extend(mono.iter().map(|s| (*s).to_string()));
        a.extend(["-C".into(), mic.into(), "-P".into(), to_phone.clone()]);
        out.push(a);
    }
    if let Some(voice) = &n.voice {
        let mut a: Vec<String> = vec!["-n".into(), "f250-call-voice".into()];
        a.extend(mono.iter().map(|s| (*s).to_string()));
        a.extend(["-C".into(), voice.clone()]);
        if let Some(sp) = speaker {
            a.extend(["-P".into(), sp.into()]);
        }
        out.push(a);
    }
    out
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
    pub pw_loopback: PathBuf,
    task: Mutex<Option<tokio::task::JoinHandle<()>>>,
}

impl PwCallAudio {
    pub fn new(
        mic: String,
        speaker: Option<String>,
        pw_dump: PathBuf,
        pw_loopback: PathBuf,
    ) -> PwCallAudio {
        PwCallAudio {
            mic,
            speaker,
            pw_dump,
            pw_loopback,
            task: Mutex::new(None),
        }
    }

    async fn dump(pw_dump: &PathBuf) -> Option<String> {
        let out = tokio::time::timeout(
            Duration::from_secs(3),
            tokio::process::Command::new(pw_dump)
                .stdin(Stdio::null())
                .stderr(Stdio::null())
                .output(),
        )
        .await
        .ok()?
        .ok()?;
        out.status
            .success()
            .then(|| String::from_utf8_lossy(&out.stdout).into_owned())
    }

    /// Finds the phone's nodes, then keeps the loopbacks running until
    /// aborted (their children are killed with the task).
    async fn run(
        address: String,
        mic: String,
        speaker: Option<String>,
        pw_dump: PathBuf,
        pw_loopback: PathBuf,
    ) {
        let until = tokio::time::Instant::now() + FIND_FOR;
        let nodes = loop {
            if let Some(d) = Self::dump(&pw_dump).await {
                let n = phone_nodes(&d, &address);
                if n.voice.is_some() && n.to_phone.is_some() {
                    break n;
                }
            }
            if tokio::time::Instant::now() >= until {
                eprintln!(
                    "[audio] call audio: the phone's hands-free nodes didn't appear in {} s",
                    FIND_FOR.as_secs()
                );
                return;
            }
            tokio::time::sleep(FIND_EVERY).await;
        };
        let mut children = Vec::new();
        for args in loopbacks(&mic, speaker.as_deref(), &nodes) {
            match tokio::process::Command::new(&pw_loopback)
                .args(&args)
                .stdin(Stdio::null())
                .stdout(Stdio::null())
                .kill_on_drop(true)
                .spawn()
            {
                Ok(c) => children.push(c),
                Err(e) => eprintln!("[audio] call audio: {}: {e}", pw_loopback.display()),
            }
        }
        eprintln!(
            "[audio] call audio: {} → phone ({}), phone ({}) → {}",
            mic,
            nodes.to_phone.as_deref().unwrap_or("?"),
            nodes.voice.as_deref().unwrap_or("?"),
            speaker.as_deref().unwrap_or("the default sink")
        );
        // Kept until the task is aborted; a loopback that ends is said.
        for mut c in children {
            if let Ok(status) = c.wait().await {
                eprintln!("[audio] call audio: a loopback ended ({status})");
            }
        }
        std::future::pending::<()>().await;
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
            self.pw_loopback.clone(),
        )));
    }

    fn stop(&self) {
        if let Some(t) = self
            .task
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .take()
        {
            t.abort();
            eprintln!("[audio] call audio: stopped");
        }
    }
}

#[cfg(test)]
#[allow(clippy::unwrap_used)]
mod tests {
    use super::*;

    const ADDR: &str = "B0:DE:31:1E:55:96";

    fn node(name: &str, class: &str, addr: &str, profile: &str) -> String {
        format!(
            r#"{{"id":1,"type":"PipeWire:Interface:Node","info":{{"props":{{"node.name":"{name}","media.class":"{class}","api.bluez5.address":"{addr}","api.bluez5.profile":"{profile}"}}}}}}"#
        )
    }

    #[test]
    fn finds_the_phones_hands_free_nodes_only() {
        let dump = format!(
            "[{},{},{},{},{},{}]",
            r#"{"id":0,"type":"PipeWire:Interface:Core","info":{}}"#,
            node("bluez_input.music", "Audio/Source", ADDR, "a2dp-sink"),
            node(
                "bluez_input.voice",
                "Audio/Source",
                ADDR,
                "headset-audio-gateway"
            ),
            node(
                "bluez_output.to_phone",
                "Audio/Sink",
                ADDR,
                "headset-audio-gateway"
            ),
            node(
                "bluez_input.other",
                "Audio/Source",
                "11:22:33:44:55:66",
                "headset-head-unit"
            ),
            r#"{"id":9,"type":"PipeWire:Interface:Node","info":{"props":{"node.name":"alsa_input.mic","media.class":"Audio/Source"}}}"#,
        );
        assert_eq!(
            phone_nodes(&dump, &ADDR.to_ascii_lowercase()),
            PhoneNodes {
                voice: Some("bluez_input.voice".into()),
                to_phone: Some("bluez_output.to_phone".into()),
            }
        );
        assert_eq!(phone_nodes(&dump, "11:22:33:44:55:66").to_phone, None);
        assert_eq!(phone_nodes("not json", ADDR), PhoneNodes::default());
    }

    #[test]
    fn the_loopbacks() {
        let n = PhoneNodes {
            voice: Some("v".into()),
            to_phone: Some("p".into()),
        };
        assert_eq!(
            loopbacks("mic", None, &n),
            vec![
                vec![
                    "-n",
                    "f250-call-mic",
                    "-c",
                    "1",
                    "-m",
                    "[ MONO ]",
                    "-C",
                    "mic",
                    "-P",
                    "p"
                ],
                vec![
                    "-n",
                    "f250-call-voice",
                    "-c",
                    "1",
                    "-m",
                    "[ MONO ]",
                    "-C",
                    "v"
                ],
            ]
        );
        assert_eq!(loopbacks("mic", Some("dac"), &n)[1].last().unwrap(), "dac");
    }
}
