//! `recorder run`: subscribe to the gateway and record to SQLite.
//! `recorder export`: write samples (or events) as CSV.
//!
//!   recorder run --gateway unix:/tmp/f250/vehicle.sock --db f250.sqlite
//!   recorder export --db f250.sqlite --signals eot,ect > drive.csv
//!   recorder export --db f250.sqlite --events > events.csv

use std::path::PathBuf;
use std::time::{Duration, SystemTime, UNIX_EPOCH};

use clap::{Parser, Subcommand};
use f250_proto::vehicle::v1::{
    ListEventsRequest, StreamSnapshotsRequest, vehicle_service_client::VehicleServiceClient,
};
use hyper_util::rt::TokioIo;
use recorder::{Db, Retention};
use tonic::transport::{Channel, Endpoint, Uri};

#[derive(Parser)]
#[command(about = "Records F-250 gateway telemetry to SQLite")]
struct Args {
    #[command(subcommand)]
    cmd: Cmd,
}

#[derive(Subcommand)]
enum Cmd {
    Run {
        #[arg(long, default_value = "unix:/tmp/f250/vehicle.sock")]
        gateway: String,
        #[arg(long, default_value = "f250-telemetry.sqlite")]
        db: PathBuf,
        /// Recording interval (ms, 250..60000).
        #[arg(long, default_value_t = 1000)]
        interval_ms: u32,
        #[arg(long, default_value_t = 30)]
        max_age_days: u32,
        #[arg(long, default_value_t = 2_000_000)]
        max_sample_rows: u64,
    },
    Export {
        #[arg(long, default_value = "f250-telemetry.sqlite")]
        db: PathBuf,
        /// Comma-separated signal ids (default: all).
        #[arg(long, value_delimiter = ',')]
        signals: Vec<String>,
        /// Unix epoch ms bounds.
        #[arg(long)]
        from: Option<i64>,
        #[arg(long)]
        to: Option<i64>,
        /// Export events instead of samples.
        #[arg(long)]
        events: bool,
    },
}

fn wall_ms() -> i64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_millis() as i64)
        .unwrap_or(0)
}

async fn connect(endpoint: &str) -> Result<Channel, Box<dyn std::error::Error>> {
    if let Some(path) = endpoint.strip_prefix("unix:") {
        let path = path.to_string();
        Ok(Endpoint::try_from("http://localhost")?
            .connect_with_connector(tower::service_fn(move |_: Uri| {
                let path = path.clone();
                async move {
                    tokio::net::UnixStream::connect(path)
                        .await
                        .map(TokioIo::new)
                }
            }))
            .await?)
    } else if let Some(addr) = endpoint.strip_prefix("tcp:") {
        Ok(Endpoint::try_from(format!("http://{addr}"))?
            .connect()
            .await?)
    } else {
        Err(format!("endpoint must start with unix: or tcp:, got {endpoint}").into())
    }
}

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    match Args::parse().cmd {
        Cmd::Export {
            db,
            signals,
            from,
            to,
            events,
        } => {
            let db = Db::open(&db)?;
            let mut out = std::io::stdout().lock();
            let n = if events {
                db.export_events_csv(&mut out)?
            } else {
                db.export_samples_csv(&mut out, &signals, from, to)?
            };
            eprintln!("{n} rows");
        }
        Cmd::Run {
            gateway,
            db,
            interval_ms,
            max_age_days,
            max_sample_rows,
        } => {
            let mut db = Db::open(&db)?;
            let retention = Retention {
                max_age_days,
                max_sample_rows,
            };
            let interval = interval_ms.clamp(250, 60_000);
            eprintln!("[recorder] session {} → {gateway}", db.session());
            loop {
                // Reconnect forever: the gateway may restart; nothing is lost
                // but the gap, which shows up as missing rows.
                match record(&gateway, &mut db, interval, retention).await {
                    Ok(()) => eprintln!("[recorder] stream ended; reconnecting"),
                    Err(e) => eprintln!("[recorder] {e}; reconnecting in 2 s"),
                }
                tokio::time::sleep(Duration::from_secs(2)).await;
            }
        }
    }
    Ok(())
}

async fn record(
    gateway: &str,
    db: &mut Db,
    interval_ms: u32,
    retention: Retention,
) -> Result<(), Box<dyn std::error::Error>> {
    let mut client = VehicleServiceClient::new(connect(gateway).await?);
    let mut stream = client
        .stream_snapshots(StreamSnapshotsRequest {
            period_ms: interval_ms.min(2000),
        })
        .await?
        .into_inner();
    let mut next_record = 0i64;
    let mut next_events = 0i64;
    let mut next_prune = 0i64;
    while let Some(msg) = stream.message().await? {
        let now = wall_ms();
        if let Some(snap) = msg.snapshot
            && now >= next_record
        {
            next_record = now + i64::from(interval_ms);
            db.record_snapshot(now, &snap)?;
        }
        if now >= next_events {
            next_events = now + 2_000;
            let events = client
                .list_events(ListEventsRequest { limit: 300 })
                .await?
                .into_inner();
            db.record_events(&events)?;
        }
        if now >= next_prune {
            next_prune = now + 600_000;
            let n = db.prune(now, retention)?;
            if n > 0 {
                eprintln!("[recorder] retention removed {n} sample rows");
            }
        }
    }
    Ok(())
}
