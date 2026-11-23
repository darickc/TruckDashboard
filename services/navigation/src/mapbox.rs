//! Mapbox's web APIs, used while there is a network (ADR-0052): routes from
//! the Directions API's `driving-traffic` profile, with Valhalla as the
//! fallback ([`OnlineFirst`]), and the online map's raster tiles from the
//! Static Tiles API ([`Tiles`]).
//!
//! Each request is one `curl` process ([`Curl`]), as each route is one
//! Valhalla process (ADR-0035): no TLS code here, and a hung request ends
//! with its process. The URL, which carries the token, goes to curl on its
//! standard input, never on its command line, and never into a log or an
//! error ([`redact`]).
//!
//! Test vectors: `tests/data/mapbox-directions-recorded.json` is a real
//! answer (`tools/dev/mapbox-record.sh`, 2026-11-23);
//! `mapbox-directions-handwritten.json` is **hand-written to Mapbox's
//! documented schema**, for what the recorded one lacks (a toll, a
//! motorway).

use std::collections::{HashMap, VecDeque};
use std::future::Future;
use std::path::PathBuf;
use std::process::Stdio;
use std::sync::{Arc, Mutex};
use std::time::Duration;

use serde_json::Value;
use tokio::io::AsyncWriteExt;
use tokio::sync::Semaphore;
use tokio::time::Instant;

use crate::valhalla::{
    Costing, LatLon, Maneuver, Route, RouteRequest, Router, Units, cumulative_m, decode_polyline6,
};

/// [`Route::provider`] for Mapbox's routes.
pub const PROVIDER: &str = "mapbox";

/// Mapbox's API host.
pub const API: &str = "https://api.mapbox.com";

/// Shown with the online map (ADR-0052 decision 7).
pub const ATTRIBUTION: &str = "© Mapbox © OpenStreetMap";

/// The online map's styles by default. The Static Tiles API's page names no
/// navigation styles; both answered with 512 px PNG tiles when checked by
/// hand (2026-11-23). Both are configuration.
pub const STYLE_DAY: &str = "mapbox/navigation-day-v1";
pub const STYLE_NIGHT: &str = "mapbox/navigation-night-v1";

/// The tiles asked for: 512 pixels, one zoom level behind 256-pixel tiles
/// (Static Tiles API).
pub const TILE_SIZE: u32 = 512;
pub const MAX_ZOOM: u32 = 22;

/// How far either side of the truck's course Mapbox may start, as Valhalla's
/// `heading_tolerance` (ADR-0035). Mapbox recommends 45 or 90.
const BEARING_RANGE_DEG: u32 = 60;

/// The token: systemd's credential `mapbox-token` in `credentials` (the
/// Pi: /etc/credstore/mapbox-token, imported by the unit), else `env`
/// (MAPBOX_ACCESS_TOKEN, for development). Empty: none.
pub fn token_from(credentials: Option<PathBuf>, env: Option<String>) -> String {
    credentials
        .and_then(|d| std::fs::read_to_string(d.join("mapbox-token")).ok())
        .map(|t| t.trim().to_string())
        .filter(|t| !t.is_empty())
        .or(env.map(|t| t.trim().to_string()))
        .unwrap_or_default()
}

/// One HTTP answer.
#[derive(Debug, Clone, PartialEq)]
pub struct Fetched {
    pub status: u16,
    pub content_type: String,
    pub body: Vec<u8>,
}

/// Fetches a URL. `Err` means no HTTP answer at all: no network, a name that
/// didn't resolve, a timeout. The error never contains the URL.
pub trait Fetch: Send + Sync + 'static {
    fn get(
        &self,
        url: &str,
        timeout: Duration,
    ) -> impl Future<Output = Result<Fetched, String>> + Send;
}

/// `curl`, one process per request.
#[derive(Debug, Clone)]
pub struct Curl {
    pub program: PathBuf,
}

impl Default for Curl {
    fn default() -> Self {
        Curl {
            program: PathBuf::from("curl"),
        }
    }
}

/// Removes the token from anything that might be logged.
pub fn redact(s: &str) -> String {
    let mut out = String::with_capacity(s.len());
    let mut rest = s;
    while let Some(i) = rest.find("access_token=") {
        let (head, tail) = rest.split_at(i + "access_token=".len());
        out.push_str(head);
        out.push_str("REDACTED");
        let end = tail
            .find(|c: char| c == '&' || c == '"' || c.is_whitespace())
            .unwrap_or(tail.len());
        rest = &tail[end..];
    }
    out.push_str(rest);
    out
}

/// curl's config for one request, read from its standard input: the URL is
/// never on a command line other users could read. Its write-out puts the
/// status and the content type on the last line of standard error.
pub fn curl_config(url: &str, timeout: Duration) -> String {
    let quoted = url.replace('\\', "\\\\").replace('"', "\\\"");
    let total = timeout.as_secs_f64().max(1.0);
    format!(
        "url = \"{quoted}\"\n\
         silent\n\
         show-error\n\
         max-time = {total:.1}\n\
         connect-timeout = {:.1}\n\
         write-out = \"%{{stderr}}\\n%{{http_code}} %{{content_type}}\\n\"\n",
        (total / 2.0).min(5.0),
    )
}

/// curl's outcome: its exit code, the body and standard error, whose last
/// line is the write-out.
pub fn parse_curl_output(
    code: Option<i32>,
    stdout: &[u8],
    stderr: &[u8],
) -> Result<Fetched, String> {
    let err = String::from_utf8_lossy(stderr);
    let mut lines = err.lines().map(str::trim).filter(|l| !l.is_empty());
    let last = lines.next_back().unwrap_or("");
    if code != Some(0) {
        // curl's own message ("curl: (6) Could not resolve host: …") is
        // before the write-out line.
        let why = err
            .lines()
            .map(str::trim)
            .find(|l| l.starts_with("curl:"))
            .map(str::to_string)
            .unwrap_or_else(|| match code {
                Some(c) => format!("curl exited with {c}"),
                None => "curl was killed".to_string(),
            });
        return Err(redact(&why));
    }
    let (status, content_type) = last.split_once(' ').unwrap_or((last, ""));
    let status: u16 = status
        .parse()
        .map_err(|_| format!("curl's write-out wasn't a status: {}", redact(last)))?;
    if status == 0 {
        return Err("no HTTP answer".to_string());
    }
    Ok(Fetched {
        status,
        content_type: content_type.trim().to_string(),
        body: stdout.to_vec(),
    })
}

impl Fetch for Curl {
    async fn get(&self, url: &str, timeout: Duration) -> Result<Fetched, String> {
        let mut child = tokio::process::Command::new(&self.program)
            .args(["--config", "-"])
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .kill_on_drop(true)
            .spawn()
            .map_err(|e| format!("can't start {}: {e}", self.program.display()))?;
        if let Some(mut stdin) = child.stdin.take() {
            stdin
                .write_all(curl_config(url, timeout).as_bytes())
                .await
                .map_err(|e| format!("curl's input: {e}"))?;
        }
        let out = tokio::time::timeout(timeout + Duration::from_secs(2), child.wait_with_output())
            .await
            .map_err(|_| format!("no answer within {} s", timeout.as_secs()))?
            .map_err(|e| format!("curl: {e}"))?;
        parse_curl_output(out.status.code(), &out.stdout, &out.stderr)
    }
}

/// Why Mapbox gave no route.
#[derive(Debug, Clone, PartialEq)]
pub enum Failure {
    /// Mapbox answered: there is no route ("NoRoute", "NoSegment"). The
    /// network is fine.
    NoRoute(String),
    /// No usable answer: no network, a timeout, a refused token, a server
    /// error. Mapbox is skipped for a while after one.
    Unreachable(String),
}

impl Failure {
    pub fn why(&self) -> &str {
        match self {
            Failure::NoRoute(w) | Failure::Unreachable(w) => w,
        }
    }
}

/// The Directions request for `req`.
pub fn directions_url(api: &str, token: &str, req: &RouteRequest) -> String {
    let mut url = format!(
        "{api}/directions/v5/mapbox/driving-traffic/{:.6},{:.6};{:.6},{:.6}\
         ?access_token={token}&geometries=polyline6&overview=full&steps=true\
         &voice_instructions=true&voice_units={}&language=en&alternatives=false",
        req.from.1,
        req.from.0,
        req.to.1,
        req.to.0,
        match req.units {
            Units::Imperial => "imperial",
            Units::Metric => "metric",
        },
    );
    if let Some(h) = req.heading_deg {
        let h = h.rem_euclid(360.0).round() as u32 % 360;
        // One entry per coordinate; the destination's left empty.
        url.push_str(&format!("&bearings={h},{BEARING_RANGE_DEG};"));
    }
    if let Costing::Truck(t) = &req.costing {
        for (k, v) in [
            ("max_height", t.height_m),
            ("max_width", t.width_m),
            ("max_weight", t.weight_t),
        ] {
            if let Some(v) = v {
                url.push_str(&format!("&{k}={v}"));
            }
        }
    }
    url
}

/// Mapbox's maneuver as Valhalla's type number (odin's
/// DirectionsLeg_Maneuver_Type), which the dashboard and the knob draw
/// (`maneuverIcon`, knob-link's pages).
pub fn maneuver_kind(kind: &str, modifier: &str, mode: &str) -> u32 {
    let right = modifier.contains("right");
    let left = modifier.contains("left");
    if mode == "ferry" {
        return 28; // ferry enter
    }
    match kind {
        "depart" if right => 2,
        "depart" if left => 3,
        "depart" => 1,
        "arrive" if right => 5,
        "arrive" if left => 6,
        "arrive" => 4,
        "merge" if right => 37,
        "merge" if left => 38,
        "merge" => 25,
        "on ramp" if right => 18,
        "on ramp" if left => 19,
        "on ramp" => 17,
        "off ramp" if right => 20,
        "off ramp" if left => 21,
        "off ramp" => 17,
        "fork" if right => 23,
        "fork" if left => 24,
        "fork" => 22,
        "roundabout" | "rotary" | "roundabout turn" => 26,
        "exit roundabout" | "exit rotary" => 27,
        "new name" => 7,
        "notification" => 8,
        // turn, end of road, continue, and any type added later.
        _ => match modifier {
            "uturn" => 13,
            "sharp right" => 11,
            "right" => 10,
            "slight right" => 9,
            "slight left" => 16,
            "left" => 15,
            "sharp left" => 14,
            _ => 8,
        },
    }
}

/// A step's spoken announcements, by `distanceAlongGeometry` (metres before
/// the next step's maneuver), farthest first.
fn announcements(step: &Value) -> Vec<(f64, String)> {
    let mut v: Vec<(f64, String)> = step
        .get("voiceInstructions")
        .and_then(Value::as_array)
        .map(|a| {
            a.iter()
                .filter_map(|vi| {
                    let text = vi.get("announcement")?.as_str()?.trim();
                    (!text.is_empty()).then(|| {
                        (
                            vi.get("distanceAlongGeometry")
                                .and_then(Value::as_f64)
                                .unwrap_or(0.0),
                            text.to_string(),
                        )
                    })
                })
                .collect()
        })
        .unwrap_or_default();
    v.sort_by(|a, b| b.0.total_cmp(&a.0));
    v
}

/// Parses a Directions answer into the guide's [`Route`] (ADR-0052 decision
/// 5). `status` is the HTTP status.
pub fn parse_directions(
    status: u16,
    text: &str,
    destination: LatLon,
    costing: &str,
) -> Result<Route, Failure> {
    let v: Value = serde_json::from_str(text.trim()).map_err(|e| {
        Failure::Unreachable(format!("Mapbox's answer (HTTP {status}) isn't JSON ({e})"))
    })?;
    let code = v.get("code").and_then(Value::as_str).unwrap_or("");
    let message = v.get("message").and_then(Value::as_str).unwrap_or("");
    let said = |what: &str| {
        let mut s = format!("Mapbox {what}");
        if !message.is_empty() {
            s.push_str(": ");
            s.push_str(message);
        }
        redact(&s)
    };
    if matches!(code, "NoRoute" | "NoSegment") {
        return Err(Failure::NoRoute(said(code)));
    }
    if status != 200 || code != "Ok" {
        let what = if code.is_empty() {
            format!("HTTP {status}")
        } else {
            format!("HTTP {status} {code}")
        };
        return Err(Failure::Unreachable(said(&what)));
    }
    let bad = |why: &str| Failure::Unreachable(format!("Mapbox's answer: {why}"));
    let route = v
        .get("routes")
        .and_then(Value::as_array)
        .and_then(|r| r.first())
        .ok_or_else(|| bad("no routes"))?;
    let legs = route
        .get("legs")
        .and_then(Value::as_array)
        .ok_or_else(|| bad("no legs"))?;
    let [leg] = legs.as_slice() else {
        return Err(bad(&format!("expected one leg, got {}", legs.len())));
    };
    let steps = leg
        .get("steps")
        .and_then(Value::as_array)
        .filter(|s| !s.is_empty())
        .ok_or_else(|| bad("no steps"))?;

    // The line: the steps' geometries joined, each step starting where the
    // last ended.
    let mut shape: Vec<LatLon> = Vec::new();
    let mut begins = Vec::with_capacity(steps.len());
    for step in steps {
        let points = decode_polyline6(
            step.get("geometry")
                .and_then(Value::as_str)
                .ok_or_else(|| bad("a step has no polyline6 geometry"))?,
        )
        .map_err(|e| bad(&e))?;
        // A step starts at the last step's end; the arrive step's line is
        // that one point twice. Repeated points are kept once.
        begins.push(match (shape.last(), points.first()) {
            (Some(last), Some(first)) if last == first => shape.len() - 1,
            _ => shape.len(),
        });
        for p in points {
            if shape.last() != Some(&p) {
                shape.push(p);
            }
        }
    }
    if shape.len() < 2 {
        return Err(bad("the route's line has fewer than two points"));
    }
    let along_m = cumulative_m(&shape);

    let (mut toll, mut highway, mut ferry) = (false, false, false);
    let mut maneuvers = Vec::with_capacity(steps.len());
    for (i, step) in steps.iter().enumerate() {
        let m = step
            .get("maneuver")
            .ok_or_else(|| bad("a step has no maneuver"))?;
        let s = |v: &Value, k: &str| v.get(k).and_then(Value::as_str).unwrap_or("").to_string();
        let mode = s(step, "mode");
        ferry |= mode == "ferry";
        for x in step
            .get("intersections")
            .and_then(Value::as_array)
            .into_iter()
            .flatten()
        {
            for c in x
                .get("classes")
                .and_then(Value::as_array)
                .into_iter()
                .flatten()
                .filter_map(Value::as_str)
            {
                toll |= c == "toll";
                highway |= c == "motorway";
                ferry |= c == "ferry";
            }
        }
        let instruction = s(m, "instruction");
        let mut street_names: Vec<String> = s(step, "ref")
            .split(';')
            .map(str::trim)
            .filter(|r| !r.is_empty())
            .map(str::to_string)
            .collect();
        let name = s(step, "name");
        if !name.trim().is_empty() && !street_names.contains(&name) {
            street_names.push(name.trim().to_string());
        }
        // The at-the-maneuver words: the previous step's last announcement
        // (it announces this step's maneuver). The first maneuver has none
        // before it: its own first announcement, what Mapbox says on
        // setting off.
        let pre = if i == 0 {
            announcements(step).into_iter().next()
        } else {
            announcements(&steps[i - 1]).into_iter().last()
        }
        .map(|(_, t)| t)
        .unwrap_or_default();
        let begin = begins[i];
        maneuvers.push(Maneuver {
            kind: maneuver_kind(&s(m, "type"), &s(m, "modifier"), &mode),
            instruction,
            street_names,
            length_m: step.get("distance").and_then(Value::as_f64).unwrap_or(0.0),
            time_s: step.get("duration").and_then(Value::as_f64).unwrap_or(0.0),
            begin_shape_index: begin,
            start_m: along_m[begin],
            // The approaching prompt ("In half a mile, …") takes the same
            // words: Mapbox's announcements are written for speech ("U.S.
            // Highway 2 81"), its instructions for the eye ("US Highway
            // 281/US 281. Continue on US 281."; recorded 2026-11-23).
            verbal_alert: String::new(),
            verbal_pre: pre,
            // Mapbox has no "continue for" words; the voice says its own.
            verbal_post: String::new(),
            verbal_multi_cue: false,
        });
    }
    Ok(Route {
        id: 0,
        shape,
        along_m,
        maneuvers,
        length_m: route.get("distance").and_then(Value::as_f64).unwrap_or(0.0),
        time_s: route.get("duration").and_then(Value::as_f64).unwrap_or(0.0),
        destination,
        costing: costing.to_string(),
        has_toll: toll,
        has_highway: highway,
        has_ferry: ferry,
        provider: PROVIDER,
    })
}

/// What [`OnlineFirst`] and [`Tiles`] share: the token and whether Mapbox
/// is being skipped after a failure.
pub struct Mapbox<F: Fetch> {
    fetch: F,
    token: String,
    pub api: String,
    pub route_timeout: Duration,
    pub tile_timeout: Duration,
    /// Mapbox is skipped this long after a failure that wasn't the route
    /// itself (ADR-0052 decision 3). An example.
    pub skip_after_failure: Duration,
    skip_until: Mutex<Option<Instant>>,
}

impl<F: Fetch> Mapbox<F> {
    /// `None` without a token: nothing goes to Mapbox.
    pub fn new(fetch: F, token: &str) -> Option<Self> {
        let token = token.trim();
        if token.is_empty() {
            return None;
        }
        Some(Mapbox {
            fetch,
            token: token.to_string(),
            api: API.to_string(),
            route_timeout: Duration::from_secs(10),
            tile_timeout: Duration::from_secs(8),
            skip_after_failure: Duration::from_secs(60),
            skip_until: Mutex::new(None),
        })
    }

    /// Routes go to Mapbox now (not skipped after a failure).
    pub fn routing_online(&self) -> bool {
        self.skip_until
            .lock()
            .map(|g| g.is_none_or(|t| Instant::now() >= t))
            .unwrap_or(true)
    }

    fn skip(&self) {
        if let Ok(mut g) = self.skip_until.lock() {
            *g = Some(Instant::now() + self.skip_after_failure);
        }
    }

    pub async fn route(&self, req: &RouteRequest) -> Result<Route, Failure> {
        let url = directions_url(&self.api, &self.token, req);
        let answer = self
            .fetch
            .get(&url, self.route_timeout)
            .await
            .map_err(|e| Failure::Unreachable(format!("Mapbox unreachable: {}", redact(&e))))?;
        let text = String::from_utf8_lossy(&answer.body);
        parse_directions(answer.status, &text, req.to, req.costing.name())
    }

    async fn tile(&self, style: &str, z: u32, x: u32, y: u32) -> Result<Fetched, String> {
        let url = format!(
            "{}/styles/v1/{style}/tiles/{TILE_SIZE}/{z}/{x}/{y}?access_token={}",
            self.api, self.token
        );
        let a = self
            .fetch
            .get(&url, self.tile_timeout)
            .await
            .map_err(|e| format!("Mapbox unreachable: {}", redact(&e)))?;
        if a.status != 200 {
            let msg = serde_json::from_slice::<Value>(&a.body)
                .ok()
                .and_then(|v| v.get("message").and_then(Value::as_str).map(str::to_string))
                .unwrap_or_default();
            return Err(redact(
                format!("Mapbox tile HTTP {} {msg}", a.status).trim(),
            ));
        }
        if !a.content_type.starts_with("image/") {
            return Err(format!("Mapbox sent {} for a tile", a.content_type));
        }
        Ok(a)
    }
}

/// Routes from Mapbox while it answers, else from `offline` (Valhalla).
pub struct OnlineFirst<R: Router, F: Fetch> {
    pub mapbox: Option<Arc<Mapbox<F>>>,
    pub offline: R,
}

impl<R: Router, F: Fetch> Router for OnlineFirst<R, F> {
    fn check(&self) -> Result<(), String> {
        match (&self.mapbox, self.offline.check()) {
            (_, Ok(())) => Ok(()),
            // Online-only routing: a route still fails without a network,
            // and says why.
            (Some(_), Err(_)) => Ok(()),
            (None, Err(e)) => Err(e),
        }
    }

    async fn route(&self, req: RouteRequest) -> Result<Route, String> {
        let mut online_why = None;
        if let Some(m) = self.mapbox.as_ref().filter(|m| m.routing_online()) {
            match m.route(&req).await {
                Ok(r) => return Ok(r),
                Err(f) => {
                    eprintln!("[navigation] {}; routing offline", f.why());
                    if matches!(f, Failure::Unreachable(_)) {
                        m.skip();
                    }
                    online_why = Some(f.why().to_string());
                }
            }
        }
        match (self.offline.route(req).await, online_why) {
            (Ok(r), _) => Ok(r),
            (Err(e), Some(o)) => Err(format!("{o}; offline: {e}")),
            (Err(e), None) => Err(e),
        }
    }
}

/// The online map's tiles: fetched from Mapbox, kept in memory for at most
/// Mapbox's 12 h (`max-age=43200`), at most `capacity` of them, a few
/// fetched at once.
pub struct Tiles<F: Fetch> {
    mapbox: Option<Arc<Mapbox<F>>>,
    pub style_day: String,
    pub style_night: String,
    cache: Mutex<TileCache>,
    fetching: Semaphore,
}

/// Mapbox's `max-age` for Static Tiles.
pub const TILE_MAX_AGE: Duration = Duration::from_secs(43_200);

/// A tile: night or day, z, x, y.
type TileKey = (bool, u32, u32, u32);

#[derive(Default)]
struct TileCache {
    tiles: HashMap<TileKey, (Instant, Arc<Fetched>)>,
    order: VecDeque<TileKey>,
}

impl<F: Fetch> Tiles<F> {
    pub fn new(mapbox: Option<Arc<Mapbox<F>>>, style_day: &str, style_night: &str) -> Self {
        Tiles {
            mapbox,
            style_day: style_day.to_string(),
            style_night: style_night.to_string(),
            cache: Mutex::new(TileCache::default()),
            fetching: Semaphore::new(6),
        }
    }

    pub const CAPACITY: usize = 300;

    pub fn configured(&self) -> bool {
        self.mapbox.is_some()
    }

    pub fn routing_online(&self) -> bool {
        self.mapbox.as_ref().is_some_and(|m| m.routing_online())
    }

    fn cached(&self, key: TileKey) -> Option<Arc<Fetched>> {
        let c = self.cache.lock().ok()?;
        let (at, t) = c.tiles.get(&key)?;
        (at.elapsed() < TILE_MAX_AGE).then(|| t.clone())
    }

    fn keep(&self, key: TileKey, t: Arc<Fetched>) {
        let Ok(mut c) = self.cache.lock() else { return };
        if c.tiles.insert(key, (Instant::now(), t)).is_none() {
            c.order.push_back(key);
        }
        while c.tiles.len() > Self::CAPACITY {
            match c.order.pop_front() {
                Some(old) => {
                    c.tiles.remove(&old);
                }
                None => break,
            }
        }
    }

    /// One tile. `Err(None)`: no token. `Err(Some(why))`: Mapbox didn't
    /// give it.
    pub async fn get(
        &self,
        night: bool,
        z: u32,
        x: u32,
        y: u32,
    ) -> Result<Arc<Fetched>, Option<String>> {
        let m = self.mapbox.as_ref().ok_or(None)?;
        let key = (night, z, x, y);
        if let Some(t) = self.cached(key) {
            return Ok(t);
        }
        let _permit = self
            .fetching
            .acquire()
            .await
            .map_err(|e| Some(e.to_string()))?;
        if let Some(t) = self.cached(key) {
            return Ok(t);
        }
        let style = if night {
            &self.style_night
        } else {
            &self.style_day
        };
        let t = Arc::new(m.tile(style, z, x, y).await.map_err(Some)?);
        self.keep(key, t.clone());
        Ok(t)
    }
}

#[cfg(test)]
#[allow(clippy::unwrap_used, clippy::expect_used)]
mod tests {
    use super::*;
    use crate::valhalla::TruckOptions;
    use std::sync::atomic::{AtomicUsize, Ordering};

    const ROUTE: &str = include_str!("../tests/data/mapbox-directions-handwritten.json");
    const DEST: LatLon = (39.8103, -98.5559);

    fn req(heading: Option<f64>, costing: Costing) -> RouteRequest {
        RouteRequest {
            from: (39.80, -98.60),
            heading_deg: heading,
            to: DEST,
            costing,
            units: Units::Imperial,
        }
    }

    #[test]
    fn the_request_asks_for_traffic_steps_and_words() {
        let u = directions_url(API, "pk.TOKEN", &req(None, Costing::Auto));
        assert!(u.starts_with(
            "https://api.mapbox.com/directions/v5/mapbox/driving-traffic/-98.600000,39.800000;-98.555900,39.810300?"
        ));
        for p in [
            "access_token=pk.TOKEN",
            "geometries=polyline6",
            "overview=full",
            "steps=true",
            "voice_instructions=true",
            "voice_units=imperial",
            "language=en",
        ] {
            assert!(u.contains(p), "{p} in {u}");
        }
        assert!(!u.contains("bearings"));
        assert!(!u.contains("max_"));
    }

    #[test]
    fn a_course_constrains_only_the_start() {
        let u = directions_url(API, "t", &req(Some(-90.4), Costing::Auto));
        assert!(u.ends_with("&bearings=270,60;"), "{u}");
    }

    #[test]
    fn truck_costing_sends_only_the_configured_limits() {
        let truck = Costing::Truck(TruckOptions {
            height_m: Some(2.1),
            weight_t: Some(4.5),
            axle_load_t: Some(3.0),
            ..TruckOptions::default()
        });
        let u = directions_url(API, "t", &req(None, truck));
        assert!(u.contains("&max_height=2.1"));
        assert!(u.contains("&max_weight=4.5"));
        assert!(!u.contains("max_width"));
        assert!(!u.contains("axle"), "Mapbox has no axle load");
    }

    #[test]
    fn every_maneuver_type_maps_to_an_icon_number() {
        let cases = [
            ("depart", "", 1),
            ("depart", "right", 2),
            ("depart", "left", 3),
            ("arrive", "", 4),
            ("arrive", "right", 5),
            ("arrive", "left", 6),
            ("new name", "straight", 7),
            ("continue", "straight", 8),
            ("turn", "slight right", 9),
            ("turn", "right", 10),
            ("turn", "sharp right", 11),
            ("turn", "uturn", 13),
            ("turn", "sharp left", 14),
            ("end of road", "left", 15),
            ("turn", "slight left", 16),
            ("on ramp", "straight", 17),
            ("on ramp", "slight right", 18),
            ("on ramp", "left", 19),
            ("off ramp", "slight right", 20),
            ("off ramp", "slight left", 21),
            ("off ramp", "straight", 17),
            ("fork", "straight", 22),
            ("fork", "slight right", 23),
            ("fork", "slight left", 24),
            ("merge", "straight", 25),
            ("roundabout", "right", 26),
            ("rotary", "left", 26),
            ("roundabout turn", "right", 26),
            ("exit roundabout", "right", 27),
            ("exit rotary", "", 27),
            ("merge", "slight right", 37),
            ("merge", "slight left", 38),
            ("notification", "", 8),
            ("a type added later", "left", 15),
        ];
        for (kind, modifier, want) in cases {
            assert_eq!(
                maneuver_kind(kind, modifier, "driving"),
                want,
                "{kind} {modifier}"
            );
        }
        assert_eq!(maneuver_kind("turn", "right", "ferry"), 28);
    }

    #[test]
    fn reads_the_handwritten_answer() {
        let r = parse_directions(200, ROUTE, DEST, "auto").unwrap();
        assert_eq!(r.provider, PROVIDER);
        assert_eq!(r.maneuvers.len(), 3);
        // The steps' lines joined, the shared points once.
        assert_eq!(r.shape.len(), 4);
        assert_eq!(r.shape[0], (39.8, -98.6));
        assert_eq!(*r.shape.last().unwrap(), DEST);
        let begins: Vec<usize> = r.maneuvers.iter().map(|m| m.begin_shape_index).collect();
        assert_eq!(begins, [0, 2, 3]);
        assert_eq!(r.maneuvers[1].start_m, r.along_m[2]);
        assert_eq!(r.length_m, 4200.5);
        assert_eq!(r.time_s, 301.2);
        let m = &r.maneuvers[1];
        assert_eq!(m.kind, 10);
        assert_eq!(m.instruction, "Turn right onto US 281.");
        assert_eq!(m.street_names, ["US 281", "North Street"]);
        assert_eq!(
            m.verbal_alert, "",
            "the voice uses verbal_pre for both prompts"
        );
        // The previous step's nearest announcement.
        assert_eq!(m.verbal_pre, "Turn right onto US 281.");
        assert_eq!(m.verbal_post, "");
        assert_eq!(r.maneuvers[0].kind, 1);
        assert_eq!(
            r.maneuvers[0].verbal_pre,
            "Drive east on Main Street. Then, in 2 miles, turn right onto US 281."
        );
        assert_eq!(r.maneuvers[2].kind, 4);
        assert_eq!(
            r.maneuvers[2].verbal_pre,
            "You have arrived at your destination."
        );
        assert!(r.has_toll);
        assert!(r.has_highway);
        assert!(!r.has_ferry);
    }

    /// A real answer, recorded with tools/dev/mapbox-record.sh on
    /// 2026-11-23: from near Lebanon, Kansas to the destination the
    /// simulator uses.
    const RECORDED: &str = include_str!("../tests/data/mapbox-directions-recorded.json");

    #[test]
    fn reads_a_recorded_answer() {
        let r = parse_directions(200, RECORDED, DEST, "auto").unwrap();
        assert_eq!(r.provider, PROVIDER);
        let kinds: Vec<u32> = r.maneuvers.iter().map(|m| m.kind).collect();
        // depart, left onto US 281, right onto Chicago Avenue, left, arrive
        // on the left.
        assert_eq!(kinds, [1, 15, 10, 15, 6]);
        assert_eq!(r.length_m, 5015.337);
        assert_eq!(r.time_s, 326.566);
        // The joined steps are the route: their length agrees with
        // Mapbox's within 1 %.
        assert!(
            (r.shape_length_m() - r.length_m).abs() < r.length_m * 0.01,
            "{} m drawn, {} m said",
            r.shape_length_m(),
            r.length_m
        );
        // Each maneuver starts where Mapbox says, in order, and the last at
        // the end of the line.
        for w in r.maneuvers.windows(2) {
            assert!(w[0].begin_shape_index < w[1].begin_shape_index);
        }
        assert_eq!(r.maneuvers[4].begin_shape_index, r.shape.len() - 1);
        for (w, len) in r
            .maneuvers
            .windows(2)
            .zip([3376.238, 1193.251, 395.549, 50.299])
        {
            let drawn = w[1].start_m - w[0].start_m;
            assert!((drawn - len).abs() < len * 0.02 + 2.0, "{drawn} vs {len}");
        }
        let left = &r.maneuvers[1];
        assert_eq!(left.street_names, ["US 281", "US Highway 281"]);
        assert_eq!(
            left.verbal_pre,
            "Turn left onto U.S. Highway 2 81, U.S. 2 81."
        );
        assert_eq!(
            r.maneuvers[0].verbal_pre,
            "Drive east on 1 50 Road for 2 miles."
        );
        assert_eq!(
            r.maneuvers[4].verbal_pre,
            "Your destination is on the left."
        );
        assert!(!r.has_toll && !r.has_highway && !r.has_ferry);
    }

    #[test]
    fn no_route_is_the_route_not_the_network() {
        let e = parse_directions(
            200,
            r#"{"code":"NoRoute","message":"No route found"}"#,
            DEST,
            "auto",
        )
        .unwrap_err();
        assert_eq!(e, Failure::NoRoute("Mapbox NoRoute: No route found".into()));
        let e = parse_directions(200, r#"{"code":"NoSegment"}"#, DEST, "auto").unwrap_err();
        assert!(matches!(e, Failure::NoRoute(_)));
    }

    #[test]
    fn a_refused_token_or_a_server_error_is_unreachable() {
        let e = parse_directions(
            401,
            r#"{"message":"Not Authorized - Invalid Token"}"#,
            DEST,
            "auto",
        )
        .unwrap_err();
        assert_eq!(
            e,
            Failure::Unreachable("Mapbox HTTP 401: Not Authorized - Invalid Token".into())
        );
        let e = parse_directions(502, "<html>bad gateway</html>", DEST, "auto").unwrap_err();
        assert!(matches!(e, Failure::Unreachable(w) if w.contains("HTTP 502")));
        let e = parse_directions(200, r#"{"code":"Ok","routes":[]}"#, DEST, "auto").unwrap_err();
        assert!(matches!(e, Failure::Unreachable(w) if w.contains("no routes")));
    }

    #[test]
    fn the_token_from_the_credential_first() {
        let dir = std::env::temp_dir().join(format!("f250-mapbox-cred-{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        assert_eq!(
            token_from(Some(dir.clone()), Some("pk.ENV".into())),
            "pk.ENV"
        );
        std::fs::write(dir.join("mapbox-token"), "pk.CRED\n").unwrap();
        assert_eq!(
            token_from(Some(dir.clone()), Some("pk.ENV".into())),
            "pk.CRED"
        );
        std::fs::write(dir.join("mapbox-token"), "  \n").unwrap();
        assert_eq!(token_from(Some(dir), None), "");
        assert_eq!(token_from(None, None), "");
    }

    #[test]
    fn the_token_never_reaches_a_message() {
        assert_eq!(
            redact("GET https://x/y?access_token=pk.abc123&steps=true failed"),
            "GET https://x/y?access_token=REDACTED&steps=true failed"
        );
        assert_eq!(redact("access_token=sk.zz"), "access_token=REDACTED");
        assert_eq!(redact("nothing"), "nothing");
    }

    #[test]
    fn curl_reads_its_url_from_its_input() {
        let c = curl_config(
            "https://a/b?access_token=x&y=\"z\"",
            Duration::from_secs(10),
        );
        assert!(c.starts_with("url = \"https://a/b?access_token=x&y=\\\"z\\\"\"\n"));
        assert!(c.contains("max-time = 10.0\n"));
        assert!(c.contains("connect-timeout = 5.0\n"));
        assert!(c.contains("write-out = \"%{stderr}\\n%{http_code} %{content_type}\\n\"\n"));
    }

    #[test]
    fn curls_outcome() {
        let ok = parse_curl_output(Some(0), b"PNG", b"\n200 image/png\n").unwrap();
        assert_eq!(ok.status, 200);
        assert_eq!(ok.content_type, "image/png");
        assert_eq!(ok.body, b"PNG");
        let no_type = parse_curl_output(Some(0), b"{}", b"\n401 \n").unwrap();
        assert_eq!((no_type.status, no_type.content_type.as_str()), (401, ""));
        let e = parse_curl_output(
            Some(6),
            b"",
            b"curl: (6) Could not resolve host: api.mapbox.com\n\n000 \n",
        )
        .unwrap_err();
        assert_eq!(e, "curl: (6) Could not resolve host: api.mapbox.com");
        assert_eq!(
            parse_curl_output(None, b"", b"").unwrap_err(),
            "curl was killed"
        );
    }

    /// Answers every request with the next of `answers`, counting them.
    struct Script {
        answers: Mutex<VecDeque<Result<Fetched, String>>>,
        asked: AtomicUsize,
        urls: Mutex<Vec<String>>,
    }

    impl Script {
        fn new(answers: Vec<Result<Fetched, String>>) -> Self {
            Script {
                answers: Mutex::new(answers.into()),
                asked: AtomicUsize::new(0),
                urls: Mutex::new(Vec::new()),
            }
        }
    }

    impl Fetch for Arc<Script> {
        async fn get(&self, url: &str, _: Duration) -> Result<Fetched, String> {
            self.asked.fetch_add(1, Ordering::SeqCst);
            self.urls.lock().unwrap().push(url.to_string());
            self.answers
                .lock()
                .unwrap()
                .pop_front()
                .unwrap_or_else(|| Err("no more answers".into()))
        }
    }

    fn ok_json(s: &str) -> Result<Fetched, String> {
        Ok(Fetched {
            status: 200,
            content_type: "application/json".into(),
            body: s.as_bytes().to_vec(),
        })
    }

    /// Valhalla, as a fake: a route marked as Valhalla's, or an error.
    struct Offline(Result<(), String>);

    impl Router for Offline {
        fn check(&self) -> Result<(), String> {
            self.0.clone()
        }
        async fn route(&self, req: RouteRequest) -> Result<Route, String> {
            self.0.clone()?;
            let mut r = parse_directions(200, ROUTE, req.to, "auto").unwrap();
            r.provider = crate::valhalla::PROVIDER;
            Ok(r)
        }
    }

    #[test]
    fn no_token_no_mapbox() {
        assert!(Mapbox::new(Arc::new(Script::new(vec![])), "  ").is_none());
    }

    #[tokio::test(start_paused = true)]
    async fn mapbox_first_then_valhalla_then_mapbox_again() {
        let script = Arc::new(Script::new(vec![
            ok_json(ROUTE),
            Err("curl: (6) Could not resolve host: api.mapbox.com".into()),
            ok_json(ROUTE),
        ]));
        let m = Arc::new(Mapbox::new(script.clone(), "pk.T").unwrap());
        let r = OnlineFirst {
            mapbox: Some(m.clone()),
            offline: Offline(Ok(())),
        };
        let req = || req(None, Costing::Auto);
        assert_eq!(r.route(req()).await.unwrap().provider, PROVIDER);
        // No network: Valhalla at once, and Mapbox is skipped for a while.
        assert_eq!(r.route(req()).await.unwrap().provider, "valhalla");
        assert!(!m.routing_online());
        assert_eq!(r.route(req()).await.unwrap().provider, "valhalla");
        assert_eq!(script.asked.load(Ordering::SeqCst), 2, "skipped, not asked");
        tokio::time::advance(Duration::from_secs(61)).await;
        assert!(m.routing_online());
        assert_eq!(r.route(req()).await.unwrap().provider, PROVIDER);
        assert!(
            script
                .urls
                .lock()
                .unwrap()
                .iter()
                .all(|u| u.contains("driving-traffic")),
        );
    }

    #[tokio::test(start_paused = true)]
    async fn no_route_falls_back_without_skipping_mapbox() {
        let script = Arc::new(Script::new(vec![ok_json(r#"{"code":"NoRoute"}"#)]));
        let m = Arc::new(Mapbox::new(script, "pk.T").unwrap());
        let r = OnlineFirst {
            mapbox: Some(m.clone()),
            offline: Offline(Ok(())),
        };
        assert_eq!(
            r.route(req(None, Costing::Auto)).await.unwrap().provider,
            "valhalla"
        );
        assert!(m.routing_online());
    }

    #[tokio::test(start_paused = true)]
    async fn both_failing_says_both() {
        let script = Arc::new(Script::new(vec![Err("curl: (7) Failed to connect".into())]));
        let r = OnlineFirst {
            mapbox: Some(Arc::new(Mapbox::new(script, "pk.T").unwrap())),
            offline: Offline(Err("no routing data".into())),
        };
        assert!(r.check().is_ok(), "online-only routing is available");
        assert_eq!(
            r.route(req(None, Costing::Auto)).await.unwrap_err(),
            "Mapbox unreachable: curl: (7) Failed to connect; offline: no routing data"
        );
        let offline_only: OnlineFirst<Offline, Arc<Script>> = OnlineFirst {
            mapbox: None,
            offline: Offline(Err("no routing data".into())),
        };
        assert_eq!(offline_only.check().unwrap_err(), "no routing data");
    }

    fn png() -> Result<Fetched, String> {
        Ok(Fetched {
            status: 200,
            content_type: "image/png".into(),
            body: b"\x89PNG".to_vec(),
        })
    }

    #[tokio::test(start_paused = true)]
    async fn tiles_are_kept_for_mapboxs_twelve_hours() {
        let script = Arc::new(Script::new(vec![png(), png(), png()]));
        let m = Arc::new(Mapbox::new(script.clone(), "pk.T").unwrap());
        let t = Tiles::new(Some(m), STYLE_DAY, STYLE_NIGHT);
        t.get(false, 15, 1, 2).await.unwrap();
        t.get(false, 15, 1, 2).await.unwrap();
        assert_eq!(script.asked.load(Ordering::SeqCst), 1);
        // Night is another style.
        t.get(true, 15, 1, 2).await.unwrap();
        assert_eq!(script.asked.load(Ordering::SeqCst), 2);
        let urls = script.urls.lock().unwrap().clone();
        assert_eq!(
            urls[0],
            "https://api.mapbox.com/styles/v1/mapbox/navigation-day-v1/tiles/512/15/1/2?access_token=pk.T"
        );
        assert!(urls[1].contains("/navigation-night-v1/"));
        tokio::time::advance(TILE_MAX_AGE).await;
        t.get(false, 15, 1, 2).await.unwrap();
        assert_eq!(script.asked.load(Ordering::SeqCst), 3, "older than max-age");
    }

    #[tokio::test(start_paused = true)]
    async fn tile_failures_say_why_without_the_token() {
        let script = Arc::new(Script::new(vec![
            Ok(Fetched {
                status: 401,
                content_type: "application/json".into(),
                body: br#"{"message":"Not Authorized - Invalid Token"}"#.to_vec(),
            }),
            ok_json("{}"),
            Err("curl: (28) Operation timed out".into()),
        ]));
        let t = Tiles::new(
            Some(Arc::new(Mapbox::new(script, "pk.SECRET").unwrap())),
            STYLE_DAY,
            STYLE_NIGHT,
        );
        let e = t.get(false, 1, 0, 0).await.unwrap_err().unwrap();
        assert_eq!(e, "Mapbox tile HTTP 401 Not Authorized - Invalid Token");
        let e = t.get(false, 1, 0, 0).await.unwrap_err().unwrap();
        assert_eq!(e, "Mapbox sent application/json for a tile");
        let e = t.get(false, 1, 0, 0).await.unwrap_err().unwrap();
        assert!(!e.contains("SECRET"), "{e}");
        let none: Tiles<Arc<Script>> = Tiles::new(None, STYLE_DAY, STYLE_NIGHT);
        assert_eq!(none.get(false, 1, 0, 0).await.unwrap_err(), None);
    }

    #[tokio::test(start_paused = true)]
    async fn the_cache_has_a_limit() {
        let n = Tiles::<Arc<Script>>::CAPACITY + 5;
        let script = Arc::new(Script::new((0..n + 1).map(|_| png()).collect()));
        let t = Tiles::new(
            Some(Arc::new(Mapbox::new(script.clone(), "pk.T").unwrap())),
            STYLE_DAY,
            STYLE_NIGHT,
        );
        for x in 0..n as u32 {
            t.get(false, 10, x, 0).await.unwrap();
        }
        assert_eq!(
            t.cache.lock().unwrap().tiles.len(),
            Tiles::<Arc<Script>>::CAPACITY
        );
        // The oldest went first.
        t.get(false, 10, 0, 0).await.unwrap();
        assert_eq!(script.asked.load(Ordering::SeqCst), n + 1);
    }
}
