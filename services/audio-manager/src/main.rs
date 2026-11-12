//! `audio-manager`: see `--help` and docs/architecture/adr/0039-audio-manager.md.
//!
//! Examples:
//!   audio-manager --listen unix:/run/f250-audio/audio.sock      # the Pi
//!   audio-manager --simulate --listen tcp:127.0.0.1:50254       # make sim

use std::path::PathBuf;
use std::process::ExitCode;
use std::sync::Arc;
use std::time::Duration;

use audio_manager::backend::Bluetooth;
use audio_manager::bluez::Bluez;
use audio_manager::dsp::{ChannelMap, Limits, Settings, Target};
use audio_manager::manager::{Config, Manager};
use audio_manager::pairing;
use audio_manager::runner::{Dsp, NoDsp, PipewireConfig, PipewireDsp};
use audio_manager::server::Api;
use audio_manager::sim::{SimConfig, SimPhone};
use clap::Parser;
use f250_proto::audio::v1::audio_service_server::AudioServiceServer;
use f250_sd_notify::{Notifier, run_watchdog};
use tokio::sync::mpsc;
use tonic::transport::Server;

#[derive(Debug, Parser)]
#[command(
    about = "Bluetooth audio (A2DP sink, AVRCP, a pairing window) and the speakers' PipeWire filter-chain, for the dashboard (f250.audio.v1, ADR-0039)"
)]
struct Args {
    /// Where to serve f250.audio.v1: unix:<path> or tcp:<host:port>.
    #[arg(long, default_value = "unix:/tmp/f250/audio.sock")]
    listen: String,
    /// A simulated phone instead of BlueZ (labelled simulated on screen).
    #[arg(long)]
    simulate: bool,
    /// The Bluetooth adapter (hci0); empty: the first.
    #[arg(long, default_value = "hci0")]
    adapter: String,
    /// The name phones see while pairing.
    #[arg(long, default_value = "F-250")]
    name: String,
    /// The pairing window's length when the dashboard doesn't say, seconds.
    /// An example value.
    #[arg(long, default_value_t = 120)]
    pair_window_s: u64,
    /// The longest pairing window anyone may ask for, seconds. An example.
    #[arg(long, default_value_t = 300)]
    pair_window_max_s: u64,
    /// The driver's speaker settings (JSON). Empty: kept in memory only.
    #[arg(long, default_value = "")]
    settings_file: String,
    /// Don't run the speakers' filter-chain (no PipeWire here).
    #[arg(long)]
    no_dsp: bool,
    /// PipeWire's daemon, run as `pipewire -c <conf>` for the filter-chain.
    #[arg(long, default_value = "pipewire")]
    pipewire: PathBuf,
    /// pw-cli, for changing fader, balance and sub level live.
    #[arg(long, default_value = "pw-cli")]
    pw_cli: PathBuf,
    /// Where the generated filter-chain configuration is written.
    #[arg(long, default_value = "/tmp/f250/audio/speakers.conf")]
    dsp_conf: PathBuf,
    /// The DAC's PipeWire node name; empty: the default sink. The DAC8x's
    /// is UNVERIFIED (see `pw-cli ls Node` on the Pi).
    #[arg(long, default_value = "")]
    dac_node: String,
    /// The DAC's channel positions, in order. UNVERIFIED for the DAC8x.
    #[arg(long, default_value = "FL,FR,RL,RR,FC,LFE,SL,SR")]
    dac_positions: String,
    /// The DAC channels (0-based, left,right) for each amplifier input.
    /// Examples: jack 1 front, jack 2 rear, jack 3 sub; UNVERIFIED.
    #[arg(long, default_value = "0,1")]
    front: String,
    #[arg(long, default_value = "2,3")]
    rear: String,
    #[arg(long, default_value = "4,5")]
    sub: String,
    /// The crossover's default, Hz. An example value: tune it in the truck.
    #[arg(long, default_value_t = 80)]
    crossover_hz: u32,
}

#[tokio::main]
async fn main() -> ExitCode {
    match run(Args::parse()).await {
        Ok(()) => ExitCode::SUCCESS,
        Err(e) => {
            eprintln!("[audio] {e}");
            ExitCode::FAILURE
        }
    }
}

async fn run(args: Args) -> Result<(), Box<dyn std::error::Error>> {
    let limits = Limits::default();
    let defaults = Settings {
        crossover_hz: args.crossover_hz,
        ..Settings::default()
    };
    limits.check()?;
    limits
        .validate(&defaults)
        .map_err(|e| format!("--crossover-hz: {e}"))?;
    let map = ChannelMap::parse(&args.dac_positions, &args.front, &args.rear, &args.sub)?;

    let notifier = Notifier::from_env();
    if let Some(problem) = notifier.problem() {
        eprintln!("[audio] {problem}");
    }

    let (agent_tx, agent_rx) = mpsc::channel(8);
    let bt: Arc<dyn Bluetooth> = if args.simulate {
        eprintln!("[audio] simulated phone: no Bluetooth is used");
        let sim = SimPhone::new(SimConfig::default(), agent_tx);
        tokio::spawn(sim.clone().run());
        Arc::new(sim)
    } else {
        Arc::new(Bluez::start(&args.adapter, &args.name, agent_tx))
    };
    let dsp: Arc<dyn Dsp> = if args.no_dsp || args.simulate {
        Arc::new(NoDsp::new(if args.simulate {
            "simulated: no PipeWire"
        } else {
            "the filter-chain is off (--no-dsp)"
        }))
    } else {
        Arc::new(PipewireDsp::new(PipewireConfig {
            pipewire: args.pipewire.clone(),
            pw_cli: args.pw_cli.clone(),
            conf: args.dsp_conf.clone(),
            limits,
            target: Target {
                dac_node: args.dac_node.clone(),
                map,
            },
            settle: Duration::from_secs(1),
            max_backoff: Duration::from_secs(30),
        }))
    };
    let manager = Manager::new(
        Config {
            pairing: pairing::Config {
                default: Duration::from_secs(args.pair_window_s),
                max: Duration::from_secs(args.pair_window_max_s.max(args.pair_window_s)),
                ..pairing::Config::default()
            },
            name: args.name.clone(),
            limits,
            defaults,
            settings_file: (!args.settings_file.is_empty())
                .then(|| PathBuf::from(&args.settings_file)),
            simulated: args.simulate,
        },
        bt,
        dsp,
    );
    tokio::spawn(run_watchdog(
        notifier.clone(),
        manager.heartbeat.clone(),
        "audio",
    ));
    tokio::spawn(Arc::clone(&manager).run(agent_rx));

    let router =
        Server::builder().add_service(AudioServiceServer::new(Api::new(Arc::clone(&manager))));
    let closer = Arc::clone(&manager);
    let shutdown = async move {
        let mut term =
            tokio::signal::unix::signal(tokio::signal::unix::SignalKind::terminate()).ok();
        tokio::select! {
            _ = tokio::signal::ctrl_c() => {}
            Some(()) = async { match term.as_mut() { Some(t) => t.recv().await, None => std::future::pending().await } } => {}
        }
        // Never left discoverable: close the window on the way out (BlueZ's
        // own timeout is the backstop if this doesn't finish).
        if closer.close_pairing("shutdown") {
            tokio::time::sleep(Duration::from_millis(500)).await;
        }
        eprintln!("[audio] shutting down");
    };
    let ready = |at: String| {
        eprintln!("[audio] listening on {at}");
        if let Err(e) = notifier.ready(&format!("listening on {at}")) {
            eprintln!("[audio] systemd READY not sent: {e}");
        }
    };
    if let Some(path) = args.listen.strip_prefix("unix:") {
        let path = std::path::Path::new(path);
        if let Some(dir) = path.parent() {
            std::fs::create_dir_all(dir)?;
        }
        let _ = std::fs::remove_file(path);
        let listener = tokio::net::UnixListener::bind(path)?;
        ready(format!("unix:{}", path.display()));
        let incoming = tokio_stream::wrappers::UnixListenerStream::new(listener);
        router
            .serve_with_incoming_shutdown(incoming, shutdown)
            .await?;
        let _ = std::fs::remove_file(path);
    } else if let Some(addr) = args.listen.strip_prefix("tcp:") {
        let addr: std::net::SocketAddr = addr.parse()?;
        ready(format!("tcp:{addr}"));
        router.serve_with_shutdown(addr, shutdown).await?;
    } else {
        return Err(format!(
            "--listen must start with unix: or tcp:, got {}",
            args.listen
        )
        .into());
    }
    let _ = notifier.stopping();
    Ok(())
}
