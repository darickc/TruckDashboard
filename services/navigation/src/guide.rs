//! Turn-by-turn guidance (ADR-0035): the destination, the route, where the
//! truck is along it, and a new route when it leaves it.
//!
//! [`Guide`] is pure (time is passed in) so every transition is tested;
//! [`run`] drives it from the position, the API's commands and the router.
//! Progress is only ever computed from a current position (CLAUDE.md rule
//! 4): with a stale fix the guidance says it is waiting, and sends none.

use std::sync::Arc;
use std::time::Duration;

use f250_proto::nav::v1 as pb;
use tokio::sync::{mpsc, watch};
use tokio::task::JoinHandle;

use crate::valhalla::{Costing, LatLon, Route, RouteRequest, Router, distance_m};

/// Limits, all examples to tune on the truck.
#[derive(Debug, Clone)]
pub struct GuideConfig {
    /// Farther than this from the route line is off the route...
    pub off_route_m: f64,
    /// ...once it has lasted this long.
    pub off_route_for: Duration,
    /// No more than one request this often, however long the truck is off
    /// the route.
    pub min_request_interval: Duration,
    /// Within this of the destination (along the route) is arrived.
    pub arrive_m: f64,
    /// Below this speed the course is noise and isn't sent to Valhalla.
    pub heading_min_mps: f64,
    pub costing: Costing,
}

impl Default for GuideConfig {
    fn default() -> Self {
        GuideConfig {
            off_route_m: 60.0,
            off_route_for: Duration::from_secs(5),
            min_request_interval: Duration::from_secs(15),
            arrive_m: 40.0,
            heading_min_mps: 2.0,
            costing: Costing::Auto,
        }
    }
}

/// How far the matched point may fall behind the last one before it costs
/// anything: GPS noise, not driving backwards.
const BACKTRACK_FREE_M: f64 = 50.0;

/// Where `at` is along `route`: (distance along, distance from the line).
/// The nearest point on the line, preferring points not behind `last_along`
/// so a route that doubles back on itself doesn't jump ahead or back.
pub fn locate(route: &Route, at: LatLon, last_along: f64) -> (f64, f64) {
    let k = at.0.to_radians().cos();
    const M_PER_DEG: f64 = 111_195.08;
    let xy = |p: LatLon| ((p.1 - at.1) * k * M_PER_DEG, (p.0 - at.0) * M_PER_DEG);
    let mut best = (0.0, f64::INFINITY, f64::INFINITY); // along, off, score
    for i in 0..route.shape.len().saturating_sub(1) {
        let (ax, ay) = xy(route.shape[i]);
        let (bx, by) = xy(route.shape[i + 1]);
        let (dx, dy) = (bx - ax, by - ay);
        let len2 = dx * dx + dy * dy;
        let t = if len2 > 0.0 {
            (-(ax * dx + ay * dy) / len2).clamp(0.0, 1.0)
        } else {
            0.0
        };
        let (px, py) = (ax + t * dx, ay + t * dy);
        let off = (px * px + py * py).sqrt();
        let along = route.along_m[i] + t * (route.along_m[i + 1] - route.along_m[i]);
        let behind = ((last_along - BACKTRACK_FREE_M) - along).max(0.0);
        let score = off + behind;
        if score < best.2 {
            best = (along, off, score);
        }
    }
    (best.0, best.1)
}

#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Progress {
    pub maneuver_index: usize,
    pub to_maneuver_m: f64,
    pub remaining_m: f64,
    pub remaining_s: f64,
    pub off_route_m: f64,
    pub along_m: f64,
}

/// Progress at `along` metres along `route`, `off` metres from it.
pub fn progress(route: &Route, along: f64, off: f64) -> Progress {
    let total = route.shape_length_m();
    let along = along.clamp(0.0, total);
    let ms = &route.maneuvers;
    // The next maneuver: the first that starts ahead.
    let next = ms
        .iter()
        .position(|m| m.start_m > along)
        .unwrap_or(ms.len() - 1);
    let to_maneuver_m = (ms[next].start_m - along).max(0.0);
    // Time: the rest of the maneuver we're in, pro rata, then the rest.
    let remaining_s = if next == 0 || ms[next].start_m <= along {
        0.0
    } else {
        let cur = &ms[next - 1];
        let span = ms[next].start_m - cur.start_m;
        let left = if span > 0.0 {
            (ms[next].start_m - along) / span
        } else {
            0.0
        };
        left * cur.time_s + ms[next..].iter().map(|m| m.time_s).sum::<f64>()
    };
    Progress {
        maneuver_index: next,
        to_maneuver_m,
        remaining_m: total - along,
        remaining_s,
        off_route_m: off,
        along_m: along,
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum State {
    Unavailable,
    Idle,
    Routing,
    Active,
    Failed,
    Arrived,
}

/// A current fix, as the guide needs it.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Here {
    pub at: LatLon,
    pub speed_mps: Option<f64>,
    pub track_deg: Option<f64>,
}

/// The current fix in navigation's own position message, or None when it
/// isn't current.
pub fn here(p: &pb::Position) -> Option<Here> {
    let f = p.fix.as_ref()?;
    p.current.then_some(Here {
        at: (f.latitude_deg, f.longitude_deg),
        speed_mps: f.speed_mps,
        track_deg: f.track_deg,
    })
}

#[derive(Debug)]
pub struct Guide {
    cfg: GuideConfig,
    state: State,
    detail: String,
    destination: Option<LatLon>,
    route: Option<Arc<Route>>,
    next_id: u64,
    /// A route is wanted: a new destination, or off the route.
    want: bool,
    /// The wanted route replaces one we left.
    reroute: bool,
    in_flight: bool,
    last_request: Option<Duration>,
    reroutes: u32,
    last_along: f64,
    off_since: Option<Duration>,
    progress: Option<Progress>,
}

impl Guide {
    pub fn new(cfg: GuideConfig) -> Self {
        Guide {
            cfg,
            state: State::Idle,
            detail: String::new(),
            destination: None,
            route: None,
            next_id: 1,
            want: false,
            reroute: false,
            in_flight: false,
            last_request: None,
            reroutes: 0,
            last_along: 0.0,
            off_since: None,
            progress: None,
        }
    }

    pub fn state(&self) -> State {
        self.state
    }

    pub fn route(&self) -> Option<&Arc<Route>> {
        self.route.as_ref()
    }

    /// Whether routing can work: the router's own check.
    pub fn set_available(&mut self, why_not: Result<(), String>) {
        match why_not {
            Err(why) => {
                if self.state != State::Unavailable {
                    self.clear();
                }
                self.state = State::Unavailable;
                self.detail = why;
            }
            Ok(()) if self.state == State::Unavailable => {
                self.state = State::Idle;
                self.detail.clear();
            }
            Ok(()) => {}
        }
    }

    pub fn set_destination(&mut self, to: LatLon) {
        if self.state == State::Unavailable {
            return;
        }
        self.clear();
        self.destination = Some(to);
        self.want = true;
        self.state = State::Routing;
    }

    pub fn clear(&mut self) {
        let unavailable = self.state == State::Unavailable;
        *self = Guide {
            next_id: self.next_id,
            ..Guide::new(self.cfg.clone())
        };
        if unavailable {
            self.state = State::Unavailable;
        }
    }

    /// A request to send now, if one is due. The caller sends it and
    /// reports back with [`Guide::routed`].
    pub fn request(&mut self, here: Option<Here>, now: Duration) -> Option<RouteRequest> {
        let to = self.destination?;
        if !self.want || self.in_flight || matches!(self.state, State::Unavailable | State::Arrived)
        {
            return None;
        }
        let Some(h) = here else {
            if self.route.is_none() {
                self.state = State::Routing;
                self.detail = "Waiting for a current position to route from".to_string();
            }
            return None;
        };
        if let Some(last) = self.last_request
            && now.saturating_sub(last) < self.cfg.min_request_interval
        {
            return None;
        }
        self.want = false;
        self.in_flight = true;
        self.last_request = Some(now);
        if self.reroute {
            self.reroutes += 1;
        }
        self.state = State::Routing;
        self.detail = if self.reroute {
            "Off the route: finding a new one".to_string()
        } else {
            String::new()
        };
        let moving = h.speed_mps.is_some_and(|s| s >= self.cfg.heading_min_mps);
        Some(RouteRequest {
            from: h.at,
            heading_deg: if moving { h.track_deg } else { None },
            to,
            costing: self.cfg.costing.clone(),
        })
    }

    /// The router's answer to the request [`Guide::request`] returned.
    pub fn routed(&mut self, result: Result<Route, String>) {
        self.in_flight = false;
        match result {
            Ok(mut route) => {
                route.id = self.next_id;
                self.next_id += 1;
                self.route = Some(Arc::new(route));
                self.state = State::Active;
                self.detail.clear();
                self.reroute = false;
                self.last_along = 0.0;
                self.off_since = None;
            }
            Err(why) => {
                self.state = State::Failed;
                self.detail = why;
                // Off the route, keep trying (at the request interval); a
                // first route waits for Retry.
                self.want = self.reroute;
            }
        }
    }

    /// A new position, or a tick.
    pub fn update(&mut self, here: Option<Here>, now: Duration) {
        self.progress = None;
        let Some(route) = self.route.clone() else {
            return;
        };
        let Some(h) = here else {
            self.off_since = None;
            return;
        };
        let (along, off) = locate(&route, h.at, self.last_along);
        let p = progress(&route, along, off);
        self.progress = Some(p);
        if self.state == State::Arrived {
            return;
        }
        if off <= self.cfg.off_route_m {
            self.off_since = None;
            self.last_along = along;
            if self.state == State::Failed {
                // A reroute failed, but the truck is back on the old route.
                self.state = State::Active;
                self.detail.clear();
                self.want = false;
                self.reroute = false;
            }
            let to_destination = distance_m(h.at, route.destination);
            if p.remaining_m <= self.cfg.arrive_m || to_destination <= self.cfg.arrive_m {
                self.state = State::Arrived;
                self.detail.clear();
                self.want = false;
            }
            return;
        }
        let since = *self.off_since.get_or_insert(now);
        if now.saturating_sub(since) >= self.cfg.off_route_for && !self.in_flight {
            self.want = true;
            self.reroute = true;
        }
    }

    pub fn guidance(&self) -> pb::Guidance {
        let state = match self.state {
            State::Unavailable => pb::RouteState::Unavailable,
            State::Idle => pb::RouteState::Idle,
            State::Routing => pb::RouteState::Routing,
            State::Active => pb::RouteState::Active,
            State::Failed => pb::RouteState::Failed,
            State::Arrived => pb::RouteState::Arrived,
        };
        let off_route = self.off_since.is_some();
        pb::Guidance {
            state: state as i32,
            route_id: self.route.as_ref().map_or(0, |r| r.id),
            destination: self.destination.map(|d| pb::LatLon {
                latitude_deg: d.0,
                longitude_deg: d.1,
            }),
            progress: self.progress.map(|p| pb::Progress {
                maneuver_index: p.maneuver_index as u32,
                to_maneuver_m: p.to_maneuver_m,
                remaining_m: p.remaining_m,
                remaining_s: p.remaining_s,
                off_route_m: p.off_route_m,
                off_route,
            }),
            detail: if self.state == State::Active && self.progress.is_none() {
                "waiting for a current position".to_string()
            } else {
                self.detail.clone()
            },
            reroutes: self.reroutes,
        }
    }
}

pub fn route_to_pb(r: &Route) -> pb::Route {
    let ll = |p: &LatLon| pb::LatLon {
        latitude_deg: p.0,
        longitude_deg: p.1,
    };
    pb::Route {
        id: r.id,
        shape: r.shape.iter().map(ll).collect(),
        maneuvers: r
            .maneuvers
            .iter()
            .map(|m| pb::Maneuver {
                r#type: m.kind,
                instruction: m.instruction.clone(),
                street_names: m.street_names.clone(),
                length_m: m.length_m,
                time_s: m.time_s,
                begin_shape_index: m.begin_shape_index as u32,
                start_m: m.start_m,
            })
            .collect(),
        length_m: r.length_m,
        time_s: r.time_s,
        destination: Some(ll(&r.destination)),
        costing: r.costing.clone(),
        has_toll: r.has_toll,
        has_highway: r.has_highway,
        has_ferry: r.has_ferry,
    }
}

/// What the API sends the guide.
#[derive(Debug, Clone, PartialEq)]
pub enum Command {
    SetDestination(LatLon),
    Clear,
}

/// How often guidance is sent with nothing new, so ages move and the
/// dashboard can tell a stalled stream.
pub const TICK: Duration = Duration::from_secs(1);

/// Runs the guide until `commands` closes. Publishes guidance and the
/// current route (for GetRoute and the simulated receiver).
pub async fn run<R: Router>(
    cfg: GuideConfig,
    router: Arc<R>,
    mut commands: mpsc::Receiver<Command>,
    mut position: watch::Receiver<pb::Position>,
    guidance: watch::Sender<pb::Guidance>,
    route_out: watch::Sender<Option<Arc<Route>>>,
) {
    let start = tokio::time::Instant::now();
    let mut guide = Guide::new(cfg);
    guide.set_available(router.check());
    let mut pending: Option<JoinHandle<Result<Route, String>>> = None;
    let mut tick = tokio::time::interval(TICK);
    loop {
        tokio::select! {
            cmd = commands.recv() => match cmd {
                None => return,
                Some(cmd) => {
                    // A new destination or a clear abandons a request in
                    // flight (and kills its Valhalla).
                    if let Some(p) = pending.take() {
                        p.abort();
                    }
                    guide.clear();
                    guide.set_available(router.check());
                    if let Command::SetDestination(to) = cmd {
                        guide.set_destination(to);
                    }
                }
            },
            changed = position.changed() => {
                if changed.is_err() {
                    return;
                }
            }
            result = async { pending.as_mut().expect("guarded").await }, if pending.is_some() => {
                pending = None;
                guide.routed(result.unwrap_or_else(|e| Err(format!("routing task: {e}"))));
            }
            _ = tick.tick() => {
                // Routing data can arrive (a stick) or go while running.
                guide.set_available(router.check());
            }
        }
        let now = start.elapsed();
        let here = here(&position.borrow());
        guide.update(here, now);
        if let Some(req) = guide.request(here, now) {
            let router = router.clone();
            pending = Some(tokio::spawn(async move { router.route(req).await }));
        }
        let route = guide.route().cloned();
        route_out.send_if_modified(|r| {
            let changed = r.as_ref().map(|r| r.id) != route.as_ref().map(|r| r.id);
            if changed {
                *r = route;
            }
            changed
        });
        guidance.send_replace(guide.guidance());
    }
}

#[cfg(test)]
#[allow(clippy::unwrap_used, clippy::expect_used)]
mod tests {
    use super::*;

    const ROUTE: &str = include_str!("../tests/data/valhalla-3.9.1-route-auto.json");
    const DEST: LatLon = (39.8103, -98.5559);

    fn route() -> Route {
        crate::valhalla::parse_response(ROUTE, DEST, "auto").unwrap()
    }

    fn at(p: LatLon) -> Option<Here> {
        Some(Here {
            at: p,
            speed_mps: Some(20.0),
            track_deg: Some(90.0),
        })
    }

    /// The point `d` metres along the route.
    fn point_along(r: &Route, d: f64) -> LatLon {
        let i = r.along_m.iter().rposition(|&a| a <= d).unwrap();
        let j = (i + 1).min(r.shape.len() - 1);
        let span = r.along_m[j] - r.along_m[i];
        let t = if span > 0.0 {
            (d - r.along_m[i]) / span
        } else {
            0.0
        };
        let (a, b) = (r.shape[i], r.shape[j]);
        (a.0 + (b.0 - a.0) * t, a.1 + (b.1 - a.1) * t)
    }

    const S: fn(u64) -> Duration = Duration::from_secs;

    #[test]
    fn locates_along_the_route() {
        let r = route();
        for d in [0.0, 500.0, 5_000.0, 20_000.0] {
            let (along, off) = locate(&r, point_along(&r, d), 0.0);
            assert!((along - d).abs() < 1.0, "{d}: {along}");
            assert!(off < 1.0, "{off}");
        }
        // 100 m north of a point on US 36 (which runs east-west).
        let p = point_along(&r, 5_000.0);
        let (along, off) = locate(&r, (p.0 + 100.0 / 111_195.0, p.1), 4_900.0);
        assert!((along - 5_000.0).abs() < 20.0, "{along}");
        assert!((off - 100.0).abs() < 5.0, "{off}");
    }

    #[test]
    fn progress_to_the_next_maneuver() {
        let r = route();
        let m3 = r.maneuvers[3].start_m;
        let p = progress(&r, m3 - 100.0, 0.0);
        assert_eq!(p.maneuver_index, 3);
        assert!((p.to_maneuver_m - 100.0).abs() < 1e-6);
        assert!((p.remaining_m - (r.shape_length_m() - m3 + 100.0)).abs() < 1e-6);
        // Time: all of maneuvers 3.. plus a share of 2.
        let rest: f64 = r.maneuvers[3..].iter().map(|m| m.time_s).sum();
        assert!(p.remaining_s > rest && p.remaining_s < rest + r.maneuvers[2].time_s);
        // At the start, the whole route's time.
        let p = progress(&r, 0.0, 0.0);
        assert_eq!(p.maneuver_index, 1);
        assert!((p.remaining_s - r.time_s).abs() < 0.01, "{}", p.remaining_s);
        // At the end: the destination maneuver, nothing left.
        let p = progress(&r, r.shape_length_m(), 0.0);
        assert_eq!(p.maneuver_index, r.maneuvers.len() - 1);
        assert_eq!(
            (p.remaining_m, p.remaining_s, p.to_maneuver_m),
            (0.0, 0.0, 0.0)
        );
    }

    fn routed_guide() -> (Guide, Route) {
        let mut g = Guide::new(GuideConfig::default());
        let r = route();
        g.set_destination(DEST);
        let req = g.request(at(r.shape[0]), S(0)).expect("a request");
        assert_eq!(req.to, DEST);
        assert_eq!(req.heading_deg, Some(90.0));
        g.routed(Ok(r.clone()));
        (g, r)
    }

    #[test]
    fn idle_to_active() {
        let g = Guide::new(GuideConfig::default());
        assert_eq!(g.state(), State::Idle);
        assert_eq!(g.guidance().route_id, 0);
        let (mut g, r) = routed_guide();
        assert_eq!(g.state(), State::Active);
        assert_eq!(g.guidance().route_id, 1);
        g.update(at(point_along(&r, 1_000.0)), S(1));
        let pg = g.guidance();
        assert_eq!(pg.state, pb::RouteState::Active as i32);
        let p = pg.progress.unwrap();
        assert!(!p.off_route);
        assert!((p.remaining_m - (r.shape_length_m() - 1_000.0)).abs() < 1.0);
        assert_eq!(pg.destination.unwrap().latitude_deg, DEST.0);
    }

    #[test]
    fn no_request_without_a_current_position() {
        let mut g = Guide::new(GuideConfig::default());
        g.set_destination(DEST);
        assert_eq!(g.request(None, S(0)), None);
        assert_eq!(g.state(), State::Routing);
        assert!(g.guidance().detail.contains("current position"));
        assert!(
            g.request(at((39.78, -98.78)), S(1)).is_some(),
            "once there is one"
        );
        assert_eq!(g.request(at((39.78, -98.78)), S(2)), None, "one at a time");
    }

    #[test]
    fn stale_position_sends_no_progress() {
        let (mut g, r) = routed_guide();
        g.update(at(point_along(&r, 1_000.0)), S(1));
        assert!(g.guidance().progress.is_some());
        g.update(None, S(2));
        let pg = g.guidance();
        assert!(pg.progress.is_none());
        assert_eq!(pg.state, pb::RouteState::Active as i32);
        assert!(pg.detail.contains("current position"));
        assert_ne!(pg.route_id, 0, "the route stays");
    }

    #[test]
    fn off_route_reroutes_after_a_while() {
        let (mut g, r) = routed_guide();
        let p = point_along(&r, 5_000.0);
        let away = (p.0 + 200.0 / 111_195.0, p.1);
        g.update(at(away), S(20));
        assert!(g.guidance().progress.unwrap().off_route);
        assert_eq!(g.request(at(away), S(20)), None, "not yet");
        g.update(at(away), S(24));
        assert_eq!(g.request(at(away), S(24)), None, "4 s");
        g.update(at(away), S(25));
        let req = g.request(at(away), S(25)).expect("5 s off: reroute");
        assert_eq!(req.from, away);
        let pg = g.guidance();
        assert_eq!(pg.state, pb::RouteState::Routing as i32);
        assert_eq!(pg.reroutes, 1);
        assert_eq!(pg.route_id, 1, "the old route stays until the new one");
        assert!(pg.detail.contains("Off the route"));
        g.routed(Ok(r.clone()));
        assert_eq!(g.guidance().route_id, 2);
        assert_eq!(g.state(), State::Active);
    }

    #[test]
    fn back_on_the_route_cancels_the_reroute() {
        let (mut g, r) = routed_guide();
        let p = point_along(&r, 5_000.0);
        g.update(at((p.0 + 200.0 / 111_195.0, p.1)), S(20));
        g.update(at(point_along(&r, 5_100.0)), S(23));
        g.update(at(point_along(&r, 5_200.0)), S(26));
        assert!(!g.guidance().progress.unwrap().off_route);
        assert_eq!(g.request(at(point_along(&r, 5_200.0)), S(26)), None);
    }

    #[test]
    fn reroutes_are_rate_limited_and_retried() {
        let (mut g, r) = routed_guide();
        let p = point_along(&r, 5_000.0);
        let away = (p.0 + 300.0 / 111_195.0, p.1);
        g.update(at(away), S(1));
        g.update(at(away), S(6));
        // The first route was requested at 0 s: not before 15 s.
        assert_eq!(g.request(at(away), S(6)), None);
        g.update(at(away), S(15));
        assert!(g.request(at(away), S(15)).is_some());
        g.routed(Err(
            "Valhalla error 171: No suitable edges near location".into()
        ));
        assert_eq!(g.state(), State::Failed);
        assert_eq!(g.guidance().route_id, 1, "the old route stays");
        g.update(at(away), S(20));
        assert_eq!(g.request(at(away), S(20)), None, "too soon");
        g.update(at(away), S(30));
        assert!(g.request(at(away), S(30)).is_some(), "retried");
        assert_eq!(g.guidance().reroutes, 2);
    }

    #[test]
    fn a_failed_first_route_waits_for_retry() {
        let mut g = Guide::new(GuideConfig::default());
        g.set_destination(DEST);
        assert!(g.request(at((39.78, -98.78)), S(0)).is_some());
        g.routed(Err(
            "Valhalla error 171: No suitable edges near location".into()
        ));
        let pg = g.guidance();
        assert_eq!(pg.state, pb::RouteState::Failed as i32);
        assert_eq!(
            pg.detail,
            "Valhalla error 171: No suitable edges near location"
        );
        assert!(pg.destination.is_some(), "kept for Retry");
        g.update(at((39.78, -98.78)), S(60));
        assert_eq!(g.request(at((39.78, -98.78)), S(60)), None);
        g.set_destination(DEST);
        assert!(
            g.request(at((39.78, -98.78)), S(61)).is_some(),
            "Retry: a new destination"
        );
    }

    #[test]
    fn arrives() {
        let (mut g, r) = routed_guide();
        g.update(at(point_along(&r, r.shape_length_m() - 100.0)), S(800));
        assert_eq!(g.state(), State::Active);
        g.update(at(point_along(&r, r.shape_length_m() - 30.0)), S(810));
        assert_eq!(g.state(), State::Arrived);
        // Wandering off after arriving doesn't reroute.
        let far = (DEST.0 + 0.01, DEST.1);
        g.update(at(far), S(820));
        g.update(at(far), S(900));
        assert_eq!(g.request(at(far), S(900)), None);
        assert_eq!(g.state(), State::Arrived);
    }

    #[test]
    fn clear_and_unavailable() {
        let (mut g, _) = routed_guide();
        g.clear();
        let pg = g.guidance();
        assert_eq!(pg.state, pb::RouteState::Idle as i32);
        assert_eq!((pg.route_id, pg.destination), (0, None));
        g.set_available(Err("no routing data at /x.tar".into()));
        g.set_destination(DEST);
        let pg = g.guidance();
        assert_eq!(pg.state, pb::RouteState::Unavailable as i32);
        assert_eq!(pg.detail, "no routing data at /x.tar");
        assert_eq!(pg.destination, None);
        g.set_available(Ok(()));
        assert_eq!(g.state(), State::Idle);
        // Ids keep counting across clears, so a client never confuses routes.
        g.set_destination(DEST);
        assert!(g.request(at((39.78, -98.78)), S(100)).is_some());
        g.routed(Ok(route()));
        assert_eq!(g.guidance().route_id, 2);
    }

    #[test]
    fn heading_only_while_moving() {
        let mut g = Guide::new(GuideConfig::default());
        g.set_destination(DEST);
        let still = Some(Here {
            at: (39.78, -98.78),
            speed_mps: Some(0.5),
            track_deg: Some(123.0),
        });
        assert_eq!(g.request(still, S(0)).unwrap().heading_deg, None);
    }

    #[test]
    fn route_pb() {
        let mut r = route();
        r.id = 7;
        let p = route_to_pb(&r);
        assert_eq!(p.id, 7);
        assert_eq!(p.shape.len(), r.shape.len());
        assert_eq!(p.maneuvers[3].r#type, 10);
        assert_eq!(p.maneuvers[3].begin_shape_index, 11);
        assert_eq!(p.costing, "auto");
        assert_eq!(p.destination.unwrap().longitude_deg, DEST.1);
    }
}
