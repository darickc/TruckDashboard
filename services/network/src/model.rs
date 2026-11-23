//! connman's properties as the API's messages (ADR-0052). connman's D-Bus
//! API (doc/service-api.txt, doc/technology-api.txt, doc/manager-api.txt in
//! connman 2.0's source) gives every object as a dictionary of variants;
//! [`Prop`] is the part of a variant this service reads, so the parsing is
//! tested without a bus.

use std::cmp::Reverse;
use std::collections::BTreeMap;

use f250_proto::network::v1 as pb;

/// A property's value, as far as this service cares.
#[derive(Debug, Clone, PartialEq)]
pub enum Prop {
    Str(String),
    Strings(Vec<String>),
    Num(u64),
    Bool(bool),
    Dict(BTreeMap<String, Prop>),
    Other,
}

pub type Props = BTreeMap<String, Prop>;

fn str_of<'a>(p: &'a Props, k: &str) -> &'a str {
    match p.get(k) {
        Some(Prop::Str(s)) => s,
        _ => "",
    }
}

fn bool_of(p: &Props, k: &str) -> bool {
    matches!(p.get(k), Some(Prop::Bool(true)))
}

/// A connman service, if it is a Wi-Fi network with a name. Hidden networks
/// have none and aren't listed.
pub fn network(id: &str, p: &Props) -> Option<pb::WifiNetwork> {
    if str_of(p, "Type") != "wifi" {
        return None;
    }
    let name = str_of(p, "Name").trim();
    if name.is_empty() {
        return None;
    }
    let security = match p.get("Security") {
        Some(Prop::Strings(s)) => security(s),
        _ => pb::Security::Unspecified,
    };
    let strength = match p.get("Strength") {
        Some(Prop::Num(n)) => (*n).min(100) as u32,
        _ => 0,
    };
    Some(pb::WifiNetwork {
        id: id.to_string(),
        name: name.to_string(),
        strength,
        security: security as i32,
        saved: bool_of(p, "Favorite"),
        state: state(str_of(p, "State")) as i32,
        error: str_of(p, "Error").to_string(),
    })
}

/// connman's Security list: "none", "psk", "wep", "ieee8021x", and "wps"
/// alongside one of them.
pub fn security(list: &[String]) -> pb::Security {
    let has = |s: &str| list.iter().any(|x| x == s);
    if has("ieee8021x") {
        pb::Security::Enterprise
    } else if has("psk") {
        pb::Security::Psk
    } else if has("wep") {
        pb::Security::Wep
    } else if has("none") {
        pb::Security::Open
    } else {
        pb::Security::Unspecified
    }
}

/// A service's State: idle, failure, association, configuration, ready,
/// disconnect, online.
pub fn state(s: &str) -> pb::NetworkState {
    match s {
        "idle" => pb::NetworkState::Idle,
        "association" | "configuration" => pb::NetworkState::Connecting,
        "ready" => pb::NetworkState::Connected,
        "online" => pb::NetworkState::Online,
        "disconnect" => pb::NetworkState::Disconnecting,
        "failure" => pb::NetworkState::Failed,
        _ => pb::NetworkState::Unspecified,
    }
}

/// The Manager's State: offline, idle, ready, online.
/// A join that didn't finish. On the Pi 5 a WPA3-only network ends this way:
/// its Wi-Fi joins WPA2 and mixed WPA2/WPA3 networks, not WPA3 alone
/// (agl/rootfs/etc/modprobe.d/zz-f250-brcmfmac.conf, bench-log 2026-11-23).
pub fn timeout_words(wait: std::time::Duration) -> String {
    format!(
        "Didn't connect within {} s. A WPA3-only network can't be joined: this Wi-Fi joins WPA2 and WPA2/WPA3",
        wait.as_secs()
    )
}

pub fn connectivity(s: &str) -> pb::Connectivity {
    match s {
        "ready" => pb::Connectivity::Connected,
        "online" => pb::Connectivity::Online,
        "offline" | "idle" => pb::Connectivity::Offline,
        _ => pb::Connectivity::Unspecified,
    }
}

/// A connected service's IPv4 address.
pub fn address(p: &Props) -> String {
    match p.get("IPv4") {
        Some(Prop::Dict(d)) => match d.get("Address") {
            Some(Prop::Str(a)) => a.clone(),
            _ => String::new(),
        },
        _ => String::new(),
    }
}

fn rank(n: &pb::WifiNetwork) -> u8 {
    use pb::NetworkState as S;
    match S::try_from(n.state).unwrap_or(S::Unspecified) {
        S::Online | S::Connected => 0,
        S::Connecting | S::Disconnecting => 1,
        _ if n.saved => 2,
        _ => 3,
    }
}

/// The connected network first, then saved ones, then by strength.
pub fn sort(networks: &mut [pb::WifiNetwork]) {
    networks.sort_by_key(|n| (rank(n), Reverse(n.strength), n.name.to_lowercase()));
}

/// connman's error names (a service's Error, or the agent's ReportError) in
/// the driver's words.
pub fn error_words(e: &str) -> String {
    match e {
        "invalid-key" => "Wrong passphrase".to_string(),
        "auth-failed" => "The network refused the login".to_string(),
        "connect-failed" => "Couldn't connect".to_string(),
        "dhcp-failed" => "No address from the network (DHCP)".to_string(),
        "out-of-range" => "Out of range".to_string(),
        "pin-missing" => "The network needs a PIN".to_string(),
        "blocked" => "Blocked".to_string(),
        "online-check-failed" => "Connected, but the internet wasn't reached".to_string(),
        "" => "Couldn't connect".to_string(),
        other => format!("Couldn't connect ({other})"),
    }
}

#[cfg(test)]
#[allow(clippy::unwrap_used)]
mod tests {
    use super::*;

    fn props(pairs: &[(&str, Prop)]) -> Props {
        pairs
            .iter()
            .map(|(k, v)| (k.to_string(), v.clone()))
            .collect()
    }

    fn s(x: &str) -> Prop {
        Prop::Str(x.to_string())
    }

    #[test]
    fn a_secured_saved_network() {
        let p = props(&[
            ("Type", s("wifi")),
            ("Name", s("F-250 Hotspot")),
            ("Security", Prop::Strings(vec!["psk".into(), "wps".into()])),
            ("Strength", Prop::Num(72)),
            ("Favorite", Prop::Bool(true)),
            ("State", s("online")),
            (
                "IPv4",
                Prop::Dict(props(&[
                    ("Address", s("172.20.10.4")),
                    ("Method", s("dhcp")),
                ])),
            ),
        ]);
        let n = network("wifi_abc_managed_psk", &p).unwrap();
        assert_eq!(n.name, "F-250 Hotspot");
        assert_eq!(n.security, pb::Security::Psk as i32);
        assert_eq!(n.strength, 72);
        assert!(n.saved);
        assert_eq!(n.state, pb::NetworkState::Online as i32);
        assert_eq!(address(&p), "172.20.10.4");
    }

    #[test]
    fn hidden_and_wired_services_are_not_listed() {
        assert!(network("x", &props(&[("Type", s("wifi"))])).is_none());
        assert!(network("x", &props(&[("Type", s("wifi")), ("Name", s("   "))])).is_none());
        assert!(
            network(
                "ethernet_x",
                &props(&[("Type", s("ethernet")), ("Name", s("Wired"))])
            )
            .is_none()
        );
    }

    #[test]
    fn every_security_and_state() {
        let v = |x: &[&str]| x.iter().map(|s| s.to_string()).collect::<Vec<_>>();
        assert_eq!(security(&v(&["none"])), pb::Security::Open);
        assert_eq!(security(&v(&["psk"])), pb::Security::Psk);
        assert_eq!(security(&v(&["wep"])), pb::Security::Wep);
        assert_eq!(security(&v(&["ieee8021x"])), pb::Security::Enterprise);
        assert_eq!(security(&v(&["wps"])), pb::Security::Unspecified);
        for (c, want) in [
            ("idle", pb::NetworkState::Idle),
            ("association", pb::NetworkState::Connecting),
            ("configuration", pb::NetworkState::Connecting),
            ("ready", pb::NetworkState::Connected),
            ("online", pb::NetworkState::Online),
            ("disconnect", pb::NetworkState::Disconnecting),
            ("failure", pb::NetworkState::Failed),
            ("something new", pb::NetworkState::Unspecified),
        ] {
            assert_eq!(state(c), want, "{c}");
        }
        assert_eq!(connectivity("offline"), pb::Connectivity::Offline);
        assert_eq!(connectivity("idle"), pb::Connectivity::Offline);
        assert_eq!(connectivity("ready"), pb::Connectivity::Connected);
        assert_eq!(connectivity("online"), pb::Connectivity::Online);
    }

    #[test]
    fn a_join_that_never_finished_says_why_it_might_not() {
        let w = timeout_words(std::time::Duration::from_secs(60));
        assert!(w.starts_with("Didn't connect within 60 s."), "{w}");
        assert!(w.contains("WPA3-only"), "{w}");
    }

    #[test]
    fn connected_then_saved_then_strongest() {
        let n = |name: &str, strength: u32, saved: bool, st: pb::NetworkState| pb::WifiNetwork {
            name: name.into(),
            strength,
            saved,
            state: st as i32,
            ..Default::default()
        };
        let mut v = vec![
            n("strong", 90, false, pb::NetworkState::Idle),
            n("saved weak", 10, true, pb::NetworkState::Idle),
            n("mine", 40, true, pb::NetworkState::Online),
            n("medium", 50, false, pb::NetworkState::Idle),
        ];
        sort(&mut v);
        let names: Vec<&str> = v.iter().map(|n| n.name.as_str()).collect();
        assert_eq!(names, ["mine", "saved weak", "strong", "medium"]);
    }

    #[test]
    fn errors_in_words() {
        assert_eq!(error_words("invalid-key"), "Wrong passphrase");
        assert_eq!(
            error_words("dhcp-failed"),
            "No address from the network (DHCP)"
        );
        assert_eq!(error_words("weird"), "Couldn't connect (weird)");
    }
}
