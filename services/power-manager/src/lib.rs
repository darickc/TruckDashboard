//! power-manager, Phase 6.7: the head unit's power key, pulse-only.
//!
//! The mini-box DCDC-USB is the only authority on power timing
//! ([ADR-0013](../../../docs/architecture/adr/0013-dcdc-usb-power-supply.md)).
//! When the ignition goes off it waits OFFDELAY, then pulses its PSW output,
//! which is wired to the Pi 5's J2 power-button pads. To Linux that is a
//! `KEY_POWER` press on the power button's input device, the same as the
//! onboard button. The supply's USB port isn't connected, so the Pi never
//! sees the ignition itself.
//!
//! The rules ([power-states.md](../../../docs/architecture/power-states.md)):
//!
//! - A press inside the boot window (`boot_key_ignore_s` after the kernel
//!   started) is ignored: it is the supply's ON pulse.
//! - Any later press shuts the Pi down. There is nothing to cancel it.
//! - The boot window ends on time alone, so a service that never gets ready
//!   can't stop the key-off pulse from working.
//!
//! logind ignores the key (`HandlePowerKey=ignore`); this service decides.
//! It powers off by exiting with [`POWER_OFF_EXIT`], and the unit's
//! `ExecStopPost` (run as root) calls `systemctl poweroff`. The service itself
//! needs no privileges.
//!
//! Not in this slice of 6.7: the reverse input, day/night and the backlight.
//!
//! Status: `[SIM]`. The policy, the event parsing and the device discovery are
//! unit-tested; nothing has run on the Pi.

pub mod evdev;
pub mod policy;
pub mod uptime;

/// Exit status that makes the unit's `ExecStopPost` power the Pi off
/// (`agl/rootfs/opt/f250/libexec/power-manager-stopped`).
pub const POWER_OFF_EXIT: u8 = 42;
