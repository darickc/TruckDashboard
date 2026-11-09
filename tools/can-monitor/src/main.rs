//! `can-monitor`: analyse a `candump -l` log offline (Phase 4.2).
//!
//!   can-monitor census LOG                     # IDs, rates, changing bytes, silences
//!   can-monitor pids LOG                       # OBD answers decoded with shared/signals
//!   can-monitor correlate LOG --signal rpm     # which broadcast field tracks RPM?
//!   can-monitor correlate LOG --signal speed --field 215:0:u16be
//!
//! See docs/diagnostics/CAN_CENSUS.md for how to record a log with PID
//! answers in it (listen-only, MX+ polling on a Y-splitter).

use std::fs::File;
use std::io::BufReader;
use std::path::{Path, PathBuf};
use std::process::ExitCode;

use can_monitor::candump::{self, Log};
use can_monitor::correlate::{self, Field, Index};
use can_monitor::{census, pids};
use clap::{Parser, Subcommand};
use f250_telemetry::Registry;

#[derive(Parser)]
#[command(about = "Offline analysis of candump logs from the F-250's HS-CAN")]
struct Args {
    #[command(subcommand)]
    cmd: Cmd,
}

#[derive(Subcommand)]
enum Cmd {
    /// Every ID: rate, period, jitter, length, which bytes change; silences.
    Census {
        log: PathBuf,
        /// Report silences longer than this.
        #[arg(long, default_value_t = 1000)]
        gap_ms: u64,
    },
    /// OBD requests and answers on the wire, decoded with the signal registry.
    Pids {
        log: PathBuf,
        /// Signal registry directory. Default: shared/signals in this checkout.
        #[arg(long)]
        signals: Option<PathBuf>,
    },
    /// Fit broadcast fields against one decoded PID signal.
    Correlate {
        log: PathBuf,
        /// Registry signal id, e.g. rpm, speed, ect.
        #[arg(long)]
        signal: String,
        /// Responder (hex), when more than one module answers, e.g. 7E8.
        #[arg(long, value_parser = parse_hex)]
        responder: Option<u32>,
        /// Fit only these fields (ID:byte:kind, kind u8|u16be|u15be|u16le).
        /// Without it, every field of every broadcast ID is tried.
        #[arg(long = "field")]
        fields: Vec<Field>,
        /// Show this many of the best fits when scanning.
        #[arg(long, default_value_t = 10)]
        top: usize,
        /// Ignore a broadcast frame older than this at a PID answer.
        #[arg(long, default_value_t = 250)]
        max_age_ms: u64,
        /// Drop fields with fewer distinct raw values than this when scanning.
        #[arg(long, default_value_t = 10)]
        min_distinct: usize,
        #[arg(long)]
        signals: Option<PathBuf>,
    },
}

fn parse_hex(s: &str) -> Result<u32, String> {
    u32::from_str_radix(s.trim_start_matches("0x"), 16).map_err(|_| format!("'{s}' is not hex"))
}

fn main() -> ExitCode {
    match run(Args::parse()) {
        Ok(()) => ExitCode::SUCCESS,
        Err(e) => {
            eprintln!("can-monitor: {e}");
            ExitCode::FAILURE
        }
    }
}

fn run(args: Args) -> Result<(), String> {
    match args.cmd {
        Cmd::Census { log, gap_ms } => {
            let log = read(&log)?;
            print_census(&log, gap_ms as f64 / 1000.0);
        }
        Cmd::Pids { log, signals } => {
            let log = read(&log)?;
            let reg = registry(signals)?;
            print_pids(&pids::decode(&log.frames, &reg));
        }
        Cmd::Correlate {
            log,
            signal,
            responder,
            fields,
            top,
            max_age_ms,
            min_distinct,
            signals,
        } => {
            let log = read(&log)?;
            let reg = registry(signals)?;
            if reg.get(&signal).is_none() {
                return Err(format!("no signal '{signal}' in the registry"));
            }
            let report = pids::decode(&log.frames, &reg);
            let mut series: Vec<_> = report
                .series
                .iter()
                .filter(|s| s.signal == signal)
                .collect();
            if series.is_empty() {
                return Err(format!(
                    "the log has no decoded '{signal}' answers. Was a tester polling it? \
                     (`can-monitor pids` lists what's there)"
                ));
            }
            if let Some(r) = responder {
                series.retain(|s| s.responder == r);
            }
            let [s] = series.as_slice() else {
                let rs: Vec<_> = series
                    .iter()
                    .map(|s| format!("{:03X}", s.responder))
                    .collect();
                return Err(format!(
                    "'{signal}' answered by {}: pick one with --responder",
                    rs.join(", ")
                ));
            };
            let index = Index::broadcasts(&log.frames);
            let max_age = max_age_ms as f64 / 1000.0;
            let fits = if fields.is_empty() {
                correlate::scan(&index, &s.samples, max_age, min_distinct)
                    .into_iter()
                    .take(top)
                    .collect()
            } else {
                fields
                    .iter()
                    .map(|&f| correlate::fit(&index, f, &s.samples, max_age).ok_or(f))
                    .filter_map(|r| {
                        r.map_err(|f| eprintln!("{f}: no fit (too few samples, or constant)"))
                            .ok()
                    })
                    .collect::<Vec<_>>()
            };
            print_fits(s, &fits);
        }
    }
    Ok(())
}

fn read(path: &Path) -> Result<Log, String> {
    let file = File::open(path).map_err(|e| format!("{}: {e}", path.display()))?;
    let log =
        candump::read_log(BufReader::new(file)).map_err(|e| format!("{}: {e}", path.display()))?;
    for (n, msg) in log.bad_lines.iter().take(5) {
        eprintln!("warning: line {n}: {msg}");
    }
    if log.bad_lines.len() > 5 {
        eprintln!("warning: {} more unparsed lines", log.bad_lines.len() - 5);
    }
    Ok(log)
}

/// `--signals`, else `shared/signals` in the nearest enclosing checkout.
fn registry(dir: Option<PathBuf>) -> Result<Registry, String> {
    let dir = match dir {
        Some(d) => d,
        None => std::env::current_dir()
            .map_err(|e| e.to_string())?
            .ancestors()
            .map(|a| a.join("shared/signals"))
            .find(|p| p.is_dir())
            .ok_or("no shared/signals here or above: pass --signals")?,
    };
    Registry::load_dir(&dir).map_err(|e| format!("{}: {e}", dir.display()))
}

fn hex(data: &[u8]) -> String {
    data.iter().map(|b| format!("{b:02X}")).collect()
}

fn print_census(log: &Log, gap_s: f64) {
    let c = census::census(&log.frames, gap_s);
    println!(
        "{:.2} s, {} frames ({:.0}/s), {} IDs, {} error frames, {} remote frames",
        c.duration_s,
        c.frames,
        if c.duration_s > 0.0 {
            c.frames as f64 / c.duration_s
        } else {
            0.0
        },
        c.ids.len(),
        log.errors.len(),
        log.remote
    );
    if c.gaps.is_empty() {
        println!("no silence over {:.1} s", gap_s);
    }
    for g in &c.gaps {
        println!(
            "SILENCE: {:.1} s with no frames, from +{:.1} s",
            g.len_s, g.at_s
        );
    }
    println!(
        "\n{:>8} {:>7} {:>7} {:>8} {:>7} {:>4} {:>6}  {:<18} first -> last",
        "ID", "frames", "Hz", "period", "jitter", "len", "values", "changing bytes"
    );
    for s in &c.ids {
        let id = if s.extended {
            format!("{:08X}", s.id)
        } else {
            format!("{:03X}", s.id)
        };
        let lens: Vec<_> = s.lengths.iter().map(usize::to_string).collect();
        println!(
            "{:>8} {:>7} {:>7.1} {:>6.1}ms {:>5.2}ms {:>4} {:>6}  {:<18} {} -> {}",
            id,
            s.count,
            s.hz,
            s.median_period_ms,
            s.jitter_ms,
            lens.join(","),
            s.distinct_payloads,
            format!("{:?}", s.changing_bytes),
            hex(&s.first),
            hex(&s.last)
        );
    }
}

fn print_pids(r: &pids::PidReport) {
    let pads: Vec<_> = r.request_pads.iter().map(|b| format!("{b:02X}")).collect();
    println!(
        "{} request frames; padding byte(s): {}",
        r.requests,
        if pads.is_empty() {
            "-".into()
        } else {
            pads.join(" ")
        }
    );
    for (p, n) in &r.request_payloads {
        println!("  {:<10} x{n}", hex(p));
    }
    println!(
        "{} answer frames; {} multi-frame (not decoded); {} decode errors",
        r.answers, r.multi_frame, r.decode_errors
    );
    for ((rsp, sid, nrc), n) in &r.negatives {
        println!("  negative {rsp:03X}: service {sid:02X} NRC {nrc:02X} x{n}");
    }
    for (p, n) in &r.unmatched {
        println!("  not in the registry: {} x{n}", hex(p));
    }
    println!(
        "\n{:<14} {:>4} {:<20} {:>6} {:>7} {:>10} {:>10}  unit",
        "signal", "from", "provenance", "n", "Hz", "min", "max"
    );
    for s in &r.series {
        let (first, last) = (
            s.samples.first().map_or(0.0, |x| x.t),
            s.samples.last().map_or(0.0, |x| x.t),
        );
        let hz = if last > first {
            (s.samples.len() - 1) as f64 / (last - first)
        } else {
            0.0
        };
        let min = s
            .samples
            .iter()
            .map(|x| x.value)
            .fold(f64::INFINITY, f64::min);
        let max = s
            .samples
            .iter()
            .map(|x| x.value)
            .fold(f64::NEG_INFINITY, f64::max);
        println!(
            "{:<14} {:>4X} {:<20} {:>6} {:>7.2} {:>10.2} {:>10.2}  {}",
            s.signal,
            s.responder,
            s.provenance.to_string(),
            s.samples.len(),
            hz,
            min,
            max,
            s.unit
        );
    }
}

fn print_fits(s: &pids::Series, fits: &[correlate::Fit]) {
    println!(
        "{} from {:03X} ({}, {} answers) against broadcast fields",
        s.signal,
        s.responder,
        s.provenance,
        s.samples.len()
    );
    println!(
        "A good fit is a candidate only: Stage B corroboration and a VERIFICATION_LOG entry come first.\n"
    );
    println!(
        "{:<14} {:>6} {:>8}   {:<34} {:>10} {:>15}  same fit as",
        "field",
        "n",
        "r",
        format!("{} ≈ slope × raw + intercept", s.signal),
        "rms",
        "raw range"
    );
    for f in fits {
        let aliases: Vec<_> = f.aliases.iter().map(ToString::to_string).collect();
        println!(
            "{:<14} {:>6} {:>8.4}   {:<34} {:>10.3} {:>7}–{:<7}  {}",
            f.field.to_string(),
            f.n,
            f.r,
            format!("{:.6} × raw {:+.3}", f.slope, f.intercept),
            f.rms,
            f.raw_min,
            f.raw_max,
            aliases.join(" ")
        );
    }
    if fits.is_empty() {
        println!("(no field fitted)");
    }
}
