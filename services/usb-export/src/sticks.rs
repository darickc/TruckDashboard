//! Finding USB sticks: the block devices under a USB controller in sysfs,
//! and what udev found on them (`/run/udev/data/b<major>:<minor>`).
//!
//! Polled rather than told by udev: one daemon that looks every couple of
//! seconds needs no udev rule of its own, and can't race the map import's
//! rule (ADR-0037 decision 2). The udev database is read, not written; its
//! `E:KEY=VALUE` lines are what `udevadm info` prints.

use std::collections::BTreeMap;
use std::fs;
use std::path::{Path, PathBuf};

/// One filesystem (or an unformatted stick) seen on a USB block device.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Found {
    /// The kernel's name: `sda1`, or `sda` for a stick without a partition
    /// table (or with nothing usable on it).
    pub device: String,
    /// udev's ID_FS_TYPE (`exfat`, `vfat`, `ntfs`, ...); empty: none found.
    pub filesystem: String,
    pub label: String,
    /// Vendor and model, from udev.
    pub model: String,
    pub size_bytes: u64,
    /// The kernel's read-only flag (a write-protect switch).
    pub read_only: bool,
}

/// Where to look: `/sys/class/block` and `/run/udev/data` on the Pi.
#[derive(Debug, Clone)]
pub struct Paths {
    pub sys_block: PathBuf,
    pub udev_data: PathBuf,
}

impl Default for Paths {
    fn default() -> Self {
        Paths {
            sys_block: PathBuf::from("/sys/class/block"),
            udev_data: PathBuf::from("/run/udev/data"),
        }
    }
}

/// Filesystems the head unit mounts on a stick: exFAT (any size of file)
/// and FAT (files under 4 GiB). The same two the map import accepts.
pub fn supported(filesystem: &str) -> bool {
    matches!(filesystem, "exfat" | "vfat")
}

/// The largest file `filesystem` holds, or 0 when there is no limit that
/// matters for a recording.
pub fn max_file_bytes(filesystem: &str) -> u64 {
    if filesystem == "vfat" {
        (4u64 << 30) - 1
    } else {
        0
    }
}

/// Every USB stick's filesystems now, sorted by device name. A device udev
/// hasn't finished with yet (no database entry) is left for the next look.
pub fn scan(paths: &Paths) -> Vec<Found> {
    let Ok(entries) = fs::read_dir(&paths.sys_block) else {
        return Vec::new();
    };
    // name -> (resolved sysfs path, is a partition)
    let mut usb: BTreeMap<String, (PathBuf, bool)> = BTreeMap::new();
    for e in entries.flatten() {
        let name = e.file_name().to_string_lossy().to_string();
        let Ok(real) = fs::canonicalize(e.path()) else {
            continue;
        };
        if !on_usb(&real) {
            continue;
        }
        let partition = real.join("partition").exists();
        usb.insert(name, (real, partition));
    }
    let mut found = Vec::new();
    for (disk, (disk_path, partition)) in &usb {
        if *partition {
            continue;
        }
        let Some(disk_props) = udev(paths, disk_path) else {
            continue;
        };
        let model = model(&disk_props);
        let mut parts: Vec<Found> = Vec::new();
        for (name, (path, partition)) in &usb {
            if !*partition || path.parent() != Some(disk_path.as_path()) {
                continue;
            }
            let Some(props) = udev(paths, path) else {
                continue;
            };
            let fs_type = props.get("ID_FS_TYPE").cloned().unwrap_or_default();
            // Partitions without a filesystem (a reserved or swap
            // partition) are nobody's business here.
            if fs_type.is_empty() || props.get("ID_FS_USAGE").is_some_and(|u| u != "filesystem") {
                continue;
            }
            parts.push(make_found(name, path, &props, &model, fs_type));
        }
        if parts.is_empty() {
            // A whole-disk filesystem, or nothing usable at all: the stick
            // still shows, so the screen can say why it can't be used.
            let fs_type = disk_props.get("ID_FS_TYPE").cloned().unwrap_or_default();
            parts.push(make_found(disk, disk_path, &disk_props, &model, fs_type));
        }
        found.extend(parts);
    }
    found.sort_by(|a, b| a.device.cmp(&b.device));
    found
}

fn make_found(
    name: &str,
    path: &Path,
    props: &BTreeMap<String, String>,
    model: &str,
    filesystem: String,
) -> Found {
    Found {
        device: name.to_string(),
        filesystem,
        label: props.get("ID_FS_LABEL").cloned().unwrap_or_default(),
        model: model.to_string(),
        size_bytes: read_trim(&path.join("size"))
            .and_then(|s| s.parse::<u64>().ok())
            .map_or(0, |sectors| sectors.saturating_mul(512)),
        read_only: read_trim(&path.join("ro")).as_deref() == Some("1"),
    }
}

/// A block device whose sysfs path runs through a USB controller
/// (`.../usb1/1-1/1-1:1.0/host0/...`).
fn on_usb(real: &Path) -> bool {
    real.components().any(|c| {
        let s = c.as_os_str().to_string_lossy();
        s.starts_with("usb") && s[3..].bytes().all(|b| b.is_ascii_digit()) && s.len() > 3
    })
}

fn udev(paths: &Paths, sys: &Path) -> Option<BTreeMap<String, String>> {
    let dev = read_trim(&sys.join("dev"))?;
    let text = fs::read_to_string(paths.udev_data.join(format!("b{dev}"))).ok()?;
    Some(parse_udev(&text))
}

/// The `E:KEY=VALUE` properties of a udev database entry.
pub fn parse_udev(text: &str) -> BTreeMap<String, String> {
    text.lines()
        .filter_map(|l| l.strip_prefix("E:"))
        .filter_map(|kv| kv.split_once('='))
        .map(|(k, v)| (k.to_string(), v.to_string()))
        .collect()
}

fn model(props: &BTreeMap<String, String>) -> String {
    let clean = |k: &str| {
        props
            .get(k)
            .map(|v| v.replace('_', " ").trim().to_string())
            .unwrap_or_default()
    };
    let (vendor, model) = (clean("ID_VENDOR"), clean("ID_MODEL"));
    match (vendor.is_empty(), model.is_empty()) {
        (false, false) => format!("{vendor} {model}"),
        (true, false) => model,
        (false, true) => vendor,
        (true, true) => String::new(),
    }
}

fn read_trim(path: &Path) -> Option<String> {
    fs::read_to_string(path).ok().map(|s| s.trim().to_string())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn udev_entries_parse_to_their_properties() {
        let p = parse_udev(
            "S:disk/by-label/STICK\nI:123\nE:ID_FS_TYPE=exfat\nE:ID_FS_LABEL=STICK\nE:ID_MODEL=Ultra_Fit\nG:systemd\n",
        );
        assert_eq!(p.get("ID_FS_TYPE").map(String::as_str), Some("exfat"));
        assert_eq!(p.get("ID_FS_LABEL").map(String::as_str), Some("STICK"));
        assert_eq!(p.len(), 3);
        assert_eq!(model(&p), "Ultra Fit");
    }

    #[test]
    fn usb_paths_are_told_from_others() {
        assert!(on_usb(Path::new(
            "/sys/devices/platform/axi/1000120000.pcie/1f00300000.usb/xhci-hcd.1/usb3/3-1/3-1:1.0/host0/target0:0:0/0:0:0:0/block/sda"
        )));
        assert!(!on_usb(Path::new(
            "/sys/devices/platform/axi/1000110000.pcie/pci0001:00/0001:00:00.0/0001:01:00.0/nvme/nvme0/nvme0n1"
        )));
        assert!(!on_usb(Path::new(
            "/sys/devices/platform/1f00300000.usb/mmc0/block/mmcblk0"
        )));
    }

    #[test]
    fn only_fat_and_exfat_are_supported_and_fat_caps_file_size() {
        assert!(supported("exfat") && supported("vfat"));
        assert!(!supported("ntfs") && !supported("ext4") && !supported(""));
        assert_eq!(max_file_bytes("vfat"), 4_294_967_295);
        assert_eq!(max_file_bytes("exfat"), 0);
    }
}
