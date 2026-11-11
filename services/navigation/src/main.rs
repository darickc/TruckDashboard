//! `navigation`: the truck's position from gpsd, served as `f250.nav.v1`
//! (Phase 6.4, ADR-0030).
//!
//!   navigation --listen unix:/run/f250-nav/nav.sock                # gpsd on 127.0.0.1:2947
//!   navigation --listen unix:/tmp/f250/nav.sock --simulate         # development
//!   navigation --listen tcp:127.0.0.1:50253 --simulate --sim-outage-every-s 60

use std::process::ExitCode;
use std::time::Duration;

use clap::Parser;
use f250_proto::nav::v1 as pb;
use f250_sd_notify::{Heartbeat, Notifier, run_watchdog};
use navigation::publisher::{self, PublisherConfig};
use navigation::server::{self, Api};
use navigation::sim::{self, SimConfig};
use navigation::source::{self, GpsdConfig};
use tokio::sync::{mpsc, watch};

#[derive(Parser)]
#[command(about = "F-250 navigation: the truck's position from gpsd (f250.nav.v1)")]
struct Args {
    /// The API: unix:PATH or tcp:HOST:PORT.
    #[arg(long, value_name = "ENDPOINT")]
    listen: String,
    /// gpsd's address.
    #[arg(long, default_value = gpsd::DEFAULT_ADDR, value_name = "HOST:PORT")]
    gpsd: String,
    /// A simulated receiver instead of gpsd: a loop in Kansas, labelled
    /// simulated on the screen.
    #[arg(long)]
    simulate: bool,
    /// The simulated receiver's speed.
    #[arg(long, default_value_t = 80.0)]
    sim_speed_kmh: f64,
    /// The simulated receiver loses its fix every this many seconds (0:
    /// never), as in a tunnel.
    #[arg(long, default_value_t = 0)]
    sim_outage_every_s: u64,
    /// ...for this long.
    #[arg(long, default_value_t = 10)]
    sim_outage_s: u64,
    /// A fix older than this is stale: never shown as current. An example
    /// value: tune it once a receiver is fitted (H11).
    #[arg(long, default_value_t = 3000)]
    stale_after_ms: u64,
}

#[tokio::main(flavor = "current_thread")]
async fn main() -> ExitCode {
    let args = Args::parse();
    let notifier = Notifier::from_env();
    if let Some(problem) = notifier.problem() {
        eprintln!("[navigation] {problem}");
    }
    let heartbeat = Heartbeat::new();
    tokio::spawn(run_watchdog(
        notifier.clone(),
        heartbeat.clone(),
        "navigation",
    ));

    let (events_tx, events_rx) = mpsc::channel(64);
    let what = if args.simulate {
        let cfg = SimConfig {
            speed_mps: args.sim_speed_kmh.max(0.0) / 3.6,
            outage_every: (args.sim_outage_every_s > 0)
                .then(|| Duration::from_secs(args.sim_outage_every_s)),
            outage_for: Duration::from_secs(args.sim_outage_s),
            ..SimConfig::default()
        };
        tokio::spawn(sim::run(cfg, events_tx));
        "a simulated receiver".to_string()
    } else {
        tokio::spawn(source::run_gpsd(GpsdConfig::new(&args.gpsd), events_tx));
        format!("gpsd at {}", args.gpsd)
    };

    let (out, position) = watch::channel(pb::Position::default());
    let cfg = PublisherConfig {
        stale_after: Duration::from_millis(args.stale_after_ms),
        simulated: args.simulate,
        tick: publisher::TICK,
    };
    tokio::spawn(publisher::run(cfg, events_rx, out, Some(heartbeat)));

    let listen = args.listen.clone();
    let serving = tokio::spawn(async move { server::serve(&listen, Api::new(position)).await });
    eprintln!("[navigation] position from {what}");
    if let Err(e) = notifier.ready(&format!("position from {what}")) {
        eprintln!("[navigation] systemd READY not sent: {e}");
    }

    let mut term = match tokio::signal::unix::signal(tokio::signal::unix::SignalKind::terminate()) {
        Ok(s) => s,
        Err(e) => {
            eprintln!("[navigation] can't watch SIGTERM: {e}");
            return ExitCode::FAILURE;
        }
    };
    tokio::select! {
        _ = term.recv() => {
            let _ = notifier.stopping();
            ExitCode::SUCCESS
        }
        _ = tokio::signal::ctrl_c() => {
            let _ = notifier.stopping();
            ExitCode::SUCCESS
        }
        r = serving => {
            match r {
                Ok(Err(e)) => eprintln!("[navigation] API on {}: {e}", args.listen),
                Ok(Ok(())) => eprintln!("[navigation] API on {} stopped", args.listen),
                Err(e) => eprintln!("[navigation] API task: {e}"),
            }
            ExitCode::FAILURE
        }
    }
}
