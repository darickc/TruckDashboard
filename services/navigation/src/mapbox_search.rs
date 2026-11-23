//! Search while there is a network (ADR-0052 decision 11): Mapbox's
//! Geocoding API (v6, `forward`) first, the offline index (ADR-0038) when
//! Mapbox doesn't answer or there is no token.
//!
//! Geocoding v6 finds addresses, streets, towns and ZIP codes, not
//! businesses ("no longer provides POI data", its documentation,
//! 2026-11-23). Its default, temporary results "may not be retained": nothing
//! here keeps them.
//!
//! Test vector: `tests/data/mapbox-geocode-handwritten.json` is
//! **hand-written** to the fields seen in real answers on 2026-11-23, which
//! aren't kept for that reason.

use std::sync::Arc;

use f250_proto::nav::v1 as pb;
use serde_json::Value;

use crate::mapbox::{Failure, Fetch, Mapbox, PROVIDER, redact};
use crate::search::{self, Searcher};

/// [`pb::SearchResponse::provider`] for the offline index's answers.
pub const OFFLINE: &str = "offline";

/// Geocoding v6 takes at most 10 results, 20 words and 256 characters, and
/// no semicolons (its documentation).
pub const MAX_RESULTS: usize = 10;
const MAX_WORDS: usize = 20;
const MAX_CHARS: usize = 256;

/// The query as Mapbox takes it: no semicolons, at most 20 words and 256
/// characters.
pub fn mapbox_query(query: &str) -> String {
    let words: Vec<&str> = query
        .split(|c: char| c == ';' || c.is_whitespace())
        .filter(|w| !w.is_empty())
        .take(MAX_WORDS)
        .collect();
    let q = words.join(" ");
    match q.char_indices().nth(MAX_CHARS) {
        Some((i, _)) => q[..i].to_string(),
        None => q,
    }
}

/// Percent-encoding for a query value: everything but RFC 3986's
/// unreserved characters.
pub fn encode(s: &str) -> String {
    let mut out = String::with_capacity(s.len() * 3);
    for b in s.bytes() {
        match b {
            b'A'..=b'Z' | b'a'..=b'z' | b'0'..=b'9' | b'-' | b'.' | b'_' | b'~' => {
                out.push(b as char)
            }
            _ => out.push_str(&format!("%{b:02X}")),
        }
    }
    out
}

/// The path and query of a forward search, without the token.
pub fn geocode_query(query: &str, near: Option<(f64, f64)>, limit: usize, country: &str) -> String {
    let mut q = format!(
        "q={}&limit={}&language=en&autocomplete=true",
        encode(&mapbox_query(query)),
        limit.clamp(1, MAX_RESULTS),
    );
    if !country.trim().is_empty() {
        q.push_str(&format!("&country={}", encode(country.trim())));
    }
    if let Some((lat, lon)) = near {
        q.push_str(&format!("&proximity={lon:.5},{lat:.5}"));
    }
    q
}

/// The query starts with a house number ("120 n main"), not a ZIP code
/// alone.
fn has_house_number(query: &str) -> bool {
    let mut words = query.split_whitespace();
    let first = words.next().unwrap_or("");
    !first.is_empty()
        && first.len() <= 6
        && first.chars().all(|c| c.is_ascii_digit())
        && words.next().is_some()
}

fn text<'a>(v: &'a Value, k: &str) -> Option<&'a str> {
    v.get(k)
        .and_then(Value::as_str)
        .map(str::trim)
        .filter(|s| !s.is_empty())
}

/// Mapbox's answer as search results, in Mapbox's order (its relevance,
/// leaning toward `near`). `Ok(empty)` for a query it rejected as input
/// (HTTP 400, 422): nothing found, the network is fine.
pub fn parse_geocode(
    status: u16,
    body: &[u8],
    query: &str,
    near: Option<(f64, f64)>,
) -> Result<Vec<pb::SearchResult>, Failure> {
    let v: Option<Value> = serde_json::from_slice(body).ok();
    let message = v
        .as_ref()
        .and_then(|v| text(v, "message").or_else(|| text(v, "error_code")))
        .unwrap_or("")
        .to_string();
    match status {
        200 => {}
        400 | 422 => return Ok(Vec::new()),
        s => {
            return Err(Failure::Unreachable(redact(
                format!("Mapbox search HTTP {s} {message}").trim(),
            )));
        }
    }
    let features = v
        .as_ref()
        .and_then(|v| v.get("features"))
        .and_then(Value::as_array)
        .ok_or_else(|| Failure::Unreachable("Mapbox search: an answer without features".into()))?;
    let numbered = has_house_number(query);
    let mut out = Vec::new();
    for f in features {
        let Some(p) = f.get("properties") else {
            continue;
        };
        let kind = match text(p, "feature_type").unwrap_or("") {
            "address" | "secondary_address" => pb::MatchKind::Address,
            "street" | "block" => pb::MatchKind::Street,
            "place" | "locality" | "neighborhood" | "district" | "postcode" | "region"
            | "country" => pb::MatchKind::Locality,
            _ => pb::MatchKind::Place,
        };
        let c = p.get("coordinates");
        // Where a route ends: the routable point (the driveway) if Mapbox
        // gives one, else the feature's own point.
        let point = c
            .and_then(|c| c.get("routable_points"))
            .and_then(Value::as_array)
            .and_then(|a| a.first())
            .or(c);
        let (Some(lat), Some(lon)) = (
            point
                .and_then(|c| c.get("latitude"))
                .and_then(Value::as_f64),
            point
                .and_then(|c| c.get("longitude"))
                .and_then(Value::as_f64),
        ) else {
            continue;
        };
        if !(lat.is_finite() && lon.is_finite()) {
            continue;
        }
        let Some(title) = text(p, "name_preferred").or_else(|| text(p, "name")) else {
            continue;
        };
        let subtitle = text(p, "place_formatted")
            .unwrap_or("")
            .trim_end_matches(", United States")
            .to_string();
        out.push(pb::SearchResult {
            kind: kind as i32,
            title: title.to_string(),
            subtitle,
            location: Some(pb::LatLon {
                latitude_deg: lat,
                longitude_deg: lon,
            }),
            distance_m: near.map(|n| geocode::distance_m(n, (lat, lon))),
            house_number_missing: numbered && kind != pb::MatchKind::Address,
            unmatched_words: Vec::new(),
        });
    }
    Ok(out)
}

impl<F: Fetch> Mapbox<F> {
    /// One forward search.
    pub async fn search(
        &self,
        query: &str,
        near: Option<(f64, f64)>,
        limit: usize,
    ) -> Result<Vec<pb::SearchResult>, Failure> {
        let q = geocode_query(query, near, limit, &self.search_country);
        let a = self
            .get("/search/geocode/v6/forward", &q, self.search_timeout)
            .await
            .map_err(|e| Failure::Unreachable(format!("Mapbox unreachable: {e}")))?;
        parse_geocode(a.status, &a.body, query, near)
    }
}

/// One search: Mapbox while it answers, else the offline index. `from` and
/// `age` say where `near` came from ([`search::ranked_from`]).
pub async fn search_online_first<F: Fetch>(
    online: Option<&Mapbox<F>>,
    offline: Option<Arc<Searcher>>,
    query: String,
    near: Option<(f64, f64)>,
    (from, age): (pb::RankedFrom, f64),
    limit: usize,
) -> pb::SearchResponse {
    let mut online_why = None;
    if let Some(m) = online.filter(|m| m.routing_online())
        && !query.trim().is_empty()
    {
        match m.search(&query, near, limit.min(MAX_RESULTS)).await {
            Ok(results) => {
                return pb::SearchResponse {
                    available: true,
                    results,
                    ranked_from: from as i32,
                    position_age_s: age,
                    query,
                    provider: PROVIDER.to_string(),
                    ..Default::default()
                };
            }
            Err(f) => {
                eprintln!("[navigation] {}; searching offline", f.why());
                if matches!(f, Failure::Unreachable(_)) {
                    m.skip();
                }
                online_why = Some(f.why().to_string());
            }
        }
    }
    let Some(searcher) = offline else {
        return pb::SearchResponse {
            available: false,
            detail: online_why.unwrap_or_else(|| "search isn't running in this service".into()),
            query,
            ..Default::default()
        };
    };
    let q = query.clone();
    let answer = tokio::task::spawn_blocking(move || searcher.search(&q, near, limit))
        .await
        .unwrap_or_else(|e| Err(format!("search task: {e}")));
    match answer {
        Ok(a) => {
            let found = a.postcode.as_ref().is_some_and(|p| p.at.is_some());
            pb::SearchResponse {
                available: true,
                detail: String::new(),
                results: a.hits.iter().map(search::hit_to_pb).collect(),
                regions: a.regions,
                data_date: a.data_date.unwrap_or_default(),
                ranked_from: if found {
                    pb::RankedFrom::Postcode as i32
                } else {
                    from as i32
                },
                position_age_s: if found { 0.0 } else { age },
                query,
                postcode: a.postcode.map(|p| p.code).unwrap_or_default(),
                postcode_found: found,
                address_ranges: a.ranges_source.unwrap_or_default(),
                provider: OFFLINE.to_string(),
            }
        }
        Err(why) => pb::SearchResponse {
            available: false,
            detail: match online_why {
                Some(o) => format!("{o}; offline: {why}"),
                None => why,
            },
            query,
            ..Default::default()
        },
    }
}

#[cfg(test)]
#[allow(clippy::unwrap_used, clippy::expect_used)]
mod tests {
    use super::*;
    use crate::mapbox::Fetched;
    use std::collections::VecDeque;
    use std::sync::Mutex;
    use std::time::Duration;

    const ANSWER: &[u8] = include_bytes!("../tests/data/mapbox-geocode-handwritten.json");
    const NEAR: (f64, f64) = (39.80, -98.60);

    #[test]
    fn the_query_as_mapbox_takes_it() {
        assert_eq!(mapbox_query("  120 n;main   st "), "120 n main st");
        let many = (0..30).map(|i| i.to_string()).collect::<Vec<_>>().join(" ");
        assert_eq!(mapbox_query(&many).split(' ').count(), 20);
        assert_eq!(mapbox_query(&"é".repeat(300)).chars().count(), 256);
        assert_eq!(
            encode("120 N Main St, Lebanon & co/é"),
            "120%20N%20Main%20St%2C%20Lebanon%20%26%20co%2F%C3%A9"
        );
    }

    #[test]
    fn the_request() {
        let q = geocode_query("120 n main", Some((39.81, -98.5559)), 8, "us");
        assert_eq!(
            q,
            "q=120%20n%20main&limit=8&language=en&autocomplete=true&country=us&proximity=-98.55590,39.81000"
        );
        let q = geocode_query("x", None, 50, "");
        assert_eq!(q, "q=x&limit=10&language=en&autocomplete=true");
    }

    #[test]
    fn reads_the_answer() {
        let r = parse_geocode(200, ANSWER, "120 n main lebanon", Some(NEAR)).unwrap();
        // The feature without coordinates is left out.
        assert_eq!(r.len(), 4);
        let kinds: Vec<_> = r.iter().map(|h| h.kind).collect();
        assert_eq!(
            kinds,
            [
                pb::MatchKind::Address as i32,
                pb::MatchKind::Street as i32,
                pb::MatchKind::Locality as i32,
                pb::MatchKind::Locality as i32,
            ]
        );
        assert_eq!(r[0].title, "120 North Main Street");
        assert_eq!(r[0].subtitle, "Lebanon, Kansas 66952");
        // The routable point, not the rooftop.
        assert_eq!(r[0].location.as_ref().unwrap().longitude_deg, -98.5564);
        assert!(!r[0].house_number_missing);
        assert!(r[1].house_number_missing, "a street for a numbered query");
        assert_eq!(r[2].title, "Smith Center");
        assert_eq!(r[2].subtitle, "Kansas");
        let d = r[0].distance_m.unwrap();
        assert!((3_000.0..4_000.0).contains(&d), "{d}");
        assert!(
            parse_geocode(200, ANSWER, "lebanon", None).unwrap()[0]
                .distance_m
                .is_none()
        );
    }

    #[test]
    fn errors() {
        let refused = parse_geocode(
            401,
            br#"{"message":"Not Authorized - Invalid Token","error_code":"INVALID_TOKEN"}"#,
            "x",
            None,
        );
        assert_eq!(
            refused.unwrap_err(),
            Failure::Unreachable("Mapbox search HTTP 401 Not Authorized - Invalid Token".into())
        );
        assert!(matches!(
            parse_geocode(500, b"", "x", None),
            Err(Failure::Unreachable(_))
        ));
        assert!(matches!(
            parse_geocode(429, b"{}", "x", None),
            Err(Failure::Unreachable(_))
        ));
        assert!(
            parse_geocode(422, br#"{"message":"Query too long"}"#, "x", None)
                .unwrap()
                .is_empty()
        );
        assert!(matches!(
            parse_geocode(200, b"<html>", "x", None),
            Err(Failure::Unreachable(_))
        ));
    }

    /// Answers each request with the next answer; records the URLs.
    #[derive(Default)]
    struct Script {
        answers: Mutex<VecDeque<Result<Fetched, String>>>,
        urls: Mutex<Vec<String>>,
    }

    impl Fetch for Arc<Script> {
        async fn get(&self, url: &str, _: Duration) -> Result<Fetched, String> {
            self.urls.lock().unwrap().push(url.to_string());
            self.answers
                .lock()
                .unwrap()
                .pop_front()
                .unwrap_or_else(|| Err("no more answers".into()))
        }
    }

    fn script(answers: Vec<Result<Fetched, String>>) -> Arc<Script> {
        let s = Arc::new(Script::default());
        *s.answers.lock().unwrap() = answers.into();
        s
    }

    fn ok(body: &[u8]) -> Result<Fetched, String> {
        Ok(Fetched {
            status: 200,
            content_type: "application/vnd.geo+json".into(),
            body: body.to_vec(),
        })
    }

    const FROM: (pb::RankedFrom, f64) = (pb::RankedFrom::Current, 0.5);

    #[tokio::test]
    async fn mapbox_answers() {
        let s = script(vec![ok(ANSWER)]);
        let m = Mapbox::new(s.clone(), "pk.secret").unwrap();
        let r = search_online_first(Some(&m), None, "120 n main".into(), Some(NEAR), FROM, 8).await;
        assert!(r.available);
        assert_eq!(r.provider, "mapbox");
        assert_eq!(r.results.len(), 4);
        assert_eq!(r.ranked_from, pb::RankedFrom::Current as i32);
        assert_eq!(r.query, "120 n main");
        let url = s.urls.lock().unwrap()[0].clone();
        assert!(
            url.starts_with("https://api.mapbox.com/search/geocode/v6/forward?q=120%20n%20main&"),
            "{url}"
        );
        assert!(url.ends_with("&access_token=pk.secret"));
    }

    #[tokio::test(start_paused = true)]
    async fn no_network_then_offline_and_mapbox_rests() {
        let s = script(vec![Err(
            "curl: (6) Could not resolve host: api.mapbox.com".into(),
        )]);
        let m = Mapbox::new(s.clone(), "pk.secret").unwrap();
        // No offline index either: both reasons, and never the token.
        let r = search_online_first(Some(&m), None, "lebanon".into(), None, FROM, 8).await;
        assert!(!r.available);
        assert!(
            r.detail.starts_with("Mapbox unreachable: curl: (6)"),
            "{}",
            r.detail
        );
        assert!(!r.detail.contains("pk.secret"));
        // Skipped for a while: not asked again.
        let r = search_online_first(Some(&m), None, "lebanon".into(), None, FROM, 8).await;
        assert_eq!(s.urls.lock().unwrap().len(), 1);
        assert_eq!(r.detail, "search isn't running in this service");
        tokio::time::advance(m.skip_after_failure + Duration::from_secs(1)).await;
        search_online_first(Some(&m), None, "lebanon".into(), None, FROM, 8).await;
        assert_eq!(
            s.urls.lock().unwrap().len(),
            2,
            "asked again after the rest"
        );
    }

    #[tokio::test]
    async fn the_offline_index_answers_when_mapbox_cannot() {
        let dir = std::env::temp_dir().join(format!("f250-nav-msearch-{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        let path = dir.join("missing.sqlite");
        let s = script(vec![Ok(Fetched {
            status: 503,
            content_type: "text/plain".into(),
            body: b"down".to_vec(),
        })]);
        let m = Mapbox::new(s, "pk.secret").unwrap();
        let r = search_online_first(
            Some(&m),
            Some(Searcher::new(path.clone())),
            "lebanon".into(),
            None,
            FROM,
            8,
        )
        .await;
        assert!(!r.available);
        assert_eq!(
            r.detail,
            format!(
                "Mapbox search HTTP 503; offline: no search data at {}",
                path.display()
            )
        );
    }

    #[tokio::test]
    async fn without_a_token_only_offline() {
        let path = std::env::temp_dir().join("f250-nav-msearch-none.sqlite");
        let r = search_online_first::<Arc<Script>>(
            None,
            Some(Searcher::new(path.clone())),
            "lebanon".into(),
            None,
            FROM,
            8,
        )
        .await;
        assert!(!r.available);
        assert_eq!(r.detail, format!("no search data at {}", path.display()));
    }
}
