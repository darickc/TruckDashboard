//! gps-clock (ADR-0049): sets the system clock, and then the RTC, from a
//! real GPS fix when there is no network time. It follows navigation's
//! `f250.nav.v1` `WatchPosition` (navigation owns gpsd; ADR-0030) and leaves
//! a flag file (`clock_sync::GPS_FILE`) once it has set or confirmed the
//! clock, which camera-manager and power-manager read as "synchronized".
//!
//! The decisions are in `lib.rs`. This file does the I/O: the stream,
//! `clock_settime(2)` (CAP_SYS_TIME), `hwclock --systohc` for the RTC, and
//! the flag. `--dry-run` only logs what it would do.
//!
//! Status: [SIM] (the decisions' tests). Not run against a real receiver:
//! none is fitted (H11).

use std::path::PathBuf;
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

use clap::Parser;
use f250_proto::nav::v1 as nav;
use f250_sd_notify::Notifier;
use gps_clock::{Decider, Policy, Verdict, gps_time};
use hyper_util::rt::TokioIo;
use nav::position_service_client::PositionServiceClient;
use tonic::transport::{Channel, Endpoint, Uri};

const RETRY: Duration = Duration::from_secs(5);
const CALL_TIMEOUT: Duration = Duration::from_secs(5);
/// No position for this long: reconnect. navigation sends at least one a
/// second.
const SILENCE: Duration = Duration::from_secs(30);
/// How often network time is asked about (timedatectl, up to 2 s).
const NETWORK_EVERY: Duration = Duration::from_secs(30);

#[derive(Debug, Parser)]
#[command(
    about = "Sets the system clock and the RTC from GPS when there is no network time (ADR-0049)"
)]
struct Args {
    /// navigation's API.
    #[arg(long, default_value = "unix:/run/f250-nav/nav.sock")]
    navigation: String,
    /// The flag file left once the clock is set or confirmed from GPS.
    #[arg(long, default_value = clock_sync::GPS_FILE)]
    flag_file: PathBuf,
    /// The program that copies the system clock into the RTC.
    #[arg(long, default_value = "/usr/sbin/hwclock")]
    hwclock: PathBuf,
    /// The RTC. Empty: don't write it.
    #[arg(long, default_value = "/dev/rtc0")]
    rtc: String,
    /// Step the clock when GPS and the system differ by more than this, ms.
    /// An example (ADR-0049).
    #[arg(long, default_value_t = 1000)]
    step_threshold_ms: u64,
    /// Log what would be done, change nothing.
    #[arg(long)]
    dry_run: bool,
    /// Use the simulated receiver's time too. Development only, with
    /// --dry-run: its time comes from this machine's clock.
    #[arg(long)]
    accept_simulated: bool,
}

fn channel(endpoint: &str) -> Result<Channel, String> {
    if let Some(path) = endpoint.strip_prefix("unix:") {
        let path = path.to_string();
        Ok(Endpoint::from_static("http://localhost")
            .connect_timeout(CALL_TIMEOUT)
            .connect_with_connector_lazy(tower::service_fn(move |_: Uri| {
                let path = path.clone();
                async move {
                    tokio::net::UnixStream::connect(path)
                        .await
                        .map(TokioIo::new)
                }
            })))
    } else if let Some(addr) = endpoint.strip_prefix("tcp:") {
        Ok(Endpoint::from_shared(format!("http://{addr}"))
            .map_err(|e| e.to_string())?
            .connect_timeout(CALL_TIMEOUT)
            .connect_lazy())
    } else {
        Err(format!(
            "{endpoint}: the endpoint must start with unix: or tcp:"
        ))
    }
}

fn now_unix() -> f64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs_f64())
        .unwrap_or(0.0)
}

/// What the loop keeps between readings.
struct State {
    args: Args,
    decider: Decider,
    network: bool,
    network_asked: Option<Instant>,
    flagged: bool,
    /// The last thing logged, so a steady state is logged once.
    said: String,
}

impl State {
    fn say(&mut self, kind: &str, text: String) {
        if self.said != kind {
            eprintln!("[gps-clock] {text}");
            self.said = kind.to_string();
        }
    }

    async fn network(&mut self) -> bool {
        if self
            .network_asked
            .is_none_or(|t| t.elapsed() >= NETWORK_EVERY)
        {
            self.network = tokio::task::spawn_blocking(clock_sync::network_synchronized)
                .await
                .unwrap_or(false);
            self.network_asked = Some(Instant::now());
        }
        self.network
    }

    async fn write_rtc(&self) {
        if self.args.rtc.is_empty() {
            return;
        }
        let out = tokio::process::Command::new(&self.args.hwclock)
            .args(["--systohc", "--utc", "--noadjfile", "--rtc", &self.args.rtc])
            .output()
            .await;
        match out {
            Ok(o) if o.status.success() => eprintln!(
                "[gps-clock] RTC {} set from the system clock",
                self.args.rtc
            ),
            Ok(o) => eprintln!(
                "[gps-clock] {} failed ({}): {}",
                self.args.hwclock.display(),
                o.status,
                String::from_utf8_lossy(&o.stderr).trim()
            ),
            Err(e) => eprintln!("[gps-clock] {}: {e}", self.args.hwclock.display()),
        }
    }

    fn flag(&mut self) {
        if self.flagged {
            return;
        }
        match std::fs::write(&self.args.flag_file, format!("{}\n", now_unix() as u64)) {
            Ok(()) => {
                self.flagged = true;
                eprintln!(
                    "[gps-clock] {}: the clock counts as synchronized",
                    self.args.flag_file.display()
                );
            }
            Err(e) => eprintln!("[gps-clock] {}: {e}", self.args.flag_file.display()),
        }
    }

    async fn position(&mut self, p: &nav::Position, at: Instant) {
        let Some(gps) = gps_time(p, self.args.accept_simulated) else {
            return;
        };
        let sys = now_unix();
        // The GPS time now, not when the message arrived.
        let gps = gps + at.elapsed().as_secs_f64();
        let network = self.network().await;
        let dry = if self.args.dry_run {
            "dry run: would have "
        } else {
            ""
        };
        match self.decider.reading(gps, Instant::now(), sys, network) {
            Verdict::Wait(why) => self.say("wait", why.to_string()),
            Verdict::HandsOff => self.say("hands-off", "network time keeps the clock: nothing to do".into()),
            Verdict::Confirm { offset_s } => {
                if !self.flagged {
                    eprintln!("[gps-clock] {dry}confirmed the clock from GPS ({offset_s:+.3} s)");
                    if !self.args.dry_run {
                        self.write_rtc().await;
                        self.flag();
                    } else {
                        self.flagged = true;
                    }
                }
                self.say("confirm", format!("the clock agrees with GPS ({offset_s:+.3} s)"));
            }
            Verdict::TooSoon { offset_s } => self.say(
                "too-soon",
                format!("the clock is {offset_s:+.3} s from GPS again, within 10 min of a step: not stepping (something else is setting it?)"),
            ),
            Verdict::Step { offset_s } => {
                let target = now_unix() + offset_s;
                if self.args.dry_run {
                    eprintln!("[gps-clock] {dry}stepped the clock by {offset_s:+.3} s");
                    self.decider.stepped(Instant::now());
                    self.said.clear();
                    return;
                }
                let ts = rustix::time::Timespec {
                    tv_sec: target.trunc() as i64,
                    tv_nsec: (target.fract() * 1e9) as _,
                };
                match rustix::time::clock_settime(rustix::time::ClockId::Realtime, ts) {
                    Ok(()) => {
                        self.decider.stepped(Instant::now());
                        eprintln!("[gps-clock] stepped the clock by {offset_s:+.3} s from GPS");
                        self.said.clear();
                        self.write_rtc().await;
                        self.flag();
                    }
                    Err(e) => self.say("step-failed", format!("can't set the clock ({e}): needs CAP_SYS_TIME")),
                }
            }
        }
    }
}

async fn follow_once(
    client: &mut PositionServiceClient<Channel>,
    state: &mut State,
    notifier: &Notifier,
) -> String {
    let mut stream = match tokio::time::timeout(
        CALL_TIMEOUT,
        client.watch_position(nav::WatchPositionRequest {}),
    )
    .await
    {
        Ok(Ok(r)) => r.into_inner(),
        Ok(Err(e)) => return format!("WatchPosition: {}", e.message()),
        Err(_) => return "WatchPosition: no answer".into(),
    };
    let _ = notifier.status("following navigation's positions");
    loop {
        match tokio::time::timeout(SILENCE, stream.message()).await {
            Err(_) => return format!("no position in {} s", SILENCE.as_secs()),
            Ok(Err(e)) => return format!("stream: {}", e.message()),
            Ok(Ok(None)) => return "navigation ended the stream".into(),
            Ok(Ok(Some(m))) => {
                if let Some(p) = m.position {
                    state.position(&p, Instant::now()).await;
                }
            }
        }
    }
}

#[tokio::main(flavor = "current_thread")]
async fn main() -> Result<(), String> {
    let args = Args::parse();
    let notifier = Notifier::from_env();
    if let Some(p) = notifier.problem() {
        eprintln!("[gps-clock] sd_notify: {p}");
    }
    let policy = Policy {
        step_threshold_s: args.step_threshold_ms as f64 / 1000.0,
        ..Policy::default()
    };
    eprintln!(
        "[gps-clock] following {}; steps the clock when it is more than {} ms from a real GPS fix and there is no network time{}{}",
        args.navigation,
        args.step_threshold_ms,
        if args.dry_run { " (dry run)" } else { "" },
        if args.accept_simulated {
            " (simulated receiver accepted: development only)"
        } else {
            ""
        },
    );
    let mut client = PositionServiceClient::new(channel(&args.navigation)?);
    let endpoint = args.navigation.clone();
    let mut state = State {
        args,
        decider: Decider::new(policy, Instant::now()),
        network: false,
        network_asked: None,
        flagged: false,
        said: String::new(),
    };
    let _ = notifier.ready("waiting for navigation");
    let mut last = String::new();
    let run = async {
        loop {
            let why = follow_once(&mut client, &mut state, &notifier).await;
            if why != last {
                eprintln!(
                    "[gps-clock] navigation ({endpoint}): {why}; retrying every {} s",
                    RETRY.as_secs()
                );
                last = why;
            }
            tokio::time::sleep(RETRY).await;
        }
    };
    tokio::select! {
        () = run => {}
        _ = tokio::signal::ctrl_c() => {}
        () = terminate() => {}
    }
    let _ = notifier.stopping();
    Ok(())
}

#[cfg(unix)]
async fn terminate() {
    match tokio::signal::unix::signal(tokio::signal::unix::SignalKind::terminate()) {
        Ok(mut s) => {
            s.recv().await;
        }
        Err(_) => std::future::pending().await,
    }
}
