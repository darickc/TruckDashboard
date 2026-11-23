//! `f250.nav.v1.PositionService`: the publisher's latest position, then
//! each new one. `RouteService`: commands to the guide, its guidance and
//! its current route. `SearchService`: Mapbox's search while it answers
//! (ADR-0052), else the offline search index, ranked from the latest
//! position (ADR-0038). `PlacesService`: Home, favourites and
//! recent destinations (ADR-0040); every SetDestination adds a recent one.
//! `OnlineMapService`: Mapbox's tiles for the online map (ADR-0052).

use std::path::Path;
use std::pin::Pin;
use std::sync::{Arc, Mutex};
use std::time::Duration;

use f250_proto::nav::v1 as pb;
use pb::online_map_service_server::{OnlineMapService, OnlineMapServiceServer};
use pb::places_service_server::{PlacesService, PlacesServiceServer};
use pb::position_service_server::{PositionService, PositionServiceServer};
use pb::route_service_server::{RouteService, RouteServiceServer};
use pb::search_service_server::{SearchService, SearchServiceServer};
use tokio::sync::{mpsc, watch};
use tokio_stream::{Stream, StreamExt, wrappers::WatchStream};
use tonic::{Request, Response, Status};

use crate::guide::{Command, route_to_pb};
use crate::mapbox::{self, Curl, Mapbox, Tiles};
use crate::mapbox_search;
use crate::places::{self, Places, Refused};
use crate::search::{self, Searcher};
use crate::valhalla::Route;

#[derive(Clone)]
pub struct Api {
    position: watch::Receiver<pb::Position>,
    routing: Option<RoutingApi>,
    search: Option<Arc<Searcher>>,
    places: Option<Arc<Mutex<Places>>>,
    online_map: Option<Arc<Tiles<Curl>>>,
    online_search: Option<Arc<Mapbox<Curl>>>,
}

/// The guide's side of the API.
#[derive(Clone)]
pub struct RoutingApi {
    pub commands: mpsc::Sender<Command>,
    pub guidance: watch::Receiver<pb::Guidance>,
    pub route: watch::Receiver<Option<Arc<Route>>>,
}

impl Api {
    pub fn new(position: watch::Receiver<pb::Position>) -> Self {
        Api {
            position,
            routing: None,
            search: None,
            places: None,
            online_map: None,
            online_search: None,
        }
    }

    /// The online map's tiles (ADR-0052); without, the map says it has no
    /// token.
    pub fn with_online_map(mut self, tiles: Arc<Tiles<Curl>>) -> Self {
        self.online_map = Some(tiles);
        self
    }

    /// Search asks Mapbox first while it answers (ADR-0052).
    pub fn with_online_search(mut self, mapbox: Arc<Mapbox<Curl>>) -> Self {
        self.online_search = Some(mapbox);
        self
    }

    pub fn with_places(mut self, places: Places) -> Self {
        self.places = Some(Arc::new(Mutex::new(places)));
        self
    }

    /// Runs `f` on the places on the blocking pool: a change writes and
    /// flushes a file, which mustn't hold up guidance on this runtime.
    async fn places<T: Send + 'static>(
        &self,
        f: impl FnOnce(&mut Places) -> T + Send + 'static,
    ) -> Result<T, Status> {
        let p = self
            .places
            .clone()
            .ok_or_else(|| Status::unimplemented("saved places aren't kept by this service"))?;
        tokio::task::spawn_blocking(move || {
            let mut g = p
                .lock()
                .map_err(|_| Status::internal("saved places: a previous change panicked"))?;
            Ok(f(&mut g))
        })
        .await
        .map_err(|e| Status::internal(format!("saved places task: {e}")))?
    }

    pub fn with_search(mut self, searcher: Arc<Searcher>) -> Self {
        self.search = Some(searcher);
        self
    }

    pub fn with_routing(mut self, routing: RoutingApi) -> Self {
        self.routing = Some(routing);
        self
    }

    fn routing(&self) -> Result<&RoutingApi, Status> {
        self.routing
            .as_ref()
            .ok_or_else(|| Status::unimplemented("routing isn't running in this service"))
    }
}

type PositionStream = Pin<Box<dyn Stream<Item = Result<pb::WatchPositionResponse, Status>> + Send>>;
type GuidanceStream = Pin<Box<dyn Stream<Item = Result<pb::WatchGuidanceResponse, Status>> + Send>>;

#[tonic::async_trait]
impl PositionService for Api {
    type WatchPositionStream = PositionStream;

    async fn watch_position(
        &self,
        _: Request<pb::WatchPositionRequest>,
    ) -> Result<Response<Self::WatchPositionStream>, Status> {
        // The channel starts with an empty Position (status UNSPECIFIED)
        // until the publisher's first; that one is skipped.
        let stream = WatchStream::new(self.position.clone())
            .filter(|p| p.status != pb::FixStatus::Unspecified as i32)
            .map(|position| {
                Ok(pb::WatchPositionResponse {
                    position: Some(position),
                })
            });
        Ok(Response::new(Box::pin(stream)))
    }
}

fn valid(p: &pb::LatLon) -> bool {
    p.latitude_deg.is_finite()
        && p.longitude_deg.is_finite()
        && (-90.0..=90.0).contains(&p.latitude_deg)
        && (-180.0..=180.0).contains(&p.longitude_deg)
}

#[tonic::async_trait]
impl RouteService for Api {
    type WatchGuidanceStream = GuidanceStream;

    async fn set_destination(
        &self,
        req: Request<pb::SetDestinationRequest>,
    ) -> Result<Response<pb::SetDestinationResponse>, Status> {
        let req = req.into_inner();
        let to = req
            .destination
            .filter(valid)
            .ok_or_else(|| Status::invalid_argument("a destination in degrees is required"))?;
        let at = (to.latitude_deg, to.longitude_deg);
        let name: String = req
            .name
            .trim()
            .chars()
            .take(places::MAX_NAME_CHARS)
            .collect();
        self.routing()?
            .commands
            .send(Command::SetDestination(at, name.clone()))
            .await
            .map_err(|_| Status::unavailable("the guide has stopped"))?;
        // A recent destination. A failure to keep it doesn't stop the route;
        // the places' own problem line says why.
        let detail = req.detail;
        if self.places.is_some()
            && let Ok(Err(e)) = self.places(move |p| p.add_recent(&name, &detail, at)).await
        {
            eprintln!("[navigation] recent destination not kept: {e}");
        }
        Ok(Response::new(pb::SetDestinationResponse {}))
    }

    async fn set_voice(
        &self,
        req: Request<pb::SetVoiceRequest>,
    ) -> Result<Response<pb::SetVoiceResponse>, Status> {
        let muted = req.into_inner().muted;
        let routing = self.routing()?;
        routing
            .commands
            .send(Command::SetVoice { muted })
            .await
            .map_err(|_| Status::unavailable("the guide has stopped"))?;
        // The guide applies it on its next turn, and says so in guidance.
        let mut rx = routing.guidance.clone();
        let applied = tokio::time::timeout(
            Duration::from_secs(2),
            rx.wait_for(|g| g.voice.as_ref().is_some_and(|v| v.muted == muted)),
        )
        .await;
        match applied {
            Ok(Ok(g)) => Ok(Response::new(pb::SetVoiceResponse {
                voice: g.voice.clone(),
            })),
            Ok(Err(_)) => Err(Status::unavailable("the guide has stopped")),
            Err(_) => Err(Status::unavailable(
                "spoken directions aren't running in this service",
            )),
        }
    }

    async fn clear_route(
        &self,
        _: Request<pb::ClearRouteRequest>,
    ) -> Result<Response<pb::ClearRouteResponse>, Status> {
        self.routing()?
            .commands
            .send(Command::Clear)
            .await
            .map_err(|_| Status::unavailable("the guide has stopped"))?;
        Ok(Response::new(pb::ClearRouteResponse {}))
    }

    async fn watch_guidance(
        &self,
        _: Request<pb::WatchGuidanceRequest>,
    ) -> Result<Response<Self::WatchGuidanceStream>, Status> {
        // Like the position: the empty value before the guide's first is
        // skipped.
        let stream = WatchStream::new(self.routing()?.guidance.clone())
            .filter(|g| g.state != pb::RouteState::Unspecified as i32)
            .map(|guidance| {
                Ok(pb::WatchGuidanceResponse {
                    guidance: Some(guidance),
                })
            });
        Ok(Response::new(Box::pin(stream)))
    }

    async fn get_route(
        &self,
        req: Request<pb::GetRouteRequest>,
    ) -> Result<Response<pb::GetRouteResponse>, Status> {
        let id = req.into_inner().route_id;
        let route = self.routing()?.route.borrow().clone();
        match route {
            Some(r) if r.id == id => Ok(Response::new(pb::GetRouteResponse {
                route: Some(route_to_pb(&r)),
            })),
            _ => Err(Status::not_found(format!(
                "no route {id}: replaced or cleared"
            ))),
        }
    }
}

#[tonic::async_trait]
impl SearchService for Api {
    async fn search(
        &self,
        req: Request<pb::SearchRequest>,
    ) -> Result<Response<pb::SearchResponse>, Status> {
        let req = req.into_inner();
        let query = search::clip(&req.query).to_string();
        let limit = search::limit(req.limit);
        let (near, from, age) = search::ranked_from(&self.position.borrow());
        let answer = mapbox_search::search_online_first(
            self.online_search.as_deref(),
            self.search.clone(),
            query,
            near,
            (from, age),
            limit,
        )
        .await;
        Ok(Response::new(answer))
    }
}

fn refused(e: Refused) -> Status {
    match e {
        Refused::Invalid(why) => Status::invalid_argument(why),
        Refused::NotFound(id) => Status::not_found(format!("no saved place {id}")),
        Refused::Full(why) => Status::failed_precondition(why),
        Refused::Write(why) => Status::unavailable(why),
    }
}

#[tonic::async_trait]
impl PlacesService for Api {
    async fn list_places(
        &self,
        _: Request<pb::ListPlacesRequest>,
    ) -> Result<Response<pb::ListPlacesResponse>, Status> {
        Ok(Response::new(pb::ListPlacesResponse {
            places: Some(self.places(|p| p.to_pb()).await?),
        }))
    }

    async fn save_place(
        &self,
        req: Request<pb::SavePlaceRequest>,
    ) -> Result<Response<pb::SavePlaceResponse>, Status> {
        let req = req.into_inner();
        let at = req
            .location
            .filter(valid)
            .map(|l| (l.latitude_deg, l.longitude_deg))
            .ok_or_else(|| Status::invalid_argument("a location in degrees is required"))?;
        let kind = match pb::PlaceKind::try_from(req.kind) {
            Ok(pb::PlaceKind::Home) => places::Kind::Home,
            Ok(pb::PlaceKind::Favourite) => places::Kind::Favourite,
            _ => return Err(Status::invalid_argument("save as HOME or FAVOURITE")),
        };
        self.places(move |p| {
            p.save(kind, &req.name, &req.detail, at)
                .map(|_| p.to_pb())
                .map_err(refused)
        })
        .await?
        .map(|places| {
            Response::new(pb::SavePlaceResponse {
                places: Some(places),
            })
        })
    }

    async fn rename_place(
        &self,
        req: Request<pb::RenamePlaceRequest>,
    ) -> Result<Response<pb::RenamePlaceResponse>, Status> {
        let req = req.into_inner();
        self.places(move |p| {
            p.rename(req.id, &req.name)
                .map(|()| p.to_pb())
                .map_err(refused)
        })
        .await?
        .map(|places| {
            Response::new(pb::RenamePlaceResponse {
                places: Some(places),
            })
        })
    }

    async fn delete_place(
        &self,
        req: Request<pb::DeletePlaceRequest>,
    ) -> Result<Response<pb::DeletePlaceResponse>, Status> {
        let id = req.into_inner().id;
        self.places(move |p| p.delete(id).map(|()| p.to_pb()).map_err(refused))
            .await?
            .map(|places| {
                Response::new(pb::DeletePlaceResponse {
                    places: Some(places),
                })
            })
    }
}

#[tonic::async_trait]
impl OnlineMapService for Api {
    async fn get_online_map_status(
        &self,
        _: Request<pb::GetOnlineMapStatusRequest>,
    ) -> Result<Response<pb::GetOnlineMapStatusResponse>, Status> {
        let r = match self.online_map.as_ref().filter(|t| t.configured()) {
            Some(t) => pb::GetOnlineMapStatusResponse {
                configured: true,
                detail: format!("Mapbox: {} by day, {} by night", t.style_day, t.style_night),
                attribution: mapbox::ATTRIBUTION.to_string(),
                tile_size: mapbox::TILE_SIZE,
                max_zoom: mapbox::MAX_ZOOM,
                routing_online: t.routing_online(),
            },
            None => pb::GetOnlineMapStatusResponse {
                detail: "no Mapbox token (MAPBOX_ACCESS_TOKEN): offline only".to_string(),
                ..Default::default()
            },
        };
        Ok(Response::new(r))
    }

    async fn get_tile(
        &self,
        req: Request<pb::GetTileRequest>,
    ) -> Result<Response<pb::GetTileResponse>, Status> {
        let r = req.into_inner();
        let tiles = self
            .online_map
            .as_ref()
            .filter(|t| t.configured())
            .ok_or_else(|| Status::failed_precondition("no Mapbox token"))?;
        if r.z > mapbox::MAX_ZOOM || u64::from(r.x) >= 1 << r.z || u64::from(r.y) >= 1 << r.z {
            return Err(Status::invalid_argument(format!(
                "no tile {}/{}/{}",
                r.z, r.x, r.y
            )));
        }
        let night = r.style == pb::MapStyle::Night as i32;
        match tiles.get(night, r.z, r.x, r.y).await {
            Ok(t) => Ok(Response::new(pb::GetTileResponse {
                data: t.body.clone(),
                content_type: t.content_type.clone(),
            })),
            Err(None) => Err(Status::failed_precondition("no Mapbox token")),
            Err(Some(why)) => Err(Status::unavailable(why)),
        }
    }
}

/// Serves on `unix:PATH` or `tcp:HOST:PORT` until the server fails.
pub async fn serve(listen: &str, api: Api) -> Result<(), String> {
    let mut builder = tonic::transport::Server::builder();
    let router = builder
        .add_service(PositionServiceServer::new(api.clone()))
        .add_service(RouteServiceServer::new(api.clone()))
        .add_service(SearchServiceServer::new(api.clone()))
        .add_service(PlacesServiceServer::new(api.clone()))
        .add_service(OnlineMapServiceServer::new(api));
    if let Some(path) = listen.strip_prefix("unix:") {
        let path = Path::new(path);
        if let Some(dir) = path.parent() {
            std::fs::create_dir_all(dir).map_err(|e| e.to_string())?;
        }
        let _ = std::fs::remove_file(path); // stale socket from a previous run
        let listener = tokio::net::UnixListener::bind(path).map_err(|e| e.to_string())?;
        eprintln!("[navigation] API on unix:{}", path.display());
        let incoming = tokio_stream::wrappers::UnixListenerStream::new(listener);
        router
            .serve_with_incoming(incoming)
            .await
            .map_err(|e| e.to_string())
    } else if let Some(addr) = listen.strip_prefix("tcp:") {
        let addr: std::net::SocketAddr = addr.parse().map_err(|e| format!("{e}"))?;
        eprintln!("[navigation] API on tcp:{addr}");
        router.serve(addr).await.map_err(|e| e.to_string())
    } else {
        Err("must start with unix: or tcp:".to_string())
    }
}
