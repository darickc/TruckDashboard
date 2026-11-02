//! `vehicle-gateway`: see `--help` and docs/architecture/overview.md.
//!
//! Examples:
//!   vehicle-gateway                                   # simulator, unix:/tmp/f250/vehicle.sock
//!   vehicle-gateway --scenario eot_ect_freeze --sim-start-s 110
//!   vehicle-gateway --transport obdlink --adapter rfcomm:00:04:3E:85:EA:FC --transmit \
//!       --traffic-log /var/lib/f250/traffic

use clap::Parser;
use f250_proto::vehicle::v1::diagnostics_service_server::DiagnosticsServiceServer;
use f250_proto::vehicle::v1::vehicle_service_server::VehicleServiceServer;
use tokio::sync::mpsc;
use tonic::transport::Server;
use vehicle_gateway::config::Config;
use vehicle_gateway::core::Core;
use vehicle_gateway::server::Api;

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    let cfg = Config::parse();
    let listen = cfg.listen.clone();
    let (core, driver_rx, snapshots) = Core::new(cfg)?;
    let (cmd_tx, cmd_rx) = mpsc::channel(64);
    tokio::spawn(core.run(cmd_rx, driver_rx));

    let api = Api::new(cmd_tx, snapshots);
    let router = Server::builder()
        .add_service(VehicleServiceServer::new(api.clone()))
        .add_service(DiagnosticsServiceServer::new(api));

    let shutdown = async {
        let _ = tokio::signal::ctrl_c().await;
        eprintln!("[gateway] shutting down");
    };
    if let Some(path) = listen.strip_prefix("unix:") {
        let path = std::path::Path::new(path);
        if let Some(dir) = path.parent() {
            std::fs::create_dir_all(dir)?;
        }
        let _ = std::fs::remove_file(path); // stale socket from a previous run
        let listener = tokio::net::UnixListener::bind(path)?;
        eprintln!("[gateway] listening on unix:{}", path.display());
        let incoming = tokio_stream::wrappers::UnixListenerStream::new(listener);
        router
            .serve_with_incoming_shutdown(incoming, shutdown)
            .await?;
        let _ = std::fs::remove_file(path);
    } else if let Some(addr) = listen.strip_prefix("tcp:") {
        let addr: std::net::SocketAddr = addr.parse()?;
        eprintln!("[gateway] listening on tcp:{addr}");
        router.serve_with_shutdown(addr, shutdown).await?;
    } else {
        return Err(format!("--listen must start with unix: or tcp:, got {listen}").into());
    }
    Ok(())
}
