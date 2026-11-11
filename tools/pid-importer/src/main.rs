//! `pid-importer`: see the library docs and shared/signals/README.md.
//!
//!   pid-importer import                       # the report: every row's fate
//!   pid-importer import --out new.yaml        # also write the new rows as registry YAML
//!   pid-importer check                        # registry rows that drifted from the export (exit 1)
//!
//! Defaults: shared/signals/imports/torque/exportedPIDs.csv and
//! shared/signals/ in the nearest enclosing checkout.

use std::collections::BTreeMap;
use std::path::PathBuf;
use std::process::ExitCode;

use clap::{Parser, Subcommand};
use f250_telemetry::Registry;
use pid_importer::import::{self, Status};
use pid_importer::torque;

#[derive(Parser)]
#[command(
    about = "Torque Pro PID export → signal registry candidates (IMPORTED_UNVERIFIED, disabled)"
)]
struct Args {
    /// The Torque export. Default: shared/signals/imports/torque/exportedPIDs.csv.
    #[arg(long, global = true)]
    csv: Option<PathBuf>,
    /// The signal registry directory. Default: shared/signals.
    #[arg(long, global = true)]
    signals: Option<PathBuf>,
    #[command(subcommand)]
    cmd: Cmd,
}

#[derive(Subcommand)]
enum Cmd {
    /// Every row: in the registry, new, or rejected and why.
    Import {
        /// Write the new rows here as registry YAML (checked against the
        /// registry first). Put it in shared/signals/ only after review.
        #[arg(long)]
        out: Option<PathBuf>,
    },
    /// Exit 1 if an IMPORTED_UNVERIFIED registry row's formula matches no
    /// export row with the same request.
    Check,
}

fn main() -> ExitCode {
    match run(Args::parse()) {
        Ok(code) => code,
        Err(e) => {
            eprintln!("pid-importer: {e}");
            ExitCode::FAILURE
        }
    }
}

fn checkout() -> Result<PathBuf, String> {
    std::env::current_dir()
        .map_err(|e| e.to_string())?
        .ancestors()
        .find(|a| a.join("shared/signals").is_dir())
        .map(PathBuf::from)
        .ok_or_else(|| "no shared/signals here or above: pass --signals and --csv".into())
}

fn run(args: Args) -> Result<ExitCode, String> {
    let signals = match args.signals {
        Some(s) => s,
        None => checkout()?.join("shared/signals"),
    };
    let csv = match args.csv {
        Some(c) => c,
        None => signals.join("imports/torque/exportedPIDs.csv"),
    };
    let text = std::fs::read_to_string(&csv).map_err(|e| format!("{}: {e}", csv.display()))?;
    let torque::Export { rows, bad } =
        torque::read(&text).map_err(|e| format!("{}: {e}", csv.display()))?;
    for (n, why) in &bad {
        eprintln!("warning: {} line {n}: {why}", csv.display());
    }
    let registry =
        Registry::load_dir(&signals).map_err(|e| format!("{}: {e}", signals.display()))?;

    match args.cmd {
        Cmd::Import { out } => {
            let reports = import::import(&rows, &registry);
            print_report(&csv, &reports, bad.len());
            if let Some(out) = out {
                let file = import::yaml_file(&reports, &csv.display().to_string());
                // The candidates must load together with the registry.
                let mut defs = registry.clone().into_defs();
                defs.extend(
                    Registry::from_yaml_str(&out.display().to_string(), &file)
                        .map_err(|e| format!("the generated YAML doesn't validate (a bug): {e}"))?
                        .into_defs(),
                );
                Registry::from_defs(defs).map_err(|e| {
                    format!("the generated YAML doesn't validate with the registry (a bug): {e}")
                })?;
                std::fs::write(&out, file).map_err(|e| format!("{}: {e}", out.display()))?;
                let n = reports
                    .iter()
                    .filter(|r| matches!(r.status, Status::New(_)))
                    .count();
                println!(
                    "\nWrote {n} candidate(s) to {} (validated with the registry).",
                    out.display()
                );
            }
            Ok(ExitCode::SUCCESS)
        }
        Cmd::Check => {
            let (ok, drift) = import::check(&rows, &registry);
            println!(
                "{} IMPORTED_UNVERIFIED registry row(s) match the export: {}",
                ok.len(),
                ok.join(", ")
            );
            for d in &drift {
                println!(
                    "DRIFT {}: registry has {:?}; the export has:",
                    d.id, d.registry_formula
                );
                for (name, f) in &d.export {
                    println!("  {name}: {f:?}");
                }
            }
            if drift.is_empty() {
                Ok(ExitCode::SUCCESS)
            } else {
                println!(
                    "An IMPORTED_UNVERIFIED row must copy the export verbatim; a formula proven \
                     on the truck belongs in a VERIFIED_ON_TRUCK row with its evidence."
                );
                Ok(ExitCode::FAILURE)
            }
        }
    }
}

fn print_report(csv: &std::path::Path, reports: &[import::RowReport], bad: usize) {
    let (mut inreg, mut new, mut rejected) = (Vec::new(), Vec::new(), Vec::new());
    for r in reports {
        match &r.status {
            Status::InRegistry { .. } => inreg.push(r),
            Status::New(_) => new.push(r),
            Status::Rejected(_) => rejected.push(r),
        }
    }
    println!(
        "{}: {} rows: {} in the registry, {} new, {} rejected{}",
        csv.display(),
        reports.len(),
        inreg.len(),
        new.len(),
        rejected.len(),
        if bad > 0 {
            format!(", {bad} unreadable")
        } else {
            String::new()
        }
    );
    println!(
        "Every imported row is IMPORTED_UNVERIFIED and disabled; agreement with Torque proves the transport, not the scaling."
    );

    println!("\nIn the registry ({}):", inreg.len());
    for r in &inreg {
        if let Status::InRegistry {
            id,
            same_formula,
            registry_formula,
        } = &r.status
        {
            println!(
                "  {:<44} {:<9} → {id}{}",
                r.row.name,
                r.row.mode_and_pid,
                if *same_formula {
                    String::new()
                } else {
                    format!("  (registry formula differs: {registry_formula})")
                }
            );
        }
    }
    println!("\nNew ({}):", new.len());
    for r in &new {
        if let Status::New(c) = &r.status {
            println!("  {:<44} {:<9} → {}", r.row.name, r.row.mode_and_pid, c.id);
            for cav in &c.caveats {
                println!("      check: {cav}");
            }
        }
    }
    println!("\nRejected ({}):", rejected.len());
    let mut by_reason: BTreeMap<String, Vec<&str>> = BTreeMap::new();
    for r in &rejected {
        if let Status::Rejected(why) = &r.status {
            by_reason.entry(why.clone()).or_default().push(&r.row.name);
        }
    }
    for (why, names) in by_reason {
        println!("  {why}:");
        for n in names {
            println!("    {n}");
        }
    }
}
