//! Reads or sets power-manager's day/night choice and levels, as the
//! dashboard's Settings → Display does: a check from a terminal (ADR-0028,
//! agl.md check 15).
//!
//!   cargo run -p power-manager --example display -- unix:/run/f250-power/power.sock
//!   cargo run -p power-manager --example display -- tcp:127.0.0.1:50298 night
//!   cargo run -p power-manager --example display -- tcp:127.0.0.1:50298 day 90
//!
//! CHOICE is auto, day or night; LEVEL (percent) sets that mode's level.
//! With no CHOICE it prints the state and exits.

use f250_proto::power::v1 as pb;
use hyper_util::rt::TokioIo;
use pb::display_service_client::DisplayServiceClient;
use tonic::transport::{Channel, Endpoint, Uri};

async fn connect(endpoint: &str) -> Result<Channel, String> {
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
        Endpoint::from_shared(format!("http://{addr}"))
            .map_err(|e| e.to_string())?
            .connect()
            .await
            .map_err(|e| e.to_string())
    } else {
        Err("the endpoint must start with unix: or tcp:".into())
    }
}

fn show(d: &pb::Display) {
    println!(
        "mode {:?}, choice {:?}, basis {:?}; backlight {} at {} % (day {} %, night {} %, floor {} %){}",
        pb::DisplayMode::try_from(d.mode).unwrap_or_default(),
        pb::DisplayChoice::try_from(d.choice).unwrap_or_default(),
        pb::ModeBasis::try_from(d.basis).unwrap_or_default(),
        if d.backlight_present {
            d.backlight.as_str()
        } else {
            "none"
        },
        d.brightness_pct,
        d.day_brightness_pct,
        d.night_brightness_pct,
        d.min_brightness_pct,
        if d.backlight_problem.is_empty() {
            String::new()
        } else {
            format!("; problem: {}", d.backlight_problem)
        },
    );
}

#[tokio::main(flavor = "current_thread")]
async fn main() -> Result<(), String> {
    let args: Vec<String> = std::env::args().skip(1).collect();
    let usage = || "usage: display ENDPOINT [auto|day|night [LEVEL]]".to_string();
    let Some(endpoint) = args.first() else {
        return Err(usage());
    };
    let mut client = DisplayServiceClient::new(connect(endpoint).await?);
    let Some(choice) = args.get(1) else {
        let mut stream = client
            .watch_display(pb::WatchDisplayRequest {})
            .await
            .map_err(|e| e.to_string())?
            .into_inner();
        let r = stream
            .message()
            .await
            .map_err(|e| e.to_string())?
            .ok_or("the service ended the stream")?;
        show(&r.display.unwrap_or_default());
        return Ok(());
    };
    let choice = match choice.as_str() {
        "auto" => pb::DisplayChoice::Auto,
        "day" => pb::DisplayChoice::Day,
        "night" => pb::DisplayChoice::Night,
        _ => return Err(usage()),
    };
    let level: u32 = match args.get(2) {
        Some(l) => l.parse().map_err(|e| format!("LEVEL: {e}"))?,
        None => 0,
    };
    let mut req = pb::SetDisplayRequest {
        choice: choice as i32,
        source: "display example".into(),
        ..Default::default()
    };
    match choice {
        pb::DisplayChoice::Day => req.day_brightness_pct = level,
        pb::DisplayChoice::Night => req.night_brightness_pct = level,
        _ if level != 0 => return Err("LEVEL goes with day or night".into()),
        _ => {}
    }
    let r = client
        .set_display(req)
        .await
        .map_err(|e| e.to_string())?
        .into_inner();
    show(&r.display.unwrap_or_default());
    Ok(())
}
