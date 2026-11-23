//! connman on the system D-Bus (ADR-0052): its `net.connman` Manager,
//! Technology and Service objects, and an agent (`net.connman.Agent`) that
//! answers connman's passphrase request with the one typed for that network.
//! The passphrase is held only while that one Connect is running; connman
//! keeps it for a network that joins.
//!
//! connman has no `org.freedesktop.DBus.Properties`: everything is read with
//! its own GetProperties/GetServices/GetTechnologies, so proxies are built
//! without property caching. The calls follow connman 2.0's doc/*-api.txt;
//! UNVERIFIED on the Pi's image until checked there.

use std::collections::{BTreeMap, HashMap};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex};
use std::time::Duration;

use f250_proto::network::v1 as pb;
use zbus::proxy::CacheProperties;
use zbus::zvariant::{OwnedObjectPath, OwnedValue, Value as Z};
use zbus::{Connection, Proxy};

use crate::Backend;
use crate::model::{self, Prop, Props};

const CONNMAN: &str = "net.connman";
const AGENT_PATH: &str = "/org/f250/network/agent";
/// Joining can take a while (association, DHCP); connman answers Connect
/// only then.
const CONNECT_WAIT: Duration = Duration::from_secs(60);
const SCAN_WAIT: Duration = Duration::from_secs(30);

#[derive(Debug, zbus::DBusError)]
#[zbus(prefix = "net.connman.Agent.Error")]
enum AgentError {
    #[zbus(error)]
    ZBus(zbus::Error),
    Canceled(String),
}

/// What the agent and the backend share.
#[derive(Default)]
struct Shared {
    /// Passphrases for Connect calls in progress, by service path.
    pending: Mutex<HashMap<String, String>>,
    /// The last error connman reported to the agent, by service path.
    reported: Mutex<HashMap<String, String>>,
}

struct Agent {
    shared: Arc<Shared>,
}

#[zbus::interface(name = "net.connman.Agent")]
impl Agent {
    async fn release(&self) {
        eprintln!("[network] connman released the agent");
    }

    async fn report_error(&self, service: OwnedObjectPath, error: String) {
        eprintln!("[network] {}: {error}", service.as_str());
        if let Ok(mut r) = self.shared.reported.lock() {
            r.insert(service.as_str().to_string(), error);
        }
    }

    async fn request_browser(
        &self,
        _service: OwnedObjectPath,
        _url: String,
    ) -> Result<(), AgentError> {
        Err(AgentError::Canceled(
            "no browser login on the head unit".into(),
        ))
    }

    /// Only a passphrase typed for this network, during its Connect.
    async fn request_input(
        &self,
        service: OwnedObjectPath,
        fields: HashMap<String, OwnedValue>,
    ) -> Result<HashMap<String, Z<'static>>, AgentError> {
        if !fields.contains_key("Passphrase") {
            return Err(AgentError::Canceled(
                "only a passphrase can be given from the dashboard".into(),
            ));
        }
        let pass = self
            .shared
            .pending
            .lock()
            .ok()
            .and_then(|p| p.get(service.as_str()).cloned());
        match pass {
            Some(p) => Ok(HashMap::from([("Passphrase".to_string(), Z::from(p))])),
            None => Err(AgentError::Canceled("no passphrase was typed".into())),
        }
    }

    async fn cancel(&self) {}
}

/// A variant as a [`Prop`].
pub fn conv(v: &Z<'_>) -> Prop {
    match v {
        Z::Str(s) => Prop::Str(s.as_str().to_string()),
        Z::Bool(b) => Prop::Bool(*b),
        Z::U8(n) => Prop::Num((*n).into()),
        Z::U16(n) => Prop::Num((*n).into()),
        Z::U32(n) => Prop::Num((*n).into()),
        Z::U64(n) => Prop::Num(*n),
        Z::Value(inner) => conv(inner),
        Z::Array(a) => {
            let strings: Option<Vec<String>> = a
                .iter()
                .map(|x| match x {
                    Z::Str(s) => Some(s.as_str().to_string()),
                    _ => None,
                })
                .collect();
            strings.map_or(Prop::Other, Prop::Strings)
        }
        Z::Dict(d) => {
            let mut out = BTreeMap::new();
            for (k, v) in d.iter() {
                if let Z::Str(k) = k {
                    out.insert(k.as_str().to_string(), conv(v));
                }
            }
            Prop::Dict(out)
        }
        _ => Prop::Other,
    }
}

fn props(m: &HashMap<String, OwnedValue>) -> Props {
    m.iter().map(|(k, v)| (k.clone(), conv(v))).collect()
}

/// A service id from the API ("wifi_…_managed_psk") as connman's object
/// path. Anything else is refused, so a caller can't name another object.
pub fn service_path(id: &str) -> Result<String, String> {
    if id.is_empty() || !id.chars().all(|c| c.is_ascii_alphanumeric() || c == '_') {
        return Err("not a Wi-Fi network id".to_string());
    }
    Ok(format!("/net/connman/service/{id}"))
}

fn reason(e: &zbus::Error) -> String {
    match e {
        zbus::Error::MethodError(name, msg, _) => {
            let n = name.as_str();
            if n == "org.freedesktop.DBus.Error.ServiceUnknown" {
                "connman isn't running".to_string()
            } else if n == "org.freedesktop.DBus.Error.AccessDenied" {
                "not allowed to talk to connman (D-Bus policy)".to_string()
            } else {
                match msg {
                    Some(m) if !m.is_empty() => format!("{n}: {m}"),
                    _ => n.to_string(),
                }
            }
        }
        other => other.to_string(),
    }
}

fn is_error(e: &zbus::Error, name: &str) -> bool {
    matches!(e, zbus::Error::MethodError(n, _, _) if n.as_str() == name)
}

/// connman, reached lazily: a lost bus is reconnected on the next call.
pub struct Connman {
    conn: Mutex<Option<Connection>>,
    shared: Arc<Shared>,
    scanning: AtomicBool,
}

impl Default for Connman {
    fn default() -> Self {
        Connman {
            conn: Mutex::new(None),
            shared: Arc::new(Shared::default()),
            scanning: AtomicBool::new(false),
        }
    }
}

impl Connman {
    async fn conn(&self) -> Result<Connection, String> {
        if let Some(c) = self.conn.lock().ok().and_then(|g| g.clone()) {
            return Ok(c);
        }
        let c = Connection::system()
            .await
            .map_err(|e| format!("no system D-Bus ({e})"))?;
        c.object_server()
            .at(
                AGENT_PATH,
                Agent {
                    shared: self.shared.clone(),
                },
            )
            .await
            .map_err(|e| reason(&e))?;
        if let Ok(mut g) = self.conn.lock() {
            *g = Some(c.clone());
        }
        Ok(c)
    }

    fn forget_conn(&self) {
        if let Ok(mut g) = self.conn.lock() {
            *g = None;
        }
    }

    async fn proxy<'a>(
        c: &'a Connection,
        path: &'a str,
        iface: &'a str,
    ) -> Result<Proxy<'a>, String> {
        zbus::proxy::Builder::<Proxy<'_>>::new(c)
            .destination(CONNMAN)
            .and_then(|b| b.path(path))
            .and_then(|b| b.interface(iface))
            .map_err(|e| e.to_string())?
            .cache_properties(CacheProperties::No)
            .build()
            .await
            .map_err(|e| reason(&e))
    }

    /// Registers the agent; connman forgets it when it restarts, so this is
    /// done before every Connect. "Already registered" is fine.
    async fn register_agent(&self, c: &Connection) -> Result<(), String> {
        let m = Self::proxy(c, "/", "net.connman.Manager").await?;
        let path = OwnedObjectPath::try_from(AGENT_PATH).map_err(|e| e.to_string())?;
        match m.call_method("RegisterAgent", &(&path,)).await {
            Ok(_) => Ok(()),
            Err(e) if is_error(&e, "net.connman.Error.AlreadyExists") => Ok(()),
            Err(e) => Err(reason(&e)),
        }
    }

    async fn wifi_technology(c: &Connection) -> Result<Option<(String, Props)>, String> {
        let m = Self::proxy(c, "/", "net.connman.Manager").await?;
        let techs: Vec<(OwnedObjectPath, HashMap<String, OwnedValue>)> = m
            .call("GetTechnologies", &())
            .await
            .map_err(|e| reason(&e))?;
        Ok(techs
            .iter()
            .map(|(p, v)| (p.as_str().to_string(), props(v)))
            .find(|(_, p)| matches!(p.get("Type"), Some(Prop::Str(t)) if t == "wifi")))
    }

    async fn read(&self) -> Result<pb::WifiStatus, String> {
        let c = self.conn().await?;
        let m = Self::proxy(&c, "/", "net.connman.Manager").await?;
        let manager: HashMap<String, OwnedValue> =
            m.call("GetProperties", &()).await.map_err(|e| reason(&e))?;
        let manager = props(&manager);
        let Some((_, tech)) = Self::wifi_technology(&c).await? else {
            return Ok(pb::WifiStatus {
                detail: "No Wi-Fi device: connman has no wifi technology".into(),
                ..Default::default()
            });
        };
        let enabled = matches!(tech.get("Powered"), Some(Prop::Bool(true)));
        let services: Vec<(OwnedObjectPath, HashMap<String, OwnedValue>)> =
            m.call("GetServices", &()).await.map_err(|e| reason(&e))?;
        let mut address = String::new();
        let mut networks = Vec::new();
        for (path, v) in &services {
            let p = props(v);
            let id = path.as_str().rsplit('/').next().unwrap_or_default();
            if let Some(n) = model::network(id, &p) {
                if address.is_empty()
                    && (n.state == pb::NetworkState::Online as i32
                        || n.state == pb::NetworkState::Connected as i32)
                {
                    address = model::address(&p);
                }
                networks.push(n);
            }
        }
        model::sort(&mut networks);
        let state = match manager.get("State") {
            Some(Prop::Str(s)) => s.as_str(),
            _ => "",
        };
        Ok(pb::WifiStatus {
            available: true,
            enabled,
            connectivity: model::connectivity(state) as i32,
            networks,
            detail: String::new(),
            simulated: false,
            address,
            scanning: self.scanning.load(Ordering::Relaxed),
        })
    }

    async fn service_error(c: &Connection, path: &str) -> String {
        let Ok(s) = Self::proxy(c, path, "net.connman.Service").await else {
            return String::new();
        };
        let p: Result<HashMap<String, OwnedValue>, _> = s.call("GetProperties", &()).await;
        match p.map(|p| props(&p)) {
            Ok(p) => match p.get("Error") {
                Some(Prop::Str(e)) => e.clone(),
                _ => String::new(),
            },
            Err(_) => String::new(),
        }
    }
}

impl Backend for Connman {
    async fn status(&self) -> pb::WifiStatus {
        match self.read().await {
            Ok(s) => s,
            Err(e) => {
                if e.starts_with("no system D-Bus") {
                    self.forget_conn();
                }
                pb::WifiStatus {
                    detail: format!("Wi-Fi unavailable: {e}"),
                    ..Default::default()
                }
            }
        }
    }

    async fn set_enabled(&self, on: bool) -> Result<(), String> {
        let c = self.conn().await?;
        let (path, _) = Self::wifi_technology(&c).await?.ok_or("no Wi-Fi device")?;
        let t = Self::proxy(&c, &path, "net.connman.Technology").await?;
        match t
            .call_method("SetProperty", &("Powered", Z::from(on)))
            .await
        {
            Ok(_) => Ok(()),
            Err(e) if is_error(&e, "net.connman.Error.AlreadyEnabled") => Ok(()),
            Err(e) if is_error(&e, "net.connman.Error.AlreadyDisabled") => Ok(()),
            Err(e) => Err(reason(&e)),
        }
    }

    async fn scan(&self) -> Result<(), String> {
        let c = self.conn().await?;
        let (path, _) = Self::wifi_technology(&c).await?.ok_or("no Wi-Fi device")?;
        let t = Self::proxy(&c, &path, "net.connman.Technology").await?;
        self.scanning.store(true, Ordering::Relaxed);
        let r = tokio::time::timeout(SCAN_WAIT, t.call_method("Scan", &())).await;
        self.scanning.store(false, Ordering::Relaxed);
        match r {
            Ok(Ok(_)) => Ok(()),
            Ok(Err(e)) => Err(reason(&e)),
            Err(_) => Err("the scan took too long".into()),
        }
    }

    async fn connect(&self, id: &str, passphrase: &str) -> Result<(), String> {
        let path = service_path(id)?;
        let c = self.conn().await?;
        self.register_agent(&c).await?;
        let s = Self::proxy(&c, &path, "net.connman.Service").await?;
        if let Ok(mut r) = self.shared.reported.lock() {
            r.remove(&path);
        }
        if !passphrase.is_empty()
            && let Ok(mut p) = self.shared.pending.lock()
        {
            p.insert(path.clone(), passphrase.to_string());
        }
        let r = tokio::time::timeout(CONNECT_WAIT, s.call_method("Connect", &())).await;
        if let Ok(mut p) = self.shared.pending.lock() {
            p.remove(&path);
        }
        match r {
            Ok(Ok(_)) => Ok(()),
            Ok(Err(e)) if is_error(&e, "net.connman.Error.AlreadyConnected") => Ok(()),
            Ok(Err(e)) => {
                let reported = self
                    .shared
                    .reported
                    .lock()
                    .ok()
                    .and_then(|r| r.get(&path).cloned())
                    .unwrap_or_default();
                let error = if reported.is_empty() {
                    Self::service_error(&c, &path).await
                } else {
                    reported
                };
                if !error.is_empty() {
                    Err(model::error_words(&error))
                } else if passphrase.is_empty() && is_error(&e, "net.connman.Agent.Error.Canceled")
                {
                    Err("A passphrase is needed".into())
                } else {
                    Err(format!("Couldn't connect: {}", reason(&e)))
                }
            }
            Err(_) => Err(format!(
                "Didn't connect within {} s",
                CONNECT_WAIT.as_secs()
            )),
        }
    }

    async fn disconnect(&self, id: &str) -> Result<(), String> {
        let path = service_path(id)?;
        let c = self.conn().await?;
        let s = Self::proxy(&c, &path, "net.connman.Service").await?;
        match s.call_method("Disconnect", &()).await {
            Ok(_) => Ok(()),
            Err(e) if is_error(&e, "net.connman.Error.NotConnected") => Ok(()),
            Err(e) => Err(reason(&e)),
        }
    }

    async fn forget(&self, id: &str) -> Result<(), String> {
        let path = service_path(id)?;
        let c = self.conn().await?;
        let s = Self::proxy(&c, &path, "net.connman.Service").await?;
        s.call_method("Remove", &())
            .await
            .map(|_| ())
            .map_err(|e| reason(&e))
    }
}

#[cfg(test)]
#[allow(clippy::unwrap_used)]
mod tests {
    use super::*;
    use zbus::zvariant::{Array, Dict, Signature};

    #[test]
    fn ids_are_service_names_only() {
        assert_eq!(
            service_path("wifi_dc85de828967_68756773_managed_psk").unwrap(),
            "/net/connman/service/wifi_dc85de828967_68756773_managed_psk"
        );
        for bad in ["", "../manager", "wifi/x", "a b", "x;y"] {
            assert!(service_path(bad).is_err(), "{bad}");
        }
    }

    #[test]
    fn variants_become_props() {
        assert_eq!(conv(&Z::U8(64)), Prop::Num(64));
        assert_eq!(conv(&Z::from("wifi")), Prop::Str("wifi".into()));
        assert_eq!(conv(&Z::Value(Box::new(Z::Bool(true)))), Prop::Bool(true));
        let a: Array<'_> = vec!["psk", "wps"].into();
        assert_eq!(
            conv(&Z::Array(a)),
            Prop::Strings(vec!["psk".into(), "wps".into()])
        );
        let mut d = Dict::new(&Signature::Str, &Signature::Variant);
        d.add("Address", Z::from("10.0.0.2")).unwrap();
        let Prop::Dict(m) = conv(&Z::Dict(d)) else {
            panic!()
        };
        assert_eq!(m.get("Address"), Some(&Prop::Str("10.0.0.2".into())));
    }
}
