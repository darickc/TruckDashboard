//! Torque rows → registry candidates (ADR-0006, PROJECT_PLAN 3.4).
//!
//! Each row ends up in exactly one of three places:
//!
//! - **In the registry**: a signal already sends the same request on the
//!   same CAN id. The report says whether its formula is the row's.
//! - **New**: YAML for `shared/signals/`, always `IMPORTED_UNVERIFIED` and
//!   `enabled: false`, with the row's formula translated syntactically
//!   (`formula::from_torque`) and nothing else guessed.
//! - **Rejected**, with the reason. Nothing is invented to make a row fit:
//!   - a header whose CAN id isn't established. `Auto` is the functional
//!     request 0x7DF and a three-hex-digit header (`726`) is a literal CAN
//!     id (docs/diagnostics/FORD_6_0_PIDS.md); `TCM`, `ABS` and `C410F1` are
//!     not known (CLAUDE.md rule 1)
//!   - a unit the registry has no quantity for (`g`, `Count`, `µs`, `°`, ...)
//!   - a service outside the read-only allow-list (ADR-0007)
//!   - an equation the grammar can't take, or one that references a signal
//!     the registry doesn't have
//!
//! The new rows' `range` is Torque's gauge scale (Min/Max Value) in the
//! canonical unit, and `poll` is an example. Both are flagged for review:
//! a gauge scale is not a plausibility limit.

use std::collections::BTreeSet;

use f250_telemetry::formula::from_torque;
use f250_telemetry::registry::{format_bytes, service_allowed};
use f250_telemetry::units::to_canonical;
use f250_telemetry::{Provenance, Quantity, Registry, Source, Unit};

use crate::torque::Row;

/// The functional request id (Torque's `Auto` header).
pub const FUNCTIONAL: u32 = 0x7DF;

/// Example poll settings for a new row: slow and low priority until it is
/// verified and someone decides it matters.
pub const POLL_PRIORITY: u8 = 5;
pub const POLL_INTERVAL_MS: u64 = 5000;
pub const POLL_TIMEOUT_MS: u64 = 500;

#[derive(Debug, Clone, PartialEq)]
pub struct Candidate {
    pub id: String,
    /// One YAML sequence item, ready for a file in `shared/signals/`.
    pub yaml: String,
    /// What a reviewer must check before enabling it.
    pub caveats: Vec<String>,
    /// Signals the formula reads (`BARO()` → `baro`).
    pub depends_on: Vec<String>,
}

#[derive(Debug, Clone, PartialEq)]
pub enum Status {
    InRegistry {
        id: String,
        /// The registry's formula is this row's, translated.
        same_formula: bool,
        registry_formula: String,
    },
    New(Candidate),
    Rejected(String),
}

#[derive(Debug, Clone, PartialEq)]
pub struct RowReport {
    pub row: Row,
    pub status: Status,
}

/// The request bytes of `0x221310` → `[0x22, 0x13, 0x10]`.
pub fn mode_and_pid(s: &str) -> Result<Vec<u8>, String> {
    let hex = s
        .trim()
        .strip_prefix("0x")
        .or_else(|| s.trim().strip_prefix("0X"))
        .unwrap_or(s.trim());
    if hex.len() < 4 || !hex.len().is_multiple_of(2) || !hex.bytes().all(|b| b.is_ascii_hexdigit())
    {
        return Err(format!(
            "ModeAndPID {s:?} is not a service and PID in hex (e.g. 0x221310)"
        ));
    }
    Ok((0..hex.len())
        .step_by(2)
        .filter_map(|i| u8::from_str_radix(&hex[i..i + 2], 16).ok())
        .collect())
}

/// The CAN id a Torque header stands for, when that is established.
pub fn header_id(header: &str) -> Result<u32, String> {
    let h = header.trim();
    if h.eq_ignore_ascii_case("auto") || h.is_empty() {
        return Ok(FUNCTIONAL);
    }
    if h.len() == 3 && h.bytes().all(|b| b.is_ascii_hexdigit()) {
        return u32::from_str_radix(h, 16).map_err(|e| e.to_string());
    }
    Err(format!(
        "header {h:?}: its CAN id isn't established (docs/diagnostics/FORD_6_0_PIDS.md); \
         hand-write the request once it is"
    ))
}

/// The registry quantity and unit for a Torque unit string.
pub fn unit(units: &str) -> Result<(Quantity, Unit), String> {
    Ok(match units.trim() {
        "°C" | "C" | "degC" => (Quantity::Temperature, Unit::DegC),
        "°F" | "F" | "degF" => (Quantity::Temperature, Unit::DegF),
        "psi" | "PSI" => (Quantity::Pressure, Unit::Psi),
        "kPa" => (Quantity::Pressure, Unit::Kpa),
        "V" | "Volts" | "volts" => (Quantity::Voltage, Unit::Volt),
        "km/h" | "kph" => (Quantity::Speed, Unit::Kmh),
        "mph" => (Quantity::Speed, Unit::Mph),
        "rpm" | "RPM" => (Quantity::Rotation, Unit::Rpm),
        "%" => (Quantity::Percent, Unit::Percent),
        other => {
            return Err(format!(
                "unit {other:?} has no quantity in the registry (docs/architecture/telemetry-model.md)"
            ));
        }
    })
}

/// A snake_case id from the row's name: `[FORD]IAT2 (Method 1)` → `iat2_method_1`.
pub fn id_from_name(name: &str) -> String {
    let name = name.strip_prefix("[FORD]").unwrap_or(name);
    let mut id = String::new();
    for c in name.chars() {
        if c.is_ascii_alphanumeric() {
            id.push(c.to_ascii_lowercase());
        } else if !id.ends_with('_') && !id.is_empty() {
            id.push('_');
        }
    }
    let id = id.trim_end_matches('_').to_string();
    if id.is_empty() || id.starts_with(|c: char| c.is_ascii_digit()) {
        format!("torque_{id}")
    } else {
        id
    }
}

/// A number for YAML: whole numbers without a point, others to 3 places.
fn num(x: f64) -> String {
    let r = (x * 1000.0).round() / 1000.0;
    if r == r.trunc() {
        format!("{r:.0}")
    } else {
        format!("{r}")
    }
}

/// A double-quoted YAML scalar.
fn quoted(s: &str) -> String {
    let mut out = String::from("\"");
    for c in s.chars() {
        match c {
            '"' => out.push_str("\\\""),
            '\\' => out.push_str("\\\\"),
            c if c.is_control() => out.push(' '),
            c => out.push(c),
        }
    }
    out.push('"');
    out
}

/// Every row's fate. `registry`: the signals already defined.
pub fn import(rows: &[Row], registry: &Registry) -> Vec<RowReport> {
    let mut taken: BTreeSet<String> = registry.ids().map(str::to_string).collect();
    rows.iter()
        .map(|row| RowReport {
            row: row.clone(),
            status: classify(row, registry, &mut taken),
        })
        .collect()
}

fn classify(row: &Row, registry: &Registry, taken: &mut BTreeSet<String>) -> Status {
    let payload = match mode_and_pid(&row.mode_and_pid) {
        Ok(p) => p,
        Err(e) => return Status::Rejected(e),
    };
    let sid = payload[0];
    if !service_allowed(sid) {
        return Status::Rejected(format!(
            "service 0x{sid:02X} is not on the read-only allow-list (ADR-0007)"
        ));
    }
    // Service 22 takes a two-byte DID; the others here a one-byte PID.
    let want = if sid == 0x22 { 3 } else { 2 };
    if payload.len() != want {
        return Status::Rejected(format!(
            "ModeAndPID {}: service {sid:02X} takes a {}-byte {}",
            row.mode_and_pid.trim(),
            want - 1,
            if sid == 0x22 { "DID" } else { "PID" }
        ));
    }
    let tx_id = match header_id(&row.header) {
        Ok(id) => id,
        Err(e) => return Status::Rejected(e),
    };
    let t = match from_torque(&row.equation) {
        Ok(t) => t,
        Err(e) => return Status::Rejected(e.to_string()),
    };

    // Already defined: the same request on the same CAN id.
    let same_request: Vec<_> = registry
        .iter()
        .filter(|d| {
            d.request
                .as_ref()
                .is_some_and(|r| r.payload == payload && r.tx_id == tx_id)
        })
        .collect();
    if !same_request.is_empty() {
        let hit = same_request
            .iter()
            .find(|d| {
                d.decode
                    .as_ref()
                    .is_some_and(|x| x.formula.source() == t.formula.source())
            })
            .unwrap_or(&same_request[0]);
        let registry_formula = hit
            .decode
            .as_ref()
            .map(|x| x.formula.source().to_string())
            .unwrap_or_default();
        return Status::InRegistry {
            id: hit.id.clone(),
            same_formula: registry_formula == t.formula.source(),
            registry_formula,
        };
    }

    let (quantity, native) = match unit(&row.units) {
        Ok(u) => u,
        Err(e) => return Status::Rejected(e),
    };
    let depends_on: Vec<String> = t.formula.references().into_iter().collect();
    for r in &depends_on {
        match registry.get(r) {
            None => {
                return Status::Rejected(format!(
                    "the formula reads signal {r:?}, which the registry doesn't have"
                ));
            }
            Some(d) if d.source == Source::Computed => {
                return Status::Rejected(format!("the formula reads {r:?}, a computed signal"));
            }
            Some(_) => {}
        }
    }
    let gauge = |s: &str| s.trim().parse::<f64>().ok().filter(|x| x.is_finite());
    let (Some(lo), Some(hi)) = (gauge(&row.min), gauge(&row.max)) else {
        return Status::Rejected(format!(
            "Min/Max Value {:?}/{:?} aren't numbers",
            row.min, row.max
        ));
    };
    let (Ok(min), Ok(max)) = (
        to_canonical(quantity, native, lo),
        to_canonical(quantity, native, hi),
    ) else {
        return Status::Rejected("Min/Max Value can't be converted".into());
    };
    if min >= max {
        return Status::Rejected(format!("Min/Max Value {lo}/{hi} isn't a range"));
    }

    let mut id = id_from_name(&row.name);
    if taken.contains(&id) {
        let base = id.clone();
        id = (2..)
            .map(|n| format!("{base}_{n}"))
            .find(|c| !taken.contains(c))
            .unwrap_or(base);
    }
    taken.insert(id.clone());

    let mut caveats = t.caveats.clone();
    caveats.push(format!(
        "range is Torque's gauge scale ({lo}–{hi} {}), not a plausibility limit",
        row.units.trim()
    ));
    if tx_id != FUNCTIONAL {
        caveats.push(format!(
            "header {} used literally as tx_id 0x{tx_id:03X}; the responder is unknown",
            row.header.trim()
        ));
    }
    let name = row.name.strip_prefix("[FORD]").unwrap_or(&row.name).trim();
    let short = if row.short_name.trim().is_empty() {
        name
    } else {
        row.short_name.trim()
    };
    let mut echo = payload.clone();
    echo[0] = sid.wrapping_add(0x40);
    let notes = format!(
        "Torque row {:?}, {}, header {}. Imported by tools/pid-importer: \
         unverified and disabled; range is the Torque gauge scale and poll an \
         example; review both, then verify on the truck (FORD_6_0_PIDS.md) \
         before enabling.",
        row.name,
        row.mode_and_pid.trim(),
        row.header.trim()
    );
    let yaml = format!(
        "- id: {id}\n  name: {name}\n  short_name: {short}\n  quantity: {quantity}\n  unit: \"{canon}\"\n  \
         source: diagnostic\n  request: {{protocol: iso15765, tx_id: \"0x{tx_id:03X}\", payload: \"{payload}\"}}\n  \
         response: {{expect: \"{expect}\", length: {len}}}\n  decode: {{formula: {formula}, unit: \"{native}\"}}\n  \
         range: {{min: {min}, max: {max}}}\n  \
         poll: {{priority: {POLL_PRIORITY}, interval_ms: {POLL_INTERVAL_MS}, timeout_ms: {POLL_TIMEOUT_MS}}}\n  \
         provenance: IMPORTED_UNVERIFIED\n  enabled: false\n  notes: {notes}\n",
        name = quoted(name),
        short = quoted(short),
        canon = quantity.canonical_unit(),
        payload = format_bytes(&payload),
        expect = format_bytes(&echo),
        len = t.formula.bytes_required(),
        formula = quoted(t.formula.source()),
        min = num(min),
        max = num(max),
        notes = quoted(&notes),
    );
    Status::New(Candidate {
        id,
        yaml,
        caveats,
        depends_on,
    })
}

/// The new rows as one YAML file for `shared/signals/`.
pub fn yaml_file(reports: &[RowReport], source: &str) -> String {
    let mut out = format!(
        "# Candidates from {source}, written by tools/pid-importer.\n\
         # Every row is IMPORTED_UNVERIFIED and disabled. Review the range (Torque's\n\
         # gauge scale) and the poll settings (examples), and verify on the truck\n\
         # (docs/diagnostics/FORD_6_0_PIDS.md) before enabling any of them.\n"
    );
    for r in reports {
        if let Status::New(c) = &r.status {
            out.push('\n');
            out.push_str(&c.yaml);
        }
    }
    out
}

/// A registry row taken from the export whose formula no longer matches
/// any export row with the same request.
#[derive(Debug, Clone, PartialEq)]
pub struct Drift {
    pub id: String,
    pub registry_formula: String,
    /// (row name, translated formula) for the export rows with that request.
    pub export: Vec<(String, String)>,
}

/// Checks every `IMPORTED_UNVERIFIED` registry row whose request the export
/// has: its formula must be one of those rows', translated (the registry
/// copies the export verbatim). Returns the ids that match and the drifts.
/// A `VERIFIED_ON_TRUCK` row may differ from Torque on purpose and isn't
/// checked.
pub fn check(rows: &[Row], registry: &Registry) -> (Vec<String>, Vec<Drift>) {
    let mut ok = Vec::new();
    let mut drift = Vec::new();
    for d in registry.iter() {
        if d.provenance != Provenance::ImportedUnverified {
            continue;
        }
        let (Some(req), Some(dec)) = (&d.request, &d.decode) else {
            continue;
        };
        let export: Vec<(String, String)> = rows
            .iter()
            .filter(|r| mode_and_pid(&r.mode_and_pid).is_ok_and(|p| p == req.payload))
            .map(|r| {
                let f = from_torque(&r.equation)
                    .map(|t| t.formula.source().to_string())
                    .unwrap_or_else(|e| format!("(untranslatable: {e})"));
                (r.name.clone(), f)
            })
            .collect();
        if export.is_empty() {
            continue;
        }
        if export.iter().any(|(_, f)| f == dec.formula.source()) {
            ok.push(d.id.clone());
        } else {
            drift.push(Drift {
                id: d.id.clone(),
                registry_formula: dec.formula.source().to_string(),
                export,
            });
        }
    }
    (ok, drift)
}

#[cfg(test)]
#[allow(clippy::unwrap_used)]
mod tests {
    use super::*;

    fn row(
        name: &str,
        pid: &str,
        eq: &str,
        min: &str,
        max: &str,
        units: &str,
        header: &str,
    ) -> Row {
        Row {
            line: 2,
            name: name.into(),
            short_name: "SN".into(),
            mode_and_pid: pid.into(),
            equation: eq.into(),
            min: min.into(),
            max: max.into(),
            units: units.into(),
            header: header.into(),
        }
    }

    const REGISTRY: &str = r#"
- id: baro
  name: Barometric pressure
  short_name: Baro
  quantity: pressure
  unit: kPa
  source: diagnostic
  request: {protocol: iso15765, tx_id: "0x7DF", payload: "01 33"}
  response: {expect: "41 33", length: 1}
  decode: {formula: "A", unit: kPa}
  range: {min: 50, max: 110}
  poll: {priority: 4, interval_ms: 30000, timeout_ms: 500}
  provenance: SAE
  enabled: true
- id: eot
  name: Engine oil temp
  short_name: EOT
  quantity: temperature
  unit: degC
  source: diagnostic
  request: {protocol: iso15765, tx_id: "0x7DF", payload: "22 13 10"}
  response: {expect: "62 13 10", length: 2}
  decode: {formula: "(((A*256)+B)/100)-40", unit: degC}
  range: {min: -40, max: 150}
  poll: {priority: 3, interval_ms: 1500, timeout_ms: 500}
  provenance: IMPORTED_UNVERIFIED
  enabled: false
"#;

    fn registry() -> Registry {
        Registry::from_yaml_str("test.yaml", REGISTRY).unwrap()
    }

    #[test]
    fn parses_requests_headers_units_and_ids() {
        assert_eq!(mode_and_pid("0x221310").unwrap(), [0x22, 0x13, 0x10]);
        assert_eq!(mode_and_pid("0105").unwrap(), [0x01, 0x05]);
        for bad in ["0x22131", "0x2", "zz1310", ""] {
            assert!(mode_and_pid(bad).is_err(), "{bad}");
        }
        assert_eq!(header_id("Auto").unwrap(), 0x7DF);
        assert_eq!(header_id("726").unwrap(), 0x726);
        for unknown in ["TCM", "ABS", "C410F1"] {
            assert!(
                header_id(unknown)
                    .unwrap_err()
                    .contains("isn't established")
            );
        }
        assert_eq!(unit("PSI").unwrap(), (Quantity::Pressure, Unit::Psi));
        assert_eq!(unit("Volts").unwrap(), (Quantity::Voltage, Unit::Volt));
        for bad in [
            "g",
            "Count",
            "µs",
            "°",
            "Deg.",
            "Gear",
            "Ft-Lb",
            "GPH",
            "mg/stroke",
        ] {
            assert!(unit(bad).is_err(), "{bad}");
        }
        assert_eq!(id_from_name("[FORD]IAT2 (Method 1)"), "iat2_method_1");
        assert_eq!(
            id_from_name("[FORD]ABS - Lateral acceleration"),
            "abs_lateral_acceleration"
        );
        assert_eq!(id_from_name("[FORD]2nd thing"), "torque_2nd_thing");
        assert_eq!(id_from_name("[FORD]"), "torque_");
    }

    #[test]
    fn a_row_already_in_the_registry_is_compared_not_written() {
        let r = registry();
        let same = row(
            "[FORD]Engine Oil Temp",
            "0x221310",
            "(((A*256)+B)/100)-40",
            "0",
            "300",
            "°C",
            "Auto",
        );
        let other = row(
            "[FORD]EOT other",
            "0x221310",
            "((A*256)+B)/10",
            "0",
            "300",
            "°C",
            "Auto",
        );
        let out = import(&[same, other], &r);
        assert_eq!(
            out[0].status,
            Status::InRegistry {
                id: "eot".into(),
                same_formula: true,
                registry_formula: "(((A*256)+B)/100)-40".into()
            }
        );
        assert!(matches!(
            &out[1].status,
            Status::InRegistry {
                same_formula: false,
                ..
            }
        ));
    }

    #[test]
    fn rejections_say_why() {
        let r = registry();
        let cases = [
            (
                row("x", "0x2E1310", "A", "0", "1", "%", "Auto"),
                "allow-list",
            ),
            (
                row("x", "0x221111", "A", "0", "1", "%", "TCM"),
                "isn't established",
            ),
            (
                row("x", "0x221111", "A", "0", "1", "Count", "Auto"),
                "no quantity",
            ),
            (
                row("x", "0x221111", "{A:3}", "0", "1", "%", "Auto"),
                "bit syntax",
            ),
            (
                row("x", "0x221111", "A-FOO()", "0", "1", "%", "Auto"),
                "translate",
            ),
            (
                row("x", "0x221111", "A", "a", "1", "%", "Auto"),
                "aren't numbers",
            ),
            (
                row("x", "0x221111", "A", "5", "5", "%", "Auto"),
                "isn't a range",
            ),
            (row("x", "0x2211", "A", "0", "1", "%", "Auto"), "ModeAndPID"),
        ];
        for (rw, why) in cases {
            let s = &import(std::slice::from_ref(&rw), &r)[0].status;
            match s {
                Status::Rejected(e) => assert!(e.contains(why), "{why}: {e}"),
                other => panic!("{why}: {other:?}"),
            }
        }
    }

    #[test]
    fn new_rows_are_unverified_disabled_and_load_with_the_registry() {
        let r = registry();
        let rows = [
            row(
                "[FORD]Fan Speed Sensor",
                "0x22099f",
                "((A*256)+B)*(1/4)",
                "0",
                "1000",
                "rpm",
                "Auto",
            ),
            row(
                "[FORD]Boost (Ford specific)",
                "0x221440",
                "(((A*256)+B)*0.03625)-BARO()",
                "0",
                "30",
                "psi",
                "Auto",
            ),
            row(
                "[FORD]Left front tyre pressure",
                "0x222813",
                "(((256*A)+B)/3+22/3)*0.145",
                "0",
                "70",
                "psi",
                "726",
            ),
            row(
                "[FORD]Fan Speed Sensor",
                "0x22099e",
                "A",
                "0",
                "1000",
                "rpm",
                "Auto",
            ),
        ];
        let out = import(&rows, &r);
        let ids: Vec<_> = out
            .iter()
            .map(|x| match &x.status {
                Status::New(c) => c.id.clone(),
                s => panic!("{s:?}"),
            })
            .collect();
        assert_eq!(
            ids,
            [
                "fan_speed_sensor",
                "boost_ford_specific",
                "left_front_tyre_pressure",
                "fan_speed_sensor_2"
            ]
        );
        let Status::New(boost) = &out[1].status else {
            panic!()
        };
        assert_eq!(boost.depends_on, ["baro"]);
        assert!(boost.caveats.iter().any(|c| c.contains("BARO()")));
        let Status::New(tyre) = &out[2].status else {
            panic!()
        };
        assert!(tyre.yaml.contains("tx_id: \"0x726\""), "{}", tyre.yaml);
        assert!(tyre.caveats.iter().any(|c| c.contains("used literally")));
        assert!(
            tyre.yaml.contains("range: {min: 0, max: 482.633}"),
            "psi → kPa: {}",
            tyre.yaml
        );

        // The file loads together with the registry and every row is safe.
        let file = yaml_file(&out, "test.csv");
        let both = format!(
            "{REGISTRY}\n{}",
            file.lines()
                .filter(|l| !l.starts_with('#'))
                .collect::<Vec<_>>()
                .join("\n")
        );
        let loaded =
            Registry::from_yaml_str("both.yaml", &both).unwrap_or_else(|e| panic!("{e}\n{both}"));
        let fan = loaded.get("fan_speed_sensor").unwrap();
        assert_eq!(fan.provenance, Provenance::ImportedUnverified);
        assert!(!fan.enabled);
        assert_eq!(fan.request.as_ref().unwrap().payload, [0x22, 0x09, 0x9F]);
        assert_eq!(fan.response.as_ref().unwrap().expect, [0x62, 0x09, 0x9F]);
        assert_eq!(
            fan.decode.as_ref().unwrap().formula.source(),
            "((A*256)+B)*(1/4)"
        );
        assert_eq!(fan.response.as_ref().unwrap().length, 2);
    }

    #[test]
    fn names_with_quotes_stay_valid_yaml() {
        let r = registry();
        let rw = row(
            "[FORD]Odd \"quoted\" \\ name",
            "0x221234",
            "A",
            "0",
            "100",
            "%",
            "Auto",
        );
        let out = import(&[rw], &r);
        let file = yaml_file(&out, "t");
        let loaded =
            Registry::from_yaml_str("t.yaml", &file).unwrap_or_else(|e| panic!("{e}\n{file}"));
        assert_eq!(loaded.iter().next().unwrap().name, "Odd \"quoted\" \\ name");
    }

    #[test]
    fn check_finds_drift_only_in_imported_rows() {
        let r = registry();
        let same = [row(
            "[FORD]Engine Oil Temp",
            "0x221310",
            "(((A*256)+B)/100)-40",
            "0",
            "300",
            "°C",
            "Auto",
        )];
        assert_eq!(check(&same, &r), (vec!["eot".to_string()], vec![]));
        let changed = [row(
            "[FORD]Engine Oil Temp",
            "0x221310",
            "((A*256)+B)/10",
            "0",
            "300",
            "°C",
            "Auto",
        )];
        let (ok, drift) = check(&changed, &r);
        assert!(ok.is_empty());
        assert_eq!(drift[0].id, "eot");
        assert_eq!(drift[0].export[0].1, "((A*256)+B)/10");
        assert_eq!(check(&[], &r), (vec![], vec![]));
    }
}
