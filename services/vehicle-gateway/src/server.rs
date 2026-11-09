//! gRPC services. Thin: every call is forwarded to the control loop
//! (crate::core), which owns the transport; snapshots come from the loop's
//! watch channel.

use std::pin::Pin;
use std::sync::Arc;
use std::time::Duration;

use f250_proto::vehicle::v1 as pb;
use pb::diagnostics_service_server::DiagnosticsService;
use pb::vehicle_service_server::VehicleService;
use tokio::sync::{mpsc, oneshot, watch};
use tokio_stream::Stream;
use tonic::{Request, Response, Status};

use crate::core::{Command, Reply};

#[derive(Clone)]
pub struct Api {
    cmds: mpsc::Sender<Command>,
    snapshots: watch::Receiver<Arc<pb::Snapshot>>,
}

impl Api {
    pub fn new(cmds: mpsc::Sender<Command>, snapshots: watch::Receiver<Arc<pb::Snapshot>>) -> Self {
        Api { cmds, snapshots }
    }

    async fn call<T>(&self, make: impl FnOnce(Reply<T>) -> Command) -> Result<T, Status> {
        let (tx, rx) = oneshot::channel();
        self.cmds
            .send(make(tx))
            .await
            .map_err(|_| Status::unavailable("gateway loop stopped"))?;
        match rx.await {
            Ok(Ok(v)) => Ok(v),
            Ok(Err(e)) => Err(Status::failed_precondition(e)),
            Err(_) => Err(Status::unavailable("gateway loop stopped")),
        }
    }
}

type SnapshotStream =
    Pin<Box<dyn Stream<Item = Result<pb::StreamSnapshotsResponse, Status>> + Send>>;

#[tonic::async_trait]
impl VehicleService for Api {
    async fn list_signals(
        &self,
        _: Request<pb::ListSignalsRequest>,
    ) -> Result<Response<pb::ListSignalsResponse>, Status> {
        let signals = self.call(Command::ListSignals).await?;
        Ok(Response::new(pb::ListSignalsResponse { signals }))
    }

    type StreamSnapshotsStream = SnapshotStream;

    async fn stream_snapshots(
        &self,
        req: Request<pb::StreamSnapshotsRequest>,
    ) -> Result<Response<Self::StreamSnapshotsStream>, Status> {
        let period = match req.into_inner().period_ms {
            0 => 250,
            p => p.clamp(100, 2000),
        };
        let mut rx = self.snapshots.clone();
        let stream = async_stream(move |tx| async move {
            let mut tick = tokio::time::interval(Duration::from_millis(u64::from(period)));
            tick.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Skip);
            loop {
                tick.tick().await;
                let snap = rx.borrow_and_update().clone();
                if tx
                    .send(Ok(pb::StreamSnapshotsResponse {
                        snapshot: Some((*snap).clone()),
                    }))
                    .await
                    .is_err()
                {
                    return; // client went away
                }
            }
        });
        Ok(Response::new(Box::pin(stream)))
    }

    async fn list_events(
        &self,
        req: Request<pb::ListEventsRequest>,
    ) -> Result<Response<pb::ListEventsResponse>, Status> {
        let limit = req.into_inner().limit;
        Ok(Response::new(
            self.call(|r| Command::ListEvents(limit, r)).await?,
        ))
    }

    async fn set_calibration(
        &self,
        req: Request<pb::SetCalibrationRequest>,
    ) -> Result<Response<pb::SetCalibrationResponse>, Status> {
        let r = req.into_inner();
        let signal = self
            .call(|reply| Command::SetCalibration {
                id: r.signal_id,
                scale: r.scale,
                offset: r.offset,
                reply,
            })
            .await?;
        Ok(Response::new(pb::SetCalibrationResponse {
            signal: Some(signal),
        }))
    }
}

#[tonic::async_trait]
impl DiagnosticsService for Api {
    async fn set_polling(
        &self,
        req: Request<pb::SetPollingRequest>,
    ) -> Result<Response<pb::SetPollingResponse>, Status> {
        let r = req.into_inner();
        self.call(|reply| Command::SetPolling {
            id: r.signal_id,
            enabled: r.enabled,
            reply,
        })
        .await?;
        Ok(Response::new(pb::SetPollingResponse {}))
    }

    async fn probe(
        &self,
        req: Request<pb::ProbeRequest>,
    ) -> Result<Response<pb::ProbeResponse>, Status> {
        let r = req.into_inner();
        Ok(Response::new(
            self.call(|reply| Command::Probe {
                id: r.signal_id,
                count: r.count,
                reply,
            })
            .await?,
        ))
    }

    async fn raw(&self, req: Request<pb::RawRequest>) -> Result<Response<pb::RawResponse>, Status> {
        let line = req.into_inner().line;
        Ok(Response::new(
            self.call(|reply| Command::Raw { line, reply }).await?,
        ))
    }

    async fn stats(
        &self,
        req: Request<pb::StatsRequest>,
    ) -> Result<Response<pb::StatsResponse>, Status> {
        let reset = req.into_inner().reset;
        Ok(Response::new(
            self.call(|reply| Command::Stats { reset, reply }).await?,
        ))
    }
}

/// A stream fed by a spawned task through a bounded channel.
fn async_stream<T, F, Fut>(f: F) -> impl Stream<Item = T>
where
    T: Send + 'static,
    F: FnOnce(mpsc::Sender<T>) -> Fut,
    Fut: std::future::Future<Output = ()> + Send + 'static,
{
    let (tx, rx) = mpsc::channel(4);
    tokio::spawn(f(tx));
    tokio_stream::wrappers::ReceiverStream::new(rx)
}
