//! The network service over its unix socket with the simulated radio
//! (ADR-0052): the status stream, joining with a wrong and a right
//! passphrase, turning Wi-Fi off. [SIM]: connman isn't involved.

#![allow(clippy::unwrap_used, clippy::expect_used)]

use std::sync::Arc;
use std::time::Duration;

use f250_proto::network::v1 as pb;
use hyper_util::rt::TokioIo;
use network::runner;
use network::server::{self, Api};
use network::sim::Sim;
use pb::wifi_service_client::WifiServiceClient;
use tokio::sync::{Notify, watch};
use tonic::transport::{Channel, Endpoint, Uri};

fn socket(test: &str) -> String {
    let dir = std::env::temp_dir().join(format!("f250-network-{test}-{}", std::process::id()));
    std::fs::create_dir_all(&dir).expect("temp dir");
    dir.join("network.sock").display().to_string()
}

async fn client(path: &str) -> WifiServiceClient<Channel> {
    let path = path.to_string();
    for _ in 0..100 {
        if std::path::Path::new(&path).exists() {
            break;
        }
        tokio::time::sleep(Duration::from_millis(20)).await;
    }
    let channel = Endpoint::from_static("http://localhost")
        .connect_with_connector(tower::service_fn(move |_: Uri| {
            let path = path.clone();
            async move {
                tokio::net::UnixStream::connect(path)
                    .await
                    .map(TokioIo::new)
            }
        }))
        .await
        .expect("connect");
    WifiServiceClient::new(channel)
}

fn start(test: &str) -> String {
    let path = socket(test);
    let backend = Arc::new(Sim::default());
    let poke = Arc::new(Notify::new());
    let (out, status) = watch::channel(pb::WifiStatus::default());
    tokio::spawn(runner::run(
        backend.clone(),
        Duration::from_millis(100),
        poke.clone(),
        out,
        None,
    ));
    let listen = format!("unix:{path}");
    tokio::spawn(async move { server::serve(&listen, Api::new(backend, status, poke)).await });
    path
}

async fn next_status(
    stream: &mut tonic::Streaming<pb::WatchWifiResponse>,
    want: impl Fn(&pb::WifiStatus) -> bool,
) -> pb::WifiStatus {
    tokio::time::timeout(Duration::from_secs(10), async {
        loop {
            let s = stream.message().await.unwrap().unwrap().status.unwrap();
            if want(&s) {
                return s;
            }
        }
    })
    .await
    .expect("the status never came")
}

#[tokio::test]
async fn join_a_network_over_the_socket() {
    let path = start("join");
    let mut c = client(&path).await;
    let mut watch = c
        .watch_wifi(pb::WatchWifiRequest {})
        .await
        .unwrap()
        .into_inner();
    let s = next_status(&mut watch, |s| s.available).await;
    assert!(s.simulated && s.enabled);
    assert_eq!(s.connectivity, pb::Connectivity::Online as i32);

    let shop = "wifi_sim_shop_managed_psk".to_string();
    let r = c
        .connect_wifi(pb::ConnectWifiRequest {
            id: shop.clone(),
            passphrase: "wrongpass".into(),
        })
        .await
        .unwrap()
        .into_inner();
    assert!(!r.connected);
    assert_eq!(r.detail, "Wrong passphrase");

    let r = c
        .connect_wifi(pb::ConnectWifiRequest {
            id: shop.clone(),
            passphrase: "correct horse".into(),
        })
        .await
        .unwrap()
        .into_inner();
    assert!(r.connected, "{}", r.detail);
    let s = next_status(&mut watch, |s| {
        s.networks
            .first()
            .is_some_and(|n| n.id == shop && n.state == pb::NetworkState::Online as i32)
    })
    .await;
    assert!(s.networks[0].saved);

    c.set_wifi_enabled(pb::SetWifiEnabledRequest { enabled: false })
        .await
        .unwrap();
    let s = next_status(&mut watch, |s| !s.enabled).await;
    assert_eq!(s.connectivity, pb::Connectivity::Offline as i32);
    assert!(s.networks.is_empty());

    let e = c
        .connect_wifi(pb::ConnectWifiRequest::default())
        .await
        .unwrap_err();
    assert_eq!(e.code(), tonic::Code::InvalidArgument);
}
