//! `power-manager`: shut the Pi down on the DCDC-USB's PSW pulse (the power
//! key), except in the boot window. Pulse-only (ADR-0013); see the library
//! docs for the rules. It also reads the 5-way switch (ADR-0024, ADR-0025,
//! ADR-0051): a short press goes to audio-manager, a long one to
//! camera-manager (ADR-0026), and which wire is which direction is set from
//! the dashboard. It decides day or night and sets the backlight (ADR-0028).
//! Both are served as `f250.power.v1`.
//!
//!   power-manager --boot-key-ignore-s 30 --camera-manager unix:/run/f250-camera/camera.sock \
//!       --audio-manager unix:/run/f250-audio/audio.sock --switch-state /var/lib/f250-power/switch \
//!       --display-listen unix:/run/f250-power/power.sock --latitude=39.74 --longitude=-104.99 \
//!       --navigation unix:/run/f250-nav/nav.sock --location-state /var/lib/f250-power/location
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
use f250_proto::power::v1 as pb;
use f250_sd_notify::{Heartbeat, Notifier, run_watchdog};
use power_manager::POWER_OFF_EXIT;
use power_manager::backlight::{Device, Writer};
use power_manager::display::{self, BacklightInfo, DisplayIo, DisplayState, RawSettings};
use power_manager::display_server;
use power_manager::evdev::{EVENT_SIZE, Event, KEY_POWER, device_keys, find_keys};
use power_manager::gps;
use power_manager::link::{Link, LinkConfig, NotQueued, Outcome};
use power_manager::policy::{Action, Input, Policy, State};
use power_manager::switch::{self, Classifier, Mapping, Wire};
use power_manager::switch_control::{self, Command, Control, Route, Saved, Sent};
use power_manager::switch_server;
use power_manager::uptime;
use power_manager::{audio_link, camera_link};
use tokio::sync::{broadcast, mpsc, watch};
use tokio::time::Instant;

#[derive(Parser)]
#[command(
    about = "F-250 power manager: the power key, pulse-only (ADR-0013), the 5-way switch, and day/night"
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
    /// Read only these event devices for the 5-way switch. Default: every
    /// /dev/input/event* with one of its keys (F13-F17, from the gpio-key
    /// overlays), rescanned every few seconds.
    #[arg(long = "switch-device")]
    switch_devices: Vec<PathBuf>,
    /// How long a switch contact must be the only one closed to count, and
    /// open to count as released. An example value: tune it on the fitted
    /// switch (H32).
    #[arg(long, default_value_t = 30)]
    switch_debounce_ms: u64,
    /// A press held this long (from the contact closing) is a long press:
    /// a camera. Shorter is a short press: media and calls. An example
    /// value.
    #[arg(long, default_value_t = 600)]
    switch_long_press_ms: u64,
    /// Where the driver's choice of which wire is which direction is kept.
    /// Without it the choice lasts until power-manager restarts.
    #[arg(long, value_name = "PATH")]
    switch_state: Option<PathBuf>,
    /// camera-manager's API (unix:PATH or tcp:HOST:PORT), which takes the
    /// switch's long presses. Without it they are only logged.
    #[arg(long, value_name = "ENDPOINT")]
    camera_manager: Option<String>,
    /// How long a call to camera-manager may take, connecting included. An
    /// example value.
    #[arg(long, default_value_t = 1000)]
    camera_call_timeout_ms: u64,
    /// A long press still waiting to be sent after this long is dropped, so
    /// the camera never changes long after the switch was held. An example
    /// value.
    #[arg(long, default_value_t = 1000)]
    camera_move_max_age_ms: u64,
    /// audio-manager's API (unix:PATH or tcp:HOST:PORT), which takes the
    /// switch's short presses. Without it they are only logged.
    #[arg(long, value_name = "ENDPOINT")]
    audio_manager: Option<String>,
    /// How long a call to audio-manager may take, connecting included. An
    /// example value.
    #[arg(long, default_value_t = 1000)]
    audio_call_timeout_ms: u64,
    /// A short press still waiting to be sent after this long is dropped,
    /// so a skip or a volume step never comes late. An example value.
    #[arg(long, default_value_t = 1000)]
    audio_max_age_ms: u64,
    /// Where sysfs is (for tests).
    #[arg(long, default_value = "/sys")]
    sysfs: PathBuf,
    /// Log a power-off instead of doing it (bench).
    #[arg(long)]
    dry_run: bool,

    // Day/night and the backlight (ADR-0028). Every value is read leniently:
    // a bad one is logged and its default used, so the display's settings
    // can never stop the power key from working.
    /// The power API (f250.power.v1: the display and the 5-way switch):
    /// unix:PATH or tcp:HOST:PORT. Without it day/night, the backlight and
    /// the switch still run; nothing can see or change them.
    #[arg(long, value_name = "ENDPOINT")]
    display_listen: Option<String>,
    /// Where the truck is, for the sun: degrees, north positive. With
    /// --longitude, or not at all.
    #[arg(long, allow_hyphen_values = true)]
    latitude: Option<String>,
    /// Degrees, east positive (the United States is negative).
    #[arg(long, allow_hyphen_values = true)]
    longitude: Option<String>,
    /// Night once the sun is below this many degrees. Default -3, an
    /// example value.
    #[arg(long, allow_hyphen_values = true)]
    night_below_deg: Option<String>,
    /// Day again only this many degrees above the night threshold. Default
    /// 1, an example value.
    #[arg(long)]
    hysteresis_deg: Option<String>,
    /// day or night: the mode when Auto can't follow the sun. Default day,
    /// an example value.
    #[arg(long)]
    fallback: Option<String>,
    /// synchronized (default: the sun only on a clock the system reports
    /// synchronized) or always.
    #[arg(long)]
    trust_clock: Option<String>,
    /// The backlight never goes below this percentage. Default 10, an
    /// example value.
    #[arg(long)]
    min_brightness_pct: Option<String>,
    /// The device under /sys/class/backlight. Default: the first there;
    /// `none`: no backlight.
    #[arg(long)]
    backlight: Option<String>,
    /// How long a brightness change takes.
    #[arg(long, default_value_t = 1000)]
    brightness_ramp_ms: u64,
    /// Where the driver's display settings are kept. Without it they last
    /// until power-manager restarts.
    #[arg(long, value_name = "PATH")]
    display_state: Option<PathBuf>,
    /// navigation's API (unix:PATH or tcp:HOST:PORT): the truck's position
    /// for the sun, replacing --latitude/--longitude once there is a fix,
    /// and its time while the system clock isn't synchronized (ADR-0028
    /// amendment). Without it, only the configured location.
    #[arg(long, value_name = "ENDPOINT")]
    navigation: Option<String>,
    /// Where the last GPS position is kept (to 0.1°), for the sun after a
    /// restart without a fix.
    #[arg(long, value_name = "PATH")]
    location_state: Option<PathBuf>,
    /// Development only: take the simulated receiver's position (never its
    /// time), labelled SIMULATED. It is never the truck.
    #[arg(long)]
    gps_accept_simulated: bool,
}

/// What a set of devices is read for.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum Reads {
    PowerKey,
    Switch,
}

impl Reads {
    fn codes(self) -> Vec<u16> {
        match self {
            Reads::PowerKey => vec![KEY_POWER],
            Reads::Switch => Wire::keycodes().to_vec(),
        }
    }
}

/// What a reader thread reports.
enum Msg {
    Opened(Reads, PathBuf),
    /// A power-key press.
    Press(PathBuf),
    /// A switch wire's contact closed (`true`) or opened.
    Contact(Wire, bool),
    Gone(Reads, PathBuf, String),
}

const TICK: Duration = Duration::from_secs(1);
const RESCAN: Duration = Duration::from_secs(5);

/// One thread per device: a blocking read never holds up the runtime or the
/// process's exit.
fn spawn_reader(role: Reads, path: PathBuf, tx: mpsc::Sender<Msg>) {
    std::thread::spawn(move || {
        let why = match read_events(role, &path, &tx) {
            Ok(()) => "closed".to_string(),
            Err(e) => e.to_string(),
        };
        let _ = tx.blocking_send(Msg::Gone(role, path, why));
    });
}

fn read_events(role: Reads, path: &Path, tx: &mpsc::Sender<Msg>) -> std::io::Result<()> {
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
            Reads::PowerKey => event
                .is_power_press()
                .then(|| Msg::Press(path.to_path_buf())),
            Reads::Switch => Wire::from_keycode(event.code)
                .zip(event.key_change())
                .map(|(w, closed)| Msg::Contact(w, closed)),
        };
        if let Some(msg) = msg
            && tx.blocking_send(msg).is_err()
        {
            return Ok(());
        }
    }
}

struct Devices {
    role: Reads,
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
    fn new(role: Reads, fixed: Vec<PathBuf>, sysfs: PathBuf) -> Self {
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

    /// The switch wires an open device has. A device given with
    /// `--switch-device` whose keys sysfs can't tell counts as all five.
    fn contacts(&self) -> Vec<Wire> {
        let keys: HashSet<u16> = self.open.values().flatten().copied().collect();
        let unknown = !self.fixed.is_empty() && self.open.values().any(Vec::is_empty);
        Wire::ALL
            .into_iter()
            .filter(|w| unknown || keys.contains(&w.keycode()))
            .collect()
    }
}

fn names(wires: &[Wire]) -> String {
    if wires.is_empty() {
        return "none".to_string();
    }
    wires
        .iter()
        .map(|w| w.name())
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
        "{power}; 5-way switch: {} of 5 wires",
        switch.contacts().len()
    )
}

/// What a link reports: logged, and passed to the dashboard as the press's
/// result (the same `seq`, so it replaces what it was first told).
fn reporter(
    service: &'static str,
    presses: broadcast::Sender<pb::Press>,
) -> impl FnMut(Sent, Outcome) + Send + 'static {
    move |sent, outcome| {
        let action = &sent.press.result;
        let result = match outcome {
            Outcome::Delivered(d) if d.is_empty() => action.clone(),
            Outcome::Delivered(d) => format!("{action} → {d}"),
            Outcome::Failed(why) => format!("{action}: {service} didn't take it: {why}"),
            Outcome::TooOld(waited) => {
                format!("{action}: dropped after waiting {} ms", waited.as_millis())
            }
        };
        eprintln!(
            "[power-manager] 5-way switch: {}: {result}",
            sent.role.name()
        );
        let mut press = sent.press;
        press.result = result;
        let _ = presses.send(press);
    }
}

/// What a link calls with each press's outcome.
type Report = Box<dyn FnMut(Sent, Outcome) + Send>;

/// Starts one link, or says why there is none; presses then are only
/// logged.
fn start_link(
    endpoint: Option<&str>,
    service: &'static str,
    what: &str,
    call_timeout_ms: u64,
    max_age_ms: u64,
    presses: &broadcast::Sender<pb::Press>,
    spawn: fn(&LinkConfig, Report) -> Result<Link<Sent>, String>,
) -> Option<Link<Sent>> {
    let Some(endpoint) = endpoint.map(str::trim).filter(|e| !e.is_empty()) else {
        eprintln!("[power-manager] no {service} endpoint: the switch's {what} are only logged");
        return None;
    };
    let cfg = LinkConfig {
        endpoint: endpoint.to_string(),
        call_timeout: Duration::from_millis(call_timeout_ms),
        max_age: Duration::from_millis(max_age_ms),
    };
    match spawn(&cfg, Box::new(reporter(service, presses.clone()))) {
        Ok(link) => {
            eprintln!("[power-manager] the switch's {what} go to {service} at {endpoint}");
            Some(link)
        }
        Err(e) => {
            // The power key matters more than the switch: run on.
            eprintln!("[power-manager] {e}: the switch's {what} are only logged");
            None
        }
    }
}

/// Sends a press down its link, or says (in the log and to the dashboard)
/// why it wasn't.
fn send(
    link: Option<&Link<Sent>>,
    service: &str,
    sent: Sent,
    presses: &broadcast::Sender<pb::Press>,
) {
    let why = match link {
        None => format!("not sent: no {service}"),
        Some(link) => match link.send(sent.clone()) {
            // The outcome is reported when the call ends (reporter).
            Ok(()) => return,
            Err(NotQueued::QueueFull) => format!("dropped: {service} is behind"),
            Err(NotQueued::Closed) => format!("dropped: the {service} link stopped"),
        },
    };
    let mut press = sent.press;
    press.result = format!("{}: {why}", press.result);
    eprintln!(
        "[power-manager] 5-way switch: {}: {}",
        sent.role.name(),
        press.result
    );
    let _ = presses.send(press);
}

/// The switch's state for the dashboard, sent when it changed; returns it.
fn publish(
    tx: &watch::Sender<pb::SwitchState>,
    control: &Control,
    switch: &Devices,
) -> pb::SwitchState {
    let problem = (switch.settled() == Some(false)).then_some(
        "No 5-way switch input device: the gpio-key overlays in config.txt aren't loaded.",
    );
    let state = control.state(&switch.contacts(), problem);
    tx.send_if_modified(|s| {
        if *s == state {
            return false;
        }
        *s = state.clone();
        true
    });
    state
}

/// A new mapping: saved if there is a file, applied either way.
fn apply_mapping(
    control: &mut Control,
    path: Option<&Path>,
    mapping: Mapping,
    source: &str,
) -> (bool, String) {
    let problem = match path {
        None => Some("not saved: no --switch-state".to_string()),
        Some(p) => switch::save_mapping(p, &mapping).err(),
    };
    let summary = Wire::ALL
        .into_iter()
        .map(|w| format!("{} {}", w.name(), mapping.role(w).name()))
        .collect::<Vec<_>>()
        .join(", ");
    match &problem {
        None => eprintln!("[power-manager] 5-way switch: {source}: directions saved: {summary}"),
        Some(p) => {
            eprintln!("[power-manager] 5-way switch: {source}: directions applied ({summary}), {p}")
        }
    }
    control.set_mapping(mapping, problem.clone());
    match problem {
        None => (true, "Saved.".to_string()),
        Some(p) => (false, format!("Applied until power-manager restarts, {p}.")),
    }
}

/// Starts day/night and the backlight: a task and the backlight's writer
/// thread. Returns its API, served with the switch's. Nothing here can fail
/// power-manager: every problem is logged and that part runs without it.
fn start_display(args: &Args) -> display_server::Api {
    let raw = RawSettings {
        latitude: args.latitude.clone(),
        longitude: args.longitude.clone(),
        night_below_deg: args.night_below_deg.clone(),
        hysteresis_deg: args.hysteresis_deg.clone(),
        fallback: args.fallback.clone(),
        trust_clock: args.trust_clock.clone(),
        min_brightness_pct: args.min_brightness_pct.clone(),
    };
    let (settings, notes) = raw.resolve();
    for n in notes {
        eprintln!("[power-manager] display: {n}");
    }
    match settings.location {
        Some(at) => eprintln!(
            "[power-manager] display: location {:.3}, {:.3}; night below {}°",
            at.latitude_deg(),
            at.longitude_deg(),
            settings.thresholds.night_below_deg
        ),
        None => eprintln!(
            "[power-manager] display: no configured location (DISPLAY_LATITUDE/DISPLAY_LONGITUDE): until a GPS position, Auto uses the {} fallback",
            settings.fallback.name()
        ),
    }
    let saved = match args.location_state.as_deref() {
        Some(path) => {
            let (saved, note) = gps::load_location(path);
            if let Some(n) = note {
                eprintln!("[power-manager] display: {n}");
            }
            if let Some(at) = saved {
                eprintln!(
                    "[power-manager] display: saved GPS position {:.1}, {:.1}",
                    at.latitude_deg(),
                    at.longitude_deg()
                );
            }
            saved
        }
        None => None,
    };
    let positions = match args.navigation.as_deref().map(str::trim) {
        None | Some("") => {
            eprintln!("[power-manager] display: no --navigation: no GPS position or time");
            None
        }
        Some(endpoint) => {
            if args.gps_accept_simulated {
                eprintln!(
                    "[power-manager] display: --gps-accept-simulated: a simulated position is used, labelled SIMULATED"
                );
            }
            let (tx, rx) = tokio::sync::watch::channel(None);
            tokio::spawn(gps::follow(endpoint.to_string(), tx));
            Some(rx)
        }
    };
    let (prefs, notes) = display::load_prefs(args.display_state.as_deref());
    for n in notes {
        eprintln!("[power-manager] display: {n}");
    }
    let device = match args.backlight.as_deref().map(str::trim) {
        Some("none") => Err("no backlight (--backlight none)".to_string()),
        Some("") | None => Device::find(&args.sysfs, None),
        Some(name) => Device::find(&args.sysfs, Some(name)),
    };
    let (reports_tx, reports_rx) = mpsc::channel(8);
    let writer = match &device {
        Ok(d) => {
            eprintln!(
                "[power-manager] display: backlight {} (max {})",
                d.name(),
                d.max()
            );
            Some(Writer::spawn(
                d.clone(),
                Duration::from_millis(args.brightness_ramp_ms),
                Duration::from_millis(25),
                move |r| {
                    let _ = reports_tx.blocking_send(r);
                },
            ))
        }
        Err(e) => {
            eprintln!("[power-manager] display: {e}: day/night still runs");
            drop(reports_tx);
            None
        }
    };
    let state = DisplayState::new(
        settings.location,
        gps::GpsInput::new(saved, args.gps_accept_simulated),
        settings.trust,
        daylight::DayNight::new(settings.thresholds, settings.fallback),
        settings.min_pct,
        prefs,
        device.map(|d| BacklightInfo {
            name: d.name().to_string(),
            max: d.max(),
        }),
    );
    let io = DisplayIo {
        clock_synchronized: std::sync::Arc::new(clock_sync::system_synchronized),
        now_unix: std::sync::Arc::new(|| {
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .map(|d| d.as_secs_f64())
                .unwrap_or(0.0)
        }),
        state_file: args.display_state.clone(),
        location_file: args.location_state.clone(),
        positions,
        writer,
        evaluate_every: display::EVALUATE_EVERY,
    };
    let (out, watch_rx) = tokio::sync::watch::channel(pb::Display::default());
    let (cmds_tx, cmds_rx) = mpsc::channel(8);
    tokio::spawn(display::run(state, io, cmds_rx, reports_rx, out));
    display_server::Api::new(cmds_tx, watch_rx)
}

/// Serves the power API (the display and the switch) on --display-listen,
/// or says nobody can see them.
fn start_api(listen: Option<&str>, display: display_server::Api, switch: switch_server::Api) {
    let Some(listen) = listen.map(str::to_string) else {
        eprintln!(
            "[power-manager] no --display-listen: the dashboard can't see or change the display or the switch"
        );
        return;
    };
    tokio::spawn(async move {
        if let Err(e) = serve_api(&listen, display, switch).await {
            eprintln!("[power-manager] power API on {listen}: {e}: not served");
        }
    });
}

async fn serve_api(
    listen: &str,
    display: display_server::Api,
    switch: switch_server::Api,
) -> Result<(), String> {
    use pb::display_service_server::DisplayServiceServer;
    use pb::switch_service_server::SwitchServiceServer;
    let router = tonic::transport::Server::builder()
        .add_service(DisplayServiceServer::new(display))
        .add_service(SwitchServiceServer::new(switch));
    if let Some(path) = listen.strip_prefix("unix:") {
        let path = Path::new(path);
        if let Some(dir) = path.parent() {
            std::fs::create_dir_all(dir).map_err(|e| e.to_string())?;
        }
        let _ = std::fs::remove_file(path); // stale socket from a previous run
        let listener = tokio::net::UnixListener::bind(path).map_err(|e| e.to_string())?;
        eprintln!("[power-manager] power API on unix:{}", path.display());
        let incoming = tokio_stream::wrappers::UnixListenerStream::new(listener);
        router
            .serve_with_incoming(incoming)
            .await
            .map_err(|e| e.to_string())
    } else if let Some(addr) = listen.strip_prefix("tcp:") {
        let addr: std::net::SocketAddr = addr.parse().map_err(|e| format!("{e}"))?;
        eprintln!("[power-manager] power API on tcp:{addr}");
        router.serve(addr).await.map_err(|e| e.to_string())
    } else {
        Err("must start with unix: or tcp:".to_string())
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

    let display_api = start_display(&args);

    let window = Duration::from_secs(args.boot_key_ignore_s);
    let mut policy = Policy::new(window);
    let (tx, mut rx) = mpsc::channel(32);
    let mut keys = Devices::new(
        Reads::PowerKey,
        args.key_devices.clone(),
        args.sysfs.clone(),
    );
    let mut switch = Devices::new(
        Reads::Switch,
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
            "[power-manager] no 5-way switch device found (the gpio-key overlays in config.txt): the switch isn't read"
        );
    }
    // The switch: presses to the dashboard (and the links' reports), the
    // state, and the dashboard's requests.
    let (presses, _) = broadcast::channel::<pb::Press>(16);
    let camera = start_link(
        args.camera_manager.as_deref(),
        "camera-manager",
        "long presses",
        args.camera_call_timeout_ms,
        args.camera_move_max_age_ms,
        &presses,
        camera_link::spawn,
    );
    let audio = start_link(
        args.audio_manager.as_deref(),
        "audio-manager",
        "short presses",
        args.audio_call_timeout_ms,
        args.audio_max_age_ms,
        &presses,
        audio_link::spawn,
    );
    let (mapping, note) = switch::load_mapping(args.switch_state.as_deref());
    if let Some(n) = &note {
        eprintln!("[power-manager] 5-way switch: {n}");
    }
    let long_press = Duration::from_millis(args.switch_long_press_ms);
    let mut control = Control::new(
        mapping,
        note,
        long_press,
        switch_control::DEFAULT_LEARNING_TIMEOUT,
    );
    eprintln!(
        "[power-manager] 5-way switch: {}; long press {} ms",
        Wire::ALL
            .into_iter()
            .map(|w| format!("{} ({}) {}", w.name(), w.pin(), mapping.role(w).name()))
            .collect::<Vec<_>>()
            .join(", "),
        long_press.as_millis()
    );
    let (state_tx, state_rx) = watch::channel(control.state(&[], None));
    let (switch_cmds_tx, mut switch_cmds) = mpsc::channel::<Command>(8);
    start_api(
        args.display_listen.as_deref(),
        display_api,
        switch_server::Api::new(switch_cmds_tx, state_rx, presses.clone()),
    );
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
    let mut classifier =
        Classifier::new(Duration::from_millis(args.switch_debounce_ms), long_press);
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
    let mut last_contacts: Option<Vec<Wire>> = None;

    loop {
        let switch_due = [classifier.deadline(), control.learning_deadline()]
            .into_iter()
            .flatten()
            .min();
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
                        Reads::PowerKey => "the power key",
                        Reads::Switch => "the 5-way switch",
                    };
                    eprintln!("[power-manager] reading {what} on {}", path.display());
                    match role {
                        Reads::PowerKey => keys.opened(path),
                        Reads::Switch => switch.opened(path),
                    }
                    None
                }
                Msg::Press(path) => {
                    eprintln!("[power-manager] power key on {} at {:.1} s after boot", path.display(), uptime::since_boot().as_secs_f64());
                    Some(Input::Key)
                }
                Msg::Contact(wire, closed) => {
                    classifier.contact(wire, closed, start.elapsed());
                    None
                }
                Msg::Gone(role, path, why) => {
                    match role {
                        Reads::PowerKey => keys.gone(&path, why),
                        Reads::Switch => switch.gone(&path, why),
                    }
                    None
                }
            },
            Some(cmd) = switch_cmds.recv() => {
                let now = start.elapsed();
                let path = args.switch_state.as_deref();
                match cmd {
                    Command::Learning { on, source, reply } => {
                        if on != control.learning() {
                            eprintln!(
                                "[power-manager] 5-way switch: {source}: learning {}",
                                if on { "on: presses are reported, not sent" } else { "off" }
                            );
                        }
                        control.set_learning(on, now);
                        let state = publish(&state_tx, &control, &switch);
                        let _ = reply.send(state);
                    }
                    Command::Mapping { mapping, source, reply } => {
                        let (saved, detail) = apply_mapping(&mut control, path, mapping, &source);
                        let state = publish(&state_tx, &control, &switch);
                        let _ = reply.send(Saved { saved, detail, state });
                    }
                    Command::Reset { source, reply } => {
                        let (saved, detail) = apply_mapping(&mut control, path, Mapping::default(), &source);
                        let state = publish(&state_tx, &control, &switch);
                        let _ = reply.send(Saved { saved, detail, state });
                    }
                }
                None
            }
            _ = term.recv() => {
                let _ = notifier.stopping();
                return ExitCode::SUCCESS;
            }
        };

        let now = start.elapsed();
        while let Some(p) = classifier.poll(now) {
            let (route, sent) = control.press(p, now);
            eprintln!(
                "[power-manager] 5-way switch: {} ({}), {}: {}",
                p.wire.name(),
                sent.role.name(),
                match p.kind {
                    switch::Kind::Short => "short",
                    switch::Kind::Long => "long",
                },
                sent.press.result
            );
            let _ = presses.send(sent.press.clone());
            match route {
                Route::Learning => {}
                Route::Camera => send(camera.as_ref(), "camera-manager", sent, &presses),
                Route::Audio => send(audio.as_ref(), "audio-manager", sent, &presses),
            }
        }
        if control.expire(now) {
            eprintln!(
                "[power-manager] 5-way switch: learning off: no press for {} s",
                switch_control::DEFAULT_LEARNING_TIMEOUT.as_secs()
            );
        }
        publish(&state_tx, &control, &switch);

        if switch.settled().is_some() {
            let contacts = switch.contacts();
            if last_contacts.as_ref() != Some(&contacts) {
                let missing: Vec<Wire> = Wire::ALL
                    .into_iter()
                    .filter(|w| !contacts.contains(w))
                    .collect();
                eprintln!(
                    "[power-manager] 5-way switch wires readable: {}; missing: {}",
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
