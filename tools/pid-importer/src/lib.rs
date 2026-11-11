//! `pid-importer`: the owner's Torque Pro PID export → signal registry
//! candidates (Phase 3.4, [ADR-0006](../../../docs/architecture/adr/0006-signal-registry-formula.md)).
//!
//! - [`torque`]: reads the export (untrusted text).
//! - [`import`]: what becomes of each row: already in the registry (and
//!   whether its formula matches), a new `IMPORTED_UNVERIFIED`, disabled
//!   candidate, or rejected with the reason; and [`import::check`], which
//!   finds registry rows that have drifted from the export.
//!
//! Nothing is invented to make a row fit (CLAUDE.md rule 1): unknown
//! headers, units the registry can't express and equations the grammar can't
//! take are rejected and said so. Agreement with Torque proves the
//! transport, not the scaling: every imported row stays unverified until a
//! VERIFICATION_LOG.md entry says otherwise.
//!
//! Status: `[SIM]`. Tested on the real export (`exportedPIDs.csv`) against
//! the real registry; nothing here touches a vehicle.

pub mod import;
pub mod torque;
