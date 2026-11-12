//! `usb-export`: see `--help` and
//! docs/architecture/adr/0037-recordings-to-a-usb-stick.md.
//!
//! Examples:
//!   usb-export --listen unix:/run/f250-export/export.sock      # the Pi
//!   usb-export --video-dir /tmp/f250-video --drive "" \
//!       --stick-dir sdz1=/tmp/f250-stick                        # development

use std::path::PathBuf;
use std::sync::Arc;
use std::time::Duration;

use clap::Parser;
use f250_proto::export::v1::export_service_server::ExportServiceServer;
use f250_sd_notify::Notifier;
use tonic::transport::Server;
use usb_export::exporter::{Config, Discover, Exporter};
use usb_export::server::Api;
use usb_export::stickfs::{DirFs, StickFs, SystemFs, valid_device};
use usb_export::sticks::{self, Found};

#[derive(Debug, Parser)]
#[command(
    about = "Copies dashcam recordings to a USB stick, for the dashboard (f250.export.v1, ADR-0037)"
)]
struct Args {
    /// Where to serve f250.export.v1: unix:<path> or tcp:<host:port>.
    #[arg(long, default_value = "unix:/tmp/f250/export.sock")]
    listen: String,
    /// camera-manager's recordings.
    #[arg(long, default_value = "/var/lib/f250/storage/video")]
    video_dir: PathBuf,
    /// The data drive's mount point; without it mounted there are no
    /// recordings. Empty: not checked (development).
    #[arg(long, default_value = "/var/lib/f250/storage")]
    drive: String,
    /// Where sticks are mounted while checked or copied to (the unit's
    /// runtime directory, in its own mount namespace).
    #[arg(long, default_value = "/run/f250-export")]
    mount_dir: PathBuf,
    #[arg(long, default_value = "/sys/class/block")]
    sys_block: PathBuf,
    #[arg(long, default_value = "/run/udev/data")]
    udev_data: PathBuf,
    #[arg(long, default_value = "/dev")]
    dev_dir: PathBuf,
    /// The map import's lock: no stick is mounted writable while it exists.
    #[arg(long, default_value = "/run/f250-maps/import.lock")]
    map_lock: PathBuf,
    /// How often to look for sticks, in milliseconds.
    #[arg(long, default_value_t = 2000)]
    poll_ms: u64,
    /// Development: DEVICE=DIR, a directory standing in for an exFAT stick
    /// (nothing is mounted, sysfs isn't read). Repeatable.
    #[arg(long, value_name = "DEVICE=DIR")]
    stick_dir: Vec<String>,
}

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    let args = Args::parse();
    let cfg = Config {
        video_root: args.video_dir.clone(),
        drive: (!args.drive.is_empty()).then(|| PathBuf::from(&args.drive)),
        map_lock: args.map_lock.clone(),
        writing_window: Duration::from_secs(15),
    };
    let (fs, discover): (Arc<dyn StickFs>, Discover) = if args.stick_dir.is_empty() {
        let paths = sticks::Paths {
            sys_block: args.sys_block.clone(),
            udev_data: args.udev_data.clone(),
        };
        (
            Arc::new(SystemFs {
                mount_dir: args.mount_dir.clone(),
                dev_dir: args.dev_dir.clone(),
                sys_block: args.sys_block.clone(),
            }),
            Box::new(move || sticks::scan(&paths)),
        )
    } else {
        let dirs = DirFs::new();
        let mut found = Vec::new();
        for s in &args.stick_dir {
            let (dev, dir) = s
                .split_once('=')
                .filter(|(d, _)| valid_device(d))
                .ok_or_else(|| {
                    format!("--stick-dir wants DEVICE=DIR (sdz1=/tmp/stick), got {s}")
                })?;
            std::fs::create_dir_all(dir)?;
            dirs.add(dev, dir);
            found.push(Found {
                device: dev.into(),
                filesystem: "exfat".into(),
                label: "DEV STICK".into(),
                model: format!("directory {dir}"),
                size_bytes: 0,
                read_only: false,
            });
            eprintln!("[export] development: {dir} stands in for stick {dev}");
        }
        let dirs = Arc::new(dirs);
        let fs: Arc<dyn StickFs> = dirs.clone();
        (
            fs,
            Box::new(move || {
                found
                    .iter()
                    .filter(|f| dirs.present(&f.device))
                    .cloned()
                    .collect()
            }),
        )
    };
    eprintln!(
        "[export] recordings in {}; drive {}; nothing on the data drive is changed",
        cfg.video_root.display(),
        cfg.drive
            .as_ref()
            .map_or("not checked".into(), |d| d.display().to_string())
    );
    let exporter = Exporter::new(cfg, fs, discover);

    let poller = Arc::clone(&exporter);
    let period = Duration::from_millis(args.poll_ms.max(200));
    tokio::spawn(async move {
        loop {
            let p = Arc::clone(&poller);
            let _ = tokio::task::spawn_blocking(move || p.poll()).await;
            tokio::time::sleep(period).await;
        }
    });

    let notifier = Notifier::from_env();
    if let Some(problem) = notifier.problem() {
        eprintln!("[export] {problem}");
    }
    let router =
        Server::builder().add_service(ExportServiceServer::new(Api::new(exporter.clone())));
    let shutdown_exporter = exporter.clone();
    let shutdown = async move {
        let mut term =
            tokio::signal::unix::signal(tokio::signal::unix::SignalKind::terminate()).ok();
        tokio::select! {
            _ = tokio::signal::ctrl_c() => {}
            Some(()) = async { match term.as_mut() { Some(t) => t.recv().await, None => std::future::pending().await } } => {}
        }
        // A copy in progress stops; its partial file is removed and the
        // stick unmounted by the copy's thread if there is time.
        if shutdown_exporter.cancel() {
            eprintln!("[export] stopping: the copy is cancelled");
            tokio::time::sleep(Duration::from_secs(2)).await;
        }
        eprintln!("[export] shutting down");
    };
    let ready = |at: String| {
        eprintln!("[export] listening on {at}");
        if let Err(e) = notifier.ready(&format!("listening on {at}")) {
            eprintln!("[export] systemd READY not sent: {e}");
        }
    };
    if let Some(path) = args.listen.strip_prefix("unix:") {
        let path = std::path::Path::new(path);
        if let Some(dir) = path.parent() {
            std::fs::create_dir_all(dir)?;
        }
        let _ = std::fs::remove_file(path);
        let listener = tokio::net::UnixListener::bind(path)?;
        ready(format!("unix:{}", path.display()));
        let incoming = tokio_stream::wrappers::UnixListenerStream::new(listener);
        router
            .serve_with_incoming_shutdown(incoming, shutdown)
            .await?;
        let _ = std::fs::remove_file(path);
    } else if let Some(addr) = args.listen.strip_prefix("tcp:") {
        let addr: std::net::SocketAddr = addr.parse()?;
        ready(format!("tcp:{addr}"));
        router.serve_with_shutdown(addr, shutdown).await?;
    } else {
        return Err(format!(
            "--listen must start with unix: or tcp:, got {}",
            args.listen
        )
        .into());
    }
    Ok(())
}
