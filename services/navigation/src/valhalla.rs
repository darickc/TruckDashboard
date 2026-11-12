//! Valhalla, one request per process (ADR-0035): `valhalla_service CONFIG
//! route REQUEST` is Valhalla's own one-shot mode. It needs no prime_server
//! and opens no port; a crash or a runaway request ends with the process.
//!
//! The request and response are Valhalla 3.9.1's JSON API. The test vectors
//! in `tests/data/` are its real output.

use std::future::Future;
use std::path::{Path, PathBuf};
use std::process::Stdio;
use std::time::Duration;

use serde_json::{Value, json};

/// A point: (latitude, longitude) in degrees.
pub type LatLon = (f64, f64);

/// Valhalla's costing model. `Auto` unless configured: the F-250 is driven
/// as a car. `Truck` takes only the dimensions the owner configured; the
/// rest stay Valhalla's defaults.
#[derive(Debug, Clone, PartialEq, Default)]
pub enum Costing {
    #[default]
    Auto,
    Truck(TruckOptions),
}

/// Valhalla's truck costing options, each set only when configured.
#[derive(Debug, Clone, PartialEq, Default)]
pub struct TruckOptions {
    pub height_m: Option<f64>,
    pub width_m: Option<f64>,
    pub length_m: Option<f64>,
    /// Metric tons.
    pub weight_t: Option<f64>,
    pub axle_load_t: Option<f64>,
}

impl Costing {
    pub fn name(&self) -> &'static str {
        match self {
            Costing::Auto => "auto",
            Costing::Truck(_) => "truck",
        }
    }
}

#[derive(Debug, Clone, PartialEq)]
pub struct RouteRequest {
    pub from: LatLon,
    /// The course over ground, while moving: the route starts the way the
    /// truck is going rather than with a U-turn.
    pub heading_deg: Option<f64>,
    pub to: LatLon,
    pub costing: Costing,
}

/// How far either side of `heading_deg` Valhalla may start.
const HEADING_TOLERANCE_DEG: u32 = 60;

/// The request's JSON.
pub fn request_json(r: &RouteRequest) -> String {
    let mut from = json!({ "lat": r.from.0, "lon": r.from.1 });
    if let Some(h) = r.heading_deg {
        from["heading"] = json!(h.rem_euclid(360.0).round() as u32 % 360);
        from["heading_tolerance"] = json!(HEADING_TOLERANCE_DEG);
    }
    let mut req = json!({
        "locations": [from, { "lat": r.to.0, "lon": r.to.1 }],
        "costing": r.costing.name(),
        "directions_options": { "units": "kilometers", "language": "en-US" },
    });
    if let Costing::Truck(t) = &r.costing {
        let mut o = serde_json::Map::new();
        for (k, v) in [
            ("height", t.height_m),
            ("width", t.width_m),
            ("length", t.length_m),
            ("weight", t.weight_t),
            ("axle_load", t.axle_load_t),
        ] {
            if let Some(v) = v {
                o.insert(k.to_string(), json!(v));
            }
        }
        req["costing_options"] = json!({ "truck": o });
    }
    req.to_string()
}

#[derive(Debug, Clone, PartialEq)]
pub struct Maneuver {
    /// Valhalla's maneuver type number.
    pub kind: u32,
    pub instruction: String,
    pub street_names: Vec<String>,
    pub length_m: f64,
    pub time_s: f64,
    pub begin_shape_index: usize,
    /// Distance from the route's start to `begin_shape_index`, along the shape.
    pub start_m: f64,
}

#[derive(Debug, Clone, PartialEq)]
pub struct Route {
    /// Set by the guide; 0 as parsed.
    pub id: u64,
    pub shape: Vec<LatLon>,
    /// Distance along the shape to each point; the last is the length.
    pub along_m: Vec<f64>,
    pub maneuvers: Vec<Maneuver>,
    /// Valhalla's length and time for the whole route.
    pub length_m: f64,
    pub time_s: f64,
    pub destination: LatLon,
    pub costing: String,
    pub has_toll: bool,
    pub has_highway: bool,
    pub has_ferry: bool,
}

impl Route {
    /// The shape's length.
    pub fn shape_length_m(&self) -> f64 {
        self.along_m.last().copied().unwrap_or(0.0)
    }
}

/// Parses Valhalla's answer to a route request: a trip, or its error JSON.
pub fn parse_response(text: &str, destination: LatLon, costing: &str) -> Result<Route, String> {
    let v: Value = serde_json::from_str(text.trim())
        .map_err(|e| format!("Valhalla's answer isn't JSON ({e})"))?;
    if let Some(msg) = v.get("error").and_then(Value::as_str) {
        let code = v.get("error_code").and_then(Value::as_u64).unwrap_or(0);
        return Err(format!("Valhalla error {code}: {msg}"));
    }
    let trip = v.get("trip").ok_or("Valhalla's answer has no trip")?;
    if let Some(status) = trip.get("status").and_then(Value::as_i64)
        && status != 0
    {
        let msg = trip
            .get("status_message")
            .and_then(Value::as_str)
            .unwrap_or("");
        return Err(format!("Valhalla trip status {status}: {msg}"));
    }
    if trip.get("units").and_then(Value::as_str) != Some("kilometers") {
        return Err("Valhalla's answer isn't in kilometres".to_string());
    }
    let legs = trip
        .get("legs")
        .and_then(Value::as_array)
        .ok_or("Valhalla's trip has no legs")?;
    let [leg] = legs.as_slice() else {
        return Err(format!("expected one leg, Valhalla sent {}", legs.len()));
    };
    let shape = decode_polyline6(
        leg.get("shape")
            .and_then(Value::as_str)
            .ok_or("the leg has no shape")?,
    )?;
    if shape.len() < 2 {
        return Err("the route's shape has fewer than two points".to_string());
    }
    let along_m = cumulative_m(&shape);
    let mut maneuvers = Vec::new();
    for m in leg
        .get("maneuvers")
        .and_then(Value::as_array)
        .ok_or("the leg has no maneuvers")?
    {
        let begin = m
            .get("begin_shape_index")
            .and_then(Value::as_u64)
            .ok_or("a maneuver has no begin_shape_index")? as usize;
        if begin >= shape.len() {
            return Err(format!(
                "a maneuver starts at shape point {begin} of {}",
                shape.len()
            ));
        }
        maneuvers.push(Maneuver {
            kind: m.get("type").and_then(Value::as_u64).unwrap_or(0) as u32,
            instruction: m
                .get("instruction")
                .and_then(Value::as_str)
                .unwrap_or("")
                .to_string(),
            street_names: m
                .get("street_names")
                .and_then(Value::as_array)
                .map(|a| {
                    a.iter()
                        .filter_map(|s| s.as_str().map(str::to_string))
                        .collect()
                })
                .unwrap_or_default(),
            length_m: m.get("length").and_then(Value::as_f64).unwrap_or(0.0) * 1000.0,
            time_s: m.get("time").and_then(Value::as_f64).unwrap_or(0.0),
            begin_shape_index: begin,
            start_m: along_m[begin],
        });
    }
    if maneuvers.is_empty() {
        return Err("the route has no maneuvers".to_string());
    }
    let summary = trip.get("summary").ok_or("the trip has no summary")?;
    let flag = |k: &str| summary.get(k).and_then(Value::as_bool).unwrap_or(false);
    Ok(Route {
        id: 0,
        shape,
        along_m,
        maneuvers,
        length_m: summary.get("length").and_then(Value::as_f64).unwrap_or(0.0) * 1000.0,
        time_s: summary.get("time").and_then(Value::as_f64).unwrap_or(0.0),
        destination,
        costing: costing.to_string(),
        has_toll: flag("has_toll"),
        has_highway: flag("has_highway"),
        has_ferry: flag("has_ferry"),
    })
}

/// Decodes an encoded polyline with six decimal places, Valhalla's
/// default `shape`.
pub fn decode_polyline6(s: &str) -> Result<Vec<LatLon>, String> {
    let bytes = s.as_bytes();
    let mut i = 0;
    let mut next = || -> Result<Option<i64>, String> {
        if i >= bytes.len() {
            return Ok(None);
        }
        let (mut result, mut shift) = (0i64, 0u32);
        loop {
            let b = *bytes.get(i).ok_or("the shape ends mid-number")? as i64 - 63;
            i += 1;
            if !(0..64).contains(&b) || shift > 60 {
                return Err("the shape isn't an encoded polyline".to_string());
            }
            result |= (b & 0x1f) << shift;
            shift += 5;
            if b < 0x20 {
                break;
            }
        }
        Ok(Some(if result & 1 != 0 {
            !(result >> 1)
        } else {
            result >> 1
        }))
    };
    let (mut lat, mut lon) = (0i64, 0i64);
    let mut out = Vec::new();
    while let Some(dlat) = next()? {
        let dlon = next()?.ok_or("the shape has a latitude without a longitude")?;
        lat += dlat;
        lon += dlon;
        out.push((lat as f64 / 1e6, lon as f64 / 1e6));
    }
    Ok(out)
}

const EARTH_RADIUS_M: f64 = 6_371_008.8;

/// Great-circle distance, metres.
pub fn distance_m(a: LatLon, b: LatLon) -> f64 {
    let (la1, lo1) = (a.0.to_radians(), a.1.to_radians());
    let (la2, lo2) = (b.0.to_radians(), b.1.to_radians());
    let h = ((la2 - la1) / 2.0).sin().powi(2)
        + la1.cos() * la2.cos() * ((lo2 - lo1) / 2.0).sin().powi(2);
    2.0 * EARTH_RADIUS_M * h.sqrt().asin()
}

fn cumulative_m(shape: &[LatLon]) -> Vec<f64> {
    let mut d = 0.0;
    let mut out = Vec::with_capacity(shape.len());
    out.push(0.0);
    for w in shape.windows(2) {
        d += distance_m(w[0], w[1]);
        out.push(d);
    }
    out
}

/// Writes the config navigation runs Valhalla with: the template (Valhalla
/// 3.9.1's `valhalla_build_config` defaults, `valhalla/` in this service)
/// pointed at one tile extract.
pub fn write_runtime_config(template: &Path, tiles: &Path, out: &Path) -> Result<(), String> {
    let text = std::fs::read_to_string(template)
        .map_err(|e| format!("Valhalla config template {}: {e}", template.display()))?;
    let mut v: Value = serde_json::from_str(&text)
        .map_err(|e| format!("Valhalla config template {}: {e}", template.display()))?;
    let mjolnir = v
        .get_mut("mjolnir")
        .and_then(Value::as_object_mut)
        .ok_or_else(|| format!("{} has no mjolnir section", template.display()))?;
    mjolnir.insert("tile_extract".into(), json!(tiles.display().to_string()));
    mjolnir.insert("tile_dir".into(), json!(""));
    if let Some(dir) = out.parent() {
        std::fs::create_dir_all(dir).map_err(|e| format!("{}: {e}", dir.display()))?;
    }
    let tmp = out.with_extension("json.tmp");
    std::fs::write(&tmp, v.to_string()).map_err(|e| format!("{}: {e}", tmp.display()))?;
    std::fs::rename(&tmp, out).map_err(|e| format!("{}: {e}", out.display()))
}

/// Anything that can answer a route request; Valhalla, or a test's fake.
pub trait Router: Send + Sync + 'static {
    /// Why routing can't work now (no program, no data), or Ok.
    fn check(&self) -> Result<(), String>;
    fn route(&self, req: RouteRequest) -> impl Future<Output = Result<Route, String>> + Send;
}

/// `valhalla_service`, run once per request.
#[derive(Debug, Clone)]
pub struct ValhallaCli {
    /// `valhalla_service`, or a wrapper taking the same arguments
    /// (`tools/dev/valhalla-docker.sh` on the Mac).
    pub program: PathBuf,
    pub template: PathBuf,
    pub tiles: PathBuf,
    /// Where the runtime config is written.
    pub config: PathBuf,
    pub timeout: Duration,
}

/// Longer than any request should take for one region; a request still
/// running then is killed.
pub const DEFAULT_TIMEOUT: Duration = Duration::from_secs(30);

impl ValhallaCli {
    fn program_found(&self) -> bool {
        if self.program.components().count() > 1 {
            return self.program.is_file();
        }
        std::env::var_os("PATH")
            .map(|paths| std::env::split_paths(&paths).any(|d| d.join(&self.program).is_file()))
            .unwrap_or(false)
    }
}

impl Router for ValhallaCli {
    fn check(&self) -> Result<(), String> {
        if !self.program_found() {
            return Err(format!(
                "{} isn't installed (Valhalla isn't in this image yet)",
                self.program.display()
            ));
        }
        if !self.tiles.is_file() {
            return Err(format!("no routing data at {}", self.tiles.display()));
        }
        if !self.template.is_file() {
            return Err(format!(
                "no Valhalla config template at {}",
                self.template.display()
            ));
        }
        Ok(())
    }

    async fn route(&self, req: RouteRequest) -> Result<Route, String> {
        self.check()?;
        // Written each time: the tiles may have been replaced by a stick.
        write_runtime_config(&self.template, &self.tiles, &self.config)?;
        let child = tokio::process::Command::new(&self.program)
            .arg(&self.config)
            .arg("route")
            .arg(request_json(&req))
            .stdin(Stdio::null())
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .kill_on_drop(true)
            .spawn()
            .map_err(|e| format!("can't start {}: {e}", self.program.display()))?;
        let out = match tokio::time::timeout(self.timeout, child.wait_with_output()).await {
            Ok(Ok(out)) => out,
            Ok(Err(e)) => return Err(format!("{}: {e}", self.program.display())),
            Err(_) => {
                return Err(format!(
                    "Valhalla took longer than {} s",
                    self.timeout.as_secs()
                ));
            }
        };
        let stdout = String::from_utf8_lossy(&out.stdout);
        match parse_response(&stdout, req.to, req.costing.name()) {
            Ok(route) if out.status.success() => Ok(route),
            Ok(_) => Err(format!("Valhalla exited with {}", out.status)),
            // No answer at all: the last thing it logged says more.
            Err(e) if stdout.trim().is_empty() => {
                let stderr = String::from_utf8_lossy(&out.stderr);
                let why = stderr
                    .lines()
                    .rev()
                    .map(str::trim)
                    .find(|l| !l.is_empty())
                    .map_or(e, str::to_string);
                Err(format!("Valhalla exited with {}: {why}", out.status))
            }
            Err(e) => Err(e),
        }
    }
}

#[cfg(test)]
#[allow(clippy::unwrap_used, clippy::expect_used)]
mod tests {
    use super::*;

    const ROUTE: &str = include_str!("../tests/data/valhalla-3.9.1-route-auto.json");
    const ERROR_171: &str = include_str!("../tests/data/valhalla-3.9.1-error-171.json");

    #[test]
    fn polyline6() {
        // Google's example, at six decimal places.
        let p = decode_polyline6("_izlhA~rlgdF_{geC~ywl@_kwzCn`{nI").unwrap();
        let want = [(38.5, -120.2), (40.7, -120.95), (43.252, -126.453)];
        assert_eq!(p.len(), 3);
        for (got, want) in p.iter().zip(want) {
            assert!(
                (got.0 - want.0).abs() < 1e-9 && (got.1 - want.1).abs() < 1e-9,
                "{got:?}"
            );
        }
        assert!(decode_polyline6("_izlhA").is_err(), "a latitude alone");
        assert!(decode_polyline6("_izlh").is_err(), "cut mid-number");
        assert_eq!(decode_polyline6("").unwrap(), vec![]);
    }

    #[test]
    fn parses_a_real_route() {
        let r = parse_response(ROUTE, (39.8103, -98.5559), "auto").unwrap();
        assert_eq!(r.maneuvers.len(), 9);
        assert_eq!(r.maneuvers[3].instruction, "Turn right onto US 36/US 281.");
        assert_eq!(r.maneuvers[3].street_names, ["US 36", "US 281"]);
        assert_eq!(r.maneuvers[3].kind, 10);
        assert_eq!(r.maneuvers[8].kind, 4, "destination");
        assert!((r.length_m - 23_351.0).abs() < 0.5, "{}", r.length_m);
        assert!((r.time_s - 922.621).abs() < 1e-6);
        assert_eq!(
            r.shape.len(),
            149,
            "end_shape_index of the last maneuver + 1"
        );
        // The shape starts and ends at the requested points, near enough.
        assert!(distance_m(r.shape[0], (39.7792, -98.7851)) < 50.0);
        assert!(distance_m(*r.shape.last().unwrap(), (39.8103, -98.5559)) < 50.0);
        // Its length agrees with Valhalla's.
        assert!(
            (r.shape_length_m() - r.length_m).abs() < r.length_m * 0.01,
            "{}",
            r.shape_length_m()
        );
        // Maneuvers start in order along it.
        assert!(r.maneuvers.windows(2).all(|w| w[0].start_m <= w[1].start_m));
        assert_eq!(r.maneuvers[0].start_m, 0.0);
        assert!(!r.has_toll && !r.has_ferry);
    }

    #[test]
    fn errors_say_why() {
        assert_eq!(
            parse_response(ERROR_171, (0.0, 0.0), "auto").unwrap_err(),
            "Valhalla error 171: No suitable edges near location"
        );
        assert!(
            parse_response("", (0.0, 0.0), "auto")
                .unwrap_err()
                .contains("isn't JSON")
        );
        assert!(
            parse_response("{}", (0.0, 0.0), "auto")
                .unwrap_err()
                .contains("no trip")
        );
        let miles = ROUTE.replace("\"units\":\"kilometers\"", "\"units\":\"miles\"");
        assert!(
            parse_response(&miles, (0.0, 0.0), "auto")
                .unwrap_err()
                .contains("kilometres")
        );
    }

    #[test]
    fn request() {
        let mut r = RouteRequest {
            from: (39.7792, -98.7851),
            heading_deg: Some(359.7),
            to: (39.8103, -98.5559),
            costing: Costing::Auto,
        };
        let v: Value = serde_json::from_str(&request_json(&r)).unwrap();
        assert_eq!(v["costing"], "auto");
        assert_eq!(v["locations"][0]["heading"], 0);
        assert_eq!(v["locations"][0]["heading_tolerance"], 60);
        assert_eq!(v["locations"][1]["lat"], 39.8103);
        assert_eq!(v["directions_options"]["units"], "kilometers");
        assert!(v.get("costing_options").is_none());
        r.heading_deg = None;
        r.costing = Costing::Truck(TruckOptions {
            height_m: Some(3.0),
            ..TruckOptions::default()
        });
        let v: Value = serde_json::from_str(&request_json(&r)).unwrap();
        assert!(v["locations"][0].get("heading").is_none());
        assert_eq!(v["costing"], "truck");
        assert_eq!(v["costing_options"], json!({ "truck": { "height": 3.0 } }));
    }

    #[test]
    fn runtime_config() {
        let dir = std::env::temp_dir().join(format!("f250-nav-cfg-{}", std::process::id()));
        let out = dir.join("valhalla.json");
        let template = Path::new(env!("CARGO_MANIFEST_DIR")).join("valhalla/valhalla-3.9.1.json");
        write_runtime_config(&template, Path::new("/data/tiles.tar"), &out).unwrap();
        let v: Value = serde_json::from_str(&std::fs::read_to_string(&out).unwrap()).unwrap();
        assert_eq!(v["mjolnir"]["tile_extract"], "/data/tiles.tar");
        assert_eq!(v["mjolnir"]["tile_dir"], "");
        assert!(
            v["service_limits"]["auto"]["max_distance"]
                .as_f64()
                .unwrap()
                > 0.0
        );
        std::fs::remove_dir_all(dir).unwrap();
    }
}
