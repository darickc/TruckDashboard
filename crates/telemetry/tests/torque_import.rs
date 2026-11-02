//! Every row of the owner's Torque export through `formula::from_torque`.

mod common;

use f250_telemetry::formula::from_torque;

/// Rows the importer must translate. Today that is every row of the export;
/// a new row that does not translate fails here with its reason.
const EXPECTED_ROWS: usize = 55;

#[test]
fn every_torque_row_translates_or_is_rejected_with_a_reason() {
    let rows = common::torque_rows();
    assert_eq!(rows.len(), EXPECTED_ROWS, "the export changed; review it");
    let mut rejected = Vec::new();
    let mut with_caveats = Vec::new();
    for row in &rows {
        match from_torque(&row.equation) {
            Ok(t) => {
                // Translation is purely syntactic: byte variables and
                // arithmetic come through unchanged, apart from case and
                // BARO().
                let expected = row
                    .equation
                    .replace("BARO()", "baro")
                    .replace("Signed(", "signed(")
                    .replace("SIGNED(", "signed(");
                assert_eq!(t.formula.source(), expected, "{}", row.name);
                // Every translated formula evaluates on a full payload of
                // zeros (references supplied), so no row hides a parse
                // surprise behind a decode error.
                let payload = vec![0u8; t.formula.bytes_required()];
                let v = t.formula.eval(&payload, &|_| Some(0.0));
                assert!(v.is_ok(), "{}: {v:?}", row.name);
                if !t.caveats.is_empty() {
                    with_caveats.push(row.name.clone());
                }
            }
            Err(e) => rejected.push(format!("{} ({}): {e}", row.name, row.equation)),
        }
    }
    assert!(
        rejected.is_empty(),
        "rejected rows:\n{}",
        rejected.join("\n")
    );
    // Only the BARO() row carries the unit caveat.
    assert_eq!(with_caveats, ["[FORD]Boost (Ford specific)"]);
}

#[test]
fn translated_rows_decode_known_vectors() {
    let rows = common::torque_rows();
    let formula = |name: &str| {
        let row = rows
            .iter()
            .find(|r| r.name == name)
            .unwrap_or_else(|| panic!("no row {name}"));
        from_torque(&row.equation).unwrap_or_else(|e| panic!("{name}: {e}"))
    };
    // VERIFICATION_LOG.md 2026-08-09: 7E9 62 16 74 04 13 → 130.4 °F.
    let trans = formula("[FORD]Transmission Fluid Temp (Method 1)");
    assert_eq!(trans.formula.eval_payload(&[0x04, 0x13]), Ok(130.375));
    // Torque reads BARO() through the `baro` signal.
    let boost = formula("[FORD]Boost (Ford specific)");
    let v = boost
        .formula
        .eval(&[0x01, 0x90], &|id| (id == "baro").then_some(1.0))
        .unwrap_or(f64::NAN);
    assert!((v - (400.0 * 0.03625 - 1.0)).abs() < 1e-12);
    // signed(A) on the alternative trans-temp row.
    let alt = formula("[FORD]Transmission Temp");
    let v = alt.formula.eval_payload(&[0xFF, 0xF0]).unwrap_or(f64::NAN);
    assert!((v - ((-256.0 + 240.0) * 9.0 / 8.0 + 320.0) / 10.0).abs() < 1e-12);
}
