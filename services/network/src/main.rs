//! `network`: Wi-Fi from connman for the dashboard, as `f250.network.v1`
//! (ADR-0052).
//!
//!   network --listen unix:/run/f250-network/network.sock     # connman on the system bus
//!   network --listen unix:/tmp/f250/network.sock --simulate  # development

use std::process::ExitCode;
use std::sync::Arc;
use std::time::Duration;

use clap::Parser;
use f250_proto::network::v1 as pb;
use f250_sd_notify::{Heartbeat, Notifier, run_watchdog};
use network::connman::Connman;
use network::server::{self, Api};
use network::sim::Sim;
use network::{Backend, runner};
use tokio::sync::{Notify, watch};

#[derive(Parser)]
#[command(about = "F-250 Wi-Fi: connman's networks for the dashboard (f250.network.v1)")]
struct Args {
    /// The API: unix:PATH or tcp:HOST:PORT.
    #[arg(long, value_name = "ENDPOINT")]
    listen: String,
    /// Made-up networks instead of connman, labelled simulated.
    #[arg(long)]
    simulate: bool,
    /// How often connman is read.
    #[arg(long, default_value_t = runner::POLL.as_millis() as u64)]
    poll_ms: u64,
}

async fn run<B: Backend>(backend: B, args: Args, what: &str) -> ExitCode {
    let notifier = Notifier::from_env();
    if let Some(problem) = notifier.problem() {
        eprintln!("[network] {problem}");
    }
    let heartbeat = Heartbeat::new();
    tokio::spawn(run_watchdog(notifier.clone(), heartbeat.clone(), "network"));
    let backend = Arc::new(backend);
    let poke = Arc::new(Notify::new());
    let (out, status) = watch::channel(pb::WifiStatus::default());
    tokio::spawn(runner::run(
        backend.clone(),
        Duration::from_millis(args.poll_ms.max(200)),
        poke.clone(),
        out,
        Some(heartbeat),
    ));
    let listen = args.listen.clone();
    let serving =
        tokio::spawn(async move { server::serve(&listen, Api::new(backend, status, poke)).await });
    eprintln!("[network] Wi-Fi from {what}");
    if let Err(e) = notifier.ready(&format!("Wi-Fi from {what}")) {
        eprintln!("[network] systemd READY not sent: {e}");
    }
    let mut term = match tokio::signal::unix::signal(tokio::signal::unix::SignalKind::terminate()) {
        Ok(s) => s,
        Err(e) => {
            eprintln!("[network] can't watch SIGTERM: {e}");
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
                Ok(Err(e)) => eprintln!("[network] API on {}: {e}", args.listen),
                Ok(Ok(())) => eprintln!("[network] API on {} stopped", args.listen),
                Err(e) => eprintln!("[network] API task: {e}"),
            }
            ExitCode::FAILURE
        }
    }
}

#[tokio::main(flavor = "current_thread")]
async fn main() -> ExitCode {
    let args = Args::parse();
    if args.simulate {
        run(Sim::default(), args, "a simulation").await
    } else {
        run(Connman::default(), args, "connman").await
    }
}
