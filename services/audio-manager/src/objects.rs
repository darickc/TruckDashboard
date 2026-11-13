//! BlueZ's object tree (`org.freedesktop.DBus.ObjectManager.GetManagedObjects`
//! on `org.bluez`) turned into a [`Snapshot`]. Pure: `bluez.rs` converts
//! D-Bus values into [`Value`] and calls [`snapshot`]; the tests build trees
//! by hand from BlueZ 5.86's documentation (doc/org.bluez.*.rst).

use std::collections::BTreeMap;

use tokio::time::Instant;

use crate::model::{Adapter, Phone, PlayState, Player, Snapshot, Track};

/// A D-Bus value, as far as audio-manager reads one.
#[derive(Debug, Clone, PartialEq)]
pub enum Value {
    Str(String),
    U32(u32),
    Bool(bool),
    Path(String),
    Strings(Vec<String>),
    Dict(BTreeMap<String, Value>),
    /// Any other type: ignored.
    Other,
}

pub type Props = BTreeMap<String, Value>;
/// interface name → properties
pub type Interfaces = BTreeMap<String, Props>;
/// object path → interfaces
pub type Objects = BTreeMap<String, Interfaces>;

pub const ADAPTER: &str = "org.bluez.Adapter1";
pub const DEVICE: &str = "org.bluez.Device1";
pub const PLAYER: &str = "org.bluez.MediaPlayer1";
pub const CONTROL: &str = "org.bluez.MediaControl1";
pub const TRANSPORT: &str = "org.bluez.MediaTransport1";

/// The A2DP Source service class (Bluetooth Assigned Numbers): the device
/// can send audio, so it is a phone to this head unit. The OBDLink MX+
/// (Serial Port only) is never listed.
pub const A2DP_SOURCE_UUID: &str = "0000110a-0000-1000-8000-00805f9b34fb";

fn str_of<'a>(p: &'a Props, k: &str) -> Option<&'a str> {
    match p.get(k) {
        Some(Value::Str(s)) => Some(s),
        _ => None,
    }
}

fn bool_of(p: &Props, k: &str) -> Option<bool> {
    match p.get(k) {
        Some(Value::Bool(b)) => Some(*b),
        _ => None,
    }
}

fn u32_of(p: &Props, k: &str) -> Option<u32> {
    match p.get(k) {
        Some(Value::U32(n)) => Some(*n),
        _ => None,
    }
}

fn path_of<'a>(p: &'a Props, k: &str) -> Option<&'a str> {
    match p.get(k) {
        Some(Value::Path(s)) => Some(s),
        _ => None,
    }
}

/// Text from a phone, for the screen: control characters dropped,
/// whitespace trimmed, at most `max` characters.
pub fn clean_text(s: &str, max: usize) -> String {
    s.chars()
        .filter(|c| !c.is_control())
        .collect::<String>()
        .trim()
        .chars()
        .take(max)
        .collect()
}

const MAX_TEXT: usize = 200;

/// `MediaPlayer1.Status` (BlueZ 5.86 lists playing, stopped, paused,
/// forward-seek, reverse-seek, error).
pub fn play_state(s: &str) -> PlayState {
    match s {
        "playing" => PlayState::Playing,
        "stopped" => PlayState::Stopped,
        "paused" => PlayState::Paused,
        "forward-seek" => PlayState::ForwardSeek,
        "reverse-seek" => PlayState::ReverseSeek,
        "error" => PlayState::Error,
        _ => PlayState::Unknown,
    }
}

/// `MediaPlayer1.Track`: Title, Artist, Album (strings), Duration (uint32,
/// milliseconds). A key of the wrong type is ignored; Duration 0 is
/// "unknown".
pub fn track(d: &Props) -> Track {
    let text = |k: &str| {
        str_of(d, k)
            .map(|s| clean_text(s, MAX_TEXT))
            .unwrap_or_default()
    };
    Track {
        title: text("Title"),
        artist: text("Artist"),
        album: text("Album"),
        duration_ms: u32_of(d, "Duration").filter(|&n| n > 0),
        // AVRCP image handles are seven digits; anything else isn't one.
        image_handle: str_of(d, "ImgHandle")
            .map(str::trim)
            .filter(|h| {
                !h.is_empty() && h.len() <= 16 && h.chars().all(|c| c.is_ascii_alphanumeric())
            })
            .map(str::to_string),
    }
}

/// `MediaPlayer1.Position` in milliseconds. BlueZ documents
/// `u32::MAX` (and anything at or past the duration) as "the track has
/// ended": that is shown as the end, when the duration is known.
pub fn position(raw: Option<u32>, duration_ms: Option<u32>) -> Option<u32> {
    match (raw?, duration_ms) {
        (u32::MAX, Some(d)) => Some(d),
        (u32::MAX, None) => None,
        (p, Some(d)) => Some(p.min(d)),
        (p, None) => Some(p),
    }
}

/// The player at `path` (its `MediaPlayer1` properties), read at `now`.
pub fn player(path: &str, address: &str, p: &Props, now: Instant) -> Player {
    let track = match p.get("Track") {
        Some(Value::Dict(d)) => track(d),
        _ => Track::default(),
    };
    Player {
        path: path.to_string(),
        address: address.to_string(),
        name: str_of(p, "Name")
            .map(|s| clean_text(s, MAX_TEXT))
            .unwrap_or_default(),
        obex_port: u32_of(p, "ObexPort")
            .and_then(|n| u16::try_from(n).ok())
            .filter(|&n| n > 0),
        state: str_of(p, "Status").map_or(PlayState::Unknown, play_state),
        position_ms: position(u32_of(p, "Position"), track.duration_ms),
        track,
        read_at: now,
    }
}

/// The adapter to use: `name` (hci0) if given and present, else the first.
pub fn adapter_path(objs: &Objects, name: &str) -> Option<String> {
    let mut adapters = objs.iter().filter(|(_, i)| i.contains_key(ADAPTER));
    if !name.is_empty() {
        let want = format!("/{name}");
        if let Some((p, _)) = objs
            .iter()
            .find(|(p, i)| i.contains_key(ADAPTER) && p.ends_with(&want))
        {
            return Some(p.clone());
        }
    }
    adapters.next().map(|(p, _)| p.clone())
}

fn under(path: &str, parent: &str) -> bool {
    path.len() > parent.len() && path.starts_with(parent) && path[parent.len()..].starts_with('/')
}

/// The snapshot of BlueZ's tree for the adapter named `adapter` (hci0; empty:
/// the first).
pub fn snapshot(objs: &Objects, adapter: &str, now: Instant) -> Snapshot {
    let Some(apath) = adapter_path(objs, adapter) else {
        return Snapshot::unavailable("no Bluetooth adapter");
    };
    let a = &objs[&apath][ADAPTER];
    if bool_of(a, "Powered") != Some(true) {
        return Snapshot::unavailable(format!("the Bluetooth adapter {apath} is off"));
    }
    let adapter_state = Adapter::Ready {
        discoverable: bool_of(a, "Discoverable").unwrap_or(false),
        pairable: bool_of(a, "Pairable").unwrap_or(false),
    };

    // Phones: devices of this adapter that send audio and are paired or
    // connected. Devices merely seen nearby aren't listed.
    let mut phones: Vec<(String, Phone)> = Vec::new();
    for (path, ifaces) in objs {
        let Some(d) = ifaces.get(DEVICE) else {
            continue;
        };
        if !under(path, &apath) {
            continue;
        }
        let audio = matches!(d.get("UUIDs"), Some(Value::Strings(u))
            if u.iter().any(|x| x.eq_ignore_ascii_case(A2DP_SOURCE_UUID)));
        let connected = bool_of(d, "Connected").unwrap_or(false);
        let paired = bool_of(d, "Paired").unwrap_or(false);
        if !audio || !(connected || paired) {
            continue;
        }
        let address = str_of(d, "Address").unwrap_or_default().to_string();
        let name = str_of(d, "Alias")
            .or_else(|| str_of(d, "Name"))
            .map(|s| clean_text(s, 64))
            .filter(|s| !s.is_empty())
            .unwrap_or_else(|| address.clone());
        phones.push((
            path.clone(),
            Phone {
                address,
                name,
                connected,
                paired,
            },
        ));
    }
    phones.sort_by(|(_, a), (_, b)| b.connected.cmp(&a.connected).then(a.name.cmp(&b.name)));

    // The player: of the connected phone only. The device's addressed player
    // (MediaControl1.Player) when BlueZ names one, else the first player
    // under it.
    let mut player_out = None;
    let mut streaming = false;
    if let Some((dpath, phone)) = phones.iter().find(|(_, p)| p.connected) {
        let addressed = objs
            .get(dpath)
            .and_then(|i| i.get(CONTROL))
            .and_then(|c| path_of(c, "Player"))
            .filter(|p| objs.get(*p).is_some_and(|i| i.contains_key(PLAYER)))
            .map(str::to_string);
        let ppath = addressed.or_else(|| {
            objs.iter()
                .find(|(p, i)| under(p, dpath) && i.contains_key(PLAYER))
                .map(|(p, _)| p.clone())
        });
        if let Some(pp) = ppath {
            player_out = Some(player(&pp, &phone.address, &objs[&pp][PLAYER], now));
        }
        streaming = objs.iter().any(|(p, i)| {
            under(p, dpath)
                && i.get(TRANSPORT)
                    .and_then(|t| str_of(t, "State"))
                    .is_some_and(|s| s == "active")
        });
    }

    Snapshot {
        adapter: adapter_state,
        phones: phones.into_iter().map(|(_, p)| p).collect(),
        player: player_out,
        streaming,
    }
}

#[cfg(test)]
#[allow(clippy::unwrap_used)]
mod tests {
    use super::*;
    use std::time::Duration;

    fn s(v: &str) -> Value {
        Value::Str(v.into())
    }

    fn props(kv: &[(&str, Value)]) -> Props {
        kv.iter().map(|(k, v)| (k.to_string(), v.clone())).collect()
    }

    const HCI: &str = "/org/bluez/hci0";
    const DEV: &str = "/org/bluez/hci0/dev_AA_BB_CC_DD_EE_01";

    fn adapter(powered: bool) -> Interfaces {
        BTreeMap::from([(
            ADAPTER.to_string(),
            props(&[
                ("Powered", Value::Bool(powered)),
                ("Discoverable", Value::Bool(false)),
                ("Pairable", Value::Bool(false)),
                ("Alias", s("F-250")),
            ]),
        )])
    }

    fn phone(connected: bool, uuids: &[&str]) -> Interfaces {
        let mut d = props(&[
            ("Address", s("AA:BB:CC:DD:EE:01")),
            ("Alias", s("Pixel 8")),
            ("Name", s("Pixel 8 raw")),
            ("Paired", Value::Bool(true)),
            ("Connected", Value::Bool(connected)),
            (
                "UUIDs",
                Value::Strings(uuids.iter().map(|u| u.to_string()).collect()),
            ),
        ]);
        d.insert("Trusted".into(), Value::Bool(true));
        BTreeMap::from([
            (DEVICE.to_string(), d),
            (
                CONTROL.to_string(),
                props(&[
                    ("Connected", Value::Bool(connected)),
                    ("Player", Value::Path(format!("{DEV}/player0"))),
                ]),
            ),
        ])
    }

    fn player_props(status: &str, position: u32, duration: u32) -> Interfaces {
        BTreeMap::from([(
            PLAYER.to_string(),
            props(&[
                ("Status", s(status)),
                ("Position", Value::U32(position)),
                ("Name", s("Spotify")),
                ("Device", Value::Path(DEV.into())),
                (
                    "Track",
                    Value::Dict(props(&[
                        ("Title", s("  Highway Song\u{7}")),
                        ("Artist", s("A Band")),
                        ("Album", s("Roads")),
                        ("Genre", s("Rock")),
                        ("TrackNumber", Value::U32(3)),
                        ("NumberOfTracks", Value::U32(12)),
                        ("Duration", Value::U32(duration)),
                    ])),
                ),
            ]),
        )])
    }

    fn transport(state: &str) -> Interfaces {
        BTreeMap::from([(
            TRANSPORT.to_string(),
            props(&[
                ("State", s(state)),
                ("Device", Value::Path(DEV.into())),
                ("Volume", Value::Other),
            ]),
        )])
    }

    fn tree(connected: bool) -> Objects {
        BTreeMap::from([
            (HCI.to_string(), adapter(true)),
            (DEV.to_string(), phone(connected, &[A2DP_SOURCE_UUID])),
            (
                format!("{DEV}/player0"),
                player_props("playing", 61_000, 200_000),
            ),
            (format!("{DEV}/fd0"), transport("active")),
        ])
    }

    #[test]
    fn track_metadata_from_the_documented_keys() {
        let now = Instant::now();
        let snap = snapshot(&tree(true), "hci0", now);
        let p = snap.player.expect("a player");
        assert_eq!(
            p.track.title, "Highway Song",
            "trimmed, control chars dropped"
        );
        assert_eq!(p.track.artist, "A Band");
        assert_eq!(p.track.album, "Roads");
        assert_eq!(p.track.duration_ms, Some(200_000));
        assert_eq!(p.state, PlayState::Playing);
        assert_eq!(p.position_ms, Some(61_000));
        assert_eq!(p.name, "Spotify");
        assert_eq!(p.address, "AA:BB:CC:DD:EE:01");
        assert_eq!(p.obex_port, None, "no ObexPort: no cover art");
        assert_eq!(p.track.image_handle, None);
        assert!(snap.streaming);
        assert_eq!(snap.phones.len(), 1);
        assert_eq!(
            snap.phones[0].name, "Pixel 8",
            "the alias, not the raw name"
        );
    }

    /// `ObexPort` (uint16) and the track's `ImgHandle` (string), both
    /// experimental in BlueZ 5.86's doc/org.bluez.MediaPlayer.rst.
    #[test]
    fn cover_art_port_and_image_handle() {
        let now = Instant::now();
        let mut objs = tree(true);
        let props = objs
            .get_mut(&format!("{DEV}/player0"))
            .and_then(|i| i.get_mut(PLAYER))
            .expect("player");
        props.insert("ObexPort".into(), Value::U32(0x1005));
        let Some(Value::Dict(t)) = props.get_mut("Track") else {
            panic!("track")
        };
        t.insert("ImgHandle".into(), s(" 1000001 "));
        let p = snapshot(&objs, "hci0", now).player.expect("a player");
        assert_eq!(p.obex_port, Some(0x1005));
        assert_eq!(p.track.image_handle.as_deref(), Some("1000001"));

        for bad in ["", "   ", "../../etc/passwd", "12345678901234567"] {
            let mut d = BTreeMap::new();
            d.insert("ImgHandle".to_string(), s(bad));
            assert_eq!(track(&d).image_handle, None, "{bad:?}");
        }
        let mut pl = BTreeMap::new();
        pl.insert("ObexPort".to_string(), Value::U32(0));
        assert_eq!(player("/p", "A", &pl, now).obex_port, None);
        pl.insert("ObexPort".to_string(), Value::U32(70_000));
        assert_eq!(player("/p", "A", &pl, now).obex_port, None, "not a u16");
    }

    #[test]
    fn every_documented_status() {
        for (s, want) in [
            ("playing", PlayState::Playing),
            ("stopped", PlayState::Stopped),
            ("paused", PlayState::Paused),
            ("forward-seek", PlayState::ForwardSeek),
            ("reverse-seek", PlayState::ReverseSeek),
            ("error", PlayState::Error),
            ("", PlayState::Unknown),
            ("PLAYING", PlayState::Unknown),
        ] {
            assert_eq!(play_state(s), want, "{s:?}");
        }
    }

    #[test]
    fn wrong_types_and_missing_keys_are_ignored() {
        let d = props(&[
            ("Title", Value::U32(4)),
            ("Artist", s("x")),
            ("Duration", s("200000")),
        ]);
        let t = track(&d);
        assert_eq!(t.title, "");
        assert_eq!(t.artist, "x");
        assert_eq!(t.duration_ms, None);
        assert_eq!(
            track(&props(&[("Duration", Value::U32(0))])).duration_ms,
            None
        );
        // A player with no Track, Status or Position at all.
        let p = player("/p", "a", &Props::new(), Instant::now());
        assert_eq!(p.state, PlayState::Unknown);
        assert_eq!(p.position_ms, None);
        assert_eq!(p.track, Track::default());
    }

    #[test]
    fn long_text_is_cut() {
        let long = "x".repeat(1000);
        assert_eq!(clean_text(&long, MAX_TEXT).chars().count(), MAX_TEXT);
        assert_eq!(clean_text("é\nü", 10), "éü");
    }

    #[test]
    fn position_end_markers() {
        assert_eq!(position(Some(u32::MAX), Some(200_000)), Some(200_000));
        assert_eq!(position(Some(u32::MAX), None), None);
        assert_eq!(position(Some(300_000), Some(200_000)), Some(200_000));
        assert_eq!(position(Some(5), None), Some(5));
        assert_eq!(position(None, Some(5)), None);
    }

    #[test]
    fn position_counts_on_only_while_playing_and_stops_at_the_end() {
        let t0 = Instant::now();
        let mut p = player(
            "/p",
            "a",
            &tree(true)[&format!("{DEV}/player0")][PLAYER],
            t0,
        );
        assert_eq!(p.position_at(t0 + Duration::from_secs(9)), Some(70_000));
        assert_eq!(p.position_at(t0 + Duration::from_secs(1000)), Some(200_000));
        p.state = PlayState::Paused;
        assert_eq!(p.position_at(t0 + Duration::from_secs(9)), Some(61_000));
    }

    #[test]
    fn link_loss_no_player_for_a_phone_that_is_gone() {
        // BlueZ may keep the player object a moment after the device drops;
        // a disconnected phone's player is never shown.
        let snap = snapshot(&tree(false), "hci0", Instant::now());
        assert!(snap.player.is_none());
        assert!(!snap.streaming);
        assert_eq!(snap.phones.len(), 1);
        assert!(!snap.phones[0].connected);
        assert!(snap.phones[0].paired);
    }

    #[test]
    fn a_device_that_sends_no_audio_is_not_a_phone() {
        let mut t = tree(true);
        // The OBDLink MX+: Serial Port only.
        t.insert(
            DEV.into(),
            phone(true, &["00001101-0000-1000-8000-00805f9b34fb"]),
        );
        let snap = snapshot(&t, "hci0", Instant::now());
        assert!(snap.phones.is_empty());
        assert!(snap.player.is_none());
    }

    #[test]
    fn the_player_bluez_addresses_wins_else_the_first() {
        let mut t = tree(true);
        t.insert(format!("{DEV}/player1"), player_props("paused", 1, 10_000));
        // MediaControl1.Player names player0.
        assert_eq!(
            snapshot(&t, "hci0", Instant::now()).player.unwrap().path,
            format!("{DEV}/player0")
        );
        // Without that property: the first under the device.
        t.get_mut(DEV).unwrap().remove(CONTROL);
        t.remove(&format!("{DEV}/player0"));
        assert_eq!(
            snapshot(&t, "hci0", Instant::now()).player.unwrap().path,
            format!("{DEV}/player1")
        );
    }

    #[test]
    fn no_adapter_or_powered_off_is_unavailable() {
        let mut t = tree(true);
        t.insert(HCI.into(), adapter(false));
        let s = snapshot(&t, "hci0", Instant::now());
        assert!(matches!(s.adapter, Adapter::Unavailable(ref w) if w.contains("off")));
        assert!(s.player.is_none() && s.phones.is_empty());
        t.remove(HCI);
        let s = snapshot(&t, "", Instant::now());
        assert_eq!(
            s.adapter,
            Adapter::Unavailable("no Bluetooth adapter".into())
        );
    }

    #[test]
    fn the_named_adapter_is_used() {
        let mut t = tree(true);
        t.insert("/org/bluez/hci1".into(), adapter(true));
        assert_eq!(adapter_path(&t, "hci1").as_deref(), Some("/org/bluez/hci1"));
        assert_eq!(adapter_path(&t, "hci0").as_deref(), Some(HCI));
        // hci1's snapshot doesn't see hci0's phone.
        assert!(snapshot(&t, "hci1", Instant::now()).phones.is_empty());
    }

    #[test]
    fn idle_transport_is_not_streaming() {
        let mut t = tree(true);
        t.insert(format!("{DEV}/fd0"), transport("idle"));
        assert!(!snapshot(&t, "hci0", Instant::now()).streaming);
        t.insert(format!("{DEV}/fd0"), transport("pending"));
        assert!(!snapshot(&t, "hci0", Instant::now()).streaming);
    }
}
