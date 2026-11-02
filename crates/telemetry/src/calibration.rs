//! Per-signal, truck-specific correction: `displayed = raw × scale + offset`.
//!
//! The usual case is vehicle speed on tires that differ from the size
//! programmed into the PCM (docs/diagnostics/CALIBRATION.md). Calibration is
//! applied to every accepted reading **before** the range check, warnings and
//! computed signals. It changes only what this head unit shows and records;
//! nothing is ever written to the truck. Mirrors
//! `apps/infotainment/lib/telemetry/calibration.dart`.

use std::fmt;

/// A validated calibration. The only way to build one with a non-identity
/// factor is [`Calibration::new`], so an out-of-bounds scale can't exist.
#[derive(Debug, Clone, PartialEq)]
pub struct Calibration {
    scale: f64,
    offset: f64,
    note: Option<String>,
}

/// Why a calibration was refused.
#[derive(Debug, Clone, PartialEq, thiserror::Error)]
pub enum CalibrationError {
    /// A factor outside the bounds is almost certainly a typo (10.3 for
    /// 1.03), not a tire size.
    #[error(
        "scale {0} is outside {min}–{max}",
        min = Calibration::MIN_SCALE,
        max = Calibration::MAX_SCALE
    )]
    ScaleOutOfBounds(f64),
    #[error("offset {0} is not finite")]
    OffsetNotFinite(f64),
}

impl Calibration {
    pub const MIN_SCALE: f64 = 0.5;
    pub const MAX_SCALE: f64 = 2.0;

    pub const IDENTITY: Calibration = Calibration {
        scale: 1.0,
        offset: 0.0,
        note: None,
    };

    /// `offset` is in the signal's canonical unit. `note` says why the
    /// calibration exists and how it was measured.
    pub fn new(scale: f64, offset: f64, note: Option<String>) -> Result<Self, CalibrationError> {
        if !scale.is_finite() || !(Self::MIN_SCALE..=Self::MAX_SCALE).contains(&scale) {
            return Err(CalibrationError::ScaleOutOfBounds(scale));
        }
        if !offset.is_finite() {
            return Err(CalibrationError::OffsetNotFinite(offset));
        }
        Ok(Self {
            scale,
            offset,
            note,
        })
    }

    pub fn scale(&self) -> f64 {
        self.scale
    }

    pub fn offset(&self) -> f64 {
        self.offset
    }

    pub fn note(&self) -> Option<&str> {
        self.note.as_deref()
    }

    pub fn is_identity(&self) -> bool {
        self.scale == 1.0 && self.offset == 0.0
    }

    /// `raw × scale + offset`.
    pub fn apply(&self, raw: f64) -> f64 {
        raw * self.scale + self.offset
    }
}

impl Default for Calibration {
    fn default() -> Self {
        Self::IDENTITY
    }
}

impl fmt::Display for Calibration {
    /// `×1.0526`, plus ` +0.5` / ` -0.5` when there is an offset (the event
    /// log format of the Flutter app).
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "×{:.4}", self.scale)?;
        if self.offset != 0.0 {
            let sign = if self.offset >= 0.0 { "+" } else { "" };
            write!(f, " {sign}{}", self.offset)?;
        }
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn identity_changes_nothing() {
        let c = Calibration::IDENTITY;
        assert!(c.is_identity());
        assert_eq!(c.apply(57.0), 57.0);
        assert_eq!(Calibration::default(), c);
    }

    #[test]
    fn offset_is_applied_after_scale() {
        let c = Calibration::new(2.0, -1.0, None).expect("valid");
        assert_eq!(c.apply(10.0), 19.0);
    }

    #[test]
    fn worked_example_from_calibration_md() {
        // GPS 60 mph, truck reports 57 mph → scale 1.0526.
        let c = Calibration::new(1.0526, 0.0, Some("GPS 60 vs 57 mph".into())).expect("valid");
        assert!((c.apply(57.0) - 59.9982).abs() < 1e-9);
        assert_eq!(c.note(), Some("GPS 60 vs 57 mph"));
        assert!(!c.is_identity());
    }

    #[test]
    fn bounds_are_inclusive() {
        assert!(Calibration::new(0.5, 0.0, None).is_ok());
        assert!(Calibration::new(2.0, 0.0, None).is_ok());
    }

    #[test]
    fn rejects_scales_outside_bounds_and_non_finite_values() {
        for bad in [0.0, 0.49, 2.01, 10.5, -1.0, f64::NAN, f64::INFINITY] {
            assert!(
                matches!(
                    Calibration::new(bad, 0.0, None),
                    Err(CalibrationError::ScaleOutOfBounds(_))
                ),
                "{bad}"
            );
        }
        assert!(matches!(
            Calibration::new(1.0, f64::NAN, None),
            Err(CalibrationError::OffsetNotFinite(_))
        ));
        let msg = Calibration::new(10.5, 0.0, None)
            .err()
            .map(|e| e.to_string())
            .unwrap_or_default();
        assert!(msg.contains("0.5"), "{msg}");
    }

    #[test]
    fn display_matches_the_event_log_format() {
        let c = Calibration::new(1.1, 0.0, None).expect("valid");
        assert_eq!(c.to_string(), "×1.1000");
        let c = Calibration::new(1.0, 0.5, None).expect("valid");
        assert_eq!(c.to_string(), "×1.0000 +0.5");
        let c = Calibration::new(1.0, -2.0, None).expect("valid");
        assert_eq!(c.to_string(), "×1.0000 -2");
    }
}
