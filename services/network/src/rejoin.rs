//! Rejoining a saved network after connman gives up (ADR-0052 decision 13).
//!
//! connman autoconnects a saved Wi-Fi network when it comes back in range,
//! but one failed attempt leaves the service in `failure`, and connman's
//! autoconnect skips a service in failure: on the bench Pi a handshake that
//! timed out once kept the Pi off its network until someone joined by hand
//! (bench-log 2026-11-23). Clearing the service's `Error` puts it back to
//! idle, and connman tries it again by itself.
//!
//! [`Rejoin`] decides when: a saved network with autoconnect on, in failure
//! for a reason that can pass ([`retried`]), waits [`FIRST_WAIT`], then
//! twice as long after each further failure, up to [`MAX_WAIT`]. Connecting
//! starts the waits over. A wrong passphrase or anything else the driver has
//! to fix is left alone.

use std::collections::HashMap;
use std::time::{Duration, Instant};

use crate::model::{Prop, Props};

/// How long a failed network waits before connman is asked to try it again.
/// An example.
pub const FIRST_WAIT: Duration = Duration::from_secs(20);
/// The longest wait, after repeated failures. An example.
pub const MAX_WAIT: Duration = Duration::from_secs(300);

/// connman's errors worth another try by themselves: the network was there
/// and the passphrase saved, but the attempt didn't finish. Not
/// `invalid-key`, `auth-failed`, `login-failed`, `pin-missing` or `blocked`:
/// trying again can't fix those, and a wrong passphrase repeated can get the
/// Pi locked out.
pub fn retried(error: &str) -> bool {
    matches!(error, "connect-failed" | "dhcp-failed" | "out-of-range")
}

fn str_of<'a>(p: &'a Props, k: &str) -> &'a str {
    match p.get(k) {
        Some(Prop::Str(s)) => s,
        _ => "",
    }
}

fn bool_of(p: &Props, k: &str) -> bool {
    matches!(p.get(k), Some(Prop::Bool(true)))
}

/// A network due to be tried again.
#[derive(Debug, Clone, PartialEq)]
pub struct Due {
    pub id: String,
    pub name: String,
    pub error: String,
    /// The wait before the next try, should this one fail too.
    pub next_wait: Duration,
}

#[derive(Debug)]
struct Entry {
    /// When this failure was first seen; `None` once it has been retried
    /// and until the next failure.
    failed_at: Option<Instant>,
    wait: Duration,
}

/// The waits of each saved network that has failed, by connman's id.
#[derive(Debug, Default)]
pub struct Rejoin {
    entries: HashMap<String, Entry>,
}

impl Rejoin {
    /// Given connman's services now, the networks to try again now.
    pub fn due<'a>(
        &mut self,
        now: Instant,
        services: impl IntoIterator<Item = (&'a str, &'a Props)>,
    ) -> Vec<Due> {
        let mut seen = Vec::new();
        let mut due = Vec::new();
        for (id, p) in services {
            if str_of(p, "Type") != "wifi" || !bool_of(p, "Favorite") {
                continue;
            }
            seen.push(id.to_string());
            let state = str_of(p, "State");
            if matches!(state, "ready" | "online") {
                self.entries.remove(id);
                continue;
            }
            let error = str_of(p, "Error");
            if state != "failure" || !bool_of(p, "AutoConnect") || !retried(error) {
                continue;
            }
            let e = self.entries.entry(id.to_string()).or_insert(Entry {
                failed_at: None,
                wait: FIRST_WAIT,
            });
            let failed_at = *e.failed_at.get_or_insert(now);
            if now.duration_since(failed_at) >= e.wait {
                e.failed_at = None;
                e.wait = (e.wait * 2).min(MAX_WAIT);
                due.push(Due {
                    id: id.to_string(),
                    name: str_of(p, "Name").to_string(),
                    error: error.to_string(),
                    next_wait: e.wait,
                });
            }
        }
        self.entries.retain(|id, _| seen.contains(id));
        due
    }
}

#[cfg(test)]
#[allow(clippy::unwrap_used)]
mod tests {
    use super::*;

    fn svc(state: &str, error: &str) -> Props {
        [
            ("Type", Prop::Str("wifi".into())),
            ("Name", Prop::Str("DC-24".into())),
            ("Favorite", Prop::Bool(true)),
            ("AutoConnect", Prop::Bool(true)),
            ("State", Prop::Str(state.into())),
            ("Error", Prop::Str(error.into())),
        ]
        .into_iter()
        .map(|(k, v)| (k.to_string(), v))
        .collect()
    }

    const ID: &str = "wifi_2ccf675bee7f_44432d3234_managed_psk";

    fn ids(d: &[Due]) -> Vec<&str> {
        d.iter().map(|d| d.id.as_str()).collect()
    }

    #[test]
    fn a_failed_saved_network_is_tried_again_after_the_first_wait() {
        let mut r = Rejoin::default();
        let t0 = Instant::now();
        let p = svc("failure", "connect-failed");
        assert!(r.due(t0, [(ID, &p)]).is_empty());
        assert!(
            r.due(t0 + FIRST_WAIT - Duration::from_secs(1), [(ID, &p)])
                .is_empty()
        );
        let d = r.due(t0 + FIRST_WAIT, [(ID, &p)]);
        assert_eq!(
            d,
            vec![Due {
                id: ID.into(),
                name: "DC-24".into(),
                error: "connect-failed".into(),
                next_wait: FIRST_WAIT * 2,
            }]
        );
    }

    #[test]
    fn each_further_failure_waits_twice_as_long_up_to_the_most() {
        let mut r = Rejoin::default();
        let failed = svc("failure", "connect-failed");
        let trying = svc("association", "");
        let mut t = Instant::now();
        let mut waits = Vec::new();
        for _ in 0..7 {
            assert!(r.due(t, [(ID, &failed)]).is_empty());
            let mut wait = Duration::ZERO;
            loop {
                wait += Duration::from_secs(1);
                if !r.due(t + wait, [(ID, &failed)]).is_empty() {
                    break;
                }
            }
            waits.push(wait.as_secs());
            t += wait;
            // connman tries, and fails again.
            assert!(r.due(t, [(ID, &trying)]).is_empty());
        }
        assert_eq!(waits, vec![20, 40, 80, 160, 300, 300, 300]);
    }

    #[test]
    fn connecting_starts_the_waits_over() {
        let mut r = Rejoin::default();
        let failed = svc("failure", "dhcp-failed");
        let t0 = Instant::now();
        r.due(t0, [(ID, &failed)]);
        assert_eq!(ids(&r.due(t0 + FIRST_WAIT, [(ID, &failed)])), vec![ID]);
        r.due(t0 + FIRST_WAIT, [(ID, &svc("online", ""))]);
        let t1 = t0 + Duration::from_secs(600);
        r.due(t1, [(ID, &failed)]);
        assert_eq!(ids(&r.due(t1 + FIRST_WAIT, [(ID, &failed)])), vec![ID]);
    }

    #[test]
    fn a_wrong_passphrase_and_others_the_driver_fixes_are_left_alone() {
        for error in [
            "invalid-key",
            "auth-failed",
            "login-failed",
            "pin-missing",
            "blocked",
            "",
        ] {
            let mut r = Rejoin::default();
            let p = svc("failure", error);
            let t0 = Instant::now();
            r.due(t0, [(ID, &p)]);
            assert!(r.due(t0 + MAX_WAIT, [(ID, &p)]).is_empty(), "{error}");
        }
    }

    #[test]
    fn unsaved_networks_autoconnect_off_and_other_types_are_left_alone() {
        let mut unsaved = svc("failure", "connect-failed");
        unsaved.insert("Favorite".into(), Prop::Bool(false));
        let mut manual = svc("failure", "connect-failed");
        manual.insert("AutoConnect".into(), Prop::Bool(false));
        let mut wired = svc("failure", "connect-failed");
        wired.insert("Type".into(), Prop::Str("ethernet".into()));
        for p in [unsaved, manual, wired] {
            let mut r = Rejoin::default();
            let t0 = Instant::now();
            r.due(t0, [(ID, &p)]);
            assert!(r.due(t0 + MAX_WAIT, [(ID, &p)]).is_empty());
        }
    }

    #[test]
    fn a_network_that_left_the_list_is_forgotten() {
        let mut r = Rejoin::default();
        let failed = svc("failure", "connect-failed");
        let t0 = Instant::now();
        r.due(t0, [(ID, &failed)]);
        r.due(t0 + FIRST_WAIT, [(ID, &failed)]);
        r.due(t0 + FIRST_WAIT, std::iter::empty());
        // Back with the first wait, not the doubled one.
        let t1 = t0 + Duration::from_secs(100);
        r.due(t1, [(ID, &failed)]);
        assert_eq!(ids(&r.due(t1 + FIRST_WAIT, [(ID, &failed)])), vec![ID]);
    }

    #[test]
    fn only_the_failed_one_of_several_is_due() {
        let mut r = Rejoin::default();
        let failed = svc("failure", "out-of-range");
        let fine = svc("idle", "");
        let t0 = Instant::now();
        r.due(t0, [(ID, &failed), ("wifi_other", &fine)]);
        let d = r.due(t0 + FIRST_WAIT, [(ID, &failed), ("wifi_other", &fine)]);
        assert_eq!(ids(&d), vec![ID]);
    }
}
