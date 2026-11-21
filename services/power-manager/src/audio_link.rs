//! Passes the 5-way switch's short presses to audio-manager: its
//! `f250.audio.v1` `PressMediaKey` call
//! ([ADR-0051](../../../docs/architecture/adr/0051-five-way-switch-media-and-cameras.md)).
//! audio-manager decides what the centre press means (answer, hang up, or
//! play/pause), as for the knob's push. The queue, timeouts and lazy
//! connection are [`crate::link`]'s.

use f250_proto::audio::v1 as pb;
use pb::audio_service_client::AudioServiceClient;
use tonic::transport::Channel;

use crate::link::{self, Link, LinkConfig, Outcome};
use crate::switch::Role;
use crate::switch_control::Sent;

/// The name audio-manager logs for these presses.
pub const SOURCE: &str = "power-manager (5-way switch)";

/// Starts the link. `report` is called once per press with what became of
/// it.
pub fn spawn<R>(cfg: &LinkConfig, report: R) -> Result<Link<Sent>, String>
where
    R: FnMut(Sent, Outcome) + Send + 'static,
{
    let client = AudioServiceClient::new(link::channel(cfg, "--audio-manager")?);
    Ok(Link::spawn(
        cfg,
        move |sent: Sent| {
            let mut client = client.clone();
            async move { call(&mut client, sent.role).await }
        },
        report,
    ))
}

/// The media key a role's short press sends.
pub fn media_key(role: Role) -> pb::MediaKey {
    match role {
        Role::Up => pb::MediaKey::VolumeUp,
        Role::Down => pb::MediaKey::VolumeDown,
        Role::Left => pb::MediaKey::Previous,
        Role::Right => pb::MediaKey::Next,
        Role::Press => pb::MediaKey::PlayPause,
    }
}

async fn call(client: &mut AudioServiceClient<Channel>, role: Role) -> Outcome {
    let request = pb::PressMediaKeyRequest {
        key: media_key(role) as i32,
        source: SOURCE.to_string(),
    };
    match client.press_media_key(request).await {
        Err(status) => Outcome::Failed(link::status_text(&status)),
        Ok(r) => {
            let r = r.into_inner();
            if r.accepted {
                Outcome::Delivered(r.detail)
            } else {
                Outcome::Failed(r.detail)
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn every_role_maps_to_its_key() {
        let keys: Vec<pb::MediaKey> = Role::ALL.into_iter().map(media_key).collect();
        assert_eq!(
            keys,
            [
                pb::MediaKey::VolumeUp,
                pb::MediaKey::VolumeDown,
                pb::MediaKey::Previous,
                pb::MediaKey::Next,
                pb::MediaKey::PlayPause,
            ]
        );
    }
}
