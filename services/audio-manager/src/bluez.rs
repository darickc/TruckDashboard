//! BlueZ over the system D-Bus (ADR-0039 decisions 2–4), with zbus.
//!
//! - Reads BlueZ's whole object tree (`GetManagedObjects`) at start, on each
//!   BlueZ signal (debounced) and every few seconds, and turns it into a
//!   [`Snapshot`] (`objects.rs`).
//! - Registers a pairing agent (`org.bluez.Agent1`, capability
//!   "DisplayYesNo") as the default agent. A phone's six-digit code goes to
//!   the dashboard; anything asked outside the pairing window is refused.
//! - Opens and closes the window through `Adapter1` (`Discoverable`,
//!   `Pairable` and their timeouts), and keeps it closed at start.
//! - Sends Play/Pause/Next/Previous to the phone's `MediaPlayer1`.
//! - Connects a paired phone (`Device1.Connect`), disconnecting any other
//!   connected phone first, disconnects one (`Device1.Disconnect`), and
//!   forgets one (`Adapter1.RemoveDevice`).
//!
//! Interfaces, properties and the agent's methods are from BlueZ 5.86's
//! doc/org.bluez.*.rst; the D-Bus policy that lets a non-root user do this is
//! BlueZ's src/bluetooth.conf (default context may send to org.bluez; root,
//! as bluetoothd, may call Agent1). Status: compiles and is linted on the
//! Mac; UNVERIFIED against a real BlueZ until the bench (ADR-0039).

use std::collections::BTreeMap;
use std::sync::{Arc, Mutex};
use std::time::Duration;

use tokio::sync::{Notify, mpsc, oneshot, watch};
use tokio::time::Instant;
use tokio_stream::StreamExt;
use zbus::zvariant::{ObjectPath, OwnedObjectPath, OwnedValue, Value as Z};
use zbus::{Connection, MatchRule, MessageStream, Proxy, fdo};

use crate::backend::Bluetooth;
use crate::model::{AgentAsk, AgentRequest, Command, Snapshot};
use crate::objects::{self, Objects, Value};

const BLUEZ: &str = "org.bluez";
const AGENT_PATH: &str = "/org/f250/audio/agent";
const CAPABILITY: &str = "DisplayYesNo";
/// How long a pairing question waits at most (BlueZ's own D-Bus call times
/// out about here too; the window's own limit is shorter).
const AGENT_WAIT: Duration = Duration::from_secs(60);
/// How long `Device1.Connect` may take (a phone out of range takes BlueZ's
/// page timeout, a few seconds; this is the backstop).
const CONNECT_WAIT: Duration = Duration::from_secs(30);

#[derive(Debug, zbus::DBusError)]
#[zbus(prefix = "org.bluez.Error")]
enum AgentError {
    #[zbus(error)]
    ZBus(zbus::Error),
    Rejected(String),
}

struct Agent {
    tx: mpsc::Sender<AgentRequest>,
    cancel: Arc<Notify>,
}

async fn device_prop<T>(conn: &Connection, device: &ObjectPath<'_>, name: &str) -> Option<T>
where
    T: TryFrom<OwnedValue>,
    <T as TryFrom<OwnedValue>>::Error: Into<zbus::Error>,
{
    let p = Proxy::new(conn, BLUEZ, device.to_owned(), "org.bluez.Device1")
        .await
        .ok()?;
    p.get_property::<T>(name).await.ok()
}

impl Agent {
    async fn ask(
        &self,
        conn: &Connection,
        device: &ObjectPath<'_>,
        ask: AgentAsk,
    ) -> Result<(), AgentError> {
        let address: String = device_prop(conn, device, "Address")
            .await
            .unwrap_or_else(|| device.to_string());
        let name: String = device_prop(conn, device, "Alias")
            .await
            .map(|s: String| objects::clean_text(&s, 64))
            .unwrap_or_else(|| address.clone());
        let (reply, rx) = oneshot::channel();
        self.tx
            .send(AgentRequest {
                address,
                name,
                ask,
                reply,
            })
            .await
            .map_err(|_| AgentError::Rejected("audio-manager is stopping".into()))?;
        tokio::select! {
            r = rx => match r {
                Ok(true) => Ok(()),
                _ => Err(AgentError::Rejected("refused".into())),
            },
            () = self.cancel.notified() => Err(AgentError::Rejected("cancelled".into())),
            () = tokio::time::sleep(AGENT_WAIT) => Err(AgentError::Rejected("no answer".into())),
        }
    }
}

#[zbus::interface(name = "org.bluez.Agent1")]
impl Agent {
    async fn release(&self) {
        eprintln!("[audio] BlueZ released the pairing agent");
    }

    async fn request_pin_code(&self, _device: OwnedObjectPath) -> Result<String, AgentError> {
        Err(AgentError::Rejected("PIN codes aren't supported".into()))
    }

    async fn display_pin_code(
        &self,
        _device: OwnedObjectPath,
        _pincode: String,
    ) -> Result<(), AgentError> {
        Err(AgentError::Rejected("PIN codes aren't supported".into()))
    }

    async fn request_passkey(&self, _device: OwnedObjectPath) -> Result<u32, AgentError> {
        Err(AgentError::Rejected(
            "typing a passkey isn't supported".into(),
        ))
    }

    async fn display_passkey(&self, _device: OwnedObjectPath, _passkey: u32, _entered: u16) {}

    async fn request_confirmation(
        &self,
        #[zbus(connection)] conn: &Connection,
        device: OwnedObjectPath,
        passkey: u32,
    ) -> Result<(), AgentError> {
        self.ask(conn, &device, AgentAsk::Confirm { passkey }).await
    }

    async fn request_authorization(
        &self,
        #[zbus(connection)] conn: &Connection,
        device: OwnedObjectPath,
    ) -> Result<(), AgentError> {
        self.ask(conn, &device, AgentAsk::Authorize).await
    }

    /// A profile connection from a device. Paired phones are allowed (a
    /// phone paired in the window is also trusted, so BlueZ doesn't ask for
    /// it again); anything else is refused.
    async fn authorize_service(
        &self,
        #[zbus(connection)] conn: &Connection,
        device: OwnedObjectPath,
        uuid: String,
    ) -> Result<(), AgentError> {
        let paired: bool = device_prop(conn, &device, "Paired").await.unwrap_or(false);
        if paired {
            Ok(())
        } else {
            eprintln!(
                "[audio] refused service {uuid} for unpaired {}",
                device.as_str()
            );
            Err(AgentError::Rejected("not paired".into()))
        }
    }

    async fn cancel(&self) {
        self.cancel.notify_waiters();
    }
}

fn conv(v: &Z<'_>) -> Value {
    match v {
        Z::Str(s) => Value::Str(s.as_str().to_string()),
        Z::U32(n) => Value::U32(*n),
        Z::U16(n) => Value::U32((*n).into()),
        Z::U8(n) => Value::U32((*n).into()),
        Z::Bool(b) => Value::Bool(*b),
        Z::ObjectPath(p) => Value::Path(p.as_str().to_string()),
        Z::Value(inner) => conv(inner),
        Z::Array(a) => {
            let strings: Option<Vec<String>> = a
                .iter()
                .map(|x| match x {
                    Z::Str(s) => Some(s.as_str().to_string()),
                    _ => None,
                })
                .collect();
            strings.map_or(Value::Other, Value::Strings)
        }
        Z::Dict(d) => {
            let mut out = BTreeMap::new();
            for (k, v) in d.iter() {
                if let Z::Str(k) = k {
                    out.insert(k.as_str().to_string(), conv(v));
                }
            }
            Value::Dict(out)
        }
        _ => Value::Other,
    }
}

fn convert(m: fdo::ManagedObjects) -> Objects {
    m.into_iter()
        .map(|(path, ifaces)| {
            (
                path.as_str().to_string(),
                ifaces
                    .into_iter()
                    .map(|(iface, props)| {
                        (
                            iface.as_str().to_string(),
                            props.iter().map(|(k, v)| (k.clone(), conv(v))).collect(),
                        )
                    })
                    .collect(),
            )
        })
        .collect()
}

#[derive(Default)]
struct Paths {
    adapter: Option<String>,
    player: Option<String>,
    devices: BTreeMap<String, String>,
}

pub struct Bluez {
    adapter: String,
    alias: String,
    snap: watch::Sender<Snapshot>,
    conn: Mutex<Option<Connection>>,
    paths: Mutex<Paths>,
    agent_tx: mpsc::Sender<AgentRequest>,
}

fn lock<T>(m: &Mutex<T>) -> std::sync::MutexGuard<'_, T> {
    m.lock().unwrap_or_else(std::sync::PoisonError::into_inner)
}

fn err(e: impl std::fmt::Display) -> String {
    e.to_string()
}

impl Bluez {
    /// Starts following BlueZ on the system bus. `adapter`: "hci0" (empty:
    /// the first); `alias`: the name phones see.
    pub fn start(adapter: &str, alias: &str, agent_tx: mpsc::Sender<AgentRequest>) -> Arc<Bluez> {
        let b = Arc::new(Bluez {
            adapter: adapter.into(),
            alias: alias.into(),
            snap: watch::Sender::new(Snapshot::unavailable("connecting to BlueZ")),
            conn: Mutex::new(None),
            paths: Mutex::default(),
            agent_tx,
        });
        tokio::spawn(Arc::clone(&b).run());
        b
    }

    async fn run(self: Arc<Self>) {
        loop {
            let e = self.session().await.err().unwrap_or_default();
            *lock(&self.conn) = None;
            *lock(&self.paths) = Paths::default();
            eprintln!("[audio] BlueZ: {e}; trying again in 5 s");
            self.snap
                .send_replace(Snapshot::unavailable(format!("Bluetooth unavailable: {e}")));
            tokio::time::sleep(Duration::from_secs(5)).await;
        }
    }

    async fn session(&self) -> Result<(), String> {
        let conn = Connection::system()
            .await
            .map_err(|e| format!("no system D-Bus ({e})"))?;
        let cancel = Arc::new(Notify::new());
        conn.object_server()
            .at(
                AGENT_PATH,
                Agent {
                    tx: self.agent_tx.clone(),
                    cancel,
                },
            )
            .await
            .map_err(err)?;

        let dbus = fdo::DBusProxy::new(&conn).await.map_err(err)?;
        let mut owner = dbus
            .receive_name_owner_changed_with_args(&[(0, BLUEZ)])
            .await
            .map_err(err)?;
        let props_rule = MatchRule::builder()
            .msg_type(zbus::message::Type::Signal)
            .path_namespace("/org/bluez")
            .map_err(err)?
            .build();
        let om_rule = MatchRule::builder()
            .msg_type(zbus::message::Type::Signal)
            .interface("org.freedesktop.DBus.ObjectManager")
            .map_err(err)?
            .build();
        let mut props = MessageStream::for_match_rule(props_rule, &conn, Some(64))
            .await
            .map_err(err)?;
        let mut om = MessageStream::for_match_rule(om_rule, &conn, Some(64))
            .await
            .map_err(err)?;

        let manager = Proxy::new(&conn, BLUEZ, "/org/bluez", "org.bluez.AgentManager1")
            .await
            .map_err(err)?;
        let agent = ObjectPath::try_from(AGENT_PATH).map_err(err)?;
        manager
            .call_method("RegisterAgent", &(&agent, CAPABILITY))
            .await
            .map_err(|e| format!("BlueZ isn't answering ({e})"))?;
        if let Err(e) = manager.call_method("RequestDefaultAgent", &(&agent,)).await {
            eprintln!("[audio] BlueZ: not the default pairing agent ({e})");
        }
        *lock(&self.conn) = Some(conn.clone());

        self.refresh(&conn).await?;
        self.close_at_start(&conn).await;
        eprintln!("[audio] BlueZ: agent registered ({CAPABILITY}); pairing window closed");

        loop {
            tokio::select! {
                m = props.next() => {
                    if m.is_none() { return Err("the D-Bus connection closed".into()); }
                    self.debounce(&mut props, &mut om).await;
                }
                m = om.next() => {
                    if m.is_none() { return Err("the D-Bus connection closed".into()); }
                    self.debounce(&mut props, &mut om).await;
                }
                _ = owner.next() => {
                    // bluetoothd stopped or restarted: its agent registration
                    // is gone; start again on a new connection.
                    return Err("bluetoothd restarted".into());
                }
                () = tokio::time::sleep(Duration::from_secs(5)) => {}
            }
            self.refresh(&conn).await?;
        }
    }

    /// Lets a burst of signals settle before reading the tree again.
    async fn debounce(&self, a: &mut MessageStream, b: &mut MessageStream) {
        let until = tokio::time::sleep(Duration::from_millis(150));
        tokio::pin!(until);
        loop {
            tokio::select! {
                () = &mut until => return,
                _ = a.next() => {}
                _ = b.next() => {}
            }
        }
    }

    async fn refresh(&self, conn: &Connection) -> Result<(), String> {
        let om = fdo::ObjectManagerProxy::builder(conn)
            .destination(BLUEZ)
            .map_err(err)?
            .path("/")
            .map_err(err)?
            .build()
            .await
            .map_err(err)?;
        let objs = convert(
            om.get_managed_objects()
                .await
                .map_err(|e| format!("BlueZ isn't answering ({e})"))?,
        );
        let snap = objects::snapshot(&objs, &self.adapter, Instant::now());
        {
            let mut p = lock(&self.paths);
            p.adapter = objects::adapter_path(&objs, &self.adapter);
            p.player = snap.player.as_ref().map(|pl| pl.path.clone());
            p.devices = objs
                .iter()
                .filter_map(|(path, i)| {
                    let d = i.get(objects::DEVICE)?;
                    match d.get("Address") {
                        Some(Value::Str(a)) => Some((a.clone(), path.clone())),
                        _ => None,
                    }
                })
                .collect();
        }
        self.snap.send_replace(snap);
        Ok(())
    }

    fn adapter_proxy_path(&self) -> Result<(Connection, String), String> {
        let conn = lock(&self.conn).clone().ok_or("BlueZ isn't connected")?;
        let path = lock(&self.paths)
            .adapter
            .clone()
            .ok_or("no Bluetooth adapter")?;
        Ok((conn, path))
    }

    /// At start: the name phones see, and the window closed (a previous
    /// audio-manager may have died with it open).
    async fn close_at_start(&self, conn: &Connection) {
        let Some(path) = lock(&self.paths).adapter.clone() else {
            return;
        };
        let Ok(a) = Proxy::new(conn, BLUEZ, path, "org.bluez.Adapter1").await else {
            return;
        };
        if !self.alias.is_empty()
            && let Err(e) = a.set_property("Alias", self.alias.as_str()).await
        {
            eprintln!("[audio] BlueZ: setting the name: {e}");
        }
        for (p, v) in [("Discoverable", false), ("Pairable", false)] {
            if let Err(e) = a.set_property(p, v).await {
                eprintln!("[audio] BlueZ: {p}=false: {e}");
            }
        }
    }
}

#[tonic::async_trait]
impl Bluetooth for Arc<Bluez> {
    fn snapshot(&self) -> watch::Receiver<Snapshot> {
        self.snap.subscribe()
    }

    async fn set_pairing(&self, on: bool, timeout_s: u32) -> Result<(), String> {
        let (conn, path) = self.adapter_proxy_path()?;
        let a = Proxy::new(&conn, BLUEZ, path, "org.bluez.Adapter1")
            .await
            .map_err(err)?;
        if on {
            // BlueZ's own timeouts close it even if audio-manager dies.
            a.set_property("DiscoverableTimeout", timeout_s)
                .await
                .map_err(err)?;
            a.set_property("PairableTimeout", timeout_s)
                .await
                .map_err(err)?;
            a.set_property("Pairable", true).await.map_err(err)?;
            a.set_property("Discoverable", true).await.map_err(err)?;
        } else {
            let d = a.set_property("Discoverable", false).await.map_err(err);
            let p = a.set_property("Pairable", false).await.map_err(err);
            d.and(p)?;
        }
        let _ = self.refresh(&conn).await;
        Ok(())
    }

    async fn control(&self, cmd: Command) -> Result<(), String> {
        let conn = lock(&self.conn).clone().ok_or("BlueZ isn't connected")?;
        let player = lock(&self.paths)
            .player
            .clone()
            .ok_or("the phone has no player")?;
        let p = Proxy::new(&conn, BLUEZ, player, "org.bluez.MediaPlayer1")
            .await
            .map_err(err)?;
        p.call_method(cmd.method(), &())
            .await
            .map_err(|e| format!("the phone refused {}: {e}", cmd.method()))?;
        let _ = self.refresh(&conn).await;
        Ok(())
    }

    async fn trust(&self, address: &str) -> Result<(), String> {
        let conn = lock(&self.conn).clone().ok_or("BlueZ isn't connected")?;
        let path = lock(&self.paths)
            .devices
            .get(address)
            .cloned()
            .ok_or("no such device")?;
        let d = Proxy::new(&conn, BLUEZ, path, "org.bluez.Device1")
            .await
            .map_err(err)?;
        d.set_property("Trusted", true).await.map_err(err)
    }

    async fn connect(&self, address: &str) -> Result<(), String> {
        let conn = lock(&self.conn).clone().ok_or("BlueZ isn't connected")?;
        let (target, others) = {
            let p = lock(&self.paths);
            let target = p
                .devices
                .get(address)
                .cloned()
                .ok_or("BlueZ doesn't know that phone")?;
            let snap = self.snap.borrow();
            let others: Vec<String> = snap
                .phones
                .iter()
                .filter(|ph| ph.connected && ph.address != address)
                .filter_map(|ph| p.devices.get(&ph.address).cloned())
                .collect();
            (target, others)
        };
        for path in others {
            let d = Proxy::new(&conn, BLUEZ, path.as_str(), "org.bluez.Device1")
                .await
                .map_err(err)?;
            if let Err(e) = d.call_method("Disconnect", &()).await {
                eprintln!("[audio] BlueZ: disconnecting {path}: {e}");
            }
        }
        let d = Proxy::new(&conn, BLUEZ, target, "org.bluez.Device1")
            .await
            .map_err(err)?;
        let r = tokio::time::timeout(CONNECT_WAIT, d.call_method("Connect", &())).await;
        let _ = self.refresh(&conn).await;
        match r {
            Err(_) => Err(format!("no answer in {} s", CONNECT_WAIT.as_secs())),
            Ok(Err(e)) => Err(bluez_reason(&e)),
            Ok(Ok(_)) => Ok(()),
        }
    }

    async fn disconnect(&self, address: &str) -> Result<(), String> {
        let conn = lock(&self.conn).clone().ok_or("BlueZ isn't connected")?;
        let path = lock(&self.paths)
            .devices
            .get(address)
            .cloned()
            .ok_or("BlueZ doesn't know that phone")?;
        let d = Proxy::new(&conn, BLUEZ, path, "org.bluez.Device1")
            .await
            .map_err(err)?;
        let r = tokio::time::timeout(CONNECT_WAIT, d.call_method("Disconnect", &())).await;
        let _ = self.refresh(&conn).await;
        match r {
            Err(_) => Err(format!("no answer in {} s", CONNECT_WAIT.as_secs())),
            Ok(Err(e)) => Err(bluez_reason(&e)),
            Ok(Ok(_)) => Ok(()),
        }
    }

    async fn remove(&self, address: &str) -> Result<(), String> {
        let (conn, adapter) = self.adapter_proxy_path()?;
        let device = lock(&self.paths)
            .devices
            .get(address)
            .cloned()
            .ok_or("BlueZ doesn't know that phone")?;
        let a = Proxy::new(&conn, BLUEZ, adapter, "org.bluez.Adapter1")
            .await
            .map_err(err)?;
        let device = ObjectPath::try_from(device.as_str()).map_err(err)?;
        let r =
            tokio::time::timeout(CONNECT_WAIT, a.call_method("RemoveDevice", &(&device,))).await;
        let _ = self.refresh(&conn).await;
        match r {
            Err(_) => Err(format!("no answer in {} s", CONNECT_WAIT.as_secs())),
            Ok(Err(e)) => Err(bluez_reason(&e)),
            Ok(Ok(_)) => Ok(()),
        }
    }
}

/// BlueZ's error, shorter: its name without the prefix, and its message.
fn bluez_reason(e: &zbus::Error) -> String {
    match e {
        zbus::Error::MethodError(name, msg, _) => {
            let name = name.as_str().trim_start_matches("org.bluez.Error.");
            match msg {
                Some(m) if !m.is_empty() => format!("{name}: {m}"),
                _ => name.to_string(),
            }
        }
        other => other.to_string(),
    }
}

#[cfg(test)]
#[allow(clippy::unwrap_used)]
mod tests {
    use super::*;
    use std::collections::HashMap;

    #[test]
    fn dbus_values_convert() {
        assert_eq!(conv(&Z::from("x")), Value::Str("x".into()));
        assert_eq!(conv(&Z::from(7u32)), Value::U32(7));
        assert_eq!(conv(&Z::from(127u16)), Value::U32(127));
        assert_eq!(conv(&Z::from(true)), Value::Bool(true));
        assert_eq!(
            conv(&Z::from(ObjectPath::try_from("/org/bluez/hci0").unwrap())),
            Value::Path("/org/bluez/hci0".into())
        );
        assert_eq!(
            conv(&Z::from(vec!["a".to_string(), "b".to_string()])),
            Value::Strings(vec!["a".into(), "b".into()])
        );
        let mut track: HashMap<String, Z<'_>> = HashMap::new();
        track.insert("Title".into(), Z::from("Song"));
        track.insert("Duration".into(), Z::from(1000u32));
        let v = conv(&Z::from(track));
        let Value::Dict(d) = v else { panic!("{v:?}") };
        assert_eq!(d["Title"], Value::Str("Song".into()));
        assert_eq!(d["Duration"], Value::U32(1000));
        assert_eq!(conv(&Z::from(1.5f64)), Value::Other);
    }
}
