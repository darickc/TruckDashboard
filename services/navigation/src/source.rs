//! gpsd over TCP: connect, ask for JSON (`?WATCH`), read reports line by
//! line, and on any failure say why and try again.

use std::time::Duration;

use gpsd::report::Report;
use tokio::io::{AsyncBufReadExt, AsyncWriteExt, BufReader};
use tokio::net::TcpStream;
use tokio::sync::mpsc;

/// What a position source says.
#[derive(Debug, Clone, PartialEq)]
pub enum Event {
    Connected,
    Disconnected(String),
    Report(Report),
}

#[derive(Debug, Clone)]
pub struct GpsdConfig {
    /// `host:port`.
    pub addr: String,
    pub connect_timeout: Duration,
    pub retry_after: Duration,
}

impl GpsdConfig {
    pub fn new(addr: &str) -> Self {
        GpsdConfig {
            addr: addr.to_string(),
            connect_timeout: Duration::from_secs(2),
            retry_after: Duration::from_secs(2),
        }
    }
}

/// Runs until `tx` closes.
pub async fn run_gpsd(cfg: GpsdConfig, tx: mpsc::Sender<Event>) {
    loop {
        let why = match session(&cfg, &tx).await {
            Ok(()) => "gpsd closed the connection".to_string(),
            Err(Stop::Closed) => return,
            Err(Stop::Failed(e)) => e,
        };
        if tx.send(Event::Disconnected(why)).await.is_err() {
            return;
        }
        tokio::time::sleep(cfg.retry_after).await;
    }
}

enum Stop {
    /// The receiver of events is gone: stop.
    Closed,
    Failed(String),
}

async fn session(cfg: &GpsdConfig, tx: &mpsc::Sender<Event>) -> Result<(), Stop> {
    let stream = tokio::time::timeout(cfg.connect_timeout, TcpStream::connect(&cfg.addr))
        .await
        .map_err(|_| Stop::Failed(format!("{}: connect timed out", cfg.addr)))?
        .map_err(|e| Stop::Failed(format!("{}: {e}", cfg.addr)))?;
    let (read, mut write) = stream.into_split();
    write
        .write_all(gpsd::WATCH.as_bytes())
        .await
        .map_err(|e| Stop::Failed(format!("{}: {e}", cfg.addr)))?;
    tx.send(Event::Connected).await.map_err(|_| Stop::Closed)?;
    let mut lines = BufReader::new(read).lines();
    let mut bad_lines = 0u64;
    loop {
        let line = lines
            .next_line()
            .await
            .map_err(|e| Stop::Failed(format!("{}: {e}", cfg.addr)))?;
        let Some(line) = line else {
            return Ok(());
        };
        match Report::parse(&line) {
            Ok(report) => {
                if let Report::Error(msg) = &report {
                    eprintln!("[navigation] gpsd: ERROR {msg}");
                }
                tx.send(Event::Report(report))
                    .await
                    .map_err(|_| Stop::Closed)?;
            }
            Err(e) => {
                bad_lines += 1;
                // The first, then every hundredth: a broken gpsd can't flood the log.
                if bad_lines == 1 || bad_lines.is_multiple_of(100) {
                    eprintln!("[navigation] gpsd: line not understood ({bad_lines} so far): {e}");
                }
            }
        }
    }
}
