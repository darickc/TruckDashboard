//! `knob-link`: see `--help` and docs/architecture/adr/0044-knob-display.md.
//!
//!   knob-link --gateway unix:/run/f250/vehicle.sock           # the Pi
//!   knob-link --gateway tcp:127.0.0.1:50251 --device /dev/cu.usbmodem1101

use std::collections::HashMap;
use std::path::PathBuf;
use std::time::Duration;

use clap::Parser;
use f250_proto::vehicle::v1::{
    ListSignalsRequest, StreamSnapshotsRequest, vehicle_service_client::VehicleServiceClient,
};
use f250_sd_notify::{Heartbeat, Notifier, run_watchdog};
use hyper_util::rt::TokioIo;
use knob_link::frame::Units;
use knob_link::link::{self, Latest, Timing};
use tokio::sync::watch;
use tokio::time::Instant;
use tonic::transport::{Channel, Endpoint, Uri};

#[derive(Debug, Parser)]
#[command(
    about = "Feeds the knob display (ADR-0044) from vehicle-gateway, over its USB serial port"
)]
struct Args {
    /// vehicle-gateway: unix:<path> or tcp:<host:port>.
    #[arg(long, default_value = "unix:/run/f250/vehicle.sock")]
    gateway: String,
    /// The dial's serial port; empty: the first /dev/serial/by-id entry with
    /// "F-250_knob" in its name (the firmware's USB product name).
    #[arg(long, default_value = "")]
    device: String,
    /// Where the by-id links are.
    #[arg(long, default_value = "/dev/serial/by-id")]
    by_id: PathBuf,
    /// Open --device as a plain file, not as a serial port (a pseudo-terminal
    /// already in raw mode, for testing without the dial; a real dial needs
    /// the serial setup, which turns its echo off).
    #[arg(long)]
    plain_file: bool,
    /// imperial (mph, °F) or metric (km/h, °C).
    #[arg(long, default_value = "imperial")]
    units: String,
}

const RETRY: Duration = Duration::from_secs(2);
const CALL_TIMEOUT: Duration = Duration::from_secs(5);
const STREAM_SILENCE: Duration = Duration::from_secs(10);

async fn connect(endpoint: &str) -> Result<Channel, String> {
    let fut = async {
        if let Some(path) = endpoint.strip_prefix("unix:") {
            let path = path.to_string();
            Endpoint::try_from("http://localhost")
                .map_err(|e| e.to_string())?
                .connect_with_connector(tower::service_fn(move |_: Uri| {
                    let path = path.clone();
                    async move {
                        tokio::net::UnixStream::connect(path)
                            .await
                            .map(TokioIo::new)
                    }
                }))
                .await
                .map_err(|e| e.to_string())
        } else if let Some(addr) = endpoint.strip_prefix("tcp:") {
            Endpoint::try_from(format!("http://{addr}"))
                .map_err(|e| e.to_string())?
                .connect()
                .await
                .map_err(|e| e.to_string())
        } else {
            Err(format!(
                "--gateway must start with unix: or tcp:, got {endpoint}"
            ))
        }
    };
    tokio::time::timeout(CALL_TIMEOUT, fut).await.map_err(|_| {
        format!(
            "no connection to {endpoint} in {} s",
            CALL_TIMEOUT.as_secs()
        )
    })?
}

/// Follows the gateway: its definitions once per connection, then each
/// snapshot. Returns why it stopped.
async fn follow(gateway: &str, tx: &watch::Sender<Latest>, heartbeat: &Heartbeat) -> String {
    let mut client = match connect(gateway).await {
        Ok(c) => VehicleServiceClient::new(c),
        Err(e) => return e,
    };
    let defs = match tokio::time::timeout(CALL_TIMEOUT, client.list_signals(ListSignalsRequest {}))
        .await
    {
        Ok(Ok(r)) => r.into_inner().signals,
        Ok(Err(e)) => return format!("ListSignals: {e}"),
        Err(_) => return "ListSignals: no answer".into(),
    };
    let defs: HashMap<_, _> = defs.into_iter().map(|d| (d.id.clone(), d)).collect();
    tx.send_modify(|l| {
        l.defs = defs;
        l.defs_gen += 1;
    });
    let mut stream = match tokio::time::timeout(
        CALL_TIMEOUT,
        client.stream_snapshots(StreamSnapshotsRequest { period_ms: 250 }),
    )
    .await
    {
        Ok(Ok(r)) => r.into_inner(),
        Ok(Err(e)) => return format!("StreamSnapshots: {e}"),
        Err(_) => return "StreamSnapshots: no answer".into(),
    };
    eprintln!("[knob-link] following {gateway}");
    loop {
        match tokio::time::timeout(STREAM_SILENCE, stream.message()).await {
            Err(_) => return format!("no snapshot in {} s", STREAM_SILENCE.as_secs()),
            Ok(Err(e)) => return format!("stream: {e}"),
            Ok(Ok(None)) => return "the gateway ended the stream".into(),
            Ok(Ok(Some(m))) => {
                heartbeat.beat();
                if let Some(s) = m.snapshot {
                    tx.send_modify(|l| l.snapshot = Some((Instant::now(), s)));
                }
            }
        }
    }
}

#[tokio::main]
async fn main() -> std::process::ExitCode {
    let args = Args::parse();
    let units = match Units::parse(&args.units) {
        Ok(u) => u,
        Err(e) => {
            eprintln!("[knob-link] {e}");
            return std::process::ExitCode::FAILURE;
        }
    };
    let notifier = Notifier::from_env();
    let heartbeat = Heartbeat::new();
    tokio::spawn(run_watchdog(
        notifier.clone(),
        heartbeat.clone(),
        "knob-link",
    ));
    let _ = notifier.ready("waiting for the gateway and the dial");

    let (tx, rx) = watch::channel(Latest::default());
    let gateway = args.gateway.clone();
    let hb = heartbeat.clone();
    tokio::spawn(async move {
        let mut last = String::new();
        loop {
            let why = follow(&gateway, &tx, &hb).await;
            if why != last {
                eprintln!(
                    "[knob-link] gateway: {why}; retrying every {} s",
                    RETRY.as_secs()
                );
                last = why;
            }
            hb.beat();
            tokio::time::sleep(RETRY).await;
        }
    });

    // The dial: open it when it's there, serve it until it goes. Not being
    // plugged in is normal (said once).
    let fixed = (!args.device.is_empty()).then(|| PathBuf::from(&args.device));
    let mut said_missing = false;
    loop {
        heartbeat.beat();
        let Some(path) = link::find_port(fixed.as_deref(), &args.by_id) else {
            if !said_missing {
                eprintln!(
                    "[knob-link] no dial plugged in (looking every {} s)",
                    RETRY.as_secs()
                );
                said_missing = true;
            }
            tokio::time::sleep(RETRY).await;
            continue;
        };
        said_missing = false;
        if args.plain_file {
            // Two handles: tokio's File runs one operation at a time, and a
            // read waiting on the tty would hold up every write.
            let (mut ro, mut wo) = (tokio::fs::OpenOptions::new(), tokio::fs::OpenOptions::new());
            ro.read(true);
            wo.write(true);
            match tokio::try_join!(ro.open(&path), wo.open(&path)) {
                Ok((r, w)) => serve_one(&path, tokio::io::join(r, w), &rx, units, &notifier).await,
                Err(e) => eprintln!("[knob-link] {}: {e}", path.display()),
            }
        } else {
            use tokio_serial::SerialPortBuilderExt;
            match tokio_serial::new(path.to_string_lossy(), 115_200).open_native_async() {
                Ok(port) => serve_one(&path, port, &rx, units, &notifier).await,
                Err(e) => eprintln!("[knob-link] {}: {e}", path.display()),
            }
        }
        tokio::time::sleep(RETRY).await;
    }
}

async fn serve_one<P>(
    path: &std::path::Path,
    port: P,
    rx: &watch::Receiver<Latest>,
    units: Units,
    notifier: &Notifier,
) where
    P: tokio::io::AsyncRead + tokio::io::AsyncWrite + Unpin,
{
    eprintln!("[knob-link] dial on {}", path.display());
    let _ = notifier.status(&format!("dial on {}", path.display()));
    let why = link::serve(port, rx.clone(), units, Timing::default(), |m| {
        eprintln!("[knob-link] {m}")
    })
    .await;
    eprintln!("[knob-link] dial on {}: {why}", path.display());
    let _ = notifier.status("dial gone");
}
