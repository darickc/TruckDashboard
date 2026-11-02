//! Threshold warnings with hysteresis, minimum durations and gates.
//!
//! A port of `apps/infotainment/lib/telemetry/warnings.dart`. Thresholds are
//! **data**: every number comes from a rules file in the format of
//! `apps/infotainment/assets/config/warning_rules.json`, whose values are
//! labelled EXAMPLE and must be verified for this truck. Nothing here
//! hard-codes a limit.
//!
//! Rules never fire on a signal that is not valid: the engine only sees
//! values through a lookup that returns `Some` while a signal is `VALID`.
//! Losing data is reported separately, as a communication alert, so a stale
//! reading can never raise or hold a threshold alert.

use std::collections::HashMap;
use std::fmt;
use std::time::Duration;

use serde::Deserialize;

use crate::registry::Registry;

#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Hash)]
pub enum AlertLevel {
    None,
    Advisory,
    Critical,
}

impl fmt::Display for AlertLevel {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(match self {
            AlertLevel::None => "none",
            AlertLevel::Advisory => "advisory",
            AlertLevel::Critical => "critical",
        })
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum AlertKind {
    /// A valid signal is beyond a configured threshold.
    Threshold,
    /// A watched signal stopped updating while the link is up.
    SignalNotUpdating,
    /// The whole vehicle-data link is down.
    LinkLost,
}

/// One active alert. The UI builds its text (it knows the unit preference).
#[derive(Debug, Clone, PartialEq)]
pub struct Alert {
    pub id: String,
    pub kind: AlertKind,
    pub level: AlertLevel,
    pub since: Duration,
    pub signal_id: Option<String>,
    pub rule_id: Option<String>,
    /// Threshold alerts: the trigger of the active level (canonical units)
    /// and the rule's direction, so a remote UI can word the alert without
    /// the rule.
    pub threshold: Option<f64>,
    pub direction: Option<Direction>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum Direction {
    Above,
    Below,
}

impl Direction {
    fn beyond(self, value: f64, limit: f64) -> bool {
        match self {
            Direction::Above => value > limit,
            Direction::Below => value < limit,
        }
    }
}

/// One level of a rule, in canonical units.
#[derive(Debug, Clone, Copy, PartialEq, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Threshold {
    pub trigger: f64,
    /// Hysteresis: once raised, the level holds until the value passes back
    /// beyond `clear`.
    pub clear: f64,
}

/// "Only evaluate while `signal` is valid and above/below `value`", e.g. the
/// EOT–ECT delta only means something on a warm engine.
#[derive(Debug, Clone, PartialEq, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Gate {
    pub signal: String,
    pub direction: Direction,
    pub value: f64,
}

#[derive(Debug, Clone, PartialEq, Deserialize)]
#[serde(deny_unknown_fields)]
struct RawRule {
    id: String,
    signal: String,
    direction: Direction,
    advisory: Option<Threshold>,
    critical: Option<Threshold>,
    #[serde(default)]
    min_duration_ms: u64,
    when: Option<Gate>,
    note: Option<String>,
}

#[derive(Debug, Clone, PartialEq)]
pub struct WarningRule {
    pub id: String,
    pub signal_id: String,
    pub direction: Direction,
    pub advisory: Option<Threshold>,
    pub critical: Option<Threshold>,
    /// The condition must hold this long before the level is raised.
    pub min_duration: Duration,
    pub gate: Option<Gate>,
    pub note: Option<String>,
}

#[derive(Debug, Clone, PartialEq, thiserror::Error)]
pub enum RuleError {
    #[error("warning rules: {0}")]
    Json(String),
    #[error("{0}: needs advisory and/or critical")]
    NoLevels(String),
    #[error("{0}: clear must be on the safe side of trigger")]
    ClearOnWrongSide(String),
    #[error("{0}: thresholds must be finite")]
    NotFinite(String),
    #[error("{0}: duplicate rule id")]
    DuplicateId(String),
    #[error("{place}: unknown signal {signal:?}")]
    UnknownSignal { place: String, signal: String },
}

impl WarningRule {
    /// Builds and validates a rule.
    #[allow(clippy::too_many_arguments)]
    pub fn new(
        id: impl Into<String>,
        signal_id: impl Into<String>,
        direction: Direction,
        advisory: Option<Threshold>,
        critical: Option<Threshold>,
        min_duration: Duration,
        gate: Option<Gate>,
        note: Option<String>,
    ) -> Result<Self, RuleError> {
        let rule = Self {
            id: id.into(),
            signal_id: signal_id.into(),
            direction,
            advisory,
            critical,
            min_duration,
            gate,
            note,
        };
        rule.validate()?;
        Ok(rule)
    }

    fn validate(&self) -> Result<(), RuleError> {
        if self.advisory.is_none() && self.critical.is_none() {
            return Err(RuleError::NoLevels(self.id.clone()));
        }
        for t in [self.advisory, self.critical].into_iter().flatten() {
            if !t.trigger.is_finite() || !t.clear.is_finite() {
                return Err(RuleError::NotFinite(self.id.clone()));
            }
            let ok = match self.direction {
                Direction::Above => t.clear <= t.trigger,
                Direction::Below => t.clear >= t.trigger,
            };
            if !ok {
                return Err(RuleError::ClearOnWrongSide(self.id.clone()));
            }
        }
        if self.gate.as_ref().is_some_and(|g| !g.value.is_finite()) {
            return Err(RuleError::NotFinite(self.id.clone()));
        }
        Ok(())
    }

    /// The level `value` calls for, given the level currently held.
    pub fn target(&self, value: f64, current: AlertLevel) -> AlertLevel {
        let d = self.direction;
        if let Some(c) = self.critical
            && (d.beyond(value, c.trigger)
                || (current == AlertLevel::Critical && d.beyond(value, c.clear)))
        {
            return AlertLevel::Critical;
        }
        if let Some(a) = self.advisory
            && (d.beyond(value, a.trigger)
                || (current != AlertLevel::None && d.beyond(value, a.clear)))
        {
            return AlertLevel::Advisory;
        }
        AlertLevel::None
    }
}

/// A parsed rules file: the threshold rules plus the signals whose silence
/// raises a "not updating" alert.
#[derive(Debug, Clone, PartialEq)]
pub struct WarningConfig {
    pub rules: Vec<WarningRule>,
    pub comm_watch: Vec<String>,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
struct RawConfig {
    #[serde(rename = "_comment")]
    _comment: Option<String>,
    rules: Vec<RawRule>,
    #[serde(default)]
    comm_watch: Vec<String>,
}

impl WarningConfig {
    /// Parses the `warning_rules.json` format. Unknown keys are errors (a
    /// misspelt `min_duration_ms` must not silently become 0).
    pub fn from_json(json: &str) -> Result<Self, RuleError> {
        let raw: RawConfig =
            serde_json::from_str(json).map_err(|e| RuleError::Json(e.to_string()))?;
        let mut rules = Vec::with_capacity(raw.rules.len());
        for r in raw.rules {
            if rules.iter().any(|x: &WarningRule| x.id == r.id) {
                return Err(RuleError::DuplicateId(r.id));
            }
            rules.push(WarningRule::new(
                r.id,
                r.signal,
                r.direction,
                r.advisory,
                r.critical,
                Duration::from_millis(r.min_duration_ms),
                r.when,
                r.note,
            )?);
        }
        Ok(Self {
            rules,
            comm_watch: raw.comm_watch,
        })
    }

    /// Checks every signal id against the registry.
    pub fn check_signals(&self, registry: &Registry) -> Result<(), RuleError> {
        let known = |signal: &str, place: String| {
            if registry.contains(signal) {
                Ok(())
            } else {
                Err(RuleError::UnknownSignal {
                    place,
                    signal: signal.to_owned(),
                })
            }
        };
        for rule in &self.rules {
            known(&rule.signal_id, format!("warning rule {}", rule.id))?;
            if let Some(g) = &rule.gate {
                known(&g.signal, format!("warning rule {} gate", rule.id))?;
            }
        }
        for id in &self.comm_watch {
            known(id, "comm_watch".into())?;
        }
        Ok(())
    }
}

/// A rule whose level changed during an evaluation (for the event log).
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct LevelChange {
    pub rule_id: String,
    pub from: AlertLevel,
    pub to: AlertLevel,
}

/// Evaluates rules with hysteresis and minimum durations.
#[derive(Debug, Clone, Default)]
pub struct WarningEngine {
    rules: Vec<WarningRule>,
    level: HashMap<String, AlertLevel>,
    since: HashMap<String, Duration>,
    pending: HashMap<String, (AlertLevel, Duration)>,
}

impl WarningEngine {
    pub fn new(rules: Vec<WarningRule>) -> Self {
        Self {
            rules,
            ..Self::default()
        }
    }

    pub fn rules(&self) -> &[WarningRule] {
        &self.rules
    }

    pub fn reset(&mut self) {
        self.level.clear();
        self.since.clear();
        self.pending.clear();
    }

    pub fn level_of(&self, rule_id: &str) -> AlertLevel {
        self.level.get(rule_id).copied().unwrap_or(AlertLevel::None)
    }

    /// Evaluates every rule at `now`. `valid_value` returns a signal's
    /// canonical value **only while it is valid**. Returns the threshold
    /// alerts now active and the level changes.
    pub fn evaluate(
        &mut self,
        valid_value: &dyn Fn(&str) -> Option<f64>,
        now: Duration,
    ) -> (Vec<Alert>, Vec<LevelChange>) {
        let mut changes = Vec::new();
        let mut active = Vec::new();
        for i in 0..self.rules.len() {
            let Some(rule) = self.rules.get(i) else {
                continue;
            };
            let current = self.level_of(&rule.id);
            let next = self.next_level(i, valid_value, now, current);
            let Some(rule) = self.rules.get(i) else {
                continue;
            };
            if next != current {
                changes.push(LevelChange {
                    rule_id: rule.id.clone(),
                    from: current,
                    to: next,
                });
                self.level.insert(rule.id.clone(), next);
                self.since.insert(rule.id.clone(), now);
            }
            if next != AlertLevel::None {
                active.push(Alert {
                    id: format!("rule:{}", rule.id),
                    kind: AlertKind::Threshold,
                    level: next,
                    since: self.since.get(&rule.id).copied().unwrap_or(now),
                    signal_id: Some(rule.signal_id.clone()),
                    rule_id: Some(rule.id.clone()),
                    threshold: match next {
                        AlertLevel::Critical => rule.critical.map(|t| t.trigger),
                        AlertLevel::Advisory => rule.advisory.map(|t| t.trigger),
                        AlertLevel::None => None,
                    },
                    direction: Some(rule.direction),
                });
            }
        }
        (active, changes)
    }

    fn next_level(
        &mut self,
        i: usize,
        valid_value: &dyn Fn(&str) -> Option<f64>,
        now: Duration,
        current: AlertLevel,
    ) -> AlertLevel {
        let Some(rule) = self.rules.get(i) else {
            return AlertLevel::None;
        };
        let gate_open = rule
            .gate
            .as_ref()
            .is_none_or(|g| valid_value(&g.signal).is_some_and(|v| g.direction.beyond(v, g.value)));
        let value = valid_value(&rule.signal_id).filter(|_| gate_open);
        let Some(value) = value else {
            self.pending.remove(&rule.id);
            return AlertLevel::None;
        };
        let target = rule.target(value, current);
        if target <= current {
            // Lowering is immediate; hysteresis is already applied.
            self.pending.remove(&rule.id);
            return target;
        }
        let min_duration = rule.min_duration;
        let id = rule.id.clone();
        let since = match self.pending.get(&id) {
            Some(&(level, since)) if level == target => since,
            _ => {
                self.pending.insert(id.clone(), (target, now));
                now
            }
        };
        if now.saturating_sub(since) >= min_duration {
            self.pending.remove(&id);
            return target;
        }
        current
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn rule(json: &str) -> Result<WarningRule, RuleError> {
        WarningConfig::from_json(&format!("{{\"rules\": [{json}]}}")).map(|mut c| c.rules.remove(0))
    }

    #[test]
    fn rejects_clear_on_the_wrong_side_of_trigger() {
        assert!(matches!(
            rule(
                r#"{"id": "x", "signal": "ect", "direction": "above", "advisory": {"trigger": 100, "clear": 105}}"#
            ),
            Err(RuleError::ClearOnWrongSide(_))
        ));
        assert!(matches!(
            rule(
                r#"{"id": "x", "signal": "b", "direction": "below", "advisory": {"trigger": 12, "clear": 11}}"#
            ),
            Err(RuleError::ClearOnWrongSide(_))
        ));
    }

    #[test]
    fn rejects_a_rule_with_no_levels() {
        assert!(matches!(
            rule(r#"{"id": "x", "signal": "ect", "direction": "above"}"#),
            Err(RuleError::NoLevels(_))
        ));
    }

    #[test]
    fn rejects_unknown_keys_and_bad_directions() {
        assert!(matches!(
            rule(
                r#"{"id": "x", "signal": "ect", "direction": "above", "advisory": {"trigger": 1, "clear": 0}, "min_duraton_ms": 5}"#
            ),
            Err(RuleError::Json(_))
        ));
        assert!(matches!(
            rule(
                r#"{"id": "x", "signal": "ect", "direction": "sideways", "advisory": {"trigger": 1, "clear": 0}}"#
            ),
            Err(RuleError::Json(_))
        ));
    }

    #[test]
    fn rejects_duplicate_ids() {
        let one = r#"{"id": "x", "signal": "ect", "direction": "above", "advisory": {"trigger": 1, "clear": 0}}"#;
        assert!(matches!(
            WarningConfig::from_json(&format!("{{\"rules\": [{one}, {one}]}}")),
            Err(RuleError::DuplicateId(_))
        ));
    }

    #[test]
    fn target_applies_hysteresis_per_level() {
        let r = rule(
            r#"{"id": "t", "signal": "s", "direction": "above",
                "advisory": {"trigger": 104, "clear": 101},
                "critical": {"trigger": 110, "clear": 107}}"#,
        )
        .expect("valid");
        use AlertLevel::*;
        assert_eq!(r.target(100.0, None), None);
        assert_eq!(r.target(105.0, None), Advisory);
        assert_eq!(r.target(102.0, None), None);
        assert_eq!(r.target(102.0, Advisory), Advisory);
        assert_eq!(r.target(100.0, Advisory), None);
        assert_eq!(r.target(111.0, Advisory), Critical);
        assert_eq!(r.target(108.0, Critical), Critical);
        assert_eq!(r.target(105.0, Critical), Advisory);
    }

    #[test]
    fn below_rules_mirror_above_rules() {
        let r = rule(
            r#"{"id": "b", "signal": "battery", "direction": "below",
                "advisory": {"trigger": 12.4, "clear": 12.8}}"#,
        )
        .expect("valid");
        assert_eq!(r.target(12.3, AlertLevel::None), AlertLevel::Advisory);
        assert_eq!(r.target(12.6, AlertLevel::Advisory), AlertLevel::Advisory);
        assert_eq!(r.target(12.9, AlertLevel::Advisory), AlertLevel::None);
    }
}
