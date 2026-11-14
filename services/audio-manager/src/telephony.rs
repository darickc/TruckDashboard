//! Phone calls behind a trait (ADR-0045): PipeWire's Telephony service over
//! the system D-Bus on the Pi ([`PwTelephony`]), nothing when calls aren't
//! configured ([`NoCalls`]), a simulated phone on the Mac and in the tests
//! (`sim_calls.rs`).
//!
//! [`PwTelephony`] reads the whole Telephony tree (`calls.rs`) at start, on
//! each signal from the service (debounced), when its owner changes, and
//! every few seconds; answers and hangs up with `Call1.Answer` and
//! `Call1.Hangup`. The call microphone is muted with `pw-cli set-param
//! <node> Props '{ mute = true }'`.
//!
//! Status: the D-Bus side follows what the bench Pi showed on 2026-11-14
//! (spike S1: the gateway and its call in the ObjectManager trees, Answer and
//! Hangup over the system bus with `busctl`), but this client itself has
//! only run against fakes [SIM]. Muting the microphone node with `pw-cli` is
//! UNVERIFIED (no call microphone yet: spikes S3, S4).

use std::path::PathBuf;
use std::process::Stdio;
use std::sync::{Arc, Mutex};
use std::time::Duration;

use tokio::sync::watch;
use tokio_stream::StreamExt;
use zbus::{Connection, MatchRule, MessageStream, Proxy, fdo};

use crate::calls::{self, CallSnapshot};
use crate::objects::Objects;

/// How long Answer or Hangup may take (the phone answers over RFCOMM in
/// well under a second on the bench; this is the backstop).
const CALL_WAIT: Duration = Duration::from_secs(10);

#[tonic::async_trait]
pub trait Telephony: Send + Sync {
    /// The calls now, replaced as a whole on each change.
    fn calls(&self) -> watch::Receiver<CallSnapshot>;
    /// Answers the call at `path` (it is incoming).
    async fn answer(&self, path: &str) -> Result<(), String>;
    /// Ends the call at `path`: declines a ringing one, hangs up any other.
    async fn hang_up(&self, path: &str) -> Result<(), String>;
    /// Mutes or unmutes the call microphone.
    async fn set_mic_muted(&self, muted: bool) -> Result<(), String>;
}

/// Calls aren't configured: they stay on the phone, and the screen says why.
pub struct NoCalls {
    snap: watch::Sender<CallSnapshot>,
}

impl NoCalls {
    pub fn new(why: impl Into<String>) -> NoCalls {
        NoCalls {
            snap: watch::Sender::new(CallSnapshot::off(why)),
        }
    }
}

#[tonic::async_trait]
impl Telephony for NoCalls {
    fn calls(&self) -> watch::Receiver<CallSnapshot> {
        self.snap.subscribe()
    }
    async fn answer(&self, _: &str) -> Result<(), String> {
        Err("Calls aren't set up on this head unit.".into())
    }
    async fn hang_up(&self, _: &str) -> Result<(), String> {
        Err("Calls aren't set up on this head unit.".into())
    }
    async fn set_mic_muted(&self, _: bool) -> Result<(), String> {
        Err("Calls aren't set up on this head unit.".into())
    }
}

/// The call microphone, muted with `pw-cli`.
#[derive(Debug, Clone)]
pub struct Mic {
    /// The PipeWire source node's name (`node.name`).
    pub node: String,
    pub pw_cli: PathBuf,
}

impl Mic {
    /// `pw-cli set-param <node> Props <this>`: the `mute` property every
    /// PipeWire audio node's Props carries (spa audioconvert). UNVERIFIED on
    /// the call microphone (S3).
    pub fn props(muted: bool) -> String {
        format!("{{ mute = {muted} }}")
    }

    pub async fn set_muted(&self, muted: bool) -> Result<(), String> {
        let out = tokio::time::timeout(
            Duration::from_secs(3),
            tokio::process::Command::new(&self.pw_cli)
                .args(["set-param", &self.node, "Props", &Mic::props(muted)])
                .stdin(Stdio::null())
                .output(),
        )
        .await
        .map_err(|_| "pw-cli didn't answer in 3 s".to_string())?
        .map_err(|e| format!("{}: {e}", self.pw_cli.display()))?;
        let err = String::from_utf8_lossy(&out.stderr);
        if !out.status.success() || err.contains("rror") {
            return Err(format!("pw-cli: {} {}", out.status, err.trim()));
        }
        Ok(())
    }
}

pub struct PwTelephony {
    mic: Mic,
    snap: watch::Sender<CallSnapshot>,
    conn: Mutex<Option<Connection>>,
}

fn lock<T>(m: &Mutex<T>) -> std::sync::MutexGuard<'_, T> {
    m.lock().unwrap_or_else(std::sync::PoisonError::into_inner)
}

fn err(e: impl std::fmt::Display) -> String {
    e.to_string()
}

/// Why the service doesn't answer, in words for the screen.
const NOT_RUNNING: &str = "the hands-free service isn't running (no org.pipewire.Telephony on \
                           the system bus: is the hfp_hf role on?)";

impl PwTelephony {
    pub fn start(mic: Mic) -> Arc<PwTelephony> {
        let t = Arc::new(PwTelephony {
            mic,
            snap: watch::Sender::new(CallSnapshot::unavailable("connecting to the system D-Bus")),
            conn: Mutex::new(None),
        });
        tokio::spawn(Arc::clone(&t).run());
        t
    }

    async fn run(self: Arc<Self>) {
        loop {
            let e = self.session().await.err().unwrap_or_default();
            *lock(&self.conn) = None;
            eprintln!("[audio] calls: {e}; trying again in 5 s");
            self.snap.send_replace(CallSnapshot::unavailable(e));
            tokio::time::sleep(Duration::from_secs(5)).await;
        }
    }

    async fn session(&self) -> Result<(), String> {
        let conn = Connection::system()
            .await
            .map_err(|e| format!("no system D-Bus ({e})"))?;
        let dbus = fdo::DBusProxy::new(&conn).await.map_err(err)?;
        let mut owner = dbus
            .receive_name_owner_changed_with_args(&[(0, calls::SERVICE)])
            .await
            .map_err(err)?;
        let rule = MatchRule::builder()
            .msg_type(zbus::message::Type::Signal)
            .path_namespace(calls::MANAGER_PATH)
            .map_err(err)?
            .build();
        let mut signals = MessageStream::for_match_rule(rule, &conn, Some(64))
            .await
            .map_err(err)?;
        *lock(&self.conn) = Some(conn.clone());
        self.refresh(&conn).await;
        loop {
            tokio::select! {
                m = signals.next() => {
                    if m.is_none() { return Err("the D-Bus connection closed".into()); }
                    // A burst (a call's state and its caller ID) settles first.
                    let settle = tokio::time::sleep(Duration::from_millis(100));
                    tokio::pin!(settle);
                    loop {
                        tokio::select! {
                            () = &mut settle => break,
                            _ = signals.next() => {}
                        }
                    }
                }
                _ = owner.next() => {}
                () = tokio::time::sleep(Duration::from_secs(3)) => {}
            }
            self.refresh(&conn).await;
        }
    }

    async fn managed(conn: &Connection, path: &str) -> fdo::Result<fdo::ManagedObjects> {
        let om = fdo::ObjectManagerProxy::builder(conn)
            .destination(calls::SERVICE)?
            .path(path.to_string())?
            .build()
            .await?;
        om.get_managed_objects().await
    }

    /// Reads the manager's tree and each gateway's, and publishes them.
    async fn refresh(&self, conn: &Connection) {
        let snap = match Self::managed(conn, calls::MANAGER_PATH).await {
            Err(fdo::Error::ServiceUnknown(_) | fdo::Error::NameHasNoOwner(_)) => {
                CallSnapshot::unavailable(NOT_RUNNING)
            }
            Err(e) => CallSnapshot::unavailable(format!("the hands-free service: {e}")),
            Ok(m) => {
                let mut objs: Objects = crate::bluez::convert(m);
                let gateways: Vec<String> = objs
                    .iter()
                    .filter(|(_, i)| i.contains_key(calls::GATEWAY))
                    .map(|(p, _)| p.clone())
                    .collect();
                for g in gateways {
                    match Self::managed(conn, &g).await {
                        Ok(m) => objs.extend(crate::bluez::convert(m)),
                        // Gone between the two reads: the next refresh has it.
                        Err(e) => eprintln!("[audio] calls: reading {g}: {e}"),
                    }
                }
                let (gateways, calls) = calls::from_objects(&objs);
                CallSnapshot {
                    availability: calls::Availability::Ready,
                    gateways,
                    calls,
                }
            }
        };
        self.snap.send_if_modified(|old| {
            if *old == snap {
                false
            } else {
                *old = snap;
                true
            }
        });
    }

    async fn call(&self, path: &str, method: &str) -> Result<(), String> {
        let conn = lock(&self.conn)
            .clone()
            .ok_or("the hands-free service isn't connected")?;
        let p = Proxy::new(&conn, calls::SERVICE, path.to_string(), calls::CALL)
            .await
            .map_err(err)?;
        let r = tokio::time::timeout(CALL_WAIT, p.call_method(method, &())).await;
        self.refresh(&conn).await;
        match r {
            Err(_) => Err(format!(
                "the phone didn't answer in {} s",
                CALL_WAIT.as_secs()
            )),
            Ok(Err(e)) => Err(reason(&e)),
            Ok(Ok(_)) => Ok(()),
        }
    }
}

/// The service's error, shorter: its name without the prefix, and its
/// message.
fn reason(e: &zbus::Error) -> String {
    match e {
        zbus::Error::MethodError(name, msg, _) => {
            let name = name
                .as_str()
                .trim_start_matches("org.pipewire.Telephony.Error.")
                .trim_start_matches("org.freedesktop.DBus.Error.");
            match msg {
                Some(m) if !m.is_empty() => format!("{name}: {m}"),
                _ => name.to_string(),
            }
        }
        other => other.to_string(),
    }
}

#[tonic::async_trait]
impl Telephony for Arc<PwTelephony> {
    fn calls(&self) -> watch::Receiver<CallSnapshot> {
        self.snap.subscribe()
    }

    async fn answer(&self, path: &str) -> Result<(), String> {
        self.call(path, "Answer").await
    }

    async fn hang_up(&self, path: &str) -> Result<(), String> {
        self.call(path, "Hangup").await
    }

    async fn set_mic_muted(&self, muted: bool) -> Result<(), String> {
        self.mic.set_muted(muted).await
    }
}

#[cfg(test)]
#[allow(clippy::unwrap_used)]
mod tests {
    use super::*;

    #[test]
    fn mute_props() {
        assert_eq!(Mic::props(true), "{ mute = true }");
        assert_eq!(Mic::props(false), "{ mute = false }");
    }

    #[tokio::test]
    async fn the_mic_is_muted_with_pw_cli() {
        let dir = std::env::temp_dir().join(format!("f250-audio-mic-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).unwrap();
        let log = dir.join("args");
        let fake = dir.join("pw-cli");
        std::fs::write(
            &fake,
            format!("#!/bin/sh\nprintf '%s|' \"$@\" > {}\n", log.display()),
        )
        .unwrap();
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            std::fs::set_permissions(&fake, std::fs::Permissions::from_mode(0o755)).unwrap();
        }
        let mic = Mic {
            node: "usb-mic".into(),
            pw_cli: fake.clone(),
        };
        mic.set_muted(true).await.unwrap();
        assert_eq!(
            std::fs::read_to_string(&log).unwrap(),
            "set-param|usb-mic|Props|{ mute = true }|"
        );
        // A pw-cli that fails says so.
        std::fs::write(
            &fake,
            "#!/bin/sh\necho 'Error: no such object' >&2\nexit 1\n",
        )
        .unwrap();
        let e = mic.set_muted(false).await.unwrap_err();
        assert!(e.contains("no such object"), "{e}");
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[tokio::test]
    async fn no_calls_says_why() {
        let n = NoCalls::new("no call microphone is configured");
        assert_eq!(
            n.calls().borrow().availability,
            calls::Availability::Off("no call microphone is configured".into())
        );
        assert!(n.answer("/x").await.is_err());
    }
}
