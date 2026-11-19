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
use crate::reverse::{self, Feed};

/// The longest gap between two `WatchReverse` messages.
const REVERSE_EVERY: Duration = Duration::from_millis(100);

#[derive(Clone)]
pub struct Api {
    cmds: mpsc::Sender<Command>,
    snapshots: watch::Receiver<Arc<pb::Snapshot>>,
    reverse: Feed,
}

impl Api {
    pub fn new(cmds: mpsc::Sender<Command>, snapshots: watch::Receiver<Arc<pb::Snapshot>>) -> Self {
        Api {
            cmds,
            snapshots,
            reverse: Feed::absent("no broadcast reader in this gateway"),
        }
    }

    /// Where `WatchReverse` reads from (ADR-0046).
    pub fn with_reverse(mut self, reverse: Feed) -> Self {
        self.reverse = reverse;
        self
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
type ReverseStream = Pin<Box<dyn Stream<Item = Result<pb::WatchReverseResponse, Status>> + Send>>;

/// One `WatchReverse` message.
pub fn reverse_message(r: &reverse::Report) -> pb::WatchReverseResponse {
    pb::WatchReverseResponse {
        state: match r.state {
            reverse::State::Unknown => pb::ReverseState::Unknown,
            reverse::State::NotEngaged => pb::ReverseState::NotEngaged,
            reverse::State::Engaged => pb::ReverseState::Engaged,
        } as i32,
        age_ms: r
            .age
            .map_or(0, |a| u32::try_from(a.as_millis()).unwrap_or(u32::MAX)),
        has_age: r.age.is_some(),
        detail: r.detail.clone(),
    }
}

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

    type WatchReverseStream = ReverseStream;

    async fn watch_reverse(
        &self,
        _: Request<pb::WatchReverseRequest>,
    ) -> Result<Response<Self::WatchReverseStream>, Status> {
        let feed = self.reverse.clone();
        let mut changes = feed.changes();
        let stream = async_stream(move |tx| async move {
            let mut tick = tokio::time::interval(REVERSE_EVERY);
            tick.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Skip);
            // False once the feed can't change: no reader (the simulator, the
            // MX+ alone) or one that ended. Then only the ticks send. (This
            // once swapped in a fresh receiver whose sender was dropped at
            // once, so `changed()` failed straight away again and the loop
            // sent as fast as the client read: a core each in the gateway
            // and camera-manager on the bench Pi in simulation, 2026-11-19.)
            let mut can_change = true;
            loop {
                tokio::select! {
                    _ = tick.tick() => {}
                    r = changes.changed(), if can_change => {
                        if r.is_err() {
                            can_change = false;
                            continue;
                        }
                        tick.reset();
                    }
                }
                let msg = reverse_message(&feed.report());
                if tx.send(Ok(msg)).await.is_err() {
                    return; // client went away
                }
            }
        });
        Ok(Response::new(Box::pin(stream)))
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
