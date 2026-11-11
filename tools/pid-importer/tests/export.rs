//! The owner's real Torque export against the real registry (PROJECT_PLAN
//! 3.4: "tests use exportedPIDs.csv"). When the export or the registry
//! changes, these fail and the report needs a look.

use std::path::PathBuf;
use std::process::Command;

use f250_telemetry::{Provenance, Registry};
use pid_importer::import::{self, Status};
use pid_importer::torque;

fn root() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../..")
}

fn load() -> (Vec<torque::Row>, Registry) {
    let text =
        std::fs::read_to_string(root().join("shared/signals/imports/torque/exportedPIDs.csv"))
            .expect("the export");
    let export = torque::read(&text).expect("readable");
    assert!(export.bad.is_empty(), "{:?}", export.bad);
    let registry = Registry::load_dir(root().join("shared/signals")).expect("the registry");
    (export.rows, registry)
}

#[test]
fn every_row_has_a_fate_and_nothing_is_invented() {
    let (rows, registry) = load();
    assert_eq!(rows.len(), 55, "the export changed; review the report");
    let reports = import::import(&rows, &registry);
    let mut new = 0;
    for r in &reports {
        match &r.status {
            Status::InRegistry { id, .. } => assert!(registry.contains(id)),
            Status::New(c) => {
                new += 1;
                assert!(!registry.contains(&c.id), "{} clashes", c.id);
            }
            Status::Rejected(why) => {
                // Only the documented reasons: an unknown header or a unit
                // the registry can't express. Every equation in this export
                // translates (crates/telemetry/tests/torque_import.rs).
                assert!(
                    why.contains("isn't established") || why.contains("no quantity"),
                    "{}: {why}",
                    r.row.name
                );
            }
        }
    }
    // Header TCM's CAN id isn't known (FORD_6_0_PIDS.md), so no TCM row is
    // given one.
    for r in reports.iter().filter(|r| r.row.header == "TCM") {
        assert!(matches!(r.status, Status::Rejected(_)), "{}", r.row.name);
    }
    // The tyre-pressure rows' header 726 is a literal CAN id.
    let tyre = reports
        .iter()
        .find(|r| r.row.name == "[FORD]Left front tyre pressure")
        .expect("row");
    let Status::New(c) = &tyre.status else {
        panic!("{:?}", tyre.status)
    };
    assert!(c.yaml.contains("tx_id: \"0x726\""));
    assert!(new > 0);
}

#[test]
fn the_candidates_load_with_the_registry_unverified_and_disabled() {
    let (rows, registry) = load();
    let reports = import::import(&rows, &registry);
    let file = import::yaml_file(&reports, "exportedPIDs.csv");
    let candidates = Registry::from_yaml_str("candidates.yaml", &file)
        .unwrap_or_else(|e| panic!("{e}\n{file}"))
        .into_defs();
    assert!(!candidates.is_empty());
    for d in &candidates {
        assert_eq!(d.provenance, Provenance::ImportedUnverified, "{}", d.id);
        assert!(!d.enabled && !d.allow_unverified, "{}", d.id);
        // The formula is the row's equation, translated syntactically only.
        let row = rows
            .iter()
            .find(|r| {
                d.notes
                    .as_deref()
                    .is_some_and(|n| n.contains(&format!("{:?}", r.name)))
            })
            .unwrap_or_else(|| panic!("{}: no row named in its notes", d.id));
        let want = row
            .equation
            .replace("BARO()", "baro")
            .replace("Signed(", "signed(");
        assert_eq!(
            d.decode.as_ref().map(|x| x.formula.source()),
            Some(want.as_str()),
            "{}",
            d.id
        );
    }
    let mut all = registry.into_defs();
    all.extend(candidates);
    Registry::from_defs(all).unwrap_or_else(|e| panic!("{e}"));
}

#[test]
fn the_registry_has_not_drifted_from_the_export() {
    let (rows, registry) = load();
    let (ok, drift) = import::check(&rows, &registry);
    assert!(drift.is_empty(), "{drift:#?}");
    assert!(ok.contains(&"eot".to_string()), "{ok:?}");
}

#[test]
fn the_command_line_reports_and_checks() {
    let run = |args: &[&str]| {
        let o = Command::new(env!("CARGO_BIN_EXE_pid-importer"))
            .args(args)
            .current_dir(root())
            .output()
            .expect("runs");
        (
            o.status.success(),
            String::from_utf8_lossy(&o.stdout).into_owned(),
        )
    };
    let (ok, out) = run(&["check"]);
    assert!(ok, "{out}");
    let dir = std::env::temp_dir().join(format!("pid-importer-{}", std::process::id()));
    std::fs::create_dir_all(&dir).expect("dir");
    let out_file = dir.join("candidates.yaml");
    let (ok, out) = run(&["import", "--out", out_file.to_str().expect("utf-8")]);
    assert!(ok, "{out}");
    assert!(out.contains("55 rows:"), "{out}");
    assert!(out.contains("validated with the registry"), "{out}");
    assert!(
        std::fs::read_to_string(&out_file)
            .expect("written")
            .contains("IMPORTED_UNVERIFIED")
    );
    let _ = std::fs::remove_dir_all(&dir);
}
