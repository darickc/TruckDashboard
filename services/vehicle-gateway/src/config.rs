//! Command-line configuration. Everything that could make the gateway
//! transmit to the vehicle is an explicit flag (ADR-0007): without
//! `--transmit`, the OBDLink transport never opens the adapter.

use std::path::PathBuf;

use clap::{Parser, ValueEnum};

#[derive(Debug, Clone, Copy, PartialEq, Eq, ValueEnum)]
pub enum TransportKind {
    /// Power Stroke scenario simulator (nothing is transmitted anywhere).
    Sim,
    /// OBDLink MX+ / ELM327 over serial, TCP or RFCOMM.
    Obdlink,
    /// Direct CAN on a SocketCAN interface (Linux): the gateway's own
    /// single-frame ISO-TP requests (ADR-0012).
    Can,
}

#[derive(Debug, Clone, Parser)]
#[command(about = "F-250 vehicle gateway: the only process that talks to the truck")]
pub struct Config {
    /// Signal registry directory.
    #[arg(long, default_value = "shared/signals")]
    pub signals: PathBuf,
    /// Warning rules (EXAMPLE thresholds; shared with the app).
    #[arg(
        long,
        default_value = "apps/infotainment/assets/config/warning_rules.json"
    )]
    pub warnings: PathBuf,
    /// gRPC endpoint: unix:/path.sock or tcp:host:port.
    #[arg(long, default_value = "unix:/tmp/f250/vehicle.sock")]
    pub listen: String,

    #[arg(long, value_enum, default_value = "sim")]
    pub transport: TransportKind,

    /// Simulator: scenario id in --scenario-dir.
    #[arg(long, default_value = "drive_cycle")]
    pub scenario: String,
    #[arg(long, default_value = "simulator/powerstroke/scenarios")]
    pub scenario_dir: PathBuf,
    /// Simulator: start this many seconds into the scenario.
    #[arg(long, default_value_t = 0)]
    pub sim_start_s: u64,

    /// OBDLink: serial:/dev/cu.X[@baud] | tcp:host:port | rfcomm:AA:BB:..[/channel].
    #[arg(long)]
    pub adapter: Option<String>,
    /// CAN: SocketCAN interface name.
    #[arg(long, default_value = "can0")]
    pub can_if: String,
    /// CAN: how long to collect answers to a request that isn't pinned to
    /// one responder, ms. 50 ms is the commonly cited ISO 15765-4 P2CAN
    /// maximum (UNVERIFIED here; the traffic log measures the real figure).
    #[arg(long, default_value_t = 50)]
    pub can_window_ms: u64,
    /// Allow diagnostic requests to the vehicle (read-only services only).
    /// Off by default: the gateway stays PASSIVE_ONLY.
    #[arg(long)]
    pub transmit: bool,
    /// Also poll these unverified signals (explicit opt-in; they show as
    /// UNVERIFIED in the UI). Comma-separated ids.
    #[arg(long, value_delimiter = ',')]
    pub enable: Vec<String>,
    /// Requests/s the transport can sustain (MX+ on 7DF measured ≈ 10).
    #[arg(long)]
    pub budget_rps: Option<f64>,
    /// Write every adapter line (TX/RX with timestamps) to files in this
    /// directory (bounded: 5 × 10 MB).
    #[arg(long)]
    pub traffic_log: Option<PathBuf>,
    /// Read the adapter supply voltage (ATRV) this often, seconds; 0 = never.
    #[arg(long, default_value_t = 10)]
    pub voltage_every_s: u64,
}

impl Config {
    pub fn budget(&self) -> f64 {
        self.budget_rps.unwrap_or(match self.transport {
            TransportKind::Sim => 15.0,
            TransportKind::Obdlink => 10.0,
            // Not measured: one unpinned request waits the whole window, so
            // 20/s is the ceiling at 50 ms. Retune from `stats` on the truck.
            TransportKind::Can => 20.0,
        })
    }
}
