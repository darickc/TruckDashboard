//! A fake ELM327 over TCP replaying the real captures from
//! docs/diagnostics/VERIFICATION_LOG.md.

#![allow(dead_code, clippy::unwrap_used)]

use std::sync::{Arc, Mutex};

use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::TcpListener;

/// Lines the fake adapter received, for asserting what reached the "wire".
pub type Wire = Arc<Mutex<Vec<String>>>;

pub async fn fake_adapter() -> (String, Wire) {
    let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
    let addr = listener.local_addr().unwrap().to_string();
    let wire: Wire = Arc::default();
    let seen = wire.clone();
    tokio::spawn(async move {
        loop {
            let Ok((mut sock, _)) = listener.accept().await else {
                return;
            };
            let seen = seen.clone();
            tokio::spawn(async move {
                let mut buf = Vec::new();
                let mut b = [0u8; 256];
                loop {
                    let Ok(n) = sock.read(&mut b).await else {
                        return;
                    };
                    if n == 0 {
                        return;
                    }
                    buf.extend_from_slice(&b[..n]);
                    while let Some(i) = buf.iter().position(|&c| c == b'\r') {
                        let line: String = String::from_utf8_lossy(&buf[..i]).trim().to_string();
                        buf.drain(..=i);
                        seen.lock().unwrap().push(line.clone());
                        let reply: &str = match line.as_str() {
                            "ATZ" => "\r\rELM327 v1.4b\r\r>",
                            "ATRV" => "12.6V\r\r>",
                            "010C" => "7E904410C0AC4\r7E804410C0AC2\r\r>",
                            "221674" => "7E8037F2231\r7E9056216740413\r\r>",
                            "221310" => "NO DATA\r\r>",
                            l if l.starts_with("AT") => "OK\r\r>",
                            _ => "?\r\r>",
                        };
                        if sock.write_all(reply.as_bytes()).await.is_err() {
                            return;
                        }
                    }
                }
            });
        }
    });
    (addr, wire)
}

/// Connections accepted so far (0 = the gateway never opened the adapter).
pub fn connections(wire: &Wire) -> usize {
    wire.lock()
        .unwrap()
        .iter()
        .filter(|l| l.as_str() == "ATZ")
        .count()
}
