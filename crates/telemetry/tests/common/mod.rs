//! Shared helpers for the integration tests. Everything here reads files from
//! the repository; nothing needs hardware.

#![allow(dead_code)]

use std::path::PathBuf;

use f250_telemetry::{Provenance, Registry};

/// The repository root (two levels above this crate).
pub fn repo_root() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../..")
}

pub fn read_repo_file(relative: &str) -> String {
    let path = repo_root().join(relative);
    std::fs::read_to_string(&path).unwrap_or_else(|e| panic!("{}: {e}", path.display()))
}

/// The real registry, `shared/signals/`.
pub fn seed_registry() -> Registry {
    Registry::load_dir(repo_root().join("shared/signals")).unwrap_or_else(|e| panic!("{e}"))
}

/// The real registry with every IMPORTED_UNVERIFIED row explicitly enabled
/// (`allow_unverified: true`), the way the Flutter tests run with the whole
/// catalog enabled. EGT stays disabled.
pub fn test_registry() -> Registry {
    let defs = seed_registry()
        .into_defs()
        .into_iter()
        .map(|mut d| {
            if d.provenance == Provenance::ImportedUnverified {
                d.enabled = true;
                d.allow_unverified = true;
            }
            d
        })
        .collect();
    Registry::from_defs(defs).unwrap_or_else(|e| panic!("{e}"))
}

/// Splits one CSV line of the Torque export into fields. Handles quoted
/// fields (with `""` escapes) and unquoted numbers, with optional spaces
/// after the commas.
pub fn csv_fields(line: &str) -> Vec<String> {
    let mut fields = Vec::new();
    let mut chars = line.chars().peekable();
    loop {
        while chars.peek() == Some(&' ') {
            chars.next();
        }
        let mut field = String::new();
        if chars.peek() == Some(&'"') {
            chars.next();
            while let Some(c) = chars.next() {
                if c == '"' {
                    if chars.peek() == Some(&'"') {
                        chars.next();
                        field.push('"');
                    } else {
                        break;
                    }
                } else {
                    field.push(c);
                }
            }
            while chars.peek().is_some_and(|c| *c != ',') {
                chars.next();
            }
        } else {
            while let Some(c) = chars.peek().copied() {
                if c == ',' {
                    break;
                }
                field.push(c);
                chars.next();
            }
            field = field.trim().to_owned();
        }
        fields.push(field);
        if chars.next().is_none() {
            return fields;
        }
    }
}

/// One row of exportedPIDs.csv.
#[derive(Debug, Clone)]
pub struct TorqueRow {
    pub name: String,
    pub mode_and_pid: String,
    pub equation: String,
    pub units: String,
    pub header: String,
}

pub fn torque_rows() -> Vec<TorqueRow> {
    let text = read_repo_file("shared/signals/imports/torque/exportedPIDs.csv");
    let mut lines = text.lines().filter(|l| !l.trim().is_empty());
    let header = csv_fields(lines.next().unwrap_or_default());
    let col = |name: &str| {
        header
            .iter()
            .position(|h| h == name)
            .unwrap_or_else(|| panic!("CSV has no {name} column: {header:?}"))
    };
    let (n, m, e, u, h) = (
        col("Name"),
        col("ModeAndPID"),
        col("Equation"),
        col("Units"),
        col("Header"),
    );
    lines
        .map(|l| {
            let f = csv_fields(l);
            assert_eq!(f.len(), header.len(), "malformed row: {l}");
            TorqueRow {
                name: f[n].clone(),
                mode_and_pid: f[m].clone(),
                equation: f[e].clone(),
                units: f[u].clone(),
                header: f[h].clone(),
            }
        })
        .collect()
}
