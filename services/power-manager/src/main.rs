//! `power-manager`: shut the Pi down on the DCDC-USB's PSW pulse (the power
//! key), except in the boot window. Pulse-only (ADR-0013); see the library
//! docs for the rules.
//!
//!   power-manager --boot-key-ignore-s 30
//!   power-manager --dry-run --key-device /dev/input/event0    # bench: log, don't power off
//!
//! Powering off is an exit with status 42; the unit's `ExecStopPost` (as root)
//! runs `systemctl poweroff`. Outside systemd, exit 42 only ends the process.

use std::collections::{HashMap, HashSet};
use std::io::Read;
use std::path::{Path, PathBuf};
use std::process::ExitCode;
use std::time::Duration;

use clap::Parser;
use f250_sd_notify::{Heartbeat, Notifier, run_watchdog};
use power_manager::POWER_OFF_EXIT;
use power_manager::evdev::{EVENT_SIZE, Event, find_power_keys};
use power_manager::policy::{Action, Input, Policy, State};
use power_manager::uptime;
use tokio::sync::mpsc;

#[derive(Parser)]
#[command(about = "F-250 power manager: the power key, pulse-only (ADR-0013)")]
struct Args {
    /// Seconds after the kernel started in which a power-key press is
    /// ignored (the supply's ON pulse). An example value: tune it once H21
    /// measures the ON pulse, and keep it shorter than the DCDC-USB's
    /// OFFDELAY.
    #[arg(long, default_value_t = 30)]
    boot_key_ignore_s: u64,
    /// Read only these event devices. Default: every /dev/input/event* whose
    /// key bitmap has KEY_POWER, rescanned every few seconds.
    #[arg(long = "key-device")]
    key_devices: Vec<PathBuf>,
    /// Where sysfs is (for tests).
    #[arg(long, default_value = "/sys")]
    sysfs: PathBuf,
    /// Log a power-off instead of doing it (bench).
    #[arg(long)]
    dry_run: bool,
}

/// What a reader thread reports.
enum Msg {
    Opened(PathBuf),
    Press(PathBuf),
    Gone(PathBuf, String),
}

const TICK: Duration = Duration::from_secs(1);
const RESCAN: Duration = Duration::from_secs(5);

/// One thread per device: a blocking read never holds up the runtime or the
/// process's exit.
fn spawn_reader(path: PathBuf, tx: mpsc::Sender<Msg>) {
    std::thread::spawn(move || {
        let why = match read_presses(&path, &tx) {
            Ok(()) => "closed".to_string(),
            Err(e) => e.to_string(),
        };
        let _ = tx.blocking_send(Msg::Gone(path, why));
    });
}

fn read_presses(path: &Path, tx: &mpsc::Sender<Msg>) -> std::io::Result<()> {
    let mut f = std::fs::File::open(path)?;
    if tx.blocking_send(Msg::Opened(path.to_path_buf())).is_err() {
        return Ok(());
    }
    let mut buf = [0u8; EVENT_SIZE];
    loop {
        f.read_exact(&mut buf)?;
        if Event::parse(&buf).is_power_press()
            && tx.blocking_send(Msg::Press(path.to_path_buf())).is_err()
        {
            return Ok(());
        }
    }
}

struct Devices {
    fixed: Vec<PathBuf>,
    sysfs: PathBuf,
    /// Readers started and not yet gone.
    started: HashSet<PathBuf>,
    /// Readers that opened their device.
    open: HashSet<PathBuf>,
    /// The last error logged per device, so a device that keeps failing
    /// is logged once, not every rescan.
    last_error: HashMap<PathBuf, String>,
}

impl Devices {
    fn candidates(&self) -> Vec<PathBuf> {
        if self.fixed.is_empty() {
            find_power_keys(&self.sysfs)
        } else {
            self.fixed.clone()
        }
    }

    fn rescan(&mut self, tx: &mpsc::Sender<Msg>) {
        for path in self.candidates() {
            if self.started.insert(path.clone()) {
                spawn_reader(path, tx.clone());
            }
        }
    }

    /// Whether a key device is open, once every started reader has
    /// answered; `None` while one hasn't.
    fn settled(&self) -> Option<bool> {
        (self.started.len() == self.open.len()).then_some(!self.open.is_empty())
    }
}

fn describe(policy: &Policy, devices: &Devices) -> String {
    let keys = devices.open.len();
    match policy.state() {
        State::Starting => format!(
            "boot window: power key ignored until {} s after boot ({keys} key device(s))",
            policy.boot_window().as_secs()
        ),
        State::Running => format!("running: the power key shuts down ({keys} key device(s))"),
        State::Fault => {
            "FAULT: no power-key device can be read: no clean shutdown, HARDOFF will cut power"
                .to_string()
        }
        State::ShuttingDown => "shutting down".to_string(),
    }
}

#[tokio::main(flavor = "current_thread")]
async fn main() -> ExitCode {
    let args = Args::parse();
    let notifier = Notifier::from_env();
    if let Some(problem) = notifier.problem() {
        eprintln!("[power-manager] {problem}");
    }
    let heartbeat = Heartbeat::new();
    tokio::spawn(run_watchdog(
        notifier.clone(),
        heartbeat.clone(),
        "power-manager",
    ));
    if !uptime::from_kernel() {
        eprintln!(
            "[power-manager] no /proc/uptime: the boot window counts from this process's start"
        );
    }

    let window = Duration::from_secs(args.boot_key_ignore_s);
    let mut policy = Policy::new(window);
    let (tx, mut rx) = mpsc::channel(32);
    let mut devices = Devices {
        fixed: args.key_devices.clone(),
        sysfs: args.sysfs.clone(),
        started: HashSet::new(),
        open: HashSet::new(),
        last_error: HashMap::new(),
    };
    devices.rescan(&tx);
    let mut had_key = true; // what the policy assumes until told otherwise
    if devices.started.is_empty() {
        eprintln!("[power-manager] no power-key device found");
        policy.handle(Input::KeyDeviceLost, uptime::since_boot());
        had_key = false;
    }
    eprintln!(
        "[power-manager] {}s after boot; presses before {}s are ignored{}",
        uptime::since_boot().as_secs(),
        window.as_secs(),
        if args.dry_run {
            " (dry run: no power-off)"
        } else {
            ""
        }
    );
    if let Err(e) = notifier.ready(&describe(&policy, &devices)) {
        eprintln!("[power-manager] systemd READY not sent: {e}");
    }

    let mut tick = tokio::time::interval(TICK);
    let mut rescan = tokio::time::interval(RESCAN);
    let mut term = match tokio::signal::unix::signal(tokio::signal::unix::SignalKind::terminate()) {
        Ok(s) => s,
        Err(e) => {
            eprintln!("[power-manager] can't watch SIGTERM: {e}");
            return ExitCode::FAILURE;
        }
    };
    let mut last_status = String::new();

    loop {
        let input = tokio::select! {
            _ = tick.tick() => {
                heartbeat.beat();
                Some(Input::Tick)
            }
            _ = rescan.tick() => {
                devices.rescan(&tx);
                None
            }
            Some(msg) = rx.recv() => match msg {
                Msg::Opened(path) => {
                    eprintln!("[power-manager] reading the power key on {}", path.display());
                    devices.last_error.remove(&path);
                    devices.open.insert(path);
                    None
                }
                Msg::Press(path) => {
                    eprintln!("[power-manager] power key on {} at {:.1} s after boot", path.display(), uptime::since_boot().as_secs_f64());
                    Some(Input::Key)
                }
                Msg::Gone(path, why) => {
                    if devices.last_error.get(&path) != Some(&why) {
                        eprintln!("[power-manager] {}: {why}", path.display());
                        devices.last_error.insert(path.clone(), why);
                    }
                    devices.started.remove(&path);
                    devices.open.remove(&path);
                    None
                }
            },
            _ = term.recv() => {
                let _ = notifier.stopping();
                return ExitCode::SUCCESS;
            }
        };

        // Key device lost or back, once every reader has answered.
        let device_input = match devices.settled() {
            Some(have) if have != had_key => {
                had_key = have;
                Some(if have {
                    Input::KeyDeviceBack
                } else {
                    Input::KeyDeviceLost
                })
            }
            _ => None,
        };

        for input in [device_input, input].into_iter().flatten() {
            match policy.handle(input, uptime::since_boot()) {
                Action::None => {}
                Action::EnteredRunning => {
                    eprintln!("[power-manager] boot window over: the power key now shuts down")
                }
                Action::EnteredFault => eprintln!(
                    "[power-manager] FAULT: no power-key device; the PSW pulse can't be seen"
                ),
                Action::LeftFault => eprintln!("[power-manager] a power-key device is back"),
                Action::IgnoredInBootWindow => eprintln!(
                    "[power-manager] ignored: inside the boot window (the supply's ON pulse)"
                ),
                Action::IgnoredWhileShuttingDown => {}
                Action::PowerOff if args.dry_run => {
                    eprintln!("[power-manager] dry run: would power off now");
                    // Start over, already past the window, so the next
                    // press is handled the same way.
                    policy = Policy::new(window);
                    policy.handle(Input::Tick, uptime::since_boot());
                    if !had_key {
                        policy.handle(Input::KeyDeviceLost, uptime::since_boot());
                    }
                }
                Action::PowerOff => {
                    eprintln!("[power-manager] power off: power key after the boot window");
                    let _ = notifier.stopping();
                    return ExitCode::from(POWER_OFF_EXIT);
                }
            }
        }

        let status = describe(&policy, &devices);
        if status != last_status {
            let _ = notifier.status(&status);
            last_status = status;
        }
    }
}
