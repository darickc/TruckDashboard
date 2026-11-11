//! `f250.nav.v1.PositionService`: the publisher's latest position, then
//! each new one.

use std::path::Path;
use std::pin::Pin;

use f250_proto::nav::v1 as pb;
use pb::position_service_server::{PositionService, PositionServiceServer};
use tokio::sync::watch;
use tokio_stream::{Stream, StreamExt, wrappers::WatchStream};
use tonic::{Request, Response, Status};

#[derive(Clone)]
pub struct Api {
    position: watch::Receiver<pb::Position>,
}

impl Api {
    pub fn new(position: watch::Receiver<pb::Position>) -> Self {
        Api { position }
    }
}

type PositionStream = Pin<Box<dyn Stream<Item = Result<pb::WatchPositionResponse, Status>> + Send>>;

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

/// Serves on `unix:PATH` or `tcp:HOST:PORT` until the server fails.
pub async fn serve(listen: &str, api: Api) -> Result<(), String> {
    let router = tonic::transport::Server::builder().add_service(PositionServiceServer::new(api));
    if let Some(path) = listen.strip_prefix("unix:") {
        let path = Path::new(path);
        if let Some(dir) = path.parent() {
            std::fs::create_dir_all(dir).map_err(|e| e.to_string())?;
        }
        let _ = std::fs::remove_file(path); // stale socket from a previous run
        let listener = tokio::net::UnixListener::bind(path).map_err(|e| e.to_string())?;
        eprintln!("[navigation] position API on unix:{}", path.display());
        let incoming = tokio_stream::wrappers::UnixListenerStream::new(listener);
        router
            .serve_with_incoming(incoming)
            .await
            .map_err(|e| e.to_string())
    } else if let Some(addr) = listen.strip_prefix("tcp:") {
        let addr: std::net::SocketAddr = addr.parse().map_err(|e| format!("{e}"))?;
        eprintln!("[navigation] position API on tcp:{addr}");
        router.serve(addr).await.map_err(|e| e.to_string())
    } else {
        Err("must start with unix: or tcp:".to_string())
    }
}
