//! `navigation`: the truck's position from gpsd, routes from Valhalla,
//! address search, saved places and spoken directions, served as
//! `f250.nav.v1` (Phase 6.4, 6.5.2–6.5.4, ADR-0030, ADR-0035, ADR-0038,
//! ADR-0040).
//!
//!   navigation --listen unix:/run/f250-nav/nav.sock                # gpsd on 127.0.0.1:2947
//!   navigation --listen unix:/tmp/f250/nav.sock --simulate         # development
//!   navigation --listen tcp:127.0.0.1:50253 --simulate --sim-outage-every-s 60

use std::path::PathBuf;
use std::process::ExitCode;
use std::sync::Arc;
use std::time::Duration;

use clap::Parser;
use f250_proto::nav::v1 as pb;
use f250_sd_notify::{Heartbeat, Notifier, run_watchdog};
use navigation::guide::{self, GuideConfig};
use navigation::places::{self, Places};
use navigation::publisher::{self, PublisherConfig};
use navigation::search::Searcher;
use navigation::server::{self, Api, RoutingApi};
use navigation::sim::{self, SimConfig};
use navigation::source::{self, GpsdConfig};
use navigation::valhalla::{self, Costing, TruckOptions, ValhallaCli};
use navigation::voice::{CommandSpeaker, LogSpeaker, Speaker, Units, Voice, VoiceConfig};
use tokio::sync::{mpsc, watch};

#[derive(Parser)]
#[command(
    about = "F-250 navigation: the truck's position from gpsd and routes from Valhalla (f250.nav.v1)"
)]
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
    /// Valhalla's `valhalla_service`, run once per route, or a wrapper with
    /// its arguments (tools/dev/valhalla-docker.sh).
    #[arg(long, default_value = "valhalla_service", value_name = "PROGRAM")]
    valhalla: PathBuf,
    /// The Valhalla config this service's routing data was built for.
    #[arg(
        long,
        default_value = "/opt/f250/share/data/valhalla/valhalla-3.9.1.json",
        value_name = "FILE"
    )]
    valhalla_config: PathBuf,
    /// The routing data: one Valhalla tile extract (`make route-region`).
    #[arg(
        long,
        default_value = "/var/lib/f250/storage/routing/valhalla_tiles.tar",
        value_name = "FILE"
    )]
    routing_tiles: PathBuf,
    /// Where the config Valhalla runs with is written.
    #[arg(long, default_value = "/run/f250-nav", value_name = "DIR")]
    run_dir: PathBuf,
    /// Valhalla's costing: auto, or truck with the dimensions below. Routes
    /// are not checked for heavy vehicles or trailers either way (ADR-0010).
    #[arg(long, default_value = "auto", value_parser = ["auto", "truck"])]
    costing: String,
    /// Truck costing only, each optional: Valhalla's default otherwise.
    #[arg(long, value_name = "M")]
    truck_height_m: Option<f64>,
    #[arg(long, value_name = "M")]
    truck_width_m: Option<f64>,
    #[arg(long, value_name = "M")]
    truck_length_m: Option<f64>,
    #[arg(long, value_name = "T")]
    truck_weight_t: Option<f64>,
    #[arg(long, value_name = "T")]
    truck_axle_load_t: Option<f64>,
    /// The offline search index (`make search-region`, brought by the map
    /// stick). Read-only; reopened when it changes.
    #[arg(
        long,
        default_value = "/var/lib/f250/storage/search/search.sqlite",
        value_name = "FILE"
    )]
    search_index: PathBuf,
    /// Off the route beyond this many metres for --off-route-s seconds
    /// asks for a new route. Examples to tune on the truck.
    #[arg(long, default_value_t = 60.0)]
    off_route_m: f64,
    #[arg(long, default_value_t = 5)]
    off_route_s: u64,
    /// Arrived within this many metres of the destination. An example.
    #[arg(long, default_value_t = 40.0)]
    arrive_m: f64,
    /// Saved places (places.json) and the voice's mute setting (voice.json)
    /// go here: on the data drive (ADR-0040).
    #[arg(
        long,
        default_value = "/var/lib/f250/storage/navigation",
        value_name = "DIR"
    )]
    places_dir: PathBuf,
    /// The data drive's mount point. When given and nothing is mounted
    /// there, --places-fallback-dir is used instead and the screen says so.
    #[arg(long, value_name = "DIR")]
    places_drive: Option<PathBuf>,
    #[arg(long, default_value = "/var/lib/f250-nav", value_name = "DIR")]
    places_fallback_dir: PathBuf,
    /// A program that speaks its last argument: "say" on the Mac,
    /// "espeak-ng -v en-us". Without one, prompts go to the log only.
    #[arg(long, value_name = "COMMAND")]
    voice_command: Option<String>,
    /// Spoken distances.
    #[arg(long, default_value = "imperial", value_parser = ["imperial", "metric"])]
    voice_units: String,
    /// When prompts are spoken: the approaching prompt this many seconds
    /// ahead at the current speed, between the two distances; then the
    /// at-the-maneuver prompt likewise. Examples to tune on the truck.
    #[arg(long, default_value_t = 30.0)]
    voice_far_s: f64,
    #[arg(long, default_value_t = 400.0)]
    voice_far_min_m: f64,
    #[arg(long, default_value_t = 2500.0)]
    voice_far_max_m: f64,
    #[arg(long, default_value_t = 8.0)]
    voice_near_s: f64,
    #[arg(long, default_value_t = 50.0)]
    voice_near_min_m: f64,
    #[arg(long, default_value_t = 300.0)]
    voice_near_max_m: f64,
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
    let (route_tx, route_rx) = watch::channel(None);
    let what = if args.simulate {
        let cfg = SimConfig {
            speed_mps: args.sim_speed_kmh.max(0.0) / 3.6,
            outage_every: (args.sim_outage_every_s > 0)
                .then(|| Duration::from_secs(args.sim_outage_every_s)),
            outage_for: Duration::from_secs(args.sim_outage_s),
            ..SimConfig::default()
        };
        tokio::spawn(sim::run(cfg, events_tx, Some(route_rx.clone())));
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

    let costing = match args.costing.as_str() {
        "truck" => Costing::Truck(TruckOptions {
            height_m: args.truck_height_m,
            width_m: args.truck_width_m,
            length_m: args.truck_length_m,
            weight_t: args.truck_weight_t,
            axle_load_t: args.truck_axle_load_t,
        }),
        _ => Costing::Auto,
    };
    let router = Arc::new(ValhallaCli {
        program: args.valhalla.clone(),
        template: args.valhalla_config.clone(),
        tiles: args.routing_tiles.clone(),
        config: args.run_dir.join("valhalla.json"),
        timeout: valhalla::DEFAULT_TIMEOUT,
    });
    match valhalla::Router::check(router.as_ref()) {
        Ok(()) => eprintln!(
            "[navigation] routing with {} ({}) from {}",
            args.valhalla.display(),
            costing.name(),
            args.routing_tiles.display()
        ),
        Err(why) => eprintln!("[navigation] routing unavailable for now: {why}"),
    }
    let guide_cfg = GuideConfig {
        off_route_m: args.off_route_m,
        off_route_for: Duration::from_secs(args.off_route_s),
        arrive_m: args.arrive_m,
        costing,
        ..GuideConfig::default()
    };
    // Saved places and the mute setting: on the data drive when it is
    // mounted, else on the SD card, saying so (ADR-0040).
    let location = places::choose_location(
        &args.places_dir.join("places.json"),
        args.places_drive.as_deref(),
        &args.places_fallback_dir.join("places.json"),
        places::is_mount_point,
    );
    let state_dir = location
        .file
        .parent()
        .map(PathBuf::from)
        .unwrap_or_else(|| args.places_dir.clone());
    eprintln!(
        "[navigation] saved places in {} ({})",
        location.file.display(),
        location.described
    );
    let saved = Places::open(location);
    if !saved.problem().is_empty() {
        eprintln!("[navigation] {}", saved.problem());
    }
    let speaker: Box<dyn Speaker> = match args
        .voice_command
        .as_deref()
        .and_then(CommandSpeaker::parse)
    {
        Some(s) => Box::new(s),
        None => Box::new(LogSpeaker {
            why: "no speech output configured (audio-manager, ADR-0039, not connected yet)"
                .to_string(),
        }),
    };
    eprintln!("[navigation] voice: {}", speaker.status().detail);
    let voice = Voice::new(
        VoiceConfig {
            far_s: args.voice_far_s,
            far_min_m: args.voice_far_min_m,
            far_max_m: args.voice_far_max_m,
            near_s: args.voice_near_s,
            near_min_m: args.voice_near_min_m,
            near_max_m: args.voice_near_max_m,
            units: if args.voice_units == "metric" {
                Units::Metric
            } else {
                Units::Imperial
            },
            ..VoiceConfig::default()
        },
        speaker,
        Some(state_dir.join("voice.json")),
    );
    let (commands_tx, commands_rx) = mpsc::channel(8);
    let (guidance_tx, guidance_rx) = watch::channel(f250_proto::nav::v1::Guidance::default());
    tokio::spawn(guide::run(
        guide_cfg,
        router,
        commands_rx,
        position.clone(),
        guidance_tx,
        route_tx,
        Some(voice),
    ));
    if args.search_index.is_file() {
        eprintln!(
            "[navigation] search data from {}",
            args.search_index.display()
        );
    } else {
        eprintln!(
            "[navigation] no search data at {} for now (make search-region; the map stick brings it)",
            args.search_index.display()
        );
    }
    let api = Api::new(position)
        .with_routing(RoutingApi {
            commands: commands_tx,
            guidance: guidance_rx,
            route: route_rx,
        })
        .with_search(Searcher::new(args.search_index.clone()))
        .with_places(saved);

    let listen = args.listen.clone();
    let serving = tokio::spawn(async move { server::serve(&listen, api).await });
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
