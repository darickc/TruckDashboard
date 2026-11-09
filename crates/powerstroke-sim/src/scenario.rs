//! The `f250.scenario.v1` scenario format: a port of
//! `simulator/powerstroke/lib/src/scenario.dart`.
//!
//! Every check below mirrors a check in the Dart parser, in the same order, so
//! a file that one side rejects the other rejects too. Message wording differs.

use std::error::Error as StdError;
use std::fmt::Write as _;
use std::fs;
use std::path::{Path, PathBuf};

use yaml_serde::{Mapping, Value};

/// Schema identifier every scenario file must declare.
pub const SCENARIO_SCHEMA: &str = "f250.scenario.v1";

/// Boxed error returned by a parent-scenario loader.
pub type LoaderError = Box<dyn StdError + Send + Sync>;

/// Why a scenario could not be loaded. Every variant names the scenario at
/// fault (the file stem), except a directory that could not be listed.
#[derive(Debug, thiserror::Error)]
pub enum ScenarioError {
    /// The file is malformed (the Dart `ScenarioFormatException`).
    #[error("scenario {scenario}: {message}")]
    Format { scenario: String, message: String },

    /// The loader could not produce the text of a parent named by `extends`.
    #[error("scenario {scenario}: cannot load parent \"{parent}\": {source}")]
    Resolve {
        scenario: String,
        parent: String,
        #[source]
        source: LoaderError,
    },

    /// A file or directory could not be read.
    #[error("cannot read {}: {source}", path.display())]
    Io {
        /// Scenario id when the path is a scenario file.
        scenario: Option<String>,
        path: PathBuf,
        #[source]
        source: std::io::Error,
    },
}

impl ScenarioError {
    /// The scenario at fault, if the error concerns one.
    pub fn scenario(&self) -> Option<&str> {
        match self {
            Self::Format { scenario, .. } | Self::Resolve { scenario, .. } => Some(scenario),
            Self::Io { scenario, .. } => scenario.as_deref(),
        }
    }

    fn format(scenario: &str, message: impl Into<String>) -> Self {
        Self::Format {
            scenario: scenario.to_owned(),
            message: message.into(),
        }
    }
}

/// One `(time, value)` point of a piecewise-linear trajectory.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Keyframe {
    pub at_seconds: f64,
    pub value: f64,
}

/// How one signal behaves when the simulated gateway polls it.
///
/// Only the parser builds these, so the keyframes are never empty and their
/// times strictly increase.
#[derive(Debug, Clone, PartialEq)]
pub struct SignalTrack {
    id: String,
    unit: String,
    interval_ms: u64,
    keyframes: Vec<Keyframe>,
    noise: f64,
    min: Option<f64>,
    max: Option<f64>,
}

impl SignalTrack {
    pub fn id(&self) -> &str {
        &self.id
    }

    /// Canonical unit of every keyframe value (e.g. `degC`, `kPa`).
    pub fn unit(&self) -> &str {
        &self.unit
    }

    /// Simulated poll interval (>= 10 ms). Each poll produces one observation.
    pub fn interval_ms(&self) -> u64 {
        self.interval_ms
    }

    /// Non-empty, strictly increasing in time.
    pub fn keyframes(&self) -> &[Keyframe] {
        &self.keyframes
    }

    /// Peak amplitude of the deterministic noise added to each sample.
    pub fn noise(&self) -> f64 {
        self.noise
    }

    /// Lower physical limit, applied after noise (not to fault overrides).
    pub fn min(&self) -> Option<f64> {
        self.min
    }

    /// Upper physical limit, applied after noise (not to fault overrides).
    pub fn max(&self) -> Option<f64> {
        self.max
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum FaultKind {
    /// The module never answers (adapter timeout / NO DATA).
    NoResponse,
    /// The module answers with a negative response (e.g. `7F 22 31`).
    NegativeResponse,
    /// A response arrives but cannot be decoded.
    InvalidResponse,
    /// A response arrives with the value replaced.
    ValueOverride,
    /// The whole diagnostic link is down; every signal is affected.
    LinkDown,
}

impl FaultKind {
    /// The name used in scenario files.
    pub fn as_str(self) -> &'static str {
        match self {
            Self::NoResponse => "no_response",
            Self::NegativeResponse => "negative_response",
            Self::InvalidResponse => "invalid_response",
            Self::ValueOverride => "value_override",
            Self::LinkDown => "link_down",
        }
    }

    fn from_name(name: &str) -> Option<Self> {
        Some(match name {
            "no_response" => Self::NoResponse,
            "negative_response" => Self::NegativeResponse,
            "invalid_response" => Self::InvalidResponse,
            "value_override" => Self::ValueOverride,
            "link_down" => Self::LinkDown,
            _ => return None,
        })
    }
}

/// A scripted fault, active over `[start_seconds, end_seconds)` of scenario
/// time.
#[derive(Debug, Clone, PartialEq)]
pub struct Fault {
    pub kind: FaultKind,
    pub start_seconds: f64,
    pub end_seconds: f64,
    /// Affected signals; empty for [`FaultKind::LinkDown`] (which affects all).
    pub signals: Vec<String>,
    /// Negative response code for [`FaultKind::NegativeResponse`].
    pub nrc: Option<i64>,
    /// Replacement value for [`FaultKind::ValueOverride`].
    pub value: Option<f64>,
}

impl Fault {
    pub fn active_at(&self, seconds: f64) -> bool {
        seconds >= self.start_seconds && seconds < self.end_seconds
    }

    pub fn affects(&self, signal_id: &str) -> bool {
        self.kind == FaultKind::LinkDown || self.signals.iter().any(|s| s == signal_id)
    }
}

/// A simulated diagnostic trouble code. Always presented as simulated.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SimulatedDtc {
    pub code: String,
    pub description: String,
    /// `stored` unless the file says otherwise.
    pub status: String,
}

/// A parsed, validated scenario with `extends` already resolved.
#[derive(Debug, Clone, PartialEq)]
pub struct Scenario {
    id: String,
    name: String,
    description: String,
    duration_seconds: f64,
    looping: bool,
    seed: i64,
    tracks: Vec<SignalTrack>,
    faults: Vec<Fault>,
    dtcs: Vec<SimulatedDtc>,
}

impl Scenario {
    /// File stem, e.g. `eot_ect_freeze`.
    pub fn id(&self) -> &str {
        &self.id
    }

    pub fn name(&self) -> &str {
        &self.name
    }

    /// Empty when the file has none (not inherited).
    pub fn description(&self) -> &str {
        &self.description
    }

    pub fn duration_seconds(&self) -> f64 {
        self.duration_seconds
    }

    /// Whether the scenario clock wraps (default true).
    pub fn looping(&self) -> bool {
        self.looping
    }

    /// Noise seed (default 1).
    pub fn seed(&self) -> i64 {
        self.seed
    }

    /// Tracks in declaration order: the parent's first (a child's override
    /// keeps the parent's position), then the child's new signals.
    pub fn tracks(&self) -> &[SignalTrack] {
        &self.tracks
    }

    /// The track for `signal_id`, if the scenario defines it.
    pub fn track(&self, signal_id: &str) -> Option<&SignalTrack> {
        self.tracks.iter().find(|t| t.id == signal_id)
    }

    /// Signal ids in track order.
    pub fn signal_ids(&self) -> impl Iterator<Item = &str> {
        self.tracks.iter().map(|t| t.id.as_str())
    }

    /// The parent's faults followed by this file's.
    pub fn faults(&self) -> &[Fault] {
        &self.faults
    }

    /// The parent's DTCs followed by this file's.
    pub fn dtcs(&self) -> &[SimulatedDtc] {
        &self.dtcs
    }

    /// Parses a scenario that does not use `extends` (one that does fails
    /// with a "no resolver" error, as in Dart).
    pub fn parse(id: &str, yaml: &str) -> Result<Self, ScenarioError> {
        parse_inner(id, yaml, None, &[])
    }

    /// Parses a scenario, calling `load` with a parent's id to fetch that
    /// scenario's YAML text whenever a file declares `extends: <id>`. The
    /// child inherits the parent's tracks (overridable per signal), duration,
    /// loop and seed, and appends its faults and DTCs to the parent's.
    pub fn parse_with<F, E>(id: &str, yaml: &str, mut load: F) -> Result<Self, ScenarioError>
    where
        F: FnMut(&str) -> Result<String, E>,
        E: Into<LoaderError>,
    {
        let mut resolve = |parent: &str| load(parent).map_err(Into::into);
        parse_inner(id, yaml, Some(&mut resolve), &[])
    }

    /// Loads `<dir>/<id>.yaml`, resolving `extends` from the same directory.
    pub fn load(dir: impl AsRef<Path>, id: &str) -> Result<Self, ScenarioError> {
        let dir = dir.as_ref();
        let text = read_scenario(dir, id)?;
        let mut resolve = |parent: &str| -> Result<String, LoaderError> {
            fs::read_to_string(scenario_path(dir, parent)).map_err(Into::into)
        };
        parse_inner(id, &text, Some(&mut resolve), &[])
    }
}

/// Loads every `*.yaml` scenario in `dir` (id = file stem), resolving
/// `extends` from the same directory. Sorted by id.
pub fn load_dir(dir: impl AsRef<Path>) -> Result<Vec<Scenario>, ScenarioError> {
    let dir = dir.as_ref();
    let io_err = |source| ScenarioError::Io {
        scenario: None,
        path: dir.to_owned(),
        source,
    };
    let mut ids = Vec::new();
    for entry in fs::read_dir(dir).map_err(io_err)? {
        let path = entry.map_err(io_err)?.path();
        if path.extension().is_some_and(|e| e == "yaml")
            && path.is_file()
            && let Some(stem) = path.file_stem().and_then(|s| s.to_str())
        {
            ids.push(stem.to_owned());
        }
    }
    ids.sort();
    ids.iter().map(|id| Scenario::load(dir, id)).collect()
}

fn scenario_path(dir: &Path, id: &str) -> PathBuf {
    dir.join(format!("{id}.yaml"))
}

fn read_scenario(dir: &Path, id: &str) -> Result<String, ScenarioError> {
    let path = scenario_path(dir, id);
    fs::read_to_string(&path).map_err(|source| ScenarioError::Io {
        scenario: Some(id.to_owned()),
        path,
        source,
    })
}

type Resolver<'a> = &'a mut dyn FnMut(&str) -> Result<String, LoaderError>;

fn parse_inner(
    id: &str,
    yaml: &str,
    resolve: Option<Resolver<'_>>,
    visiting: &[String],
) -> Result<Scenario, ScenarioError> {
    let doc: Value = yaml_serde::from_str(yaml)
        .map_err(|e| ScenarioError::format(id, format!("invalid YAML: {e}")))?;
    let Some(map) = untag(&doc).as_mapping() else {
        return Err(ScenarioError::format(id, "top level must be a mapping"));
    };
    let r = Reader::new(id, "", map);

    let schema = r.string("schema")?;
    if schema != SCENARIO_SCHEMA {
        return Err(ScenarioError::format(
            id,
            format!("schema must be \"{SCENARIO_SCHEMA}\", got \"{schema}\""),
        ));
    }

    let mut parent: Option<Scenario> = None;
    if let Some(parent_id) = r.optional_string("extends")? {
        let Some(resolve) = resolve else {
            return Err(ScenarioError::format(
                id,
                format!("extends \"{parent_id}\" but no resolver was given"),
            ));
        };
        if parent_id == id || visiting.iter().any(|v| v == parent_id) {
            return Err(ScenarioError::format(
                id,
                format!("extends cycle via \"{parent_id}\""),
            ));
        }
        let text = resolve(parent_id).map_err(|source| ScenarioError::Resolve {
            scenario: id.to_owned(),
            parent: parent_id.to_owned(),
            source,
        })?;
        let mut chain = visiting.to_vec();
        chain.push(id.to_owned());
        parent = Some(parse_inner(parent_id, &text, Some(resolve), &chain)?);
    }

    let mut tracks: Vec<SignalTrack> = parent
        .as_ref()
        .map(|p| p.tracks.clone())
        .unwrap_or_default();
    if let Some(signals) = r.optional_map("signals")? {
        for (key, node) in signals {
            let sid = display_scalar(key);
            let track = parse_track(id, &sid, node)?;
            match tracks.iter_mut().find(|t| t.id == sid) {
                Some(existing) => *existing = track,
                None => tracks.push(track),
            }
        }
    }
    if tracks.is_empty() {
        return Err(ScenarioError::format(id, "no signals defined"));
    }

    let duration = match r.optional_number("duration_s")? {
        Some(d) => Some(d),
        None => parent.as_ref().map(|p| p.duration_seconds),
    };
    // Same test as Dart (`duration <= 0`), so NaN slips through there too.
    let duration = match duration {
        Some(d) if d <= 0.0 => None,
        other => other,
    }
    .ok_or_else(|| ScenarioError::format(id, "duration_s must be > 0"))?;

    let mut faults = parent
        .as_ref()
        .map(|p| p.faults.clone())
        .unwrap_or_default();
    if let Some(list) = r.optional_list("faults")? {
        for (i, node) in list.iter().enumerate() {
            faults.push(parse_fault(id, i, node, &tracks)?);
        }
    }

    let mut dtcs = parent.as_ref().map(|p| p.dtcs.clone()).unwrap_or_default();
    if let Some(list) = r.optional_list("dtcs")? {
        for (i, node) in list.iter().enumerate() {
            let Some(m) = untag(node).as_mapping() else {
                return Err(ScenarioError::format(
                    id,
                    format!("dtcs[{i}] must be a mapping"),
                ));
            };
            let dr = Reader::new(id, &format!("dtcs[{i}]"), m);
            dtcs.push(SimulatedDtc {
                code: dr.string("code")?.to_owned(),
                description: dr.string("description")?.to_owned(),
                status: dr.optional_string("status")?.unwrap_or("stored").to_owned(),
            });
        }
    }

    let name = r.string("name")?.to_owned();
    let description = r
        .optional_string("description")?
        .unwrap_or_default()
        .to_owned();
    let looping = r
        .optional_bool("loop")?
        .or(parent.as_ref().map(|p| p.looping))
        .unwrap_or(true);
    let seed = match r.optional_number("seed")? {
        Some(s) => {
            dart_to_int(s).ok_or_else(|| ScenarioError::format(id, "seed must be finite"))?
        }
        None => parent.as_ref().map_or(1, |p| p.seed),
    };

    Ok(Scenario {
        id: id.to_owned(),
        name,
        description,
        duration_seconds: duration,
        looping,
        seed,
        tracks,
        faults,
        dtcs,
    })
}

fn parse_track(id: &str, sid: &str, node: &Value) -> Result<SignalTrack, ScenarioError> {
    let Some(map) = untag(node).as_mapping() else {
        return Err(ScenarioError::format(
            id,
            format!("signals.{sid} must be a mapping"),
        ));
    };
    let r = Reader::new(id, &format!("signals.{sid}"), map);
    let interval = dart_to_int(r.number("interval_ms")?).filter(|i| *i >= 10);
    let Some(interval) = interval.and_then(|i| u64::try_from(i).ok()) else {
        return Err(ScenarioError::format(
            id,
            format!("signals.{sid}.interval_ms must be >= 10"),
        ));
    };

    let mut frames: Vec<Keyframe> = Vec::new();
    for (i, kf) in r.list("keyframes")?.iter().enumerate() {
        let pair = match untag(kf).as_sequence().map(Vec::as_slice) {
            Some([at, value]) => as_number(at).zip(as_number(value)),
            _ => None,
        };
        let Some((at, value)) = pair else {
            return Err(ScenarioError::format(
                id,
                format!("signals.{sid}.keyframes[{i}] must be [seconds, value]"),
            ));
        };
        if frames.last().is_some_and(|last| at <= last.at_seconds) {
            return Err(ScenarioError::format(
                id,
                format!("signals.{sid}.keyframes must have increasing times"),
            ));
        }
        frames.push(Keyframe {
            at_seconds: at,
            value,
        });
    }
    if frames.is_empty() {
        return Err(ScenarioError::format(
            id,
            format!("signals.{sid}.keyframes is empty"),
        ));
    }

    let noise = r.optional_number("noise")?.unwrap_or(0.0);
    if noise < 0.0 {
        return Err(ScenarioError::format(
            id,
            format!("signals.{sid}.noise must be >= 0"),
        ));
    }
    let min = r.optional_number("min")?;
    let max = r.optional_number("max")?;
    if let (Some(lo), Some(hi)) = (min, max)
        && lo >= hi
    {
        return Err(ScenarioError::format(
            id,
            format!("signals.{sid}: min must be < max"),
        ));
    }

    Ok(SignalTrack {
        id: sid.to_owned(),
        unit: r.string("unit")?.to_owned(),
        interval_ms: interval,
        keyframes: frames,
        noise,
        min,
        max,
    })
}

fn parse_fault(
    id: &str,
    i: usize,
    node: &Value,
    tracks: &[SignalTrack],
) -> Result<Fault, ScenarioError> {
    let Some(map) = untag(node).as_mapping() else {
        return Err(ScenarioError::format(
            id,
            format!("faults[{i}] must be a mapping"),
        ));
    };
    let r = Reader::new(id, &format!("faults[{i}]"), map);
    let kind_name = r.string("kind")?;
    let Some(kind) = FaultKind::from_name(kind_name) else {
        return Err(ScenarioError::format(
            id,
            format!("faults[{i}].kind \"{kind_name}\" is unknown"),
        ));
    };
    let start = r.number("start_s")?;
    let end = r.number("end_s")?;
    if end <= start {
        return Err(ScenarioError::format(
            id,
            format!("faults[{i}]: end_s must be > start_s"),
        ));
    }
    let signals: Vec<String> = r
        .optional_list("signals")?
        .map(|list| list.iter().map(display_scalar).collect())
        .unwrap_or_default();
    if kind == FaultKind::LinkDown && !signals.is_empty() {
        return Err(ScenarioError::format(
            id,
            format!("faults[{i}]: link_down takes no signals"),
        ));
    }
    if kind != FaultKind::LinkDown && signals.is_empty() {
        return Err(ScenarioError::format(
            id,
            format!("faults[{i}]: signals is required"),
        ));
    }
    for s in &signals {
        if !tracks.iter().any(|t| &t.id == s) {
            return Err(ScenarioError::format(
                id,
                format!("faults[{i}]: unknown signal \"{s}\""),
            ));
        }
    }
    let nrc = match r.optional_number("nrc")? {
        Some(n) => Some(dart_to_int(n).ok_or_else(|| {
            ScenarioError::format(id, format!("faults[{i}]: nrc must be finite"))
        })?),
        None => None,
    };
    if kind == FaultKind::NegativeResponse && nrc.is_none() {
        return Err(ScenarioError::format(
            id,
            format!("faults[{i}]: negative_response needs nrc"),
        ));
    }
    let value = r.optional_number("value")?;
    if kind == FaultKind::ValueOverride && value.is_none() {
        return Err(ScenarioError::format(
            id,
            format!("faults[{i}]: value_override needs value"),
        ));
    }
    Ok(Fault {
        kind,
        start_seconds: start,
        end_seconds: end,
        signals,
        nrc,
        value,
    })
}

/// Dart `double.toInt()`: truncates toward zero. Dart throws for NaN and
/// infinity; we report `None`. Out-of-range values saturate.
fn dart_to_int(v: f64) -> Option<i64> {
    v.is_finite().then(|| v.trunc() as i64)
}

/// Custom YAML tags carry no meaning in this format; look through them.
fn untag(v: &Value) -> &Value {
    match v {
        Value::Tagged(t) => untag(&t.value),
        other => other,
    }
}

/// Dart `v is num ? v.toDouble() : null`.
fn as_number(v: &Value) -> Option<f64> {
    match untag(v) {
        Value::Number(n) => n.as_f64(),
        _ => None,
    }
}

/// Dart `toString()` of a YAML scalar (used for signal ids written as keys or
/// list items) and a readable rendering of anything else for messages.
fn display_scalar(v: &Value) -> String {
    let mut out = String::new();
    render(&mut out, v);
    out
}

fn render(out: &mut String, v: &Value) {
    match v {
        Value::Null => out.push_str("null"),
        Value::Bool(b) => {
            let _ = write!(out, "{b}");
        }
        Value::Number(n) => {
            let _ = write!(out, "{n}");
        }
        Value::String(s) => out.push_str(s),
        Value::Sequence(items) => {
            out.push('[');
            for (i, item) in items.iter().enumerate() {
                if i > 0 {
                    out.push_str(", ");
                }
                render(out, item);
            }
            out.push(']');
        }
        Value::Mapping(m) => {
            out.push('{');
            for (i, (k, val)) in m.iter().enumerate() {
                if i > 0 {
                    out.push_str(", ");
                }
                render(out, k);
                out.push_str(": ");
                render(out, val);
            }
            out.push('}');
        }
        Value::Tagged(t) => render(out, &t.value),
    }
}

/// Typed field access with uniform error messages (the Dart `_Reader`).
/// A missing key and an explicit YAML null are the same thing, as in Dart.
struct Reader<'a> {
    scenario: &'a str,
    at: String,
    map: &'a Mapping,
}

impl<'a> Reader<'a> {
    fn new(scenario: &'a str, at: &str, map: &'a Mapping) -> Self {
        Self {
            scenario,
            at: at.to_owned(),
            map,
        }
    }

    fn get(&self, field: &str) -> Option<&'a Value> {
        self.map.get(field).map(untag).filter(|v| !v.is_null())
    }

    fn fail(&self, field: &str, expected: &str) -> ScenarioError {
        let got = self
            .get(field)
            .map_or_else(|| "null".to_owned(), display_scalar);
        let at = if self.at.is_empty() {
            String::new()
        } else {
            format!("{}: ", self.at)
        };
        ScenarioError::format(
            self.scenario,
            format!("{at}\"{field}\" must be {expected} (got {got})"),
        )
    }

    fn string(&self, field: &str) -> Result<&'a str, ScenarioError> {
        self.optional_string(field)?
            .ok_or_else(|| self.fail(field, "a non-empty string"))
    }

    fn optional_string(&self, field: &str) -> Result<Option<&'a str>, ScenarioError> {
        match self.get(field) {
            None => Ok(None),
            Some(Value::String(s)) if !s.is_empty() => Ok(Some(s)),
            Some(_) => Err(self.fail(field, "a non-empty string")),
        }
    }

    fn number(&self, field: &str) -> Result<f64, ScenarioError> {
        self.optional_number(field)?
            .ok_or_else(|| self.fail(field, "a number"))
    }

    fn optional_number(&self, field: &str) -> Result<Option<f64>, ScenarioError> {
        match self.get(field) {
            None => Ok(None),
            Some(v) => as_number(v)
                .map(Some)
                .ok_or_else(|| self.fail(field, "a number")),
        }
    }

    fn optional_bool(&self, field: &str) -> Result<Option<bool>, ScenarioError> {
        match self.get(field) {
            None => Ok(None),
            Some(Value::Bool(b)) => Ok(Some(*b)),
            Some(_) => Err(self.fail(field, "true or false")),
        }
    }

    fn list(&self, field: &str) -> Result<&'a [Value], ScenarioError> {
        self.optional_list(field)?
            .ok_or_else(|| self.fail(field, "a list"))
    }

    fn optional_list(&self, field: &str) -> Result<Option<&'a [Value]>, ScenarioError> {
        match self.get(field) {
            None => Ok(None),
            Some(Value::Sequence(s)) => Ok(Some(s.as_slice())),
            Some(_) => Err(self.fail(field, "a list")),
        }
    }

    fn optional_map(&self, field: &str) -> Result<Option<&'a Mapping>, ScenarioError> {
        match self.get(field) {
            None => Ok(None),
            Some(Value::Mapping(m)) => Ok(Some(m)),
            Some(_) => Err(self.fail(field, "a mapping")),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn dart_to_int_truncates_toward_zero() {
        assert_eq!(dart_to_int(250.9), Some(250));
        assert_eq!(dart_to_int(-2.5), Some(-2));
        assert_eq!(dart_to_int(f64::NAN), None);
        assert_eq!(dart_to_int(f64::INFINITY), None);
    }
}
