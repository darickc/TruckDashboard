//! An in-memory CAN bus with scripted ECUs, replaying replies captured on the
//! truck (docs/diagnostics/VERIFICATION_LOG.md, 2026-08-09 and 2026-11-03).
//! [SIM]: no interface, no adapter, no truck.

#![allow(dead_code, clippy::unwrap_used)]

use std::collections::HashMap;
use std::io;
use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::{Arc, Mutex};
use std::time::Duration;

use tokio::sync::mpsc;
use vehicle_gateway::transport::can::{BoxFuture, BusEvent, CanBus, Opener};
use vehicle_gateway::transport::isotp::Frame;

/// One scripted reply: after `delay_ms`, `id` sends `data` (8 bytes, hex).
#[derive(Clone)]
pub struct Reply {
    pub delay_ms: u64,
    pub id: u16,
    pub data: &'static str,
}

pub fn r(delay_ms: u64, id: u16, data: &'static str) -> Reply {
    Reply { delay_ms, id, data }
}

fn bytes(hex: &str) -> Vec<u8> {
    (0..hex.len())
        .step_by(2)
        .map(|i| u8::from_str_radix(&hex[i..i + 2], 16).unwrap())
        .collect()
}

/// Request key: "7DF 0322131000000000".
fn key(f: &Frame) -> String {
    let hex: String = f.data.iter().map(|b| format!("{b:02X}")).collect();
    format!("{:03X} {hex}", f.id)
}

/// Reply sets per request key, and the index of the next set to use.
type Script = HashMap<String, (usize, Vec<Vec<Reply>>)>;

#[derive(Clone, Default)]
pub struct FakeBus {
    /// Replies per request, by [`key`]. A list per key is consumed in turn
    /// (the last entry repeats), so a test can script "truncated, then
    /// normal".
    script: Arc<Mutex<Script>>,
    /// Every frame the gateway wrote.
    pub sent: Arc<Mutex<Vec<Frame>>>,
    /// How many times the bus was opened.
    pub opens: Arc<AtomicUsize>,
    /// Events injected by the test (error frames, read failures).
    inject: Arc<Mutex<Option<mpsc::UnboundedSender<io::Result<BusEvent>>>>>,
}

impl FakeBus {
    /// The truck as captured: PCM 7E8, TCM 7E9.
    pub fn truck() -> Self {
        let bus = FakeBus::default();
        // 01 0C: both answer, 7E9 first (2026-08-09).
        bus.on(
            "7DF 02010C0000000000",
            vec![
                r(12, 0x7E9, "04410C0AC4000000"),
                r(15, 0x7E8, "04410C0AC2000000"),
            ],
        );
        // 22 1674: the PCM refuses, the TCM answers 04 13 (2026-08-09).
        bus.on(
            "7DF 0322167400000000",
            vec![
                r(15, 0x7E9, "0562167404130000"),
                r(30, 0x7E8, "037F223100000000"),
            ],
        );
        // 22 1310: the TCM refuses 7F 22 12, the PCM answers 26 91 (2026-11-03).
        bus.on(
            "7DF 0322131000000000",
            vec![
                r(18, 0x7E9, "037F221200000000"),
                r(40, 0x7E8, "0562131026910000"),
            ],
        );
        // The other default SAE signals, at the values in the 2026-11-03
        // console transcript after the drive (ECT 56 °C, baro 84 kPa, IAT
        // 19 °C, load 35 %, speed 0). Both modules answer ECT there; the
        // others answer from 7E8 here, which the census has not established.
        bus.on(
            "7DF 0201050000000000",
            vec![
                r(12, 0x7E9, "0341056000000000"),
                r(15, 0x7E8, "0341056000000000"),
            ],
        );
        bus.on(
            "7DF 02010D0000000000",
            vec![r(12, 0x7E8, "03410D0000000000")],
        );
        bus.on(
            "7DF 0201330000000000",
            vec![r(12, 0x7E8, "0341335400000000")],
        );
        bus.on(
            "7DF 02010F0000000000",
            vec![r(12, 0x7E8, "03410F3B00000000")],
        );
        bus.on(
            "7DF 0201040000000000",
            vec![r(12, 0x7E8, "0341045A00000000")],
        );
        bus
    }

    pub fn on(&self, request: &str, replies: Vec<Reply>) {
        self.script
            .lock()
            .unwrap()
            .insert(request.to_string(), (0, vec![replies]));
    }

    /// Successive reply sets for one request (the last one repeats).
    pub fn on_seq(&self, request: &str, sets: Vec<Vec<Reply>>) {
        self.script
            .lock()
            .unwrap()
            .insert(request.to_string(), (0, sets));
    }

    pub fn inject(&self, ev: io::Result<BusEvent>) {
        if let Some(tx) = self.inject.lock().unwrap().as_ref() {
            let _ = tx.send(ev);
        }
    }

    pub fn opener(&self) -> Opener {
        let bus = self.clone();
        Arc::new(move || {
            let bus = bus.clone();
            Box::pin(async move {
                bus.opens.fetch_add(1, Ordering::SeqCst);
                let (tx, rx) = mpsc::unbounded_channel();
                *bus.inject.lock().unwrap() = Some(tx.clone());
                Ok(Box::new(Open { bus, tx, rx }) as Box<dyn CanBus>)
            })
        })
    }

    pub fn sent(&self) -> Vec<Frame> {
        self.sent.lock().unwrap().clone()
    }
}

struct Open {
    bus: FakeBus,
    tx: mpsc::UnboundedSender<io::Result<BusEvent>>,
    rx: mpsc::UnboundedReceiver<io::Result<BusEvent>>,
}

impl CanBus for Open {
    fn send<'a>(&'a mut self, frame: &'a Frame) -> BoxFuture<'a, io::Result<()>> {
        Box::pin(async move {
            self.bus.sent.lock().unwrap().push(frame.clone());
            let replies = {
                let mut script = self.bus.script.lock().unwrap();
                match script.get_mut(&key(frame)) {
                    Some((next, sets)) => {
                        let i = (*next).min(sets.len() - 1);
                        *next += 1;
                        sets[i].clone()
                    }
                    None => vec![],
                }
            };
            for rep in replies {
                let tx = self.tx.clone();
                tokio::spawn(async move {
                    tokio::time::sleep(Duration::from_millis(rep.delay_ms)).await;
                    let _ = tx.send(Ok(BusEvent::Data(Frame {
                        id: rep.id,
                        data: bytes(rep.data),
                    })));
                });
            }
            Ok(())
        })
    }

    fn recv(&mut self) -> BoxFuture<'_, io::Result<BusEvent>> {
        Box::pin(async move {
            match self.rx.recv().await {
                Some(ev) => ev,
                None => Err(io::Error::new(io::ErrorKind::BrokenPipe, "fake bus closed")),
            }
        })
    }
}
