//! Phone calls (ADR-0045): what audio-manager knows about the phone's calls,
//! independent of how it learnt it — PipeWire's Telephony service over the
//! system D-Bus on the Pi (`telephony.rs`), or the simulated phone
//! (`sim_calls.rs`).
//!
//! The Telephony service (PipeWire 1.6.8, `spa/plugins/bluez5/telephony.c`
//! and `README-Telephony.md`): a manager object `/org/pipewire/Telephony`
//! whose ObjectManager lists one `org.pipewire.Telephony.AudioGateway1` per
//! connected phone (`…/ag0`, property `Address`; its call audio link in
//! `AudioGatewayTransport1.State`: error, idle, pending, active), and each gateway's own
//! ObjectManager lists its `org.pipewire.Telephony.Call1` objects
//! (`…/ag0/call0`: `State`, `LineIdentification`, `Name`, `Multiparty`).
//! The trees are read whole (`GetManagedObjects`), never property by
//! property: `Properties.Get` on `Call1` is broken in 1.6.8 (bench-log
//! 2026-11-14). Pure: the tests build trees by hand.

use crate::objects::{Objects, Props, Value, clean_text};

pub const SERVICE: &str = "org.pipewire.Telephony";
pub const MANAGER_PATH: &str = "/org/pipewire/Telephony";
pub const GATEWAY: &str = "org.pipewire.Telephony.AudioGateway1";
pub const GATEWAY_TRANSPORT: &str = "org.pipewire.Telephony.AudioGatewayTransport1";
pub const CALL: &str = "org.pipewire.Telephony.Call1";

/// `Call1.State` (README-Telephony.md lists these seven).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum CallState {
    Incoming,
    Waiting,
    Dialing,
    Alerting,
    Active,
    Held,
    /// Ended: the object goes shortly. Never shown.
    Disconnected,
    /// A value the documentation doesn't list.
    Unknown,
}

impl CallState {
    pub fn parse(s: &str) -> CallState {
        match s {
            "incoming" => CallState::Incoming,
            "waiting" => CallState::Waiting,
            "dialing" => CallState::Dialing,
            "alerting" => CallState::Alerting,
            "active" => CallState::Active,
            "held" => CallState::Held,
            "disconnected" => CallState::Disconnected,
            _ => CallState::Unknown,
        }
    }

    /// Ringing here: the driver is asked.
    pub fn rings(self) -> bool {
        matches!(self, CallState::Incoming | CallState::Waiting)
    }

    /// Which call the screen shows first: ringing, then talking, then
    /// setting up, then held.
    fn rank(self) -> u8 {
        match self {
            CallState::Incoming => 0,
            CallState::Waiting => 1,
            CallState::Active => 2,
            CallState::Dialing | CallState::Alerting => 3,
            CallState::Held => 4,
            CallState::Unknown => 5,
            CallState::Disconnected => 6,
        }
    }
}

/// One call, as last reported.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Call {
    /// The call's object path (the simulation's name for it).
    pub path: String,
    /// The phone it is on: its gateway's `Address`, upper case.
    pub address: String,
    pub state: CallState,
    /// `LineIdentification`; empty: none given (or withheld).
    pub number: String,
    /// `Name`; empty: none given.
    pub name: String,
    /// `LineIdentification` "withheld": the caller hid their number.
    pub withheld: bool,
    pub multiparty: bool,
}

/// Whether calls can come to the head unit.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Availability {
    /// Not configured (no call microphone): why, for the screen.
    Off(String),
    /// Configured, but the Telephony service doesn't answer: why.
    Unavailable(String),
    Ready,
}

/// A phone's hands-free gateway.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Gateway {
    /// The phone's address, upper case.
    pub address: String,
    /// Call audio is flowing from the phone (the transport is "active"):
    /// while a call rings, the phone sends its own ring tone (in-band; the
    /// owner's Z Fold8 does, bench-log 2026-11-14).
    pub audio: bool,
}

/// Everything the telephony backend knows, replaced as a whole on each
/// change.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct CallSnapshot {
    pub availability: Availability,
    /// Phones whose hands-free gateway is connected.
    pub gateways: Vec<Gateway>,
    pub calls: Vec<Call>,
}

impl CallSnapshot {
    pub fn off(why: impl Into<String>) -> CallSnapshot {
        CallSnapshot {
            availability: Availability::Off(why.into()),
            gateways: Vec::new(),
            calls: Vec::new(),
        }
    }

    pub fn unavailable(why: impl Into<String>) -> CallSnapshot {
        CallSnapshot {
            availability: Availability::Unavailable(why.into()),
            gateways: Vec::new(),
            calls: Vec::new(),
        }
    }
}

fn str_of<'a>(p: &'a Props, k: &str) -> Option<&'a str> {
    match p.get(k) {
        Some(Value::Str(s)) => Some(s),
        _ => None,
    }
}

const MAX_TEXT: usize = 64;

/// The gateways and calls in the Telephony tree: the manager's
/// `GetManagedObjects` and each gateway's, merged by path. A call whose
/// gateway isn't in the tree is left out (it can't be placed on a phone).
pub fn from_objects(objs: &Objects) -> (Vec<Gateway>, Vec<Call>) {
    let gateways: Vec<(String, Gateway)> = objs
        .iter()
        .filter_map(|(path, i)| {
            let a = str_of(i.get(GATEWAY)?, "Address")?;
            let audio = i.get(GATEWAY_TRANSPORT).and_then(|t| str_of(t, "State")) == Some("active");
            Some((
                path.clone(),
                Gateway {
                    address: a.trim().to_ascii_uppercase(),
                    audio,
                },
            ))
        })
        .collect();
    let calls = objs
        .iter()
        .filter_map(|(path, i)| {
            let c = i.get(CALL)?;
            let (parent, _) = path.rsplit_once('/')?;
            let address = gateways
                .iter()
                .find(|(p, _)| p == parent)?
                .1
                .address
                .clone();
            let line = clean_text(str_of(c, "LineIdentification").unwrap_or(""), MAX_TEXT);
            let withheld = line.eq_ignore_ascii_case("withheld");
            Some(Call {
                path: path.clone(),
                address,
                state: CallState::parse(str_of(c, "State").unwrap_or("")),
                number: if withheld { String::new() } else { line },
                name: clean_text(str_of(c, "Name").unwrap_or(""), MAX_TEXT),
                withheld,
                multiparty: matches!(c.get("Multiparty"), Some(Value::Bool(true))),
            })
        })
        .collect();
    (gateways.into_iter().map(|(_, a)| a).collect(), calls)
}

/// The call to show on `address`'s phone, and how many others it has. Ended
/// calls aren't counted.
pub fn pick<'a>(calls: &'a [Call], address: &str) -> (Option<&'a Call>, u32) {
    let mut mine: Vec<&Call> = calls
        .iter()
        .filter(|c| c.address == address && c.state != CallState::Disconnected)
        .collect();
    mine.sort_by(|a, b| {
        a.state
            .rank()
            .cmp(&b.state.rank())
            .then(a.path.cmp(&b.path))
    });
    let others = u32::try_from(mine.len().saturating_sub(1)).unwrap_or(u32::MAX);
    (mine.first().copied(), others)
}

/// Who is calling, in words for the log and the knob display: the name,
/// else the number, else "withheld" or "unknown caller".
pub fn caller(c: &Call) -> String {
    if !c.name.is_empty() {
        c.name.clone()
    } else if !c.number.is_empty() {
        c.number.clone()
    } else if c.withheld {
        "a withheld number".into()
    } else {
        "an unknown caller".into()
    }
}

#[cfg(test)]
#[allow(clippy::unwrap_used)]
mod tests {
    use super::*;

    fn props(kv: &[(&str, Value)]) -> Props {
        kv.iter()
            .map(|(k, v)| ((*k).to_string(), v.clone()))
            .collect()
    }

    fn s(v: &str) -> Value {
        Value::Str(v.into())
    }

    fn tree(entries: Vec<(&str, &str, Props)>) -> Objects {
        let mut o = Objects::new();
        for (path, iface, p) in entries {
            o.entry(path.to_string())
                .or_default()
                .insert(iface.to_string(), p);
        }
        o
    }

    const AG: &str = "/org/pipewire/Telephony/ag1";

    fn gateway(address: &str) -> Props {
        props(&[("Address", s(address)), ("SpeakerVolume", Value::U32(15))])
    }

    #[test]
    fn a_ringing_call_is_placed_on_its_phone() {
        // As the bench Pi showed it (2026-11-14), the number changed.
        let objs = tree(vec![
            (AG, GATEWAY, gateway("b0:de:31:1e:55:96")),
            (
                "/org/pipewire/Telephony/ag1/call1",
                CALL,
                props(&[
                    ("State", s("incoming")),
                    ("LineIdentification", s("+15550100")),
                    ("Name", s("Test Caller")),
                    ("Multiparty", Value::Bool(false)),
                ]),
            ),
        ]);
        let (gateways, calls) = from_objects(&objs);
        assert_eq!(
            gateways,
            vec![Gateway {
                address: "B0:DE:31:1E:55:96".into(),
                audio: false
            }]
        );
        assert_eq!(
            calls,
            vec![Call {
                path: "/org/pipewire/Telephony/ag1/call1".into(),
                address: "B0:DE:31:1E:55:96".into(),
                state: CallState::Incoming,
                number: "+15550100".into(),
                name: "Test Caller".into(),
                withheld: false,
                multiparty: false,
            }]
        );
        assert_eq!(caller(&calls[0]), "Test Caller");
    }

    #[test]
    fn withheld_numbers_and_missing_names() {
        let objs = tree(vec![
            (AG, GATEWAY, gateway("02:00:00:00:00:01")),
            (
                "/org/pipewire/Telephony/ag1/call0",
                CALL,
                props(&[
                    ("State", s("incoming")),
                    ("LineIdentification", s("withheld")),
                ]),
            ),
            (
                "/org/pipewire/Telephony/ag1/call2",
                CALL,
                props(&[
                    ("State", s("active")),
                    ("LineIdentification", s("+1\u{7}555")),
                ]),
            ),
            (
                "/org/pipewire/Telephony/ag1/call3",
                CALL,
                props(&[("State", s("something new"))]),
            ),
        ]);
        let (_, calls) = from_objects(&objs);
        assert!(calls[0].withheld && calls[0].number.is_empty());
        assert_eq!(caller(&calls[0]), "a withheld number");
        assert_eq!(calls[1].number, "+1555", "control characters dropped");
        assert_eq!(caller(&calls[1]), "+1555");
        assert_eq!(calls[2].state, CallState::Unknown);
        assert_eq!(caller(&calls[2]), "an unknown caller");
    }

    #[test]
    fn a_phone_ringing_in_band() {
        let mut objs = tree(vec![(AG, GATEWAY, gateway("02:00:00:00:00:01"))]);
        let transport = |st: &str| props(&[("State", s(st)), ("Codec", Value::U32(2))]);
        for (st, audio) in [
            ("active", true),
            ("pending", false),
            ("idle", false),
            ("error", false),
        ] {
            objs.get_mut(AG)
                .unwrap()
                .insert(GATEWAY_TRANSPORT.into(), transport(st));
            assert_eq!(from_objects(&objs).0[0].audio, audio, "{st}");
        }
    }

    #[test]
    fn a_call_without_its_gateway_is_left_out() {
        let objs = tree(vec![(
            "/org/pipewire/Telephony/ag4/call0",
            CALL,
            props(&[("State", s("incoming"))]),
        )]);
        let (gateways, calls) = from_objects(&objs);
        assert!(gateways.is_empty() && calls.is_empty());
    }

    #[test]
    fn the_ringing_call_is_shown_first_and_ended_ones_not_at_all() {
        let call = |n: u32, st: CallState, addr: &str| Call {
            path: format!("{AG}/call{n}"),
            address: addr.into(),
            state: st,
            number: String::new(),
            name: String::new(),
            withheld: false,
            multiparty: false,
        };
        let me = "02:00:00:00:00:01";
        let calls = vec![
            call(0, CallState::Held, me),
            call(1, CallState::Active, me),
            call(2, CallState::Waiting, me),
            call(3, CallState::Disconnected, me),
            call(4, CallState::Incoming, "02:00:00:00:00:09"),
        ];
        let (shown, others) = pick(&calls, me);
        assert_eq!(shown.unwrap().state, CallState::Waiting);
        assert_eq!(others, 2);
        let (shown, others) = pick(&calls[..2], me);
        assert_eq!(shown.unwrap().state, CallState::Active);
        assert_eq!(others, 1);
        assert_eq!(pick(&calls[3..4], me), (None, 0));
        assert_eq!(pick(&calls, "02:00:00:00:00:05"), (None, 0));
    }

    #[test]
    fn states_parse() {
        for (t, st) in [
            ("incoming", CallState::Incoming),
            ("waiting", CallState::Waiting),
            ("dialing", CallState::Dialing),
            ("alerting", CallState::Alerting),
            ("active", CallState::Active),
            ("held", CallState::Held),
            ("disconnected", CallState::Disconnected),
            ("", CallState::Unknown),
        ] {
            assert_eq!(CallState::parse(t), st);
        }
        assert!(CallState::Incoming.rings() && CallState::Waiting.rings());
        assert!(!CallState::Active.rings());
    }
}
