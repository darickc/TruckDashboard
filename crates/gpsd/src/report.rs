//! gpsd's JSON reports, one per line (gpsd_json(5)). Only the fields the
//! head unit uses are read; everything else is ignored, so a newer gpsd that
//! adds fields still parses. A field of the wrong type reads as absent.

use serde_json::{Map, Value};

/// One line from gpsd.
#[derive(Debug, Clone, PartialEq)]
pub enum Report {
    /// Sent on connect.
    Version {
        release: String,
        proto_major: u64,
        proto_minor: u64,
    },
    /// Every receiver gpsd knows of; empty when none is plugged in.
    Devices(Vec<Device>),
    /// One receiver appeared, changed, or (without `activated`) went away.
    Device(Device),
    Tpv(Tpv),
    Sky(Sky),
    /// gpsd refused something the client sent.
    Error(String),
    /// A class the head unit doesn't use (WATCH, GST, ATT, PPS, ...).
    Other(String),
}

#[derive(Debug, Clone, PartialEq)]
pub struct Device {
    pub path: String,
    /// When gpsd opened it; absent when it has been closed.
    pub activated: Option<String>,
    pub driver: Option<String>,
}

impl Device {
    pub fn active(&self) -> bool {
        self.activated.is_some()
    }
}

/// gpsd's NMEA mode: what the receiver can say about where it is.
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord)]
pub enum Mode {
    /// 0: gpsd hasn't heard enough yet.
    Unknown,
    /// 1: the receiver is talking but has no fix.
    NoFix,
    /// 2: latitude and longitude, no altitude.
    Fix2d,
    /// 3: latitude, longitude and altitude.
    Fix3d,
}

impl Mode {
    fn from_json(v: Option<&Value>) -> Mode {
        match v.and_then(Value::as_u64) {
            Some(2) => Mode::Fix2d,
            Some(3) => Mode::Fix3d,
            Some(1) => Mode::NoFix,
            _ => Mode::Unknown,
        }
    }

    pub fn is_fix(self) -> bool {
        matches!(self, Mode::Fix2d | Mode::Fix3d)
    }
}

/// Time-position-velocity: one report per receiver cycle, or (with NMEA
/// receivers) one per sentence, each with what gpsd knows so far.
#[derive(Debug, Clone, PartialEq, Default)]
pub struct Tpv {
    pub device: Option<String>,
    pub mode: Option<Mode>,
    /// UTC, as gpsd sent it.
    pub time: Option<String>,
    pub lat: Option<f64>,
    pub lon: Option<f64>,
    /// Above mean sea level: `altMSL`, else the deprecated `alt`.
    pub alt_msl_m: Option<f64>,
    /// Speed over ground, m/s.
    pub speed_mps: Option<f64>,
    /// Course over ground, degrees from true north.
    pub track_deg: Option<f64>,
    /// Estimated horizontal error, metres (gpsd's `eph`; its confidence
    /// level depends on the receiver).
    pub eph_m: Option<f64>,
}

impl Tpv {
    pub fn mode(&self) -> Mode {
        self.mode.unwrap_or(Mode::Unknown)
    }

    /// A fix with a usable position: mode 2 or 3 and a latitude and
    /// longitude in range.
    pub fn has_position(&self) -> bool {
        self.mode().is_fix()
            && matches!(self.lat, Some(lat) if (-90.0..=90.0).contains(&lat))
            && matches!(self.lon, Some(lon) if (-180.0..=180.0).contains(&lon))
    }
}

/// Satellites. gpsd sends a short SKY (counts only) between full ones.
#[derive(Debug, Clone, PartialEq, Default)]
pub struct Sky {
    pub device: Option<String>,
    /// Seen (`nSat`, else the length of `satellites`).
    pub visible: Option<u32>,
    /// Used in the fix (`uSat`, else the `used` flags in `satellites`).
    pub used: Option<u32>,
}

impl Report {
    /// Parses one line. `Err` for a line that isn't a JSON object with a
    /// `class`.
    pub fn parse(line: &str) -> Result<Report, String> {
        let v: Value = serde_json::from_str(line.trim()).map_err(|e| format!("not JSON: {e}"))?;
        let Some(o) = v.as_object() else {
            return Err("not a JSON object".to_string());
        };
        let class = o
            .get("class")
            .and_then(Value::as_str)
            .ok_or_else(|| "no class".to_string())?;
        Ok(match class {
            "VERSION" => Report::Version {
                release: str_of(o, "release").unwrap_or_default(),
                proto_major: o.get("proto_major").and_then(Value::as_u64).unwrap_or(0),
                proto_minor: o.get("proto_minor").and_then(Value::as_u64).unwrap_or(0),
            },
            "DEVICES" => Report::Devices(
                o.get("devices")
                    .and_then(Value::as_array)
                    .map(|a| {
                        a.iter()
                            .filter_map(Value::as_object)
                            .filter_map(device_of)
                            .collect()
                    })
                    .unwrap_or_default(),
            ),
            "DEVICE" => match device_of(o) {
                Some(d) => Report::Device(d),
                None => Report::Other("DEVICE".to_string()),
            },
            "TPV" => Report::Tpv(Tpv {
                device: str_of(o, "device"),
                mode: o.get("mode").map(|m| Mode::from_json(Some(m))),
                time: str_of(o, "time"),
                lat: f64_of(o, "lat"),
                lon: f64_of(o, "lon"),
                alt_msl_m: f64_of(o, "altMSL").or_else(|| f64_of(o, "alt")),
                speed_mps: f64_of(o, "speed"),
                track_deg: f64_of(o, "track"),
                eph_m: f64_of(o, "eph"),
            }),
            "SKY" => {
                let sats = o.get("satellites").and_then(Value::as_array);
                let count = |key: &str| {
                    o.get(key)
                        .and_then(Value::as_u64)
                        .and_then(|n| u32::try_from(n).ok())
                };
                Report::Sky(Sky {
                    device: str_of(o, "device"),
                    visible: count("nSat")
                        .or_else(|| sats.and_then(|a| u32::try_from(a.len()).ok())),
                    used: count("uSat").or_else(|| {
                        sats.and_then(|a| {
                            u32::try_from(
                                a.iter()
                                    .filter(|s| {
                                        s.get("used").and_then(Value::as_bool) == Some(true)
                                    })
                                    .count(),
                            )
                            .ok()
                        })
                    }),
                })
            }
            "ERROR" => Report::Error(str_of(o, "message").unwrap_or_default()),
            other => Report::Other(other.to_string()),
        })
    }
}

fn str_of(o: &Map<String, Value>, key: &str) -> Option<String> {
    o.get(key).and_then(Value::as_str).map(str::to_string)
}

fn f64_of(o: &Map<String, Value>, key: &str) -> Option<f64> {
    o.get(key).and_then(Value::as_f64).filter(|v| v.is_finite())
}

fn device_of(o: &Map<String, Value>) -> Option<Device> {
    Some(Device {
        path: str_of(o, "path")?,
        activated: str_of(o, "activated").filter(|a| !a.is_empty() && a != "0"),
        driver: str_of(o, "driver"),
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    // Lines from tests/data/gpsd-3.27.5-nmea-udp.jsonl (gpsd's own output).
    const VERSION: &str =
        r#"{"class":"VERSION","release":"3.27.5","rev":"3.27.5","proto_major":16,"proto_minor":1}"#;
    const DEVICES: &str = r#"{"class":"DEVICES","devices":[{"class":"DEVICE","path":"udp://127.0.0.1:5948","activated":"2026-11-11T17:46:13.026Z"}]}"#;
    const TPV_3D: &str = r#"{"class":"TPV","device":"udp://127.0.0.1:5948","mode":3,"time":"2026-11-11T18:00:06.000Z","ept":0.005,"lat":39.828700000,"lon":-98.579100000,"altHAE":536.0000,"altMSL":560.0000,"alt":560.0000,"epx":29.305,"epy":29.054,"epv":39.100,"track":45.0000,"magtrack":49.1619,"magvar":4.2,"speed":15.433,"climb":0.000,"eps":58.61,"epc":78.20,"geoidSep":-24.000,"eph":22.800,"sep":39.900}"#;
    const TPV_NO_FIX: &str = r#"{"class":"TPV","device":"udp://127.0.0.1:5948","mode":1,"time":"2026-11-11T18:00:16.000Z","ept":0.005}"#;
    const SKY_SHORT: &str = r#"{"class":"SKY","device":"udp://127.0.0.1:5948","gdop":58.14,"hdop":1.20,"pdop":2.10,"tdop":28.64,"xdop":1.95,"ydop":1.94,"vdop":1.70,"uSat":8}"#;

    #[test]
    fn version() {
        assert_eq!(
            Report::parse(VERSION),
            Ok(Report::Version {
                release: "3.27.5".to_string(),
                proto_major: 16,
                proto_minor: 1
            })
        );
    }

    #[test]
    fn devices() {
        let Ok(Report::Devices(d)) = Report::parse(DEVICES) else {
            panic!("DEVICES")
        };
        assert_eq!(d.len(), 1);
        assert_eq!(d[0].path, "udp://127.0.0.1:5948");
        assert!(d[0].active());
        assert_eq!(
            Report::parse(r#"{"class":"DEVICES","devices":[]}"#),
            Ok(Report::Devices(vec![]))
        );
    }

    #[test]
    fn a_device_without_activated_is_gone() {
        let Ok(Report::Device(d)) = Report::parse(r#"{"class":"DEVICE","path":"/dev/ttyACM0"}"#)
        else {
            panic!("DEVICE")
        };
        assert!(!d.active());
    }

    #[test]
    fn tpv_3d() {
        let Ok(Report::Tpv(t)) = Report::parse(TPV_3D) else {
            panic!("TPV")
        };
        assert_eq!(t.mode(), Mode::Fix3d);
        assert!(t.has_position());
        assert_eq!(t.lat, Some(39.8287));
        assert_eq!(t.lon, Some(-98.5791));
        assert_eq!(t.alt_msl_m, Some(560.0));
        assert_eq!(t.speed_mps, Some(15.433));
        assert_eq!(t.track_deg, Some(45.0));
        assert_eq!(t.eph_m, Some(22.8));
        assert_eq!(t.time.as_deref(), Some("2026-11-11T18:00:06.000Z"));
    }

    #[test]
    fn tpv_without_a_fix_has_no_position() {
        let Ok(Report::Tpv(t)) = Report::parse(TPV_NO_FIX) else {
            panic!("TPV")
        };
        assert_eq!(t.mode(), Mode::NoFix);
        assert!(!t.has_position());
    }

    #[test]
    fn a_fix_mode_without_coordinates_or_out_of_range_is_no_position() {
        let Ok(Report::Tpv(t)) = Report::parse(r#"{"class":"TPV","mode":3}"#) else {
            panic!("TPV")
        };
        assert!(!t.has_position());
        let Ok(Report::Tpv(t)) = Report::parse(r#"{"class":"TPV","mode":2,"lat":91.0,"lon":0.0}"#)
        else {
            panic!("TPV")
        };
        assert!(!t.has_position());
        // Wrong types read as absent.
        let Ok(Report::Tpv(t)) = Report::parse(r#"{"class":"TPV","mode":"3","lat":"1","lon":2}"#)
        else {
            panic!("TPV")
        };
        assert_eq!(t.mode(), Mode::Unknown);
        assert_eq!(t.lat, None);
    }

    #[test]
    fn sky_counts() {
        assert_eq!(
            Report::parse(SKY_SHORT),
            Ok(Report::Sky(Sky {
                device: Some("udp://127.0.0.1:5948".to_string()),
                visible: None,
                used: Some(8)
            }))
        );
        // No nSat/uSat: counted from the list.
        let line = r#"{"class":"SKY","satellites":[{"PRN":1,"used":true},{"PRN":2,"used":false},{"PRN":3}]}"#;
        let Ok(Report::Sky(s)) = Report::parse(line) else {
            panic!("SKY")
        };
        assert_eq!((s.visible, s.used), (Some(3), Some(1)));
    }

    #[test]
    fn other_classes_and_errors() {
        assert_eq!(
            Report::parse(r#"{"class":"WATCH","enable":true}"#),
            Ok(Report::Other("WATCH".to_string()))
        );
        assert_eq!(
            Report::parse(r#"{"class":"ERROR","message":"Unrecognized request"}"#),
            Ok(Report::Error("Unrecognized request".to_string()))
        );
        assert!(Report::parse("not json").is_err());
        assert!(Report::parse("[1,2]").is_err());
        assert!(Report::parse(r#"{"mode":3}"#).is_err());
    }
}
