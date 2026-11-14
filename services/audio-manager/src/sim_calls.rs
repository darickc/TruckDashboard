//! Calls on the simulated phone, for the Mac (`make sim`) and the tests: no
//! Bluetooth, labelled simulated on the screen. A made-up caller rings `every`
//! after start and after each call ends (`--sim-call-every`); Answer, decline
//! and Hang up work, and the far end hangs up by itself after `talk`. Tests
//! ring, answer on the phone and end calls with the methods here.

use std::sync::{Arc, Mutex};
use std::time::Duration;

use tokio::sync::watch;

use crate::calls::{Availability, Call, CallSnapshot, CallState, Gateway};
use crate::sim::FIRST;
use crate::telephony::Telephony;

pub const SIM_NUMBER: &str = "+15550100";
pub const SIM_CALLER: &str = "Simulated Caller";

#[derive(Debug, Clone, Copy)]
pub struct SimCallsConfig {
    /// A call rings this long after start and after each call ends; None:
    /// only when a test rings.
    pub every: Option<Duration>,
    /// An unanswered call stops ringing after this.
    pub ring_for: Duration,
    /// The far end hangs up this long after it is answered.
    pub talk: Duration,
}

impl Default for SimCallsConfig {
    fn default() -> SimCallsConfig {
        SimCallsConfig {
            every: None,
            ring_for: Duration::from_secs(30),
            talk: Duration::from_secs(60),
        }
    }
}

#[derive(Debug, Default)]
struct State {
    calls: Vec<Call>,
    next: u32,
    /// Counts state changes, so an old timer does nothing.
    generation: u64,
    muted: Vec<bool>,
    /// The phone sends its own ring tone (and call audio) while a call rings.
    in_band: bool,
}

#[derive(Clone)]
pub struct SimCalls {
    cfg: SimCallsConfig,
    state: Arc<Mutex<State>>,
    snap: watch::Sender<CallSnapshot>,
}

impl SimCalls {
    pub fn new(cfg: SimCallsConfig) -> SimCalls {
        let s = SimCalls {
            cfg,
            state: Arc::default(),
            snap: watch::Sender::new(CallSnapshot {
                availability: Availability::Ready,
                gateways: Vec::new(),
                calls: Vec::new(),
            }),
        };
        s.publish(&s.lock());
        s
    }

    fn lock(&self) -> std::sync::MutexGuard<'_, State> {
        self.state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
    }

    fn publish(&self, st: &State) {
        // Call audio flows during a call, and while ringing if the phone
        // rings in-band.
        let audio = st
            .calls
            .iter()
            .any(|c| !c.state.rings() || (st.in_band && c.state == CallState::Incoming));
        self.snap.send_replace(CallSnapshot {
            availability: Availability::Ready,
            gateways: vec![Gateway {
                address: FIRST.into(),
                audio,
            }],
            calls: st.calls.clone(),
        });
    }

    /// The simulated phone sends its own ring tone (as the Z Fold8 does), or
    /// not (the default: audio-manager rings).
    pub fn set_in_band(&self, yes: bool) {
        let mut st = self.lock();
        st.in_band = yes;
        self.publish(&st);
    }

    /// Rings `every`, if set: a call after start, and again after each one
    /// ends.
    pub async fn run(self) {
        let Some(every) = self.cfg.every else {
            return;
        };
        let mut calls = self.snap.subscribe();
        loop {
            tokio::time::sleep(every).await;
            if self.lock().calls.is_empty() {
                self.ring(SIM_NUMBER, SIM_CALLER);
            }
            // Until this call (and any other) has ended.
            loop {
                if calls.borrow_and_update().calls.is_empty() {
                    break;
                }
                if calls.changed().await.is_err() {
                    return;
                }
            }
        }
    }

    /// A call rings on the simulated phone (incoming, or waiting during
    /// another). Returns its path.
    pub fn ring(&self, number: &str, name: &str) -> String {
        let path = {
            let mut st = self.lock();
            let path = format!("/sim/telephony/ag0/call{}", st.next);
            st.next += 1;
            let busy = st.calls.iter().any(|c| !c.state.rings());
            st.calls.push(Call {
                path: path.clone(),
                address: FIRST.into(),
                state: if busy {
                    CallState::Waiting
                } else {
                    CallState::Incoming
                },
                number: number.into(),
                name: name.into(),
                withheld: number.is_empty(),
                multiparty: false,
            });
            st.generation += 1;
            self.publish(&st);
            path
        };
        self.end_after(&path, self.cfg.ring_for, true);
        path
    }

    /// Ends `path` after `after`, unless something happened to the calls in
    /// between. `if_ringing`: only if it still rings.
    fn end_after(&self, path: &str, after: Duration, if_ringing: bool) {
        let me = self.clone();
        let path = path.to_string();
        let generation = self.lock().generation;
        tokio::spawn(async move {
            tokio::time::sleep(after).await;
            let st = me.lock();
            if st.generation != generation {
                return;
            }
            let rings = st.calls.iter().any(|c| c.path == path && c.state.rings());
            drop(st);
            if !if_ringing || rings {
                me.end(&path);
            }
        });
    }

    /// The far end hangs up (or stops ringing).
    pub fn end(&self, path: &str) {
        let mut st = self.lock();
        let before = st.calls.len();
        st.calls.retain(|c| c.path != path);
        if st.calls.len() != before {
            st.generation += 1;
            // A held call left alone comes back.
            if st.calls.iter().all(|c| c.state != CallState::Active)
                && let Some(c) = st.calls.iter_mut().find(|c| c.state == CallState::Held)
            {
                c.state = CallState::Active;
            }
            self.publish(&st);
        }
    }

    /// The call is answered on the phone itself.
    pub fn answer_on_phone(&self, path: &str) {
        let mut st = self.lock();
        for c in &mut st.calls {
            if c.path == path {
                c.state = CallState::Active;
            } else if c.state == CallState::Active {
                c.state = CallState::Held;
            }
        }
        st.generation += 1;
        self.publish(&st);
        drop(st);
        self.end_after(path, self.cfg.talk, false);
    }

    /// Every mute asked for, in order (tests).
    pub fn mutes(&self) -> Vec<bool> {
        self.lock().muted.clone()
    }
}

#[tonic::async_trait]
impl Telephony for SimCalls {
    fn calls(&self) -> watch::Receiver<CallSnapshot> {
        self.snap.subscribe()
    }

    async fn answer(&self, path: &str) -> Result<(), String> {
        let state = self
            .lock()
            .calls
            .iter()
            .find(|c| c.path == path)
            .map(|c| c.state);
        match state {
            Some(CallState::Incoming) => {
                self.answer_on_phone(path);
                Ok(())
            }
            Some(_) => Err("InvalidState".into()),
            None => Err("simulated: no such call".into()),
        }
    }

    async fn hang_up(&self, path: &str) -> Result<(), String> {
        if !self.lock().calls.iter().any(|c| c.path == path) {
            return Err("simulated: no such call".into());
        }
        self.end(path);
        Ok(())
    }

    async fn set_mic_muted(&self, muted: bool) -> Result<(), String> {
        self.lock().muted.push(muted);
        Ok(())
    }
}

#[cfg(test)]
#[allow(clippy::unwrap_used)]
mod tests {
    use super::*;

    #[tokio::test(start_paused = true)]
    async fn ring_answer_wait_and_hang_up() {
        let s = SimCalls::new(SimCallsConfig::default());
        let rx = s.calls();
        let a = s.ring(SIM_NUMBER, SIM_CALLER);
        assert_eq!(rx.borrow().calls[0].state, CallState::Incoming);
        s.answer(&a).await.unwrap();
        assert_eq!(rx.borrow().calls[0].state, CallState::Active);
        assert!(s.answer(&a).await.is_err(), "not incoming any more");
        let b = s.ring("", "");
        let c = rx.borrow().calls[1].clone();
        assert_eq!(c.state, CallState::Waiting);
        assert!(c.withheld);
        s.hang_up(&b).await.unwrap();
        assert_eq!(rx.borrow().calls.len(), 1);
        s.hang_up(&a).await.unwrap();
        assert!(rx.borrow().calls.is_empty());
    }

    #[tokio::test(start_paused = true)]
    async fn an_unanswered_call_stops_ringing_and_the_far_end_hangs_up() {
        let s = SimCalls::new(SimCallsConfig {
            every: None,
            ring_for: Duration::from_secs(5),
            talk: Duration::from_secs(10),
        });
        let rx = s.calls();
        s.ring(SIM_NUMBER, SIM_CALLER);
        tokio::time::sleep(Duration::from_secs(6)).await;
        assert!(rx.borrow().calls.is_empty());
        let p = s.ring(SIM_NUMBER, SIM_CALLER);
        s.answer(&p).await.unwrap();
        tokio::time::sleep(Duration::from_secs(6)).await;
        assert_eq!(rx.borrow().calls.len(), 1, "answered: no ringing timeout");
        tokio::time::sleep(Duration::from_secs(5)).await;
        assert!(rx.borrow().calls.is_empty());
    }

    #[tokio::test(start_paused = true)]
    async fn it_rings_by_itself_again_after_each_call() {
        let s = SimCalls::new(SimCallsConfig {
            every: Some(Duration::from_secs(20)),
            ring_for: Duration::from_secs(5),
            talk: Duration::from_secs(10),
        });
        let rx = s.calls();
        tokio::spawn(s.clone().run());
        tokio::time::sleep(Duration::from_secs(21)).await;
        assert_eq!(rx.borrow().calls.len(), 1);
        tokio::time::sleep(Duration::from_secs(5)).await;
        assert!(rx.borrow().calls.is_empty(), "stopped ringing");
        tokio::time::sleep(Duration::from_secs(21)).await;
        assert_eq!(rx.borrow().calls.len(), 1, "rings again");
    }
}
