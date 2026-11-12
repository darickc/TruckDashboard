//! The `f250.export.v1` gRPC service: thin, over [`Exporter`]. Calls that
//! touch the drive or a stick run on blocking threads.

use std::pin::Pin;
use std::sync::Arc;

use f250_proto::export::v1 as pb;
use pb::export_service_server::ExportService;
use tokio_stream::{Stream, StreamExt, wrappers::WatchStream};
use tonic::{Request, Response, Status};

use crate::copy::Ref;
use crate::exporter::Exporter;

#[derive(Clone)]
pub struct Api {
    exporter: Arc<Exporter>,
}

impl Api {
    pub fn new(exporter: Arc<Exporter>) -> Api {
        Api { exporter }
    }
}

type ExportStream = Pin<Box<dyn Stream<Item = Result<pb::WatchExportResponse, Status>> + Send>>;

fn source_of(s: &str) -> String {
    if s.trim().is_empty() {
        "unnamed client".to_string()
    } else {
        s.chars().take(64).collect()
    }
}

/// Every request is refused beyond this many recordings (a day of both
/// cameras in one-minute segments is under 3000).
const MAX_REFS: usize = 20_000;

#[tonic::async_trait]
impl ExportService for Api {
    type WatchExportStream = ExportStream;

    async fn list_recordings(
        &self,
        _: Request<pb::ListRecordingsRequest>,
    ) -> Result<Response<pb::ListRecordingsResponse>, Status> {
        let e = Arc::clone(&self.exporter);
        let list = tokio::task::spawn_blocking(move || e.list())
            .await
            .map_err(|_| Status::internal("listing panicked"))?;
        Ok(Response::new(list))
    }

    async fn watch_export(
        &self,
        _: Request<pb::WatchExportRequest>,
    ) -> Result<Response<Self::WatchExportStream>, Status> {
        // WatchStream yields the current value first, then each change.
        let stream = WatchStream::new(self.exporter.watch()).map(Ok);
        Ok(Response::new(Box::pin(stream)))
    }

    async fn start_copy(
        &self,
        req: Request<pb::StartCopyRequest>,
    ) -> Result<Response<pb::StartCopyResponse>, Status> {
        let req = req.into_inner();
        if req.recordings.len() > MAX_REFS {
            return Err(Status::invalid_argument(format!(
                "at most {MAX_REFS} recordings in one copy"
            )));
        }
        let refs: Vec<Ref> = req
            .recordings
            .into_iter()
            .map(|r| Ref {
                camera: r.camera,
                file_name: r.file_name,
                protected: r.protected,
            })
            .collect();
        let source = source_of(&req.source);
        let e = Arc::clone(&self.exporter);
        let r = tokio::task::spawn_blocking(move || e.start(&req.device, &refs, &source))
            .await
            .map_err(|_| Status::internal("starting the copy panicked"))?;
        Ok(Response::new(r))
    }

    async fn cancel_copy(
        &self,
        _: Request<pb::CancelCopyRequest>,
    ) -> Result<Response<pb::CancelCopyResponse>, Status> {
        Ok(Response::new(pb::CancelCopyResponse {
            cancelling: self.exporter.cancel(),
        }))
    }
}
