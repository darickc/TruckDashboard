//! `f250.nav.v1.PositionService`: the publisher's latest position, then
//! each new one. `RouteService`: commands to the guide, its guidance and
//! its current route.

use std::path::Path;
use std::pin::Pin;
use std::sync::Arc;

use f250_proto::nav::v1 as pb;
use pb::position_service_server::{PositionService, PositionServiceServer};
use pb::route_service_server::{RouteService, RouteServiceServer};
use tokio::sync::{mpsc, watch};
use tokio_stream::{Stream, StreamExt, wrappers::WatchStream};
use tonic::{Request, Response, Status};

use crate::guide::{Command, route_to_pb};
use crate::valhalla::Route;

#[derive(Clone)]
pub struct Api {
    position: watch::Receiver<pb::Position>,
    routing: Option<RoutingApi>,
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
        }
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
        let to = req
            .into_inner()
            .destination
            .filter(valid)
            .ok_or_else(|| Status::invalid_argument("a destination in degrees is required"))?;
        self.routing()?
            .commands
            .send(Command::SetDestination((to.latitude_deg, to.longitude_deg)))
            .await
            .map_err(|_| Status::unavailable("the guide has stopped"))?;
        Ok(Response::new(pb::SetDestinationResponse {}))
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

/// Serves on `unix:PATH` or `tcp:HOST:PORT` until the server fails.
pub async fn serve(listen: &str, api: Api) -> Result<(), String> {
    let mut builder = tonic::transport::Server::builder();
    let router = builder
        .add_service(PositionServiceServer::new(api.clone()))
        .add_service(RouteServiceServer::new(api));
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
