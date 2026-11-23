//! A made-up radio for the Mac and the browser (`--simulate`; ADR-0052):
//! four networks, the truck's hotspot saved and online. Labelled simulated
//! on the screen. A passphrase shorter than 8 characters, or "wrongpass",
//! is refused as wrong; joining takes [`Sim::JOIN`].

use std::sync::Mutex;
use std::time::Duration;

use f250_proto::network::v1 as pb;

use crate::Backend;
use crate::model;

pub struct Sim {
    state: Mutex<SimState>,
}

struct SimState {
    enabled: bool,
    networks: Vec<pb::WifiNetwork>,
}

fn net(
    id: &str,
    name: &str,
    strength: u32,
    security: pb::Security,
    saved: bool,
) -> pb::WifiNetwork {
    pb::WifiNetwork {
        id: id.to_string(),
        name: name.to_string(),
        strength,
        security: security as i32,
        saved,
        state: pb::NetworkState::Idle as i32,
        error: String::new(),
    }
}

impl Default for Sim {
    fn default() -> Self {
        let mut hotspot = net(
            "wifi_sim_hotspot_managed_psk",
            "F-250 Hotspot",
            72,
            pb::Security::Psk,
            true,
        );
        hotspot.state = pb::NetworkState::Online as i32;
        Sim {
            state: Mutex::new(SimState {
                enabled: true,
                networks: vec![
                    hotspot,
                    net(
                        "wifi_sim_shop_managed_psk",
                        "Shop Wi-Fi",
                        48,
                        pb::Security::Psk,
                        false,
                    ),
                    net(
                        "wifi_sim_stop_managed_none",
                        "Truck Stop Free",
                        30,
                        pb::Security::Open,
                        false,
                    ),
                    net(
                        "wifi_sim_corp_managed_ieee8021x",
                        "Corp",
                        22,
                        pb::Security::Enterprise,
                        false,
                    ),
                ],
            }),
        }
    }
}

impl Sim {
    /// How long joining takes.
    pub const JOIN: Duration = Duration::from_secs(2);

    fn with<T>(&self, f: impl FnOnce(&mut SimState) -> T) -> Result<T, String> {
        let mut g = self
            .state
            .lock()
            .map_err(|_| "the simulation panicked".to_string())?;
        Ok(f(&mut g))
    }

    fn set_state(&self, id: &str, st: pb::NetworkState, error: &str) -> Result<(), String> {
        self.with(|s| {
            for n in &mut s.networks {
                if n.id == id {
                    n.state = st as i32;
                    n.error = error.to_string();
                }
            }
        })
    }
}

impl Backend for Sim {
    async fn status(&self) -> pb::WifiStatus {
        let snap = self.with(|s| (s.enabled, s.networks.clone()));
        let Ok((enabled, mut networks)) = snap else {
            return pb::WifiStatus {
                detail: "the simulation panicked".into(),
                simulated: true,
                ..Default::default()
            };
        };
        if !enabled {
            networks.clear();
        }
        model::sort(&mut networks);
        let connected = networks.iter().any(|n| {
            n.state == pb::NetworkState::Online as i32
                || n.state == pb::NetworkState::Connected as i32
        });
        pb::WifiStatus {
            available: true,
            enabled,
            connectivity: if connected {
                pb::Connectivity::Online
            } else {
                pb::Connectivity::Offline
            } as i32,
            address: if connected {
                "192.0.2.10".into()
            } else {
                String::new()
            },
            networks,
            detail: "Simulated Wi-Fi: no real networks".into(),
            simulated: true,
            scanning: false,
        }
    }

    async fn set_enabled(&self, on: bool) -> Result<(), String> {
        self.with(|s| {
            s.enabled = on;
            if !on {
                for n in &mut s.networks {
                    n.state = pb::NetworkState::Idle as i32;
                }
            } else if let Some(n) = s.networks.iter_mut().find(|n| n.saved) {
                n.state = pb::NetworkState::Online as i32;
            }
        })
    }

    async fn scan(&self) -> Result<(), String> {
        tokio::time::sleep(Duration::from_millis(500)).await;
        Ok(())
    }

    async fn connect(&self, id: &str, passphrase: &str) -> Result<(), String> {
        let (enabled, target) =
            self.with(|s| (s.enabled, s.networks.iter().find(|n| n.id == id).cloned()))?;
        if !enabled {
            return Err("Wi-Fi is off".into());
        }
        let n = target.ok_or("That network is gone")?;
        let secured = n.security != pb::Security::Open as i32;
        if n.security == pb::Security::Enterprise as i32 {
            return Err("Enterprise (802.1X) networks can't be joined from the dashboard".into());
        }
        // Leave the current one.
        self.with(|s| {
            for m in &mut s.networks {
                if m.id != id {
                    m.state = pb::NetworkState::Idle as i32;
                }
            }
        })?;
        self.set_state(id, pb::NetworkState::Connecting, "")?;
        tokio::time::sleep(Self::JOIN).await;
        if secured && !n.saved && (passphrase.chars().count() < 8 || passphrase == "wrongpass") {
            self.set_state(id, pb::NetworkState::Failed, "invalid-key")?;
            return Err(model::error_words("invalid-key"));
        }
        self.with(|s| {
            for m in &mut s.networks {
                if m.id == id {
                    m.state = pb::NetworkState::Online as i32;
                    m.saved = true;
                    m.error.clear();
                }
            }
        })
    }

    async fn disconnect(&self, id: &str) -> Result<(), String> {
        self.set_state(id, pb::NetworkState::Idle, "")
    }

    async fn forget(&self, id: &str) -> Result<(), String> {
        self.with(|s| {
            for n in &mut s.networks {
                if n.id == id {
                    n.saved = false;
                    n.state = pb::NetworkState::Idle as i32;
                }
            }
        })
    }
}

#[cfg(test)]
#[allow(clippy::unwrap_used)]
mod tests {
    use super::*;

    fn find<'a>(s: &'a pb::WifiStatus, name: &str) -> &'a pb::WifiNetwork {
        s.networks.iter().find(|n| n.name == name).unwrap()
    }

    #[tokio::test(start_paused = true)]
    async fn starts_online_on_the_hotspot() {
        let s = Sim::default().status().await;
        assert!(s.available && s.enabled && s.simulated);
        assert_eq!(s.connectivity, pb::Connectivity::Online as i32);
        assert_eq!(s.networks[0].name, "F-250 Hotspot");
    }

    #[tokio::test(start_paused = true)]
    async fn a_wrong_passphrase_then_the_right_one() {
        let sim = Sim::default();
        let id = "wifi_sim_shop_managed_psk";
        assert_eq!(
            sim.connect(id, "short").await.unwrap_err(),
            "Wrong passphrase"
        );
        assert_eq!(
            find(&sim.status().await, "Shop Wi-Fi").state,
            pb::NetworkState::Failed as i32
        );
        sim.connect(id, "long enough").await.unwrap();
        let s = sim.status().await;
        assert_eq!(s.networks[0].name, "Shop Wi-Fi");
        assert!(s.networks[0].saved);
        assert_eq!(
            find(&s, "F-250 Hotspot").state,
            pb::NetworkState::Idle as i32
        );
    }

    #[tokio::test(start_paused = true)]
    async fn off_forget_and_enterprise() {
        let sim = Sim::default();
        sim.set_enabled(false).await.unwrap();
        let s = sim.status().await;
        assert!(!s.enabled && s.networks.is_empty());
        assert_eq!(s.connectivity, pb::Connectivity::Offline as i32);
        assert_eq!(
            sim.connect("wifi_sim_shop_managed_psk", "x")
                .await
                .unwrap_err(),
            "Wi-Fi is off"
        );
        sim.set_enabled(true).await.unwrap();
        sim.forget("wifi_sim_hotspot_managed_psk").await.unwrap();
        assert!(!find(&sim.status().await, "F-250 Hotspot").saved);
        assert!(
            sim.connect("wifi_sim_corp_managed_ieee8021x", "")
                .await
                .is_err()
        );
    }
}
