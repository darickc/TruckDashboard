//! The online map as vector tiles (ADR-0052 decision 6, amended 2026-11-24):
//! Mapbox's style document and sprites from the Styles API, and Mapbox
//! Vector Tiles from the Vector Tiles API, which the dashboard draws itself
//! with that style. Labels then stay upright when the map turns with the
//! heading, which Mapbox's raster tiles can't do (bench-log 2026-11-23).
//!
//! - Style: `GET /styles/v1/{user}/{style}`; its vector sources name their
//!   tilesets as `mapbox://a,b` (navigation-night-v1: `composite` is
//!   `mapbox.mapbox-streets-v8,mapbox.mapbox-terrain-v2`, plus traffic and
//!   incidents).
//! - Sprites: `GET /styles/v1/{user}/{style}/sprite.json` and `.png`, or
//!   `sprite@2x.json` and `.png` for a screen of 2 pixels per point.
//! - A source's zooms: its TileJSON, `GET /v4/{tilesets}.json`.
//! - A tile: `GET /v4/{tilesets}/{z}/{x}/{y}.mvt`, gzip (curl undoes it).
//!
//! (docs.mapbox.com/api/maps/styles, …/vector-tiles, checked 2026-11-24.)

use std::sync::Arc;
use tokio::time::Instant;

use serde_json::Value;

use crate::mapbox::{Fetch, Fetched, Mapbox, redact};

/// One vector source of a style: the id its layers use and Mapbox's tilesets.
#[derive(Debug, Clone, PartialEq)]
pub struct Source {
    pub id: String,
    /// `mapbox.mapbox-streets-v8,mapbox.mapbox-terrain-v2`.
    pub tilesets: String,
    pub min_zoom: u32,
    pub max_zoom: u32,
}

/// A style ready for the dashboard.
#[derive(Debug)]
pub struct Style {
    pub style_json: String,
    pub sources: Vec<Source>,
    pub at: Instant,
}

/// A style's icons: the sheet and where each icon is on it.
#[derive(Debug)]
pub struct Sprites {
    pub json: String,
    pub png: Vec<u8>,
    pub at: Instant,
}

/// The vector sources a style document names, as (id, tilesets). A source
/// whose URL isn't `mapbox://` (a raster DEM, a GeoJSON) is left out; the
/// dashboard draws nothing for layers that use it.
pub fn style_sources(style_json: &str) -> Result<Vec<(String, String)>, String> {
    let v: Value =
        serde_json::from_str(style_json).map_err(|e| format!("Mapbox's style isn't JSON: {e}"))?;
    let sources = v
        .get("sources")
        .and_then(Value::as_object)
        .ok_or("Mapbox's style has no sources")?;
    let mut out: Vec<(String, String)> = sources
        .iter()
        .filter(|(_, s)| s.get("type").and_then(Value::as_str) == Some("vector"))
        .filter_map(|(id, s)| {
            let url = s.get("url")?.as_str()?;
            let tilesets = url.strip_prefix("mapbox://")?;
            tileset_ids_ok(tilesets).then(|| (id.clone(), tilesets.to_string()))
        })
        .collect();
    out.sort();
    if out.is_empty() {
        return Err("Mapbox's style has no Mapbox vector sources".to_string());
    }
    Ok(out)
}

/// Tileset ids as they go into a URL path: `user.name`, comma-separated.
fn tileset_ids_ok(s: &str) -> bool {
    !s.is_empty()
        && s.split(',').all(|t| {
            !t.is_empty()
                && t.contains('.')
                && t.chars()
                    .all(|c| c.is_ascii_alphanumeric() || matches!(c, '.' | '-' | '_'))
        })
}

/// A TileJSON's zooms (`minzoom`, `maxzoom`).
pub fn tilejson_zooms(body: &[u8]) -> Result<(u32, u32), String> {
    let v: Value =
        serde_json::from_slice(body).map_err(|e| format!("Mapbox's TileJSON isn't JSON: {e}"))?;
    let zoom = |k: &str| {
        v.get(k)
            .and_then(Value::as_u64)
            .and_then(|z| u32::try_from(z).ok())
            .filter(|z| *z <= 30)
    };
    match (zoom("minzoom"), zoom("maxzoom")) {
        (Some(min), Some(max)) if min <= max => Ok((min, max)),
        _ => Err("Mapbox's TileJSON has no usable minzoom/maxzoom".to_string()),
    }
}

/// HTTP 200 or a short reason, from Mapbox's `message` when it gives one.
fn ok(a: Fetched, what: &str) -> Result<Fetched, String> {
    if a.status == 200 {
        return Ok(a);
    }
    let msg = serde_json::from_slice::<Value>(&a.body)
        .ok()
        .and_then(|v| v.get("message").and_then(Value::as_str).map(str::to_string))
        .unwrap_or_default();
    Err(redact(
        format!("Mapbox {what} HTTP {} {msg}", a.status).trim(),
    ))
}

impl<F: Fetch> Mapbox<F> {
    async fn fetch_ok(&self, path: &str, what: &str) -> Result<Fetched, String> {
        let a = self
            .get(path, "", self.tile_timeout)
            .await
            .map_err(|e| format!("Mapbox unreachable: {e}"))?;
        ok(a, what)
    }

    /// A style with each vector source's zooms: 1 + one request per source.
    pub async fn vector_style(&self, style: &str) -> Result<Style, String> {
        let doc = self
            .fetch_ok(&format!("/styles/v1/{style}"), "style")
            .await?;
        let style_json =
            String::from_utf8(doc.body).map_err(|_| "Mapbox's style isn't UTF-8".to_string())?;
        let mut sources = Vec::new();
        for (id, tilesets) in style_sources(&style_json)? {
            let tj = self
                .fetch_ok(&format!("/v4/{tilesets}.json"), "TileJSON")
                .await?;
            let (min_zoom, max_zoom) = tilejson_zooms(&tj.body)?;
            sources.push(Source {
                id,
                tilesets,
                min_zoom,
                max_zoom,
            });
        }
        Ok(Style {
            style_json,
            sources,
            at: Instant::now(),
        })
    }

    /// A style's sprites, 2x (`hi_dpi`) or 1x: 2 requests.
    pub async fn sprites(&self, style: &str, hi_dpi: bool) -> Result<Sprites, String> {
        let at = if hi_dpi { "@2x" } else { "" };
        let json = self
            .fetch_ok(
                &format!("/styles/v1/{style}/sprite{at}.json"),
                "sprite index",
            )
            .await?;
        let png = self
            .fetch_ok(
                &format!("/styles/v1/{style}/sprite{at}.png"),
                "sprite image",
            )
            .await?;
        Ok(Sprites {
            json: String::from_utf8(json.body)
                .map_err(|_| "Mapbox's sprite index isn't UTF-8".to_string())?,
            png: png.body,
            at: Instant::now(),
        })
    }

    /// One vector tile, uncompressed. Mapbox's 404 is a tile with nothing in
    /// it (open water, a source with no data there): empty, not a failure.
    pub async fn vector_tile(
        &self,
        tilesets: &str,
        z: u32,
        x: u32,
        y: u32,
    ) -> Result<Fetched, String> {
        let a = self
            .get(
                &format!("/v4/{tilesets}/{z}/{x}/{y}.mvt"),
                "",
                self.tile_timeout,
            )
            .await
            .map_err(|e| format!("Mapbox unreachable: {e}"))?;
        if a.status == 404 {
            return Ok(Fetched {
                max_age: None,
                status: 200,
                content_type: VECTOR_TILE.to_string(),
                body: Vec::new(),
            });
        }
        let a = ok(a, "vector tile")?;
        if a.content_type.starts_with("application/json") || a.content_type.starts_with("text/") {
            return Err(format!("Mapbox sent {} for a vector tile", a.content_type));
        }
        Ok(a)
    }
}

/// The type a vector tile is handed on with.
pub const VECTOR_TILE: &str = "application/vnd.mapbox-vector-tile";

/// A style kept in memory, shared by tile requests.
pub type Shared = Arc<Style>;

#[cfg(test)]
#[allow(clippy::unwrap_used)]
mod tests {
    use super::*;

    #[test]
    fn a_styles_mapbox_vector_sources() {
        let s = r#"{"version":8,"sources":{
            "mapbox-traffic":{"type":"vector","url":"mapbox://mapbox.mapbox-traffic-v1"},
            "composite":{"type":"vector","url":"mapbox://mapbox.mapbox-streets-v8,mapbox.mapbox-terrain-v2"},
            "dem":{"type":"raster-dem","url":"mapbox://mapbox.mapbox-terrain-dem-v1"},
            "elsewhere":{"type":"vector","url":"https://example.com/tiles.json"},
            "odd":{"type":"vector","url":"mapbox://../../secrets"}
        },"layers":[]}"#;
        assert_eq!(
            style_sources(s).unwrap(),
            vec![
                (
                    "composite".to_string(),
                    "mapbox.mapbox-streets-v8,mapbox.mapbox-terrain-v2".to_string()
                ),
                (
                    "mapbox-traffic".to_string(),
                    "mapbox.mapbox-traffic-v1".to_string()
                ),
            ]
        );
    }

    #[test]
    fn a_style_without_mapbox_vector_sources_is_refused() {
        assert!(style_sources("not json").is_err());
        assert!(style_sources(r#"{"layers":[]}"#).is_err());
        assert!(
            style_sources(r#"{"sources":{"a":{"type":"raster","url":"mapbox://a.b"}}}"#).is_err()
        );
    }

    #[test]
    fn a_tilejsons_zooms() {
        assert_eq!(
            tilejson_zooms(br#"{"tilejson":"2.2.0","minzoom":0,"maxzoom":16}"#).unwrap(),
            (0, 16)
        );
        assert!(tilejson_zooms(br#"{"minzoom":5}"#).is_err());
        assert!(tilejson_zooms(br#"{"minzoom":9,"maxzoom":3}"#).is_err());
        assert!(tilejson_zooms(br#"{"minzoom":0,"maxzoom":99}"#).is_err());
    }

    #[test]
    fn failures_say_what_and_why_without_the_token() {
        let a = Fetched {
            max_age: None,
            status: 401,
            content_type: "application/json".into(),
            body: br#"{"message":"Not Authorized - Invalid Token"}"#.to_vec(),
        };
        assert_eq!(
            ok(a, "style").unwrap_err(),
            "Mapbox style HTTP 401 Not Authorized - Invalid Token"
        );
    }
}
