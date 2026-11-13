//! The volume knob (ADR-0043 decision 7), as Linux input: whatever device
//! has the volume keys or a dial, read from `/dev/input/event*`.
//!
//! - `KEY_VOLUMEUP`/`KEY_VOLUMEDOWN`: one step a press and one at each
//!   autorepeat (holding a button ramps); `KEY_MUTE`: a press toggles mute.
//!   A USB volume knob (HID Consumer Control), a keyboard's media keys,
//!   buttons on `gpio-key`.
//! - `KEY_PLAYPAUSE`: a press plays or pauses the phone (the knob display's
//!   push or tap, a USB knob's button).
//! - `REL_DIAL`: each event's value in steps, clockwise up. A rotary encoder
//!   through the kernel's `rotary-encoder` driver with `linux,axis = 7` in
//!   relative mode (the overlay's settings are UNVERIFIED on the image).
//!   Never `REL_X` or `REL_WHEEL`, so a mouse doesn't turn the volume.
//!
//! Which knob the truck gets is the owner's choice (TODO); none of it is
//! tested on the Pi (bench check 24).

use std::collections::HashSet;
use std::io::Read;
use std::path::{Path, PathBuf};
use std::time::Duration;

use f250_evdev::{
    EV_KEY, EV_REL, EVENT_SIZE, Event, KEY_MUTE, KEY_PLAYPAUSE, KEY_PRESSED, KEY_REPEATED,
    KEY_VOLUMEDOWN, KEY_VOLUMEUP, REL_DIAL, device_name, find_devices,
};
use tokio::sync::mpsc;

use crate::volume::Change;

pub const KEYS: [u16; 4] = [KEY_MUTE, KEY_VOLUMEDOWN, KEY_VOLUMEUP, KEY_PLAYPAUSE];
pub const RELS: [u16; 1] = [REL_DIAL];
/// A knob plugged in later is found within this long.
pub const RESCAN: Duration = Duration::from_secs(5);

#[derive(Debug, Clone)]
pub struct KnobConfig {
    /// Normally `/sys`.
    pub sysfs: PathBuf,
    /// Counter-clockwise up (an encoder wired the other way round).
    pub invert: bool,
}

/// What the knob asks for.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Action {
    Volume(Change),
    /// Play or pause the phone, whichever it isn't doing.
    PlayPause,
}

/// What an input event does, if anything.
pub fn action_for(e: &Event, invert: bool) -> Option<Action> {
    let volume = |c| Some(Action::Volume(c));
    match (e.kind, e.code) {
        (EV_KEY, KEY_VOLUMEUP) if e.value == KEY_PRESSED || e.value == KEY_REPEATED => {
            volume(Change::Steps(1))
        }
        (EV_KEY, KEY_VOLUMEDOWN) if e.value == KEY_PRESSED || e.value == KEY_REPEATED => {
            volume(Change::Steps(-1))
        }
        (EV_KEY, KEY_MUTE) if e.value == KEY_PRESSED => volume(Change::ToggleMute),
        // The press only: holding it doesn't toggle again.
        (EV_KEY, KEY_PLAYPAUSE) if e.value == KEY_PRESSED => Some(Action::PlayPause),
        (EV_REL, REL_DIAL) if e.value != 0 => {
            let steps = if invert {
                e.value.saturating_neg()
            } else {
                e.value
            };
            volume(Change::Steps(steps))
        }
        _ => None,
    }
}

/// Reads `path` until it fails or `tx` closes, sending each change.
pub fn read_events(path: &Path, invert: bool, tx: &mpsc::Sender<Action>) -> std::io::Result<()> {
    let mut f = std::fs::File::open(path)?;
    let mut buf = [0u8; EVENT_SIZE];
    loop {
        f.read_exact(&mut buf)?;
        if let Some(c) = action_for(&Event::parse(&buf), invert)
            && tx.blocking_send(c).is_err()
        {
            return Ok(());
        }
    }
}

enum Msg {
    Gone(PathBuf, String),
}

/// Finds knob devices now and every [RESCAN], one reader thread each (a
/// blocking read never holds up the runtime), until `tx` closes.
pub async fn run(cfg: KnobConfig, tx: mpsc::Sender<Action>) {
    let (gone_tx, mut gone_rx) = mpsc::channel::<Msg>(8);
    let mut started: HashSet<PathBuf> = HashSet::new();
    // A device that keeps failing is logged once, not every rescan.
    let mut last_error: std::collections::HashMap<PathBuf, String> = Default::default();
    let mut rescan = tokio::time::interval(RESCAN);
    rescan.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Delay);
    let mut said_none = false;
    loop {
        tokio::select! {
            _ = rescan.tick() => {
                if tx.is_closed() {
                    return;
                }
                let found = find_devices(&cfg.sysfs, &KEYS, &RELS);
                if found.is_empty() && started.is_empty() && !said_none {
                    eprintln!("[audio] volume knob: no input device has the volume keys or a dial (REL_DIAL); looking every {} s", RESCAN.as_secs());
                    said_none = true;
                }
                for d in found {
                    if !started.insert(d.path.clone()) {
                        continue;
                    }
                    let name = device_name(&cfg.sysfs, &d.path).unwrap_or_default();
                    let mut what: Vec<&str> = d.keys.iter().map(|&k| match k {
                        KEY_MUTE => "KEY_MUTE",
                        KEY_VOLUMEDOWN => "KEY_VOLUMEDOWN",
                        KEY_PLAYPAUSE => "KEY_PLAYPAUSE",
                        _ => "KEY_VOLUMEUP",
                    }).collect();
                    if !d.rels.is_empty() {
                        what.push("REL_DIAL");
                    }
                    if !last_error.contains_key(&d.path) {
                        eprintln!("[audio] volume knob: {} ({name}): {}", d.path.display(), what.join(", "));
                    }
                    let (path, tx, gone, invert) = (d.path, tx.clone(), gone_tx.clone(), cfg.invert);
                    std::thread::spawn(move || {
                        let why = match read_events(&path, invert, &tx) {
                            Ok(()) => "closed".to_string(),
                            Err(e) => e.to_string(),
                        };
                        let _ = gone.blocking_send(Msg::Gone(path, why));
                    });
                }
            }
            Some(Msg::Gone(path, why)) = gone_rx.recv() => {
                if last_error.get(&path) != Some(&why) {
                    eprintln!("[audio] volume knob: {}: {why}", path.display());
                    last_error.insert(path.clone(), why);
                }
                started.remove(&path);
            }
        }
    }
}

#[cfg(test)]
#[allow(clippy::unwrap_used)]
mod tests {
    use super::*;

    fn raw(kind: u16, code: u16, value: i32) -> [u8; EVENT_SIZE] {
        let mut r = [0u8; EVENT_SIZE];
        r[16..18].copy_from_slice(&kind.to_ne_bytes());
        r[18..20].copy_from_slice(&code.to_ne_bytes());
        r[20..24].copy_from_slice(&value.to_ne_bytes());
        r
    }

    fn ev(kind: u16, code: u16, value: i32) -> Event {
        Event::parse(&raw(kind, code, value))
    }

    #[test]
    fn volume_keys_step_and_repeat() {
        assert_eq!(
            action_for(&ev(EV_KEY, KEY_VOLUMEUP, 1), false),
            Some(Action::Volume(Change::Steps(1)))
        );
        assert_eq!(
            action_for(&ev(EV_KEY, KEY_VOLUMEUP, 2), false),
            Some(Action::Volume(Change::Steps(1))),
            "held"
        );
        assert_eq!(
            action_for(&ev(EV_KEY, KEY_VOLUMEUP, 0), false),
            None,
            "release"
        );
        assert_eq!(
            action_for(&ev(EV_KEY, KEY_VOLUMEDOWN, 1), false),
            Some(Action::Volume(Change::Steps(-1)))
        );
        assert_eq!(
            action_for(&ev(EV_KEY, KEY_VOLUMEDOWN, 2), false),
            Some(Action::Volume(Change::Steps(-1)))
        );
    }

    #[test]
    fn mute_toggles_on_the_press_only() {
        assert_eq!(
            action_for(&ev(EV_KEY, KEY_MUTE, 1), false),
            Some(Action::Volume(Change::ToggleMute))
        );
        assert_eq!(
            action_for(&ev(EV_KEY, KEY_MUTE, 2), false),
            None,
            "held: not toggled again"
        );
        assert_eq!(action_for(&ev(EV_KEY, KEY_MUTE, 0), false), None);
    }

    #[test]
    fn play_pause_on_the_press_only() {
        assert_eq!(
            action_for(&ev(EV_KEY, KEY_PLAYPAUSE, 1), false),
            Some(Action::PlayPause)
        );
        assert_eq!(
            action_for(&ev(EV_KEY, KEY_PLAYPAUSE, 2), false),
            None,
            "held"
        );
        assert_eq!(
            action_for(&ev(EV_KEY, KEY_PLAYPAUSE, 0), false),
            None,
            "release"
        );
    }

    #[test]
    fn the_dial_turns_by_its_value() {
        assert_eq!(
            action_for(&ev(EV_REL, REL_DIAL, 1), false),
            Some(Action::Volume(Change::Steps(1)))
        );
        assert_eq!(
            action_for(&ev(EV_REL, REL_DIAL, -3), false),
            Some(Action::Volume(Change::Steps(-3)))
        );
        assert_eq!(
            action_for(&ev(EV_REL, REL_DIAL, 2), true),
            Some(Action::Volume(Change::Steps(-2))),
            "inverted"
        );
        assert_eq!(action_for(&ev(EV_REL, REL_DIAL, 0), false), None);
    }

    #[test]
    fn a_mouse_and_other_keys_do_nothing() {
        for e in [
            ev(EV_REL, 0x00, 5),       // REL_X
            ev(EV_REL, 0x08, -1),      // REL_WHEEL
            ev(EV_KEY, 116, 1),        // KEY_POWER
            ev(EV_KEY, 183, 1),        // KEY_F13 (the camera switch)
            ev(0, 0, 0),               // EV_SYN
            ev(0x04, KEY_VOLUMEUP, 1), // EV_MSC
        ] {
            assert_eq!(action_for(&e, false), None, "{e:?}");
        }
    }

    #[tokio::test]
    async fn reads_a_device_until_it_ends() {
        // Recorded events: volume up, its release, a dial turn of two
        // detents, a mouse wheel, mute; then the device goes (end of file).
        let path = std::env::temp_dir().join(format!("f250-knob-{}", std::process::id()));
        let mut bytes = Vec::new();
        for (k, c, v) in [
            (EV_KEY, KEY_VOLUMEUP, 1),
            (0, 0, 0),
            (EV_KEY, KEY_VOLUMEUP, 0),
            (EV_REL, REL_DIAL, -2),
            (EV_REL, 0x08, 1),
            (EV_KEY, KEY_MUTE, 1),
            (EV_KEY, KEY_PLAYPAUSE, 1),
            (EV_KEY, KEY_PLAYPAUSE, 0),
        ] {
            bytes.extend_from_slice(&raw(k, c, v));
        }
        std::fs::write(&path, bytes).unwrap();
        let (tx, mut rx) = mpsc::channel(16);
        let p = path.clone();
        let r = tokio::task::spawn_blocking(move || read_events(&p, false, &tx))
            .await
            .unwrap();
        let _ = std::fs::remove_file(&path);
        assert_eq!(
            r.unwrap_err().kind(),
            std::io::ErrorKind::UnexpectedEof,
            "a device that goes is an error"
        );
        let mut got = Vec::new();
        while let Ok(c) = rx.try_recv() {
            got.push(c);
        }
        assert_eq!(
            got,
            [
                Action::Volume(Change::Steps(1)),
                Action::Volume(Change::Steps(-2)),
                Action::Volume(Change::ToggleMute),
                Action::PlayPause
            ]
        );
    }
}
