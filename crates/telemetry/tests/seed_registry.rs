//! The real `shared/signals/` registry against its sources: the Dart
//! catalog, the Torque export, the calibration and warning-rule configs.

mod common;

use std::time::Duration;

use f250_telemetry::registry::{Source, format_bytes, service_allowed};
use f250_telemetry::units::{Quantity, Unit};
use f250_telemetry::{Provenance, WarningConfig};

#[test]
fn trans_temp_is_the_only_verified_on_truck_signal() {
    let r = common::seed_registry();
    let verified: Vec<_> = r
        .iter()
        .filter(|d| d.provenance == Provenance::VerifiedOnTruck)
        .map(|d| d.id.as_str())
        .collect();
    assert_eq!(verified, ["trans_temp"]);
    let t = r.get("trans_temp").unwrap_or_else(|| panic!("trans_temp"));
    assert!(t.evidence.as_deref().is_some_and(|e| {
        e.contains("docs/diagnostics/VERIFICATION_LOG.md") && e.contains("2026-08-09")
    }));
    assert_eq!(t.request.as_ref().and_then(|q| q.rx_id), Some(0x7E9));
    assert!(t.enabled);
}

#[test]
fn every_ford_row_is_disabled_and_unverified() {
    let r = common::seed_registry();
    let mut ford = 0;
    for d in r.iter() {
        let service = d.request.as_ref().and_then(|q| q.service());
        if service == Some(0x22) && d.provenance != Provenance::VerifiedOnTruck {
            ford += 1;
            assert_eq!(d.provenance, Provenance::ImportedUnverified, "{}", d.id);
            assert!(!d.enabled, "{} must start disabled", d.id);
            assert!(!d.allow_unverified, "{}", d.id);
        }
        if d.provenance == Provenance::ImportedUnverified {
            assert_eq!(service, Some(0x22), "{}", d.id);
        }
    }
    assert_eq!(ford, 7);
}

#[test]
fn every_request_uses_an_allowed_read_service() {
    for d in common::seed_registry().iter() {
        if let Some(q) = &d.request {
            let sid = q.service().unwrap_or(0xFF);
            assert!(service_allowed(sid), "{}: 0x{sid:02X}", d.id);
        }
    }
}

/// The fields of one `SignalDef(...)` in signal_catalog.dart.
#[derive(Debug, Default)]
struct DartDef {
    id: String,
    name: String,
    short_name: String,
    quantity: String,
    unit: String,
    provenance: String,
    min: f64,
    max: f64,
    request: Option<String>,
    responder: Option<String>,
    stale_after: Duration,
    max_input_skew: Duration,
    enabled: bool,
    inputs: Vec<String>,
}

fn after<'a>(block: &'a str, key: &str) -> Option<&'a str> {
    // Match `key` only at the start of an argument, so `name: ` does not
    // match inside `shortName: `.
    let mut from = 0;
    while let Some(i) = block[from..].find(key) {
        let at = from + i;
        let prev = block[..at].chars().next_back();
        if prev.is_none_or(|c| !c.is_alphanumeric()) {
            return Some(&block[at + key.len()..]);
        }
        from = at + key.len();
    }
    None
}

fn quoted(block: &str, key: &str) -> Option<String> {
    let rest = after(block, &format!("{key}: '"))?;
    Some(rest[..rest.find('\'')?].to_owned())
}

fn word(block: &str, key: &str) -> Option<String> {
    let rest = after(block, key)?;
    Some(rest.chars().take_while(|c| c.is_alphanumeric()).collect())
}

fn number(block: &str, key: &str) -> Option<f64> {
    let rest = after(block, &format!("{key}: "))?;
    let end = rest.find([',', ')', '\n'])?;
    rest[..end].trim().parse().ok()
}

fn duration(block: &str, key: &str) -> Option<Duration> {
    let rest = after(block, &format!("{key}: Duration("))?;
    let inner = &rest[..rest.find(')')?];
    let (unit, n) = inner.split_once(':')?;
    let n: u64 = n.trim().parse().ok()?;
    match unit.trim() {
        "milliseconds" => Some(Duration::from_millis(n)),
        "seconds" => Some(Duration::from_secs(n)),
        _ => None,
    }
}

fn dart_catalog() -> Vec<DartDef> {
    let text = common::read_repo_file("apps/infotainment/lib/model/signal_catalog.dart");
    text.split("SignalDef(")
        .skip(1)
        .map(|block| {
            let block = &block[..block.find("\n  ),").unwrap_or(block.len())];
            let req = |v: Option<String>, what: &str| {
                v.unwrap_or_else(|| panic!("no {what} in Dart block:\n{block}"))
            };
            DartDef {
                id: req(quoted(block, "id"), "id"),
                name: req(quoted(block, "name"), "name"),
                short_name: req(quoted(block, "shortName"), "shortName"),
                quantity: req(word(block, "quantity: Quantity."), "quantity"),
                unit: req(quoted(block, "unit"), "unit"),
                provenance: req(word(block, "provenance: Provenance."), "provenance"),
                min: number(block, "min").unwrap_or_else(|| panic!("min:\n{block}")),
                max: number(block, "max").unwrap_or_else(|| panic!("max:\n{block}")),
                request: quoted(block, "request"),
                responder: quoted(block, "responder"),
                // Defaults of the Dart SignalDef constructor.
                stale_after: duration(block, "staleAfter").unwrap_or(Duration::from_secs(3)),
                max_input_skew: duration(block, "maxInputSkew").unwrap_or(Duration::from_secs(2)),
                enabled: !block.contains("enabled: false"),
                inputs: after(block, "inputs: [")
                    .and_then(|r| r.find(']').map(|e| &r[..e]))
                    .map(|s| {
                        s.split(',')
                            .map(|i| i.trim().trim_matches('\'').to_owned())
                            .filter(|i| !i.is_empty())
                            .collect()
                    })
                    .unwrap_or_default(),
            }
        })
        .collect()
}

fn quantity_name(q: Quantity) -> &'static str {
    match q {
        Quantity::Temperature => "temperature",
        Quantity::TemperatureDelta => "temperatureDelta",
        Quantity::Pressure => "pressure",
        Quantity::Voltage => "voltage",
        Quantity::Speed => "speed",
        Quantity::Rotation => "rotation",
        Quantity::Percent => "percent",
    }
}

fn provenance_name(p: Provenance) -> &'static str {
    match p {
        Provenance::Sae => "sae",
        Provenance::VerifiedOnTruck => "verifiedOnTruck",
        Provenance::ImportedUnverified => "importedUnverified",
        Provenance::Computed => "computed",
        Provenance::AuxSensor => "auxSensor",
        Provenance::BroadcastDecoded => "broadcastDecoded",
    }
}

#[test]
fn registry_mirrors_the_dart_catalog() {
    let dart = dart_catalog();
    let r = common::seed_registry();
    let mut dart_ids: Vec<&str> = dart.iter().map(|d| d.id.as_str()).collect();
    let mut ids: Vec<&str> = r.ids().collect();
    assert_eq!(dart_ids.len(), 17, "Dart catalog parse");
    dart_ids.sort_unstable();
    ids.sort_unstable();
    assert_eq!(ids, dart_ids);

    for d in &dart {
        let s = r.get(&d.id).unwrap_or_else(|| panic!("{}", d.id));
        let id = &d.id;
        assert_eq!(s.name, d.name, "{id} name");
        assert_eq!(s.short_name, d.short_name, "{id} short_name");
        assert_eq!(quantity_name(s.quantity), d.quantity, "{id} quantity");
        assert_eq!(s.unit.symbol(), d.unit, "{id} unit");
        assert_eq!(
            provenance_name(s.provenance),
            d.provenance,
            "{id} provenance"
        );
        assert_eq!((s.range.min, s.range.max), (d.min, d.max), "{id} range");
        let payload = s.request.as_ref().map(|q| format_bytes(&q.payload));
        assert_eq!(payload, d.request, "{id} request");
        let responder = s
            .request
            .as_ref()
            .and_then(|q| q.rx_id)
            .map(|r| format!("{r:X}"));
        assert_eq!(responder, d.responder, "{id} responder");
        assert_eq!(s.inputs, d.inputs, "{id} inputs");
        if s.is_computed() {
            assert_eq!(s.stale_after, None, "{id}");
            assert_eq!(s.input_skew_limit(), d.max_input_skew, "{id} skew");
        } else {
            assert_eq!(s.stale_after, Some(d.stale_after), "{id} stale_after");
        }
        // The Dart catalog enables Ford rows for the simulator; the
        // registry starts them disabled.
        if s.provenance != Provenance::ImportedUnverified {
            assert_eq!(s.enabled, d.enabled, "{id} enabled");
        }
    }
}

#[test]
fn imported_formulas_are_verbatim_from_the_torque_export() {
    let rows = common::torque_rows();
    let r = common::seed_registry();
    for d in r.iter().filter(|d| {
        matches!(
            d.provenance,
            Provenance::ImportedUnverified | Provenance::VerifiedOnTruck
        )
    }) {
        let q = d.request.as_ref().unwrap_or_else(|| panic!("{}", d.id));
        let mode_and_pid = format!(
            "0x{}",
            q.payload
                .iter()
                .map(|b| format!("{b:02x}"))
                .collect::<String>()
        );
        let decode = d.decode.as_ref().unwrap_or_else(|| panic!("{}", d.id));
        let unit = match decode.unit {
            Unit::DegF => "°F",
            Unit::DegC => "°C",
            Unit::Psi => "psi",
            Unit::Volt => "V",
            Unit::Percent => "%",
            other => panic!("{}: unexpected Torque unit {other}", d.id),
        };
        let matching: Vec<_> = rows
            .iter()
            .filter(|row| {
                row.mode_and_pid.eq_ignore_ascii_case(&mode_and_pid)
                    && row.equation == decode.formula.source()
                    && (row.units == unit || (unit == "V" && row.units == "Volts"))
                    && row.header == "Auto"
            })
            .collect();
        assert!(
            !matching.is_empty(),
            "{}: no Torque row {mode_and_pid} with equation {:?} [{unit}] header Auto",
            d.id,
            decode.formula.source()
        );
        assert_eq!(
            q.tx_id, 0x7DF,
            "{}: header Auto is the functional 0x7DF",
            d.id
        );
    }
}

#[test]
fn sae_formulas_are_the_documented_j1979_ones() {
    let r = common::seed_registry();
    let expected = [
        ("rpm", "01 0C", "((A*256)+B)/4", Unit::Rpm),
        ("speed", "01 0D", "A", Unit::Kmh),
        ("ect", "01 05", "A-40", Unit::DegC),
        ("baro", "01 33", "A", Unit::Kpa),
        ("load", "01 04", "A*100/255", Unit::Percent),
        ("iat", "01 0F", "A-40", Unit::DegC),
    ];
    let sae: Vec<_> = r
        .iter()
        .filter(|d| d.provenance == Provenance::Sae)
        .map(|d| d.id.as_str())
        .collect();
    assert_eq!(sae.len(), expected.len());
    for (id, payload, formula, unit) in expected {
        let d = r.get(id).unwrap_or_else(|| panic!("{id}"));
        assert_eq!(d.provenance, Provenance::Sae, "{id}");
        let q = d.request.as_ref().unwrap_or_else(|| panic!("{id}"));
        assert_eq!(format_bytes(&q.payload), payload, "{id}");
        let dec = d.decode.as_ref().unwrap_or_else(|| panic!("{id}"));
        assert_eq!(dec.formula.source(), formula, "{id}");
        assert_eq!(dec.unit, unit, "{id}");
        assert!(d.enabled, "{id}");
    }
}

#[test]
fn verified_capture_decodes_through_the_registry() {
    let r = common::seed_registry();
    let t = r.get("trans_temp").unwrap_or_else(|| panic!("trans_temp"));
    // 7E9 05 62 16 74 04 13 (VERIFICATION_LOG.md 2026-08-09).
    let c = t
        .decode_response(&[0x62, 0x16, 0x74, 0x04, 0x13], &|_| None)
        .unwrap_or_else(|e| panic!("{e}"));
    let f = c * 9.0 / 5.0 + 32.0;
    assert!((f - 130.375).abs() < 1e-9, "{f}");
    // The PCM's 7F 22 31 is not a positive response.
    assert!(t.decode_response(&[0x7F, 0x22, 0x31], &|_| None).is_err());

    let rpm = r.get("rpm").unwrap_or_else(|| panic!("rpm"));
    let v = rpm.decode_response(&[0x41, 0x0C, 0x0A, 0xC4], &|_| None);
    assert_eq!(v, Ok(689.0));
}

#[test]
fn computed_and_aux_signals() {
    let r = common::seed_registry();
    for (id, inputs, compute) in [
        ("eot_ect_delta", ["eot", "ect"], "eot - ect"),
        ("boost", ["map", "baro"], "map - baro"),
    ] {
        let d = r.get(id).unwrap_or_else(|| panic!("{id}"));
        assert_eq!(d.source, Source::Computed);
        assert_eq!(d.inputs, inputs);
        assert_eq!(d.compute.as_ref().map(|f| f.source()), Some(compute));
    }
    let egt = r.get("egt").unwrap_or_else(|| panic!("egt"));
    assert_eq!(egt.source, Source::Aux);
    assert_eq!(egt.provenance, Provenance::AuxSensor);
    assert!(!egt.enabled);
}

#[test]
fn speed_calibration_matches_the_app_config() {
    let r = common::seed_registry();
    let json: serde_json::Value = serde_json::from_str(&common::read_repo_file(
        "apps/infotainment/assets/config/calibration.json",
    ))
    .unwrap_or_else(|e| panic!("{e}"));
    let signals = json["signals"]
        .as_object()
        .unwrap_or_else(|| panic!("signals"));
    for (id, cfg) in signals {
        let d = r
            .get(id)
            .unwrap_or_else(|| panic!("{id} in calibration.json"));
        let c = d
            .calibration
            .as_ref()
            .unwrap_or_else(|| panic!("{id} has no calibration block"));
        assert_eq!(Some(c.scale()), cfg["scale"].as_f64(), "{id}");
        assert_eq!(Some(c.offset()), cfg["offset"].as_f64(), "{id}");
    }
    let calibrated: Vec<_> = r
        .iter()
        .filter(|d| d.calibration.is_some())
        .map(|d| d.id.as_str())
        .collect();
    assert_eq!(calibrated, ["speed"]);
    assert_eq!(
        r.get("speed")
            .and_then(|d| d.calibration.as_ref())
            .map(|c| c.scale()),
        Some(1.0),
        "unmeasured: stays ×1.0 until a GPS comparison"
    );
}

#[test]
fn shipped_warning_rules_parse_and_reference_registry_signals() {
    let cfg = WarningConfig::from_json(&common::read_repo_file(
        "apps/infotainment/assets/config/warning_rules.json",
    ))
    .unwrap_or_else(|e| panic!("{e}"));
    cfg.check_signals(&common::seed_registry())
        .unwrap_or_else(|e| panic!("{e}"));
    assert!(!cfg.rules.is_empty());
    assert_eq!(cfg.comm_watch, ["eot", "ect", "trans_temp"]);
    // Every shipped rule says it is an example.
    for rule in &cfg.rules {
        assert!(
            rule.note.as_deref().is_some_and(|n| n.contains("EXAMPLE")),
            "{} is not labelled EXAMPLE",
            rule.id
        );
    }
}
