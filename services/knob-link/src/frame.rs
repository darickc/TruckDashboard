//! The knob display's frames (ADR-0044 decision 3), built from the gateway's
//! signal definitions and snapshots. The dial parses them in
//! `firmware/knob-display/lib/KnobCore/src/Frame.cpp`; the golden lines in
//! the tests below are parsed there too (`test_frame`).
//!
//!   C1 <slot>:<unit>:<min>:<max>:<v|u> ...*CS
//!   D1 <seq> <live|sim> <slot>:<c|a|k|s|n>[:<value>[:<age_s>]] ...*CS

use std::collections::HashMap;

use f250_proto::vehicle::v1 as pb;

/// The dial's slots and the gateway signal each shows.
pub const SLOTS: [(&str, &str); 5] = [
    ("spd", "speed"),
    ("fuel", "fuel_level"),
    ("eot", "eot"),
    ("ect", "ect"),
    ("dlt", "eot_ect_delta"),
];

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Units {
    Imperial,
    Metric,
}

impl Units {
    pub fn parse(s: &str) -> Result<Units, String> {
        match s {
            "imperial" => Ok(Units::Imperial),
            "metric" => Ok(Units::Metric),
            _ => Err(format!("units: imperial or metric, not {s:?}")),
        }
    }
}

/// A slot's unit and arc range in the display's units. Examples (the arc's
/// scale, not limits or thresholds).
fn range(slot: &str, units: Units) -> (&'static str, f64, f64) {
    match (slot, units) {
        ("spd", Units::Imperial) => ("mph", 0.0, 100.0),
        ("spd", Units::Metric) => ("kmh", 0.0, 160.0),
        ("fuel", _) => ("%", 0.0, 100.0),
        ("dlt", Units::Imperial) => ("F", -10.0, 40.0),
        ("dlt", Units::Metric) => ("C", -5.0, 20.0),
        (_, Units::Imperial) => ("F", 100.0, 260.0),
        (_, Units::Metric) => ("C", 40.0, 125.0),
    }
}

/// From the gateway's canonical unit (degC, km/h, %) to the display's.
pub fn convert(slot: &str, canonical: f64, units: Units) -> f64 {
    match (slot, units) {
        (_, Units::Metric) | ("fuel", _) => canonical,
        ("spd", Units::Imperial) => canonical / 1.609_344,
        ("dlt", Units::Imperial) => canonical * 9.0 / 5.0,
        (_, Units::Imperial) => canonical * 9.0 / 5.0 + 32.0,
    }
}

pub fn checksum(body: &str) -> u8 {
    body.bytes().fold(0, |x, b| x ^ b)
}

pub fn with_checksum(body: &str) -> String {
    format!("{body}*{:02X}", checksum(body))
}

/// "62", "62.4": one decimal at most.
fn num(x: f64) -> String {
    let s = format!("{x:.1}");
    s.strip_suffix(".0").map(str::to_string).unwrap_or(s)
}

/// A signal is trusted (`v`) when it is SAE, verified on the truck, an aux
/// sensor or a decoded broadcast, or computed only from trusted signals.
/// Imported, unknown or missing: `u`.
pub fn trusted(id: &str, defs: &HashMap<String, pb::SignalDefinition>) -> bool {
    fn go(id: &str, defs: &HashMap<String, pb::SignalDefinition>, depth: u8) -> bool {
        let Some(d) = defs.get(id) else { return false };
        match pb::Provenance::try_from(d.provenance) {
            Ok(
                pb::Provenance::Sae
                | pb::Provenance::VerifiedOnTruck
                | pb::Provenance::AuxSensor
                | pb::Provenance::BroadcastDecoded,
            ) => true,
            Ok(pb::Provenance::Computed) => {
                depth < 4 && !d.inputs.is_empty() && d.inputs.iter().all(|i| go(i, defs, depth + 1))
            }
            _ => false,
        }
    }
    go(id, defs, 0)
}

pub fn config_line(defs: &HashMap<String, pb::SignalDefinition>, units: Units) -> String {
    let mut body = String::from("C1");
    for (slot, signal) in SLOTS {
        let (unit, min, max) = range(slot, units);
        let trust = if trusted(signal, defs) { 'v' } else { 'u' };
        body.push_str(&format!(" {slot}:{unit}:{}:{}:{trust}", num(min), num(max)));
    }
    with_checksum(&body)
}

/// One slot's token from its sample and the snapshot's alerts.
fn token(slot: &str, sample: Option<&pb::Sample>, alerts: &[pb::Alert], units: Units) -> String {
    let Some(s) = sample else {
        return format!("{slot}:n");
    };
    let valid = pb::Validity::try_from(s.validity) == Ok(pb::Validity::Valid);
    match (valid, s.value, s.last_good_value) {
        (true, Some(v), _) => {
            let level = alerts
                .iter()
                .filter(|a| a.signal_id == s.signal_id)
                .filter_map(|a| pb::AlertLevel::try_from(a.level).ok())
                .max_by_key(|l| *l as i32);
            let state = match level {
                Some(pb::AlertLevel::Critical) => 'k',
                Some(pb::AlertLevel::Advisory) => 'a',
                _ => 'c',
            };
            format!("{slot}:{state}:{}", num(convert(slot, v, units)))
        }
        // Never shown as current (CLAUDE.md rule 4): the last good value and
        // its age.
        (_, _, Some(last)) => {
            let age = s.last_good_age_ms.unwrap_or(0) as f64 / 1000.0;
            format!("{slot}:s:{}:{}", num(convert(slot, last, units)), num(age))
        }
        _ => format!("{slot}:n"),
    }
}

pub fn data_line(seq: u32, snap: &pb::Snapshot, units: Units) -> String {
    let simulated = snap.link.as_ref().is_some_and(|l| l.simulated);
    let mut body = format!("D1 {seq} {}", if simulated { "sim" } else { "live" });
    for (slot, signal) in SLOTS {
        let sample = snap.samples.iter().find(|s| s.signal_id == signal);
        body.push(' ');
        body.push_str(&token(slot, sample, &snap.alerts, units));
    }
    with_checksum(&body)
}

/// A line from the dial: its hello (`H1 <name> <version>`), its log
/// (`# ...`), or something else.
#[derive(Debug, PartialEq, Eq)]
pub enum FromDial {
    Hello(String),
    Log(String),
    /// A call button on the dial (`K1`).
    Call(CallRequest),
    Other(String),
}

/// What a call button on the dial asks for (`K1 <answer|decline|end>`): the
/// button it pressed, so knob-link acts only if the call is still in the
/// state that button was for (pages::call_command).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum CallRequest {
    Answer,
    Decline,
    End,
}

pub fn from_dial(line: &str) -> FromDial {
    let line = line.trim_end_matches(['\r', '\n']);
    if let Some(log) = line.strip_prefix('#') {
        return FromDial::Log(log.trim().to_string());
    }
    if let Some((body, cs)) = line.rsplit_once('*')
        && u8::from_str_radix(cs, 16).ok() == Some(checksum(body))
    {
        if let Some(hello) = body.strip_prefix("H1 ") {
            return FromDial::Hello(hello.to_string());
        }
        match body {
            "K1 answer" => return FromDial::Call(CallRequest::Answer),
            "K1 decline" => return FromDial::Call(CallRequest::Decline),
            "K1 end" => return FromDial::Call(CallRequest::End),
            _ => {}
        }
    }
    FromDial::Other(line.to_string())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn def(id: &str, p: pb::Provenance, inputs: &[&str]) -> (String, pb::SignalDefinition) {
        (
            id.to_string(),
            pb::SignalDefinition {
                id: id.into(),
                provenance: p.into(),
                inputs: inputs.iter().map(|s| s.to_string()).collect(),
                ..Default::default()
            },
        )
    }

    fn defs() -> HashMap<String, pb::SignalDefinition> {
        HashMap::from([
            def("speed", pb::Provenance::Sae, &[]),
            def("ect", pb::Provenance::Sae, &[]),
            def("eot", pb::Provenance::ImportedUnverified, &[]),
            def("fuel_level", pb::Provenance::ImportedUnverified, &[]),
            def("eot_ect_delta", pb::Provenance::Computed, &["eot", "ect"]),
        ])
    }

    fn valid(id: &str, v: f64) -> pb::Sample {
        pb::Sample {
            signal_id: id.into(),
            validity: pb::Validity::Valid.into(),
            value: Some(v),
            last_good_value: Some(v),
            last_good_age_ms: Some(0),
            ..Default::default()
        }
    }

    #[test]
    fn checksums_match_the_dials() {
        // The same vector as firmware test_frame: "H1 x" -> 21.
        assert_eq!(with_checksum("H1 x"), "H1 x*21");
    }

    #[test]
    fn config_marks_imported_and_what_is_computed_from_it() {
        let line = config_line(&defs(), Units::Imperial);
        // Golden: firmware test_frame parses this exact line.
        assert_eq!(
            line,
            "C1 spd:mph:0:100:v fuel:%:0:100:u eot:F:100:260:u ect:F:100:260:v dlt:F:-10:40:u*14"
        );
        let mut d = defs();
        d.extend([def("eot", pb::Provenance::VerifiedOnTruck, &[])]);
        assert!(config_line(&d, Units::Imperial).contains("dlt:F:-10:40:v"));
        assert!(config_line(&d, Units::Metric).contains("spd:kmh:0:160:v"));
        // A signal the gateway doesn't know is not trusted.
        assert!(!trusted("boost", &d));
    }

    #[test]
    fn data_states() {
        let mut ect = valid("ect", 110.0);
        ect.signal_id = "ect".into();
        let snap = pb::Snapshot {
            samples: vec![
                valid("speed", 100.0),
                valid("fuel_level", 61.0),
                pb::Sample {
                    signal_id: "eot".into(),
                    validity: pb::Validity::Stale.into(),
                    value: None,
                    last_good_value: Some(96.0),
                    last_good_age_ms: Some(12_400),
                    ..Default::default()
                },
                ect,
                pb::Sample {
                    signal_id: "eot_ect_delta".into(),
                    validity: pb::Validity::NoData.into(),
                    ..Default::default()
                },
            ],
            link: Some(pb::LinkStatus {
                simulated: true,
                ..Default::default()
            }),
            alerts: vec![
                pb::Alert {
                    signal_id: "ect".into(),
                    level: pb::AlertLevel::Advisory.into(),
                    ..Default::default()
                },
                pb::Alert {
                    signal_id: "ect".into(),
                    level: pb::AlertLevel::Critical.into(),
                    ..Default::default()
                },
            ],
            ..Default::default()
        };
        let line = data_line(7, &snap, Units::Imperial);
        // Golden: firmware test_frame parses this exact line.
        assert_eq!(
            line,
            "D1 7 sim spd:c:62.1 fuel:c:61 eot:s:204.8:12.4 ect:k:230 dlt:n*7A"
        );
        let metric = data_line(8, &snap, Units::Metric);
        assert!(metric.starts_with("D1 8 sim spd:c:100 fuel:c:61 eot:s:96:12.4 ect:k:110 dlt:n*"));
    }

    #[test]
    fn a_value_that_isnt_valid_is_never_current() {
        let snap = pb::Snapshot {
            samples: vec![pb::Sample {
                signal_id: "speed".into(),
                validity: pb::Validity::OutOfRange.into(),
                value: Some(300.0),
                last_good_value: Some(80.0),
                last_good_age_ms: Some(1500),
                ..Default::default()
            }],
            ..Default::default()
        };
        let line = data_line(1, &snap, Units::Metric);
        assert!(line.contains(" spd:s:80:1.5 "), "{line}");
        assert!(
            line.contains(" eot:n "),
            "a signal not in the snapshot: {line}"
        );
        assert!(line.contains(" live "));
    }

    #[test]
    fn conversions() {
        assert!((convert("eot", 100.0, Units::Imperial) - 212.0).abs() < 1e-9);
        assert!((convert("dlt", 5.0, Units::Imperial) - 9.0).abs() < 1e-9);
        assert!((convert("spd", 160.934_4, Units::Imperial) - 100.0).abs() < 1e-9);
        assert_eq!(convert("fuel", 40.0, Units::Imperial), 40.0);
        assert_eq!(convert("ect", 90.0, Units::Metric), 90.0);
        assert!(Units::parse("furlongs").is_err());
    }

    #[test]
    fn lines_from_the_dial() {
        assert_eq!(
            from_dial(&with_checksum("H1 knob-display 0.1.0")),
            FromDial::Hello("knob-display 0.1.0".into())
        );
        assert_eq!(
            from_dial("# frames: 3 data\r\n"),
            FromDial::Log("frames: 3 data".into())
        );
        assert_eq!(
            from_dial("H1 knob-display 0.1.0*00"),
            FromDial::Other("H1 knob-display 0.1.0*00".into())
        );
        // The call buttons, only with a good checksum.
        assert_eq!(
            from_dial(&with_checksum("K1 answer")),
            FromDial::Call(CallRequest::Answer)
        );
        assert_eq!(
            from_dial(&format!("{}\r", with_checksum("K1 decline"))),
            FromDial::Call(CallRequest::Decline)
        );
        assert_eq!(
            from_dial(&with_checksum("K1 end")),
            FromDial::Call(CallRequest::End)
        );
        assert_eq!(from_dial("K1 end*00"), FromDial::Other("K1 end*00".into()));
        assert!(matches!(
            from_dial(&with_checksum("K1 mute")),
            FromDial::Other(_)
        ));
    }
}
