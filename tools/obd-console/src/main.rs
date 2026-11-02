//! `obd-console`: run docs/diagnostics/TRUCK_SESSION.md against the vehicle
//! gateway from the Pi, the way the ESP32 serial console does over USB.
//!
//! Every command and its output is also appended to a transcript file, ready
//! to paste into docs/diagnostics/VERIFICATION_LOG.md. The gateway enforces
//! the ADR-0007 allow-list on everything sent from here; a refused line is
//! reported, never sent.

use std::io::Write as _;
use std::path::PathBuf;
use std::time::{SystemTime, UNIX_EPOCH};

use clap::Parser;
use f250_proto::vehicle::v1::{
    ListEventsRequest, ListSignalsRequest, ProbeRequest, RawRequest, SetPollingRequest,
    StatsRequest, StreamSnapshotsRequest, diagnostics_service_client::DiagnosticsServiceClient,
    vehicle_service_client::VehicleServiceClient,
};
use hyper_util::rt::TokioIo;
use tokio::io::{AsyncBufReadExt, BufReader};
use tonic::transport::{Channel, Endpoint, Uri};

#[derive(Parser)]
#[command(about = "Diagnostics console for the F-250 vehicle gateway")]
struct Args {
    /// Gateway endpoint: unix:/path/to.sock or tcp:host:port.
    #[arg(long, default_value = "unix:/tmp/f250/vehicle.sock")]
    gateway: String,
    /// Directory for transcript files.
    #[arg(long, default_value = ".")]
    transcripts: PathBuf,
    /// Run one command and exit (e.g. --exec "raw ATRV").
    #[arg(long)]
    exec: Option<String>,
}

const HELP: &str = "\
commands:
  pids                 every signal: enabled, provenance, state, validity, value
  on <id> | off <id>   enable/disable polling of a signal (until the gateway restarts)
  probe <id> [n]       request a signal now, n times (default 1), showing every responder
  raw <line>           send one AT command or allow-listed OBD request (e.g. raw ATRV, raw 221674)
  stats [reset]        per-signal success/failure and latency; requests/s
  events [n]           newest gateway events
  help | quit";

async fn connect(endpoint: &str) -> Result<Channel, Box<dyn std::error::Error>> {
    if let Some(path) = endpoint.strip_prefix("unix:") {
        let path = path.to_string();
        // The URI is ignored by the connector; tonic just needs a valid one.
        let ch = Endpoint::try_from("http://localhost")?
            .connect_with_connector(tower::service_fn(move |_: Uri| {
                let path = path.clone();
                async move {
                    tokio::net::UnixStream::connect(path)
                        .await
                        .map(TokioIo::new)
                }
            }))
            .await?;
        Ok(ch)
    } else if let Some(addr) = endpoint.strip_prefix("tcp:") {
        Ok(Endpoint::try_from(format!("http://{addr}"))?
            .connect()
            .await?)
    } else {
        Err(format!("endpoint must start with unix: or tcp:, got {endpoint}").into())
    }
}

struct Console {
    vehicle: VehicleServiceClient<Channel>,
    diag: DiagnosticsServiceClient<Channel>,
    transcript: std::fs::File,
}

impl Console {
    fn out(&mut self, line: &str) {
        println!("{line}");
        let _ = writeln!(self.transcript, "  {line}");
    }

    async fn run(&mut self, cmd: &str) -> Result<bool, Box<dyn std::error::Error>> {
        let _ = writeln!(self.transcript, "> {cmd}");
        let mut words = cmd.split_whitespace();
        let Some(verb) = words.next() else {
            return Ok(true);
        };
        let arg = words.next();
        match (verb, arg) {
            ("quit" | "exit", _) => return Ok(false),
            ("help", _) => self.out(HELP),
            ("pids", _) => self.pids().await?,
            ("on" | "off", Some(id)) => {
                self.diag
                    .set_polling(SetPollingRequest {
                        signal_id: id.into(),
                        enabled: verb == "on",
                    })
                    .await?;
                self.out(&format!("{id}: polling {verb}"));
            }
            ("probe", Some(id)) => {
                let count = words.next().and_then(|n| n.parse().ok()).unwrap_or(1);
                let r = self
                    .diag
                    .probe(ProbeRequest {
                        signal_id: id.into(),
                        count,
                    })
                    .await?
                    .into_inner();
                for (i, a) in r.attempts.iter().enumerate() {
                    self.out(&format!(
                        "#{} {} {} ms{}{}",
                        i + 1,
                        a.outcome,
                        a.latency_ms,
                        if a.nrc != 0 {
                            format!(" NRC {:02X}", a.nrc)
                        } else {
                            String::new()
                        },
                        if a.detail.is_empty() {
                            String::new()
                        } else {
                            format!(" ({})", a.detail)
                        }
                    ));
                    for resp in &a.responders {
                        let decoded = resp
                            .decoded
                            .map(|v| format!(" = {v:.3}"))
                            .unwrap_or_default();
                        self.out(&format!(
                            "    {} : {}{decoded}",
                            resp.can_id, resp.payload_hex
                        ));
                    }
                }
            }
            ("raw", Some(_)) => {
                let line = cmd.trim_start()["raw".len()..].trim().to_string();
                let r = self.diag.raw(RawRequest { line }).await?.into_inner();
                if !r.refused.is_empty() {
                    self.out(&format!("REFUSED: {}", r.refused));
                } else {
                    for l in &r.lines {
                        self.out(l);
                    }
                    self.out(&format!("({} ms)", r.latency_ms));
                }
            }
            ("stats", a) => {
                let r = self
                    .diag
                    .stats(StatsRequest {
                        reset: a == Some("reset"),
                    })
                    .await?
                    .into_inner();
                self.out(&format!(
                    "{:.1} requests/s over {:.0} s",
                    r.requests_per_second,
                    r.window_ms as f64 / 1000.0
                ));
                for s in &r.signals {
                    self.out(&format!(
                        "{:<14} {:<12} ok {:>6}  fail {:>5}  p50 {:>4} ms  p95 {:>4} ms  every {} ms",
                        s.signal_id, s.poll_state, s.successes, s.failures, s.latency_p50_ms,
                        s.latency_p95_ms, s.interval_ms
                    ));
                }
            }
            ("events", n) => {
                let limit = n.and_then(|n| n.parse().ok()).unwrap_or(20);
                let r = self
                    .vehicle
                    .list_events(ListEventsRequest { limit })
                    .await?
                    .into_inner();
                for e in r.events.iter().rev() {
                    self.out(&format!("{:>10} ms  {}", e.mono_ms, e.message));
                }
            }
            _ => self.out("? (type help)"),
        }
        Ok(true)
    }

    async fn pids(&mut self) -> Result<(), Box<dyn std::error::Error>> {
        let defs = self
            .vehicle
            .list_signals(ListSignalsRequest {})
            .await?
            .into_inner()
            .signals;
        let mut stream = self
            .vehicle
            .stream_snapshots(StreamSnapshotsRequest { period_ms: 0 })
            .await?
            .into_inner();
        let snap = stream
            .message()
            .await?
            .and_then(|r| r.snapshot)
            .unwrap_or_default();
        for d in defs {
            let s = snap.samples.iter().find(|s| s.signal_id == d.id);
            let value = s
                .and_then(|s| s.value)
                .map(|v| format!("{v:.2} {}", d.unit))
                .unwrap_or_else(|| "—".into());
            self.out(&format!(
                "{} {:<14} {:<11} {:<20} {:<12} {:<12} {}",
                if d.enabled { '*' } else { ' ' },
                d.id,
                d.request,
                format!("{:?}", d.provenance())
                    .trim_start_matches("Provenance")
                    .to_string(),
                s.map(|s| s.poll_state.as_str()).unwrap_or("-"),
                s.map(|s| format!("{:?}", s.validity())).unwrap_or_default(),
                value
            ));
        }
        Ok(())
    }
}

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    let args = Args::parse();
    let channel = connect(&args.gateway).await?;
    std::fs::create_dir_all(&args.transcripts)?;
    let stamp = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs())
        .unwrap_or(0);
    let path = args.transcripts.join(format!("obd-console-{stamp}.log"));
    let transcript = std::fs::OpenOptions::new()
        .create(true)
        .append(true)
        .open(&path)?;
    let mut console = Console {
        vehicle: VehicleServiceClient::new(channel.clone()),
        diag: DiagnosticsServiceClient::new(channel),
        transcript,
    };
    if let Some(cmd) = args.exec {
        console.run(&cmd).await?;
        return Ok(());
    }
    eprintln!(
        "connected to {} — transcript: {}\n{HELP}",
        args.gateway,
        path.display()
    );
    let mut lines = BufReader::new(tokio::io::stdin()).lines();
    loop {
        print!("obd> ");
        std::io::stdout().flush()?;
        let Some(line) = lines.next_line().await? else {
            break;
        };
        match console.run(line.trim()).await {
            Ok(true) => {}
            Ok(false) => break,
            Err(e) => console.out(&format!("error: {e}")),
        }
    }
    Ok(())
}
