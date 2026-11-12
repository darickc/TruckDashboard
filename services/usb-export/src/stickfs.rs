//! Mounting a stick, its free space, and whether it is still plugged in.
//! [`SystemFs`] runs `mount` and `umount` in the service's own mount
//! namespace (the unit's `PrivateMounts=yes`), so nothing else on the head
//! unit sees the stick mounted. [`DirFs`] stands a directory in for a stick,
//! for the tests and for development on the Mac.

use std::io;
use std::path::{Path, PathBuf};
use std::process::Command;
use std::sync::Mutex;

/// A mounted filesystem's space.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Space {
    pub free_bytes: u64,
    pub total_bytes: u64,
    /// Mounted read-only, whatever was asked: `mount` falls back to
    /// read-only on a write-protected stick and only warns.
    pub read_only: bool,
}

pub trait StickFs: Send + Sync {
    /// Mounts `device` (`sda1`) and returns where. `writable` false mounts
    /// it read-only. Always nosuid, nodev, noexec: nothing on a stick runs.
    fn mount(&self, device: &str, filesystem: &str, writable: bool) -> io::Result<PathBuf>;
    /// Unmounts what [`Self::mount`] mounted. `lazy` detaches it even while
    /// busy (for a stick that has gone).
    fn unmount(&self, at: &Path, lazy: bool) -> io::Result<()>;
    fn space(&self, at: &Path) -> io::Result<Space>;
    /// Flushes everything written to the filesystem at `at` to the stick.
    fn sync(&self, at: &Path) -> io::Result<()>;
    /// The device is still there (not pulled out).
    fn present(&self, device: &str) -> bool;
}

/// The real thing, on the Pi.
#[derive(Debug, Clone)]
pub struct SystemFs {
    /// Where mount points go: `/run/f250-export` (the unit's runtime
    /// directory).
    pub mount_dir: PathBuf,
    pub dev_dir: PathBuf,
    pub sys_block: PathBuf,
}

/// A device name the kernel could have made: `sda`, `sdb1`. Anything else
/// is refused before it gets near a path or a command line.
pub fn valid_device(name: &str) -> bool {
    (1..=16).contains(&name.len())
        && name
            .bytes()
            .all(|b| b.is_ascii_lowercase() || b.is_ascii_digit())
        && name.as_bytes()[0].is_ascii_lowercase()
}

fn checked(device: &str) -> io::Result<&str> {
    if valid_device(device) {
        Ok(device)
    } else {
        Err(io::Error::new(
            io::ErrorKind::InvalidInput,
            format!("not a device name: {device:?}"),
        ))
    }
}

/// `mount -o` options for a stick.
pub fn mount_options(writable: bool) -> String {
    format!(
        "{},nosuid,nodev,noexec,noatime",
        if writable { "rw" } else { "ro" }
    )
}

fn run(cmd: &mut Command) -> io::Result<()> {
    let out = cmd.output()?;
    if out.status.success() {
        return Ok(());
    }
    let err = String::from_utf8_lossy(&out.stderr).trim().to_string();
    Err(io::Error::other(if err.is_empty() {
        format!("{:?} failed ({})", cmd.get_program(), out.status)
    } else {
        err
    }))
}

impl StickFs for SystemFs {
    fn mount(&self, device: &str, filesystem: &str, writable: bool) -> io::Result<PathBuf> {
        let device = checked(device)?;
        if !crate::sticks::supported(filesystem) {
            return Err(io::Error::new(
                io::ErrorKind::Unsupported,
                format!("{filesystem} isn't mounted here"),
            ));
        }
        let at = self.mount_dir.join(format!("stick-{device}"));
        std::fs::create_dir_all(&at)?;
        run(Command::new("mount")
            .arg("-t")
            .arg(filesystem)
            .arg("-o")
            .arg(mount_options(writable))
            .arg(self.dev_dir.join(device))
            .arg(&at))?;
        Ok(at)
    }

    fn unmount(&self, at: &Path, lazy: bool) -> io::Result<()> {
        let mut cmd = Command::new("umount");
        if lazy {
            cmd.arg("-l");
        }
        run(cmd.arg(at))?;
        let _ = std::fs::remove_dir(at);
        Ok(())
    }

    fn space(&self, at: &Path) -> io::Result<Space> {
        statvfs_space(at)
    }

    fn sync(&self, at: &Path) -> io::Result<()> {
        let dir = std::fs::File::open(at)?;
        #[cfg(target_os = "linux")]
        return rustix::fs::syncfs(&dir).map_err(io::Error::from);
        #[cfg(not(target_os = "linux"))]
        dir.sync_all()
    }

    fn present(&self, device: &str) -> bool {
        valid_device(device) && self.sys_block.join(device).exists()
    }
}

fn statvfs_space(at: &Path) -> io::Result<Space> {
    let s = rustix::fs::statvfs(at).map_err(io::Error::from)?;
    Ok(Space {
        free_bytes: s.f_bavail.saturating_mul(s.f_frsize),
        total_bytes: s.f_blocks.saturating_mul(s.f_frsize),
        read_only: s.f_flag.contains(rustix::fs::StatVfsMountFlags::RDONLY),
    })
}

/// Directories standing in for sticks: `device` → directory. Mounting
/// returns the directory; nothing is mounted. Free space is the real
/// filesystem's unless set; a stick can be made read-only or pulled out.
#[derive(Debug, Default)]
pub struct DirFs {
    inner: Mutex<DirFsInner>,
}

#[derive(Debug, Default)]
struct DirFsInner {
    sticks: Vec<(String, PathBuf)>,
    free: Option<u64>,
    read_only: bool,
    gone: Vec<String>,
    mounts: Vec<(PathBuf, bool)>,
    /// (device, presence checks left before it is pulled)
    pull_after: Option<(String, u32)>,
}

impl DirFs {
    pub fn new() -> DirFs {
        DirFs::default()
    }

    pub fn add(&self, device: &str, dir: impl Into<PathBuf>) {
        self.lock().sticks.push((device.to_string(), dir.into()));
    }

    /// Reports this much free space (and as much again in total).
    pub fn set_free(&self, bytes: u64) {
        self.lock().free = Some(bytes);
    }

    pub fn set_read_only(&self, ro: bool) {
        self.lock().read_only = ro;
    }

    /// The stick is pulled out: `present` is false from now on.
    pub fn pull(&self, device: &str) {
        self.lock().gone.push(device.to_string());
    }

    /// The stick is pulled out after `checks` more calls to `present` (the
    /// copy asks before each chunk): a pull in the middle of a copy.
    pub fn pull_after(&self, device: &str, checks: u32) {
        self.lock().pull_after = Some((device.to_string(), checks));
    }

    /// Mounted now: (directory, writable).
    pub fn mounts(&self) -> Vec<(PathBuf, bool)> {
        self.lock().mounts.clone()
    }

    fn lock(&self) -> std::sync::MutexGuard<'_, DirFsInner> {
        self.inner.lock().unwrap_or_else(|e| e.into_inner())
    }
}

impl StickFs for DirFs {
    fn mount(&self, device: &str, _filesystem: &str, writable: bool) -> io::Result<PathBuf> {
        let mut g = self.lock();
        if g.gone.iter().any(|d| d == device) {
            return Err(io::Error::new(io::ErrorKind::NotFound, "no such device"));
        }
        let dir = g
            .sticks
            .iter()
            .find(|(d, _)| d == device)
            .map(|(_, p)| p.clone())
            .ok_or_else(|| io::Error::new(io::ErrorKind::NotFound, "no such device"))?;
        if g.mounts.iter().any(|(p, _)| *p == dir) {
            return Err(io::Error::other("already mounted"));
        }
        let writable = writable && !g.read_only;
        g.mounts.push((dir.clone(), writable));
        Ok(dir)
    }

    fn unmount(&self, at: &Path, _lazy: bool) -> io::Result<()> {
        let mut g = self.lock();
        let before = g.mounts.len();
        g.mounts.retain(|(p, _)| p != at);
        if g.mounts.len() == before {
            return Err(io::Error::other("not mounted"));
        }
        Ok(())
    }

    fn space(&self, at: &Path) -> io::Result<Space> {
        let g = self.lock();
        let real = statvfs_space(at)?;
        let writable = g.mounts.iter().any(|(p, w)| p == at && *w);
        Ok(Space {
            free_bytes: g.free.unwrap_or(real.free_bytes),
            total_bytes: g.free.map_or(real.total_bytes, |f| f.saturating_mul(2)),
            read_only: !writable,
        })
    }

    fn sync(&self, _at: &Path) -> io::Result<()> {
        Ok(())
    }

    fn present(&self, device: &str) -> bool {
        let mut g = self.lock();
        if let Some((d, n)) = g.pull_after.as_mut()
            && d == device
        {
            if *n == 0 {
                g.pull_after = None;
                g.gone.push(device.to_string());
            } else {
                *n -= 1;
            }
        }
        g.sticks.iter().any(|(d, _)| d == device) && !g.gone.iter().any(|d| d == device)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn only_kernel_style_names_are_devices() {
        for ok in ["sda", "sda1", "sdb12", "mmcblk0p1"] {
            assert!(valid_device(ok), "{ok}");
        }
        for bad in [
            "",
            "../sda",
            "sda/1",
            "SDA",
            "1sda",
            "sda 1",
            "sda1;reboot",
            "averyveryverylongname",
        ] {
            assert!(!valid_device(bad), "{bad}");
        }
    }

    #[test]
    fn sticks_are_never_mounted_with_suid_devices_or_exec() {
        assert_eq!(mount_options(false), "ro,nosuid,nodev,noexec,noatime");
        assert_eq!(mount_options(true), "rw,nosuid,nodev,noexec,noatime");
    }
}
