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
//! It also reads the camera switch ([`camera_switch`]; ADR-0024, ADR-0025):
//! five contacts the kernel turns into keys, debounced here, and logged until
//! camera-manager (Phase 6.6) takes the moves.
//!
//! Not in this slice of 6.7: day/night and the backlight.
//!
//! Status: the power key is unit-tested `[SIM]`, and `[BENCH]` on the Pi 5
//! with its own button (bench-log 2026-11-09): presses after the window power
//! off, a press inside it is ignored. The DCDC-USB's PSW on J2 isn't wired
//! yet. The camera switch is `[SIM]` only: the `gpio-key` overlays haven't run
//! on the Pi.

pub mod camera_switch;
pub mod evdev;
pub mod policy;
pub mod uptime;

/// Exit status that makes the unit's `ExecStopPost` power the Pi off
/// (`agl/rootfs/opt/f250/libexec/power-manager-stopped`).
pub const POWER_OFF_EXIT: u8 = 42;
