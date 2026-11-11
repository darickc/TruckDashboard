//! The driver's display settings as power-manager keeps them
//! (`/var/lib/f250-power/display`): `key=value` lines.
//!
//! ```text
//! choice=auto
//! day_pct=100
//! night_pct=40
//! ```
//!
//! Reading is lenient: a missing or bad line keeps that setting's default
//! and is reported, so a damaged file never stops the display from working.

use crate::brightness::Levels;
use crate::decide::Choice;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Prefs {
    pub choice: Choice,
    pub levels: Levels,
}

impl Default for Prefs {
    fn default() -> Self {
        Self {
            choice: Choice::Auto,
            levels: Levels::default(),
        }
    }
}

impl Prefs {
    /// The settings in `text`, and a note for each line that was ignored.
    pub fn parse(text: &str) -> (Prefs, Vec<String>) {
        let mut p = Prefs::default();
        let mut notes = Vec::new();
        for (i, line) in text.lines().enumerate() {
            let line = line.trim();
            if line.is_empty() || line.starts_with('#') {
                continue;
            }
            let Some((key, value)) = line.split_once('=') else {
                notes.push(format!("line {}: not key=value: {line:?}", i + 1));
                continue;
            };
            let (key, value) = (key.trim(), value.trim());
            let ok = match key {
                "choice" => Choice::parse(value).map(|c| p.choice = c).is_some(),
                "day_pct" => pct(value).map(|v| p.levels.day_pct = v).is_some(),
                "night_pct" => pct(value).map(|v| p.levels.night_pct = v).is_some(),
                _ => {
                    notes.push(format!("line {}: unknown setting {key:?}", i + 1));
                    continue;
                }
            };
            if !ok {
                notes.push(format!("line {}: bad value for {key}: {value:?}", i + 1));
            }
        }
        (p, notes)
    }

    pub fn format(&self) -> String {
        format!(
            "# power-manager's display settings (ADR-0028); written by power-manager\n\
             choice={}\nday_pct={}\nnight_pct={}\n",
            self.choice.name(),
            self.levels.day_pct,
            self.levels.night_pct
        )
    }
}

fn pct(s: &str) -> Option<u8> {
    s.parse::<u8>().ok().filter(|v| *v <= 100)
}

#[cfg(test)]
#[allow(clippy::unwrap_used, clippy::expect_used)]
mod tests {
    use super::*;

    #[test]
    fn round_trips() {
        let p = Prefs {
            choice: Choice::Night,
            levels: Levels {
                day_pct: 80,
                night_pct: 15,
            },
        };
        let (back, notes) = Prefs::parse(&p.format());
        assert_eq!(back, p);
        assert!(notes.is_empty(), "{notes:?}");
    }

    #[test]
    fn empty_is_the_defaults() {
        let (p, notes) = Prefs::parse("");
        assert_eq!(p, Prefs::default());
        assert!(notes.is_empty());
        assert_eq!(p.choice, Choice::Auto);
    }

    #[test]
    fn bad_lines_keep_defaults_and_are_reported() {
        let (p, notes) = Prefs::parse(
            "choice=dusk\nday_pct=150\nnight_pct=abc\nbrightness=3\njunk\nnight_pct = 25\n",
        );
        assert_eq!(p.choice, Choice::Auto);
        assert_eq!(p.levels.day_pct, 100);
        assert_eq!(p.levels.night_pct, 25, "a later good line wins");
        assert_eq!(notes.len(), 5, "{notes:?}");
        assert!(notes[0].contains("choice"));
        assert!(notes[3].contains("unknown"));
        assert!(notes[4].contains("not key=value"));
    }
}
