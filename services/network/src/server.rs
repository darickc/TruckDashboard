//! `f250.network.v1.WifiService` (ADR-0052).

use std::path::Path;
use std::pin::Pin;
use std::sync::Arc;

use f250_proto::network::v1 as pb;
use pb::wifi_service_server::{WifiService, WifiServiceServer};
use tokio::sync::{Notify, watch};
use tokio_stream::{Stream, StreamExt, wrappers::WatchStream};
use tonic::{Request, Response, Status};

use crate::Backend;

pub struct Api<B: Backend> {
    backend: Arc<B>,
    status: watch::Receiver<pb::WifiStatus>,
    poke: Arc<Notify>,
}

impl<B: Backend> Clone for Api<B> {
    fn clone(&self) -> Self {
        Api {
            backend: self.backend.clone(),
            status: self.status.clone(),
            poke: self.poke.clone(),
        }
    }
}

impl<B: Backend> Api<B> {
    pub fn new(
        backend: Arc<B>,
        status: watch::Receiver<pb::WifiStatus>,
        poke: Arc<Notify>,
    ) -> Self {
        Api {
            backend,
            status,
            poke,
        }
    }

    fn done<T>(&self, r: Result<(), String>, ok: T) -> Result<Response<T>, Status> {
        self.poke.notify_one();
        r.map(|()| Response::new(ok))
            .map_err(Status::failed_precondition)
    }
}

type WifiStream = Pin<Box<dyn Stream<Item = Result<pb::WatchWifiResponse, Status>> + Send>>;

#[tonic::async_trait]
impl<B: Backend> WifiService for Api<B> {
    type WatchWifiStream = WifiStream;

    async fn watch_wifi(
        &self,
        _: Request<pb::WatchWifiRequest>,
    ) -> Result<Response<Self::WatchWifiStream>, Status> {
        let s = WatchStream::new(self.status.clone()).map(|status| {
            Ok(pb::WatchWifiResponse {
                status: Some(status),
            })
        });
        Ok(Response::new(Box::pin(s)))
    }

    async fn set_wifi_enabled(
        &self,
        req: Request<pb::SetWifiEnabledRequest>,
    ) -> Result<Response<pb::SetWifiEnabledResponse>, Status> {
        let on = req.into_inner().enabled;
        let r = self.backend.set_enabled(on).await;
        self.done(r, pb::SetWifiEnabledResponse {})
    }

    async fn scan_wifi(
        &self,
        _: Request<pb::ScanWifiRequest>,
    ) -> Result<Response<pb::ScanWifiResponse>, Status> {
        // The scan's own state shows while it runs.
        self.poke.notify_one();
        let r = self.backend.scan().await;
        self.done(r, pb::ScanWifiResponse {})
    }

    async fn connect_wifi(
        &self,
        req: Request<pb::ConnectWifiRequest>,
    ) -> Result<Response<pb::ConnectWifiResponse>, Status> {
        let r = req.into_inner();
        if r.id.is_empty() {
            return Err(Status::invalid_argument("which network?"));
        }
        // Connecting shows while it runs: poll during the attempt.
        let poke = self.poke.clone();
        let ticker = tokio::spawn(async move {
            loop {
                tokio::time::sleep(std::time::Duration::from_millis(700)).await;
                poke.notify_one();
            }
        });
        let out = self.backend.connect(&r.id, &r.passphrase).await;
        ticker.abort();
        self.poke.notify_one();
        Ok(Response::new(match out {
            Ok(()) => pb::ConnectWifiResponse {
                connected: true,
                detail: String::new(),
            },
            Err(why) => {
                eprintln!("[network] joining {} failed: {why}", r.id);
                pb::ConnectWifiResponse {
                    connected: false,
                    detail: why,
                }
            }
        }))
    }

    async fn disconnect_wifi(
        &self,
        req: Request<pb::DisconnectWifiRequest>,
    ) -> Result<Response<pb::DisconnectWifiResponse>, Status> {
        let r = self.backend.disconnect(&req.into_inner().id).await;
        self.done(r, pb::DisconnectWifiResponse {})
    }

    async fn forget_wifi(
        &self,
        req: Request<pb::ForgetWifiRequest>,
    ) -> Result<Response<pb::ForgetWifiResponse>, Status> {
        let r = self.backend.forget(&req.into_inner().id).await;
        self.done(r, pb::ForgetWifiResponse {})
    }
}

/// Serves on `unix:PATH` or `tcp:HOST:PORT` until the server fails.
pub async fn serve<B: Backend>(listen: &str, api: Api<B>) -> Result<(), String> {
    let router = tonic::transport::Server::builder().add_service(WifiServiceServer::new(api));
    if let Some(path) = listen.strip_prefix("unix:") {
        let path = Path::new(path);
        if let Some(dir) = path.parent() {
            std::fs::create_dir_all(dir).map_err(|e| e.to_string())?;
        }
        let _ = std::fs::remove_file(path); // stale socket from a previous run
        let listener = tokio::net::UnixListener::bind(path).map_err(|e| e.to_string())?;
        eprintln!("[network] API on unix:{}", path.display());
        router
            .serve_with_incoming(tokio_stream::wrappers::UnixListenerStream::new(listener))
            .await
            .map_err(|e| e.to_string())
    } else if let Some(addr) = listen.strip_prefix("tcp:") {
        let addr: std::net::SocketAddr = addr.parse().map_err(|e| format!("{e}"))?;
        eprintln!("[network] API on tcp:{addr}");
        router.serve(addr).await.map_err(|e| e.to_string())
    } else {
        Err("must start with unix: or tcp:".to_string())
    }
}
