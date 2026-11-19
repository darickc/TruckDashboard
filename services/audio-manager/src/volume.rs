//! The master volume (ADR-0043): a level in steps, a gain in the speakers'
//! filter-chain on every output, never above 0 dB. The top step is 0 dB,
//! each step below it `step_db` quieter, step 0 silent. Mute is its own
//! state, so the level is kept.
//!
//! Every number in [`VolumeLimits::default`] is an example (CLAUDE.md rule
//! 10): set with `AUDIO_VOLUME_*`.

/// What the level may be. Examples, not recommendations.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct VolumeLimits {
    /// The top step (0 dB).
    pub steps: u32,
    /// dB a step.
    pub step_db: f32,
    /// The driver can't go above this (speakers that can't take the
    /// amplifiers' full output).
    pub max: u32,
    /// audio-manager starts no louder than this, whatever it saved. Off
    /// (equal to `max`) unless configured: the saved level comes back as it
    /// was (owner, 2026-11-18).
    pub start_max: u32,
}

impl Default for VolumeLimits {
    fn default() -> VolumeLimits {
        VolumeLimits {
            steps: 30,
            step_db: 2.0,
            max: 30,
            start_max: 30,
        }
    }
}

impl VolumeLimits {
    pub fn check(&self) -> Result<(), String> {
        if !(1..=100).contains(&self.steps) {
            return Err(format!("volume steps must be 1..=100, not {}", self.steps));
        }
        if !(self.step_db > 0.0 && self.step_db <= 6.0) {
            return Err(format!(
                "volume step must be >0 and <=6 dB, not {}",
                self.step_db
            ));
        }
        if !(1..=self.steps).contains(&self.max) {
            return Err(format!(
                "the volume's maximum must be 1..={}, not {}",
                self.steps, self.max
            ));
        }
        if !(1..=self.max).contains(&self.start_max) {
            return Err(format!(
                "the volume's start maximum must be 1..={} (the maximum), not {}",
                self.max, self.start_max
            ));
        }
        Ok(())
    }
}

/// The driver's volume.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Volume {
    /// 0 ..= `max`.
    pub level: u32,
    pub muted: bool,
}

/// What the driver asked for.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Change {
    Level(u32),
    /// Up (positive) or down; up unmutes.
    Steps(i32),
    Mute,
    Unmute,
    ToggleMute,
}

fn db(x: f32) -> f32 {
    10f32.powf(x / 20.0)
}

/// The linear gain for `v`: 1 at the top step, 0 at step 0 or muted.
pub fn gain(l: &VolumeLimits, v: &Volume) -> f32 {
    if v.muted || v.level == 0 {
        return 0.0;
    }
    let below = l.steps.saturating_sub(v.level.min(l.steps));
    db(-(below as f32) * l.step_db)
}

/// The level in dB for the log and the screen (None: silent).
pub fn level_db(l: &VolumeLimits, level: u32) -> Option<f32> {
    (level > 0).then(|| -(l.steps.saturating_sub(level.min(l.steps)) as f32) * l.step_db)
}

/// The volume after `c`, and a note when it isn't what was asked (above the
/// cap).
pub fn apply(l: &VolumeLimits, v: Volume, c: Change) -> (Volume, Option<String>) {
    let capped = |n: u32| {
        if n > l.max {
            (
                l.max,
                Some(format!("The maximum is {} (configuration).", l.max)),
            )
        } else {
            (n, None)
        }
    };
    match c {
        Change::Level(n) => {
            let (level, note) = capped(n);
            (
                Volume {
                    level,
                    muted: false,
                },
                note,
            )
        }
        Change::Steps(d) => {
            let want = i64::from(v.level) + i64::from(d);
            let (level, note) = capped(u32::try_from(want.max(0)).unwrap_or(u32::MAX));
            (
                Volume {
                    level,
                    muted: v.muted && d <= 0,
                },
                note,
            )
        }
        Change::Mute => (Volume { muted: true, ..v }, None),
        Change::Unmute => (Volume { muted: false, ..v }, None),
        Change::ToggleMute => (
            Volume {
                muted: !v.muted,
                ..v
            },
            None,
        ),
    }
}

/// The level with nothing saved (a new install, a damaged file): half the
/// steps, rounded up (15 of 30).
pub fn first_level(l: &VolumeLimits) -> u32 {
    l.steps.div_ceil(2)
}

/// The volume at start: the saved level ([`first_level`] when there is
/// none), no louder than the start maximum or the cap, unmuted.
pub fn at_start(l: &VolumeLimits, saved: Option<u32>) -> Volume {
    Volume {
        level: saved
            .unwrap_or_else(|| first_level(l))
            .min(l.start_max)
            .min(l.max),
        muted: false,
    }
}

/// `volume.json`: `{"level": n}`.
pub fn parse_saved(text: &str) -> Result<u32, String> {
    let v: serde_json::Value = serde_json::from_str(text).map_err(|e| format!("not JSON: {e}"))?;
    let n = v
        .get("level")
        .ok_or("no level")?
        .as_u64()
        .ok_or("level isn't a whole number >= 0")?;
    u32::try_from(n).map_err(|_| "level is out of range".to_string())
}

pub fn saved_json(level: u32) -> String {
    serde_json::json!({ "level": level }).to_string()
}

#[cfg(test)]
#[allow(clippy::unwrap_used)]
mod tests {
    use super::*;

    fn close(a: f32, b: f32) -> bool {
        (a - b).abs() < 1e-5
    }

    #[test]
    fn the_examples_are_consistent() {
        VolumeLimits::default().check().unwrap();
    }

    #[test]
    fn bad_limits_are_refused() {
        let ok = VolumeLimits::default();
        for bad in [
            VolumeLimits { steps: 0, ..ok },
            VolumeLimits { steps: 101, ..ok },
            VolumeLimits { step_db: 0.0, ..ok },
            VolumeLimits { step_db: 7.0, ..ok },
            VolumeLimits { max: 0, ..ok },
            VolumeLimits { max: 31, ..ok },
            VolumeLimits {
                max: 20,
                start_max: 21,
                ..ok
            },
            VolumeLimits { start_max: 0, ..ok },
        ] {
            assert!(bad.check().is_err(), "{bad:?}");
        }
    }

    #[test]
    fn gain_is_zero_db_at_the_top_and_never_more() {
        let l = VolumeLimits::default();
        let v = |level| Volume {
            level,
            muted: false,
        };
        assert_eq!(gain(&l, &v(30)), 1.0);
        assert!(close(gain(&l, &v(29)), db(-2.0)));
        assert!(close(gain(&l, &v(1)), db(-58.0)));
        assert_eq!(gain(&l, &v(0)), 0.0);
        // A level past the top (a bad caller) is still 0 dB, never a boost.
        assert_eq!(gain(&l, &v(99)), 1.0);
        assert_eq!(
            gain(
                &l,
                &Volume {
                    level: 30,
                    muted: true
                }
            ),
            0.0
        );
        assert_eq!(level_db(&l, 0), None);
        assert_eq!(level_db(&l, 25), Some(-10.0));
    }

    #[test]
    fn changes() {
        let l = VolumeLimits {
            max: 24,
            ..VolumeLimits::default()
        };
        let v = Volume {
            level: 10,
            muted: false,
        };
        assert_eq!(apply(&l, v, Change::Steps(3)).0.level, 13);
        assert_eq!(apply(&l, v, Change::Steps(-30)).0.level, 0, "not below 0");
        let (up, note) = apply(&l, v, Change::Steps(50));
        assert_eq!(up.level, 24, "not above the cap");
        assert_eq!(note.as_deref(), Some("The maximum is 24 (configuration)."));
        let (set, note) = apply(&l, v, Change::Level(30));
        assert_eq!((set.level, note.is_some()), (24, true));
        assert_eq!(
            apply(&l, v, Change::Level(5)),
            (
                Volume {
                    level: 5,
                    muted: false
                },
                None
            )
        );

        let muted = apply(&l, v, Change::Mute).0;
        assert_eq!(
            muted,
            Volume {
                level: 10,
                muted: true
            },
            "the level is kept"
        );
        assert!(!apply(&l, muted, Change::Steps(1)).0.muted, "up unmutes");
        let down = apply(&l, muted, Change::Steps(-1)).0;
        assert_eq!(
            down,
            Volume {
                level: 9,
                muted: true
            },
            "down stays muted"
        );
        assert!(
            !apply(&l, muted, Change::Level(10)).0.muted,
            "a level unmutes"
        );
        assert!(!apply(&l, muted, Change::Unmute).0.muted);
        assert!(!apply(&l, muted, Change::ToggleMute).0.muted);
        assert!(apply(&l, v, Change::ToggleMute).0.muted);
    }

    #[test]
    fn starts_at_the_saved_level() {
        let l = VolumeLimits::default();
        assert_eq!(
            at_start(&l, Some(28)),
            Volume {
                level: 28,
                muted: false
            },
            "no start cap unless configured"
        );
        assert_eq!(at_start(&l, Some(30)).level, 30);
        assert_eq!(at_start(&l, Some(6)).level, 6);
        assert_eq!(at_start(&l, Some(0)).level, 0);
        assert_eq!(at_start(&l, None).level, 15, "nothing saved: half way");
        assert_eq!(
            first_level(&VolumeLimits {
                steps: 1,
                max: 1,
                start_max: 1,
                ..l
            }),
            1
        );
    }

    #[test]
    fn starts_no_louder_than_a_configured_start_cap_or_the_cap() {
        let l = VolumeLimits {
            max: 24,
            start_max: 15,
            ..VolumeLimits::default()
        };
        l.check().unwrap();
        assert_eq!(at_start(&l, Some(28)).level, 15);
        assert_eq!(at_start(&l, Some(6)).level, 6);
        assert_eq!(at_start(&l, None).level, 15);
        let capped = VolumeLimits {
            max: 10,
            start_max: 10,
            ..VolumeLimits::default()
        };
        assert_eq!(
            at_start(&capped, Some(28)).level,
            10,
            "a saved level above the cap"
        );
        assert_eq!(at_start(&capped, None).level, 10);
    }

    #[test]
    fn the_saved_file() {
        assert_eq!(parse_saved(&saved_json(12)).unwrap(), 12);
        assert!(parse_saved("not json").is_err());
        assert!(parse_saved("{}").is_err());
        assert!(parse_saved("{\"level\": -1}").is_err());
        assert!(parse_saved("{\"level\": \"x\"}").is_err());
    }
}
