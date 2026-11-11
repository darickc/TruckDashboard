//! `camera-manager`: see `--help` and docs/architecture/adr/0026-camera-manager-interfaces.md.
//!
//! Examples:
//!   camera-manager --camera rear=/dev/video0          # unix:/tmp/f250/camera.sock
//!   camera-manager --listen unix:/run/f250-camera/camera.sock \
//!       --camera rear=/dev/v4l/by-id/usb-046d_0804-video-index0
//!   camera-manager --camera front=/dev/video0 --record front \
//!       --record-dir /tmp/f250-video --record-drive ""   # development only

use camera_manager::config::{Config, MediaChoice, camera_name};
use camera_manager::manager::{Command, Manager};
use camera_manager::media::Media;
use camera_manager::pipeline::LaunchMedia;
use camera_manager::server::Api;
use clap::Parser;
use f250_proto::camera::v1::camera_service_server::CameraServiceServer;
use f250_sd_notify::{Notifier, run_watchdog};
use tokio::sync::mpsc;
use tonic::transport::Server;

/// How long a stop may take before camera-manager exits regardless: a
/// recording gets up to 3 s to finish its segment, then the clean-stop
/// marker. Inside the unit's TimeoutStopSec (10 s).
const STOP_GRACE: std::time::Duration = std::time::Duration::from_secs(8);

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    let cfg = Config::parse();
    let env: std::collections::HashMap<String, String> = std::env::vars().collect();
    let settings = cfg
        .settings_with(&env)
        .map_err(|e| format!("recording settings: {e}"))?;
    if settings.cameras.is_empty() {
        eprintln!("[camera] no --camera given: every camera will show as unavailable");
    }
    for (c, d) in &settings.cameras {
        eprintln!("[camera] {} camera: {d}", camera_name(*c));
    }
    eprintln!("[camera] automatic reverse off; speed limit off (ADR-0024, ADR-0026)");

    let media = make_media(cfg.media, &settings.gst_launch)?;
    match (&settings.recording, media.can_record()) {
        (None, _) => eprintln!("[camera] recording off (--record)"),
        (Some(r), Ok(())) => eprintln!(
            "[camera] recording {} into {} (drive {}); retention {:?}",
            r.cameras
                .iter()
                .map(|c| camera_name(*c))
                .collect::<Vec<_>>()
                .join(", "),
            r.root.display(),
            r.mount
                .as_ref()
                .map_or("not checked".to_string(), |m| m.display().to_string()),
            r.settings
        ),
        (Some(_), Err(why)) => eprintln!("[camera] recording asked for, but {why}"),
    }

    let (manager, watches) = Manager::new(settings, media);
    let (cmd_tx, cmd_rx) = mpsc::channel(32);
    let notifier = Notifier::from_env();
    if let Some(problem) = notifier.problem() {
        eprintln!("[camera] {problem}");
    }
    tokio::spawn(run_watchdog(
        notifier.clone(),
        manager.heartbeat(),
        "camera",
    ));
    let manager_done = tokio::spawn(manager.run(cmd_rx));

    let stop_cmds = cmd_tx.clone();
    let router = Server::builder().add_service(CameraServiceServer::new(Api::new(cmd_tx, watches)));

    let stopping = notifier.clone();
    // SIGTERM (systemd) and Ctrl-C: the loop stops every capture (closing
    // the window, finishing the segments being recorded) and returns, which ends every WatchView stream; then the
    // server's graceful shutdown can finish. A stuck stop is cut short so
    // shutdown never waits on camera-manager (the unit's TimeoutStopSec is
    // the last resort).
    let shutdown = async move {
        let mut term =
            tokio::signal::unix::signal(tokio::signal::unix::SignalKind::terminate()).ok();
        tokio::select! {
            _ = tokio::signal::ctrl_c() => {}
            Some(()) = async { match term.as_mut() { Some(t) => t.recv().await, None => std::future::pending().await } } => {}
        }
        eprintln!("[camera] shutting down");
        let _ = stopping.stopping();
        let _ = stop_cmds.send(Command::Shutdown).await;
        tokio::spawn(async {
            tokio::time::sleep(STOP_GRACE).await;
            eprintln!(
                "[camera] still stopping after {} s: exiting anyway",
                STOP_GRACE.as_secs()
            );
            std::process::exit(1);
        });
    };
    let ready = |at: String| {
        eprintln!("[camera] listening on {at}");
        if let Err(e) = notifier.ready(&format!("listening on {at}")) {
            eprintln!("[camera] systemd READY not sent: {e}");
        }
    };
    let listen = cfg.listen.clone();
    if let Some(path) = listen.strip_prefix("unix:") {
        let path = std::path::Path::new(path);
        if let Some(dir) = path.parent() {
            std::fs::create_dir_all(dir)?;
        }
        let _ = std::fs::remove_file(path); // stale socket from a previous run
        let listener = tokio::net::UnixListener::bind(path)?;
        ready(format!("unix:{}", path.display()));
        let incoming = tokio_stream::wrappers::UnixListenerStream::new(listener);
        router
            .serve_with_incoming_shutdown(incoming, shutdown)
            .await?;
        let _ = std::fs::remove_file(path);
    } else if let Some(addr) = listen.strip_prefix("tcp:") {
        let addr: std::net::SocketAddr = addr.parse()?;
        ready(format!("tcp:{addr}"));
        router.serve_with_shutdown(addr, shutdown).await?;
    } else {
        return Err(format!("--listen must start with unix: or tcp:, got {listen}").into());
    }
    // The server dropped its command sender: the loop stops the pipeline
    // and returns.
    let _ = manager_done.await;
    Ok(())
}

fn make_media(choice: MediaChoice, gst_launch: &str) -> Result<Box<dyn Media>, String> {
    match choice {
        MediaChoice::Launch => Ok(Box::new(LaunchMedia {
            program: gst_launch.to_string(),
            why_not_recording: if cfg!(feature = "gstreamer") {
                "--media launch can't record: recording needs the in-process GStreamer pipeline"
                    .into()
            } else {
                "this camera-manager was built without GStreamer (the gstreamer feature), so it \
                 can't record"
                    .into()
            },
        })),
        #[cfg(feature = "gstreamer")]
        MediaChoice::Gstreamer => camera_manager::gst::GstMedia::new()
            .map(|m| Box::new(m) as Box<dyn Media>)
            .map_err(|e| format!("GStreamer: {e}")),
        #[cfg(not(feature = "gstreamer"))]
        MediaChoice::Gstreamer => {
            Err("--media gstreamer: this build has no GStreamer (the gstreamer feature)".into())
        }
    }
}
