//! `camera-ctl`: talk to camera-manager's `f250.camera.v1` API by hand, for
//! the bench and for development. A switch move without the switch, and the
//! view as camera-manager reports it.
//!
//!   camera-ctl move back          # as if the switch moved back; prints the view
//!   camera-ctl view               # the view now
//!   camera-ctl watch              # every change, until Ctrl-C
//!   camera-ctl --to unix:/tmp/f250/camera.sock view
//!
//! Without `--to` it uses the Pi's socket (/run/f250-camera/camera.sock) when
//! that exists, otherwise the development default (/tmp/f250/camera.sock).

use std::process::ExitCode;
use std::time::Duration;

use camera_manager::manager::describe_view;
use clap::{Parser, Subcommand, ValueEnum};
use f250_proto::camera::v1 as pb;
use hyper_util::rt::TokioIo;
use pb::camera_service_client::CameraServiceClient;
use tokio_stream::StreamExt;
use tonic::transport::{Channel, Endpoint, Uri};

const PI_SOCKET: &str = "/run/f250-camera/camera.sock";
const DEV_SOCKET: &str = "/tmp/f250/camera.sock";
const TIMEOUT: Duration = Duration::from_secs(5);

#[derive(Parser)]
#[command(
    name = "camera-ctl",
    about = "Send camera-switch moves to camera-manager and show its view"
)]
struct Args {
    /// camera-manager's API: unix:PATH or tcp:HOST:PORT.
    #[arg(long, value_name = "ENDPOINT")]
    to: Option<String>,
    #[command(subcommand)]
    cmd: Cmd,
}

#[derive(Subcommand)]
enum Cmd {
    /// A switch move, as power-manager sends it. Prints the view that follows.
    Move { direction: Direction },
    /// The view now.
    View,
    /// The view now and every change, until interrupted.
    Watch,
}

#[derive(Clone, Copy, ValueEnum)]
enum Direction {
    Left,
    Right,
    Back,
    Forward,
    Press,
}

impl Direction {
    fn pb(self) -> pb::SwitchMove {
        match self {
            Direction::Left => pb::SwitchMove::Left,
            Direction::Right => pb::SwitchMove::Right,
            Direction::Back => pb::SwitchMove::Back,
            Direction::Forward => pb::SwitchMove::Forward,
            Direction::Press => pb::SwitchMove::Press,
        }
    }
}

async fn connect(endpoint: &str) -> Result<Channel, String> {
    let fut = async {
        if let Some(path) = endpoint.strip_prefix("unix:") {
            let path = path.to_string();
            Endpoint::from_static("http://localhost")
                .connect_with_connector(tower::service_fn(move |_: Uri| {
                    let path = path.clone();
                    async move {
                        tokio::net::UnixStream::connect(path)
                            .await
                            .map(TokioIo::new)
                    }
                }))
                .await
                .map_err(|e| e.to_string())
        } else if let Some(addr) = endpoint.strip_prefix("tcp:") {
            Endpoint::try_from(format!("http://{addr}"))
                .map_err(|e| e.to_string())?
                .connect()
                .await
                .map_err(|e| e.to_string())
        } else {
            Err(format!(
                "--to must start with unix: or tcp:, got {endpoint}"
            ))
        }
    };
    match tokio::time::timeout(TIMEOUT, fut).await {
        Ok(Ok(ch)) => Ok(ch),
        Ok(Err(e)) => Err(format!("no connection to {endpoint}: {e}")),
        Err(_) => Err(format!(
            "no connection to {endpoint} in {} s",
            TIMEOUT.as_secs()
        )),
    }
}

async fn run(args: Args) -> Result<(), String> {
    let endpoint = args.to.unwrap_or_else(|| {
        let path = if std::path::Path::new(PI_SOCKET).exists() {
            PI_SOCKET
        } else {
            DEV_SOCKET
        };
        format!("unix:{path}")
    });
    let mut client = CameraServiceClient::new(connect(&endpoint).await?);
    match args.cmd {
        Cmd::Move { direction } => {
            let request = pb::MoveRequest {
                r#move: direction.pb() as i32,
                source: "camera-ctl".into(),
            };
            let view = tokio::time::timeout(TIMEOUT, client.r#move(request))
                .await
                .map_err(|_| "no answer from camera-manager".to_string())?
                .map_err(|s| format!("camera-manager refused the move: {}", s.message()))?
                .into_inner()
                .view
                .unwrap_or_default();
            println!("{}", describe_view(&view));
        }
        Cmd::View | Cmd::Watch => {
            let once = matches!(args.cmd, Cmd::View);
            let mut stream = client
                .watch_view(pb::WatchViewRequest {})
                .await
                .map_err(|s| format!("WatchView: {}", s.message()))?
                .into_inner();
            while let Some(item) = stream.next().await {
                let view = item
                    .map_err(|s| format!("WatchView: {}", s.message()))?
                    .view
                    .unwrap_or_default();
                println!("{}", describe_view(&view));
                if once {
                    return Ok(());
                }
            }
            return Err("camera-manager ended the stream".into());
        }
    }
    Ok(())
}

#[tokio::main(flavor = "current_thread")]
async fn main() -> ExitCode {
    match run(Args::parse()).await {
        Ok(()) => ExitCode::SUCCESS,
        Err(e) => {
            eprintln!("camera-ctl: {e}");
            ExitCode::FAILURE
        }
    }
}
