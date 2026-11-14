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
use audio_manager::dsp::{ChannelMap, Limits, Settings, Target, render};
use audio_manager::knob::{self, KnobConfig};
use audio_manager::manager::{Config, Manager, Reconnect, load_settings};
use audio_manager::pairing;
use audio_manager::phonebook::{Lists, NoPhonebook, ObexReader, Phonebook, SimReader};
use audio_manager::ring::{CommandRinger, NoRinger, Ringer, SimRinger, Tone};
use audio_manager::runner::{Dsp, NoDsp, PipewireConfig, PipewireDsp};
use audio_manager::server::Api;
use audio_manager::sim::{SimConfig, SimPhone};
use audio_manager::sim_calls::{SimCalls, SimCallsConfig};
use audio_manager::telephony::{Mic, NoCalls, PwTelephony, Telephony};
use audio_manager::voice::{CommandVoice, NoVoice, SimVoice, Voice};
use audio_manager::volume::{self, VolumeLimits};
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
    /// pw-cli, for changing fader, balance, sub level and crossover live.
    #[arg(long, default_value = "pw-cli")]
    pw_cli: PathBuf,
    /// pw-metadata, to make WirePlumber relink the chain through the
    /// filter-chain each time it starts.
    #[arg(long, default_value = "pw-metadata")]
    pw_metadata: PathBuf,
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
    /// Print the filter-chain configuration the current settings give, and
    /// exit (for checking it on the bench: `pipewire -c` takes this file).
    #[arg(long)]
    print_dsp_config: bool,
    /// Says spoken prompts (navigation): a program that says its last
    /// argument and exits (/opt/f250/libexec/speak-prompt on the Pi, `say` on
    /// the Mac). Empty: simulated with --simulate, else prompts are refused.
    #[arg(long)]
    voice_command: Option<PathBuf>,
    /// The music resumes this long after the last prompt, milliseconds. An
    /// example value.
    #[arg(long, default_value_t = 1000)]
    prompt_hold_ms: u64,
    /// Where the phone connected last is remembered (its address). Empty:
    /// in memory only.
    #[arg(long, default_value = "")]
    last_phone_file: String,
    /// Reconnecting the last phone by itself: an attempt this often,
    /// seconds. An example value.
    #[arg(long, default_value_t = 20)]
    reconnect_every_s: u64,
    /// ... for this long after start, Bluetooth coming back or the link
    /// dropping, seconds; 0: never by itself. An example value.
    #[arg(long, default_value_t = 300)]
    reconnect_for_s: u64,
    /// Cover art (ADR-0042): the file obexd fetches each picture into, an
    /// absolute path both obexd and audio-manager can reach. Empty: no cover
    /// art. Needs obexd on the system bus (f250-obexd.service) and
    /// bluetoothd with --experimental (for the player's ObexPort).
    #[arg(long, default_value = "")]
    cover_art_file: String,
    /// The master volume's steps; the top one is 0 dB (ADR-0043). An
    /// example value.
    #[arg(long, default_value_t = 30)]
    volume_steps: u32,
    /// dB a volume step. An example value.
    #[arg(long, default_value_t = 2.0)]
    volume_step_db: f32,
    /// The highest level the driver may set; default: the top step. An
    /// example value: lower it for speakers that can't take the amplifiers'
    /// full output.
    #[arg(long)]
    volume_max: Option<u32>,
    /// audio-manager starts no louder than this, whatever it saved. An
    /// example value.
    #[arg(long, default_value_t = 15)]
    volume_start_max: u32,
    /// Where the volume level is kept (JSON). Empty: in memory only.
    #[arg(long, default_value = "")]
    volume_file: String,
    /// Read the volume knob from /dev/input: any device with the volume
    /// keys, play/pause or REL_DIAL (ADR-0043).
    #[arg(long)]
    knob: bool,
    /// The knob's dial counts counter-clockwise as up.
    #[arg(long)]
    knob_invert: bool,
    /// sysfs, where input devices are found (for the tests).
    #[arg(long, default_value = "/sys")]
    sysfs: PathBuf,
    /// Phone calls (ADR-0045): the PipeWire source node (`node.name`) of the
    /// call microphone. Empty: calls aren't taken here and stay on the
    /// phone. The phone sees a hands-free unit only when WirePlumber's
    /// bluez5 roles include hfp_hf (configured with it, not by this flag).
    #[arg(long, default_value = "")]
    call_mic: String,
    /// The ring tone for a phone that sends none (ADR-0045): a program that
    /// plays the WAV file named by its argument and exits (`afplay` on the
    /// Mac). Empty: simulated (silent) with --simulate, else such a phone
    /// rings only on the phone.
    #[arg(long)]
    ring_command: Option<PathBuf>,
    /// Where the ring tone's WAV is written for --ring-command.
    #[arg(long, default_value = "/tmp/f250/audio/ring.wav")]
    ring_file: PathBuf,
    /// A call ringing this long without the phone's own ring tone is rung
    /// through the speakers, milliseconds. An example value.
    #[arg(long, default_value_t = 1500)]
    ring_after_ms: u64,
    /// With --simulate: a made-up call rings this often (after start and
    /// after each call ends), seconds; 0: never.
    #[arg(long, default_value_t = 0)]
    sim_call_every_s: u64,
    /// The phone's contacts and recent calls over PBAP (ADR-0045 phase 2):
    /// the file obexd writes each list into, an absolute path on tmpfs
    /// (/run) so they are never kept on disk; read and removed at once.
    /// Empty: not read. Needs obexd on the system bus (f250-obexd.service).
    #[arg(long, default_value = "")]
    phonebook_file: String,
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
    let volume_limits = VolumeLimits {
        steps: args.volume_steps,
        step_db: args.volume_step_db,
        max: args.volume_max.unwrap_or(args.volume_steps),
        start_max: args.volume_start_max,
    };
    volume_limits.check()?;
    let settings_file =
        (!args.settings_file.is_empty()).then(|| PathBuf::from(&args.settings_file));
    let pairing = pairing::Config {
        default: Duration::from_secs(args.pair_window_s),
        max: Duration::from_secs(args.pair_window_max_s.max(args.pair_window_s)),
        ..pairing::Config::default()
    };
    let config = Config {
        pairing,
        name: args.name.clone(),
        limits,
        defaults,
        settings_file,
        simulated: args.simulate,
        prompt_hold: Duration::from_millis(args.prompt_hold_ms),
        last_phone_file: (!args.last_phone_file.is_empty())
            .then(|| PathBuf::from(&args.last_phone_file)),
        reconnect: Reconnect {
            every: Duration::from_secs(args.reconnect_every_s.max(1)),
            window: Duration::from_secs(args.reconnect_for_s),
        },
        volume: volume_limits,
        volume_file: (!args.volume_file.is_empty()).then(|| PathBuf::from(&args.volume_file)),
        ring_after: Duration::from_millis(args.ring_after_ms),
    };
    let target = Target {
        dac_node: args.dac_node.clone(),
        map,
    };
    if args.print_dsp_config {
        let (settings, problem) = load_settings(&config);
        if let Some(p) = problem {
            eprintln!("[audio] {p}");
        }
        let (saved, _) = audio_manager::manager::load_volume(config.volume_file.as_deref());
        let master = volume::gain(&volume_limits, &volume::at_start(&volume_limits, saved));
        print!("{}", render(&limits, &settings, master, &target));
        return Ok(());
    }

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
        let cover_art =
            (!args.cover_art_file.is_empty()).then(|| PathBuf::from(&args.cover_art_file));
        if cover_art.as_ref().is_some_and(|p| !p.is_absolute()) {
            return Err("--cover-art-file: an absolute path (obexd is another process)".into());
        }
        Arc::new(Bluez::start(&args.adapter, &args.name, agent_tx, cover_art))
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
            pw_metadata: args.pw_metadata.clone(),
            conf: args.dsp_conf.clone(),
            limits,
            target,
            settle: Duration::from_secs(1),
            max_backoff: Duration::from_secs(30),
        }))
    };
    let voice: Arc<dyn Voice> = if let Some(program) = &args.voice_command {
        Arc::new(CommandVoice {
            program: program.clone(),
            timeout: Duration::from_secs(30),
        })
    } else if args.simulate {
        Arc::new(SimVoice::default())
    } else {
        Arc::new(NoVoice(
            "no voice is configured (--voice-command): prompts aren't spoken".into(),
        ))
    };
    let calls: Arc<dyn Telephony> = if args.simulate {
        let sim = SimCalls::new(SimCallsConfig {
            every: (args.sim_call_every_s > 0).then(|| Duration::from_secs(args.sim_call_every_s)),
            ..SimCallsConfig::default()
        });
        tokio::spawn(sim.clone().run());
        Arc::new(sim)
    } else if args.call_mic.trim().is_empty() {
        Arc::new(NoCalls::new("no call microphone is configured"))
    } else {
        eprintln!(
            "[audio] calls: following org.pipewire.Telephony; microphone {}",
            args.call_mic.trim()
        );
        Arc::new(PwTelephony::start(Mic {
            node: args.call_mic.trim().to_string(),
            pw_cli: args.pw_cli.clone(),
        }))
    };
    let ringer: Arc<dyn Ringer> = if let Some(program) = &args.ring_command {
        Arc::new(CommandRinger {
            program: program.clone(),
            file: args.ring_file.clone(),
            tone: Tone::default(),
        })
    } else if args.simulate {
        Arc::new(SimRinger::new(Tone::default().cycle()))
    } else {
        Arc::new(NoRinger(
            "no ring tone is configured (--ring-command)".into(),
        ))
    };
    let book: Arc<dyn Phonebook> = if args.simulate {
        Lists::start(SimReader {
            delay: Duration::from_millis(500),
        })
    } else if args.phonebook_file.is_empty() {
        Arc::new(NoPhonebook::new("not configured (--phonebook-file)"))
    } else {
        let file = PathBuf::from(&args.phonebook_file);
        if !file.is_absolute() {
            return Err("--phonebook-file: an absolute path (obexd is another process)".into());
        }
        Lists::start(ObexReader { file })
    };
    let manager = Manager::new(config, bt, dsp, voice, calls, ringer, book);
    tokio::spawn(run_watchdog(
        notifier.clone(),
        manager.heartbeat.clone(),
        "audio",
    ));
    tokio::spawn(Arc::clone(&manager).run(agent_rx));
    if args.knob {
        let (tx, mut rx) = mpsc::channel(32);
        tokio::spawn(knob::run(
            KnobConfig {
                sysfs: args.sysfs.clone(),
                invert: args.knob_invert,
            },
            tx,
        ));
        let m = Arc::clone(&manager);
        tokio::spawn(async move {
            while let Some(a) = rx.recv().await {
                match a {
                    knob::Action::Volume(c) => {
                        m.set_volume(c, "knob");
                    }
                    // During a call the push answers or hangs up (ADR-0045).
                    knob::Action::PlayPause => {
                        if let Err(e) = m.knob_push("knob").await {
                            eprintln!("[audio] knob: push: {e}");
                        }
                    }
                }
            }
        });
    }

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
        closer.stop();
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
