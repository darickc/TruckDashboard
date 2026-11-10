//! `power-manager`: shut the Pi down on the DCDC-USB's PSW pulse (the power
//! key), except in the boot window. Pulse-only (ADR-0013); see the library
//! docs for the rules. It also reads the camera switch (ADR-0024, ADR-0025)
//! and passes each move to camera-manager (ADR-0026).
//!
//!   power-manager --boot-key-ignore-s 30 --camera-manager unix:/run/f250/camera.sock
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
use power_manager::camera_link::{self, Link, LinkConfig, NotQueued, Outcome};
use power_manager::camera_switch::{Debouncer, Direction};
use power_manager::evdev::{EVENT_SIZE, Event, KEY_POWER, device_keys, find_keys};
use power_manager::policy::{Action, Input, Policy, State};
use power_manager::uptime;
use tokio::sync::mpsc;
use tokio::time::Instant;

#[derive(Parser)]
#[command(
    about = "F-250 power manager: the power key, pulse-only (ADR-0013), and the camera switch"
)]
struct Args {
    /// Seconds after the kernel started in which a power-key press is
    /// ignored (the supply's ON pulse). An example value: tune it once H21
    /// measures the ON pulse, and keep it shorter than the DCDC-USB's
    /// OFFDELAY.
    #[arg(long, default_value_t = 30)]
    boot_key_ignore_s: u64,
    /// Read only these event devices for the power key. Default: every
    /// /dev/input/event* whose key bitmap has KEY_POWER, rescanned every few
    /// seconds.
    #[arg(long = "key-device")]
    key_devices: Vec<PathBuf>,
    /// Read only these event devices for the camera switch. Default: every
    /// /dev/input/event* with one of its keys (F13-F17, from the gpio-key
    /// overlays), rescanned every few seconds.
    #[arg(long = "switch-device")]
    switch_devices: Vec<PathBuf>,
    /// How long a camera-switch contact must be the only one closed to
    /// count. An example value: tune it on the fitted switch (H32).
    #[arg(long, default_value_t = 30)]
    switch_debounce_ms: u64,
    /// camera-manager's API (unix:PATH or tcp:HOST:PORT), which takes the
    /// camera switch's moves. Without it the moves are only logged.
    #[arg(long, value_name = "ENDPOINT")]
    camera_manager: Option<String>,
    /// How long a call to camera-manager may take, connecting included. An
    /// example value.
    #[arg(long, default_value_t = 1000)]
    camera_call_timeout_ms: u64,
    /// A move still waiting to be sent after this long is dropped, so the
    /// camera never changes long after the switch moved. An example value.
    #[arg(long, default_value_t = 1000)]
    camera_move_max_age_ms: u64,
    /// Where sysfs is (for tests).
    #[arg(long, default_value = "/sys")]
    sysfs: PathBuf,
    /// Log a power-off instead of doing it (bench).
    #[arg(long)]
    dry_run: bool,
}

/// What a set of devices is read for.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum Role {
    PowerKey,
    Switch,
}

impl Role {
    fn codes(self) -> Vec<u16> {
        match self {
            Role::PowerKey => vec![KEY_POWER],
            Role::Switch => Direction::keycodes().to_vec(),
        }
    }
}

/// What a reader thread reports.
enum Msg {
    Opened(Role, PathBuf),
    /// A power-key press.
    Press(PathBuf),
    /// A camera-switch contact closed (`true`) or opened.
    Contact(Direction, bool),
    Gone(Role, PathBuf, String),
}

const TICK: Duration = Duration::from_secs(1);
const RESCAN: Duration = Duration::from_secs(5);

/// One thread per device: a blocking read never holds up the runtime or the
/// process's exit.
fn spawn_reader(role: Role, path: PathBuf, tx: mpsc::Sender<Msg>) {
    std::thread::spawn(move || {
        let why = match read_events(role, &path, &tx) {
            Ok(()) => "closed".to_string(),
            Err(e) => e.to_string(),
        };
        let _ = tx.blocking_send(Msg::Gone(role, path, why));
    });
}

fn read_events(role: Role, path: &Path, tx: &mpsc::Sender<Msg>) -> std::io::Result<()> {
    let mut f = std::fs::File::open(path)?;
    if tx
        .blocking_send(Msg::Opened(role, path.to_path_buf()))
        .is_err()
    {
        return Ok(());
    }
    let mut buf = [0u8; EVENT_SIZE];
    loop {
        f.read_exact(&mut buf)?;
        let event = Event::parse(&buf);
        let msg = match role {
            Role::PowerKey => event
                .is_power_press()
                .then(|| Msg::Press(path.to_path_buf())),
            Role::Switch => Direction::from_keycode(event.code)
                .zip(event.key_change())
                .map(|(d, closed)| Msg::Contact(d, closed)),
        };
        if let Some(msg) = msg
            && tx.blocking_send(msg).is_err()
        {
            return Ok(());
        }
    }
}

struct Devices {
    role: Role,
    fixed: Vec<PathBuf>,
    sysfs: PathBuf,
    /// Readers started and not yet gone.
    started: HashSet<PathBuf>,
    /// Readers that opened their device, with the role's keys each has.
    open: HashMap<PathBuf, Vec<u16>>,
    /// The last error logged per device, so a device that keeps failing
    /// is logged once, not every rescan.
    last_error: HashMap<PathBuf, String>,
}

impl Devices {
    fn new(role: Role, fixed: Vec<PathBuf>, sysfs: PathBuf) -> Self {
        Self {
            role,
            fixed,
            sysfs,
            started: HashSet::new(),
            open: HashMap::new(),
            last_error: HashMap::new(),
        }
    }

    fn candidates(&self) -> Vec<PathBuf> {
        if self.fixed.is_empty() {
            find_keys(&self.sysfs, &self.role.codes())
                .into_iter()
                .map(|(path, _)| path)
                .collect()
        } else {
            self.fixed.clone()
        }
    }

    fn rescan(&mut self, tx: &mpsc::Sender<Msg>) {
        for path in self.candidates() {
            if self.started.insert(path.clone()) {
                spawn_reader(self.role, path, tx.clone());
            }
        }
    }

    fn opened(&mut self, path: PathBuf) {
        let keys = device_keys(&self.sysfs, &path, &self.role.codes());
        self.last_error.remove(&path);
        self.open.insert(path, keys);
    }

    fn gone(&mut self, path: &Path, why: String) {
        if self.last_error.get(path) != Some(&why) {
            eprintln!("[power-manager] {}: {why}", path.display());
            self.last_error.insert(path.to_path_buf(), why);
        }
        self.started.remove(path);
        self.open.remove(path);
    }

    /// Whether a device is open, once every started reader has answered;
    /// `None` while one hasn't.
    fn settled(&self) -> Option<bool> {
        (self.started.len() == self.open.len()).then_some(!self.open.is_empty())
    }

    /// The switch contacts an open device has. A device given with
    /// `--switch-device` whose keys sysfs can't tell counts as all five.
    fn contacts(&self) -> Vec<Direction> {
        let keys: HashSet<u16> = self.open.values().flatten().copied().collect();
        let unknown = !self.fixed.is_empty() && self.open.values().any(Vec::is_empty);
        Direction::ALL
            .into_iter()
            .filter(|d| unknown || keys.contains(&d.keycode()))
            .collect()
    }
}

fn names(directions: &[Direction]) -> String {
    if directions.is_empty() {
        return "none".to_string();
    }
    directions
        .iter()
        .map(|d| d.name())
        .collect::<Vec<_>>()
        .join(", ")
}

fn describe(policy: &Policy, keys: &Devices, switch: &Devices) -> String {
    let n = keys.open.len();
    let power = match policy.state() {
        State::Starting => format!(
            "boot window: power key ignored until {} s after boot ({n} key device(s))",
            policy.boot_window().as_secs()
        ),
        State::Running => format!("running: the power key shuts down ({n} key device(s))"),
        State::Fault => {
            "FAULT: no power-key device can be read: no clean shutdown, HARDOFF will cut power"
                .to_string()
        }
        State::ShuttingDown => "shutting down".to_string(),
    };
    format!(
        "{power}; camera switch: {} of 5 contacts",
        switch.contacts().len()
    )
}

fn log_outcome(direction: Direction, outcome: Outcome) {
    let name = direction.name();
    match outcome {
        Outcome::Delivered(view) => eprintln!(
            "[power-manager] camera switch: {name} → {}",
            camera_link::describe_view(&view)
        ),
        Outcome::Failed(why) => {
            eprintln!("[power-manager] camera switch: {name}: camera-manager didn't take it: {why}")
        }
        Outcome::TooOld(waited) => eprintln!(
            "[power-manager] camera switch: {name}: dropped after waiting {} ms",
            waited.as_millis()
        ),
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
    let mut keys = Devices::new(Role::PowerKey, args.key_devices.clone(), args.sysfs.clone());
    let mut switch = Devices::new(
        Role::Switch,
        args.switch_devices.clone(),
        args.sysfs.clone(),
    );
    keys.rescan(&tx);
    switch.rescan(&tx);
    let mut had_key = true; // what the policy assumes until told otherwise
    if keys.started.is_empty() {
        eprintln!("[power-manager] no power-key device found");
        policy.handle(Input::KeyDeviceLost, uptime::since_boot());
        had_key = false;
    }
    if switch.started.is_empty() {
        eprintln!(
            "[power-manager] no camera-switch device found (the gpio-key overlays in config.txt): the switch isn't read"
        );
    }
    let camera = match &args.camera_manager {
        None => {
            eprintln!("[power-manager] no --camera-manager: camera-switch moves are only logged");
            None
        }
        Some(endpoint) => {
            let cfg = LinkConfig {
                endpoint: endpoint.clone(),
                call_timeout: Duration::from_millis(args.camera_call_timeout_ms),
                max_age: Duration::from_millis(args.camera_move_max_age_ms),
            };
            match Link::spawn(cfg, log_outcome) {
                Ok(link) => {
                    eprintln!(
                        "[power-manager] camera-switch moves go to camera-manager at {endpoint}"
                    );
                    Some(link)
                }
                Err(e) => {
                    // The power key matters more than the switch: run on.
                    eprintln!("[power-manager] {e}: camera-switch moves are only logged");
                    None
                }
            }
        }
    };
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
    if let Err(e) = notifier.ready(&describe(&policy, &keys, &switch)) {
        eprintln!("[power-manager] systemd READY not sent: {e}");
    }

    let start = Instant::now();
    let mut debouncer = Debouncer::new(Duration::from_millis(args.switch_debounce_ms));
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
    let mut last_contacts: Option<Vec<Direction>> = None;

    loop {
        let switch_due = debouncer.deadline();
        let input = tokio::select! {
            _ = tick.tick() => {
                heartbeat.beat();
                Some(Input::Tick)
            }
            _ = rescan.tick() => {
                keys.rescan(&tx);
                switch.rescan(&tx);
                None
            }
            () = async {
                match switch_due {
                    Some(due) => tokio::time::sleep_until(start + due).await,
                    None => std::future::pending().await,
                }
            } => None,
            Some(msg) = rx.recv() => match msg {
                Msg::Opened(role, path) => {
                    let what = match role {
                        Role::PowerKey => "the power key",
                        Role::Switch => "the camera switch",
                    };
                    eprintln!("[power-manager] reading {what} on {}", path.display());
                    match role {
                        Role::PowerKey => keys.opened(path),
                        Role::Switch => switch.opened(path),
                    }
                    None
                }
                Msg::Press(path) => {
                    eprintln!("[power-manager] power key on {} at {:.1} s after boot", path.display(), uptime::since_boot().as_secs_f64());
                    Some(Input::Key)
                }
                Msg::Contact(direction, closed) => {
                    debouncer.contact(direction, closed, start.elapsed());
                    None
                }
                Msg::Gone(role, path, why) => {
                    match role {
                        Role::PowerKey => keys.gone(&path, why),
                        Role::Switch => switch.gone(&path, why),
                    }
                    None
                }
            },
            _ = term.recv() => {
                let _ = notifier.stopping();
                return ExitCode::SUCCESS;
            }
        };

        if let Some(direction) = debouncer.poll(start.elapsed()) {
            match &camera {
                None => eprintln!("[power-manager] camera switch: {}", direction.name()),
                // The outcome is logged when the call ends (log_outcome).
                Some(link) => match link.send(direction) {
                    Ok(()) => {}
                    Err(NotQueued::QueueFull) => eprintln!(
                        "[power-manager] camera switch: {}: dropped, camera-manager is behind",
                        direction.name()
                    ),
                    Err(NotQueued::Closed) => eprintln!(
                        "[power-manager] camera switch: {}: dropped, the camera-manager link stopped",
                        direction.name()
                    ),
                },
            }
        }

        if switch.settled().is_some() {
            let contacts = switch.contacts();
            if last_contacts.as_ref() != Some(&contacts) {
                let missing: Vec<Direction> = Direction::ALL
                    .into_iter()
                    .filter(|d| !contacts.contains(d))
                    .collect();
                eprintln!(
                    "[power-manager] camera switch contacts readable: {}; missing: {}",
                    names(&contacts),
                    names(&missing)
                );
                last_contacts = Some(contacts);
            }
        }

        // Key device lost or back, once every reader has answered.
        let device_input = match keys.settled() {
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

        let status = describe(&policy, &keys, &switch);
        if status != last_status {
            let _ = notifier.status(&status);
            last_status = status;
        }
    }
}
