//! Reading the power key from Linux input devices, with no C library.
//!
//! An event device (`/dev/input/eventN`) delivers `struct input_event`
//! records (`linux/input.h`). On 64-bit Linux, the Pi 5's aarch64 included,
//! one is 24 bytes: a `struct timeval` (two 8-byte longs), then `__u16 type`,
//! `__u16 code` and `__s32 value`, in the CPU's byte order.
//!
//! Which device is the power key is found from sysfs: each
//! `/sys/class/input/eventN/device/capabilities/key` is the device's key
//! bitmap, and the ones with `KEY_POWER` are opened. That covers the Pi 5's
//! power button, which J2 and the DCDC-USB's PSW share
//! ([compatibility matrix](../../../docs/hardware/compatibility-matrix.md#raspberry-pi-5-power-button-and-5-v-input)),
//! without depending on its device name. A USB keyboard with a power key is
//! found too, and its power key shuts down as logind's would.

use std::path::{Path, PathBuf};

/// `sizeof(struct input_event)` on 64-bit Linux.
pub const EVENT_SIZE: usize = 24;
/// `EV_KEY`.
pub const EV_KEY: u16 = 0x01;
/// `KEY_POWER`.
pub const KEY_POWER: u16 = 116;
/// The value of an `EV_KEY` event for a press (0 is a release, 2 autorepeat).
pub const KEY_PRESSED: i32 = 1;

/// One input event, without its timestamp (realtime clock; not used).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Event {
    pub kind: u16,
    pub code: u16,
    pub value: i32,
}

impl Event {
    /// Parse one `struct input_event`.
    pub fn parse(raw: &[u8; EVENT_SIZE]) -> Self {
        Self {
            kind: u16::from_ne_bytes([raw[16], raw[17]]),
            code: u16::from_ne_bytes([raw[18], raw[19]]),
            value: i32::from_ne_bytes([raw[20], raw[21], raw[22], raw[23]]),
        }
    }

    /// A power key going down. Releases and autorepeat don't count, so one
    /// pulse is one press however long it lasts (its length is H21).
    pub fn is_power_press(&self) -> bool {
        self.kind == EV_KEY && self.code == KEY_POWER && self.value == KEY_PRESSED
    }
}

/// Whether a sysfs key bitmap (`capabilities/key`) has `code` set.
///
/// The kernel prints the bitmap as hex words of `unsigned long` (64 bits
/// here), most significant first, separated by spaces, with leading zero
/// words left out: `KEY_POWER` alone is `10000000000000 0`.
pub fn bitmap_has(bitmap: &str, code: u16) -> bool {
    let word = usize::from(code) / 64;
    let bit = u32::from(code) % 64;
    let words: Vec<&str> = bitmap.split_whitespace().collect();
    let Some(index) = words.len().checked_sub(1 + word) else {
        return false;
    };
    u64::from_str_radix(words[index], 16).is_ok_and(|w| w >> bit & 1 == 1)
}

/// The event devices whose key bitmap has `KEY_POWER`, as `/dev/input/eventN`
/// paths, sorted. `sysfs` is normally `/sys`.
pub fn find_power_keys(sysfs: &Path) -> Vec<PathBuf> {
    let Ok(entries) = std::fs::read_dir(sysfs.join("class/input")) else {
        return Vec::new();
    };
    let mut found: Vec<PathBuf> = entries
        .filter_map(Result::ok)
        .filter_map(|e| {
            let name = e.file_name().into_string().ok()?;
            if !name.starts_with("event") {
                return None;
            }
            let bitmap = std::fs::read_to_string(e.path().join("device/capabilities/key")).ok()?;
            bitmap_has(&bitmap, KEY_POWER).then(|| Path::new("/dev/input").join(name))
        })
        .collect();
    found.sort();
    found
}

#[cfg(test)]
mod tests {
    use super::*;

    fn raw(kind: u16, code: u16, value: i32) -> [u8; EVENT_SIZE] {
        let mut r = [0u8; EVENT_SIZE];
        r[..8].copy_from_slice(&1_762_700_000i64.to_ne_bytes()); // tv_sec
        r[8..16].copy_from_slice(&123_456i64.to_ne_bytes()); // tv_usec
        r[16..18].copy_from_slice(&kind.to_ne_bytes());
        r[18..20].copy_from_slice(&code.to_ne_bytes());
        r[20..24].copy_from_slice(&value.to_ne_bytes());
        r
    }

    #[test]
    fn parses_the_fields_after_the_timestamp() {
        let e = Event::parse(&raw(EV_KEY, KEY_POWER, 1));
        assert_eq!(
            e,
            Event {
                kind: 1,
                code: 116,
                value: 1
            }
        );
    }

    #[test]
    #[cfg(target_endian = "little")]
    fn little_endian_layout() {
        // EV_KEY, KEY_POWER, pressed, as the Pi 5 (aarch64, little-endian)
        // writes them after the 16-byte timeval.
        let mut r = [0u8; EVENT_SIZE];
        r[16..].copy_from_slice(&[0x01, 0x00, 0x74, 0x00, 0x01, 0x00, 0x00, 0x00]);
        assert!(Event::parse(&r).is_power_press());
    }

    #[test]
    fn only_a_power_key_press_counts() {
        assert!(Event::parse(&raw(EV_KEY, KEY_POWER, 1)).is_power_press());
        assert!(
            !Event::parse(&raw(EV_KEY, KEY_POWER, 0)).is_power_press(),
            "release"
        );
        assert!(
            !Event::parse(&raw(EV_KEY, KEY_POWER, 2)).is_power_press(),
            "autorepeat"
        );
        assert!(
            !Event::parse(&raw(EV_KEY, 115, 1)).is_power_press(),
            "KEY_VOLUMEUP"
        );
        assert!(!Event::parse(&raw(0, 0, 0)).is_power_press(), "EV_SYN");
        assert!(
            !Event::parse(&raw(0x04, KEY_POWER, 1)).is_power_press(),
            "EV_MSC"
        );
    }

    #[test]
    fn bitmap_with_only_the_power_key() {
        assert!(bitmap_has("10000000000000 0", KEY_POWER));
        assert!(bitmap_has("10000000000000 0\n", KEY_POWER));
    }

    #[test]
    fn bitmap_without_the_power_key() {
        assert!(!bitmap_has("0", KEY_POWER));
        assert!(!bitmap_has("", KEY_POWER));
        // KEY_ESC..KEY_D only (a word-0-only keyboard fragment).
        assert!(!bitmap_has("fffffffffffffffe", KEY_POWER));
        // Bit 115 (KEY_VOLUMEUP) and 117, not 116.
        assert!(!bitmap_has("28000000000000 0", KEY_POWER));
    }

    #[test]
    fn bitmap_of_a_full_keyboard() {
        // A typical USB keyboard: several words, KEY_POWER among them.
        let kb = "1000000000007 ff9f207ac14057ff febeffdfffefffff fffffffffffffffe";
        assert!(bitmap_has(kb, KEY_POWER));
        assert!(bitmap_has(kb, 1)); // KEY_ESC
    }

    #[test]
    fn bitmap_garbage_is_no() {
        assert!(!bitmap_has("zz 0", KEY_POWER));
    }

    #[test]
    fn finds_power_key_devices_in_sysfs() {
        let root = std::env::temp_dir().join(format!("f250-pm-sysfs-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&root);
        let dev = |name: &str, bitmap: Option<&str>| {
            let d = root
                .join("class/input")
                .join(name)
                .join("device/capabilities");
            std::fs::create_dir_all(&d).expect("mkdir");
            if let Some(b) = bitmap {
                std::fs::write(d.join("key"), b).expect("write");
            }
        };
        dev("event0", Some("10000000000000 0\n")); // the power button
        dev("event1", Some("0\n")); // touchscreen: no keys
        dev("event2", None); // no key bitmap at all
        dev(
            "event10",
            Some("1000000000007 ff9f207ac14057ff febeffdfffefffff fffffffffffffffe\n"),
        );
        dev("mouse0", Some("10000000000000 0\n")); // not an event device
        dev("input3", Some("10000000000000 0\n"));

        let found = find_power_keys(&root);
        let _ = std::fs::remove_dir_all(&root);
        assert_eq!(
            found,
            vec![
                PathBuf::from("/dev/input/event0"),
                PathBuf::from("/dev/input/event10")
            ]
        );
    }

    #[test]
    fn no_sysfs_means_no_devices() {
        assert!(find_power_keys(Path::new("/nonexistent-f250")).is_empty());
    }
}
