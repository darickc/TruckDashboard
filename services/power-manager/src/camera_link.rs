//! Passes the 5-way switch's long presses to camera-manager: its
//! `f250.camera.v1` `Move` call
//! ([ADR-0026](../../../docs/architecture/adr/0026-camera-manager-interfaces.md),
//! [ADR-0051](../../../docs/architecture/adr/0051-five-way-switch-media-and-cameras.md)).
//! The queue, timeouts and lazy connection are [`crate::link`]'s.

use f250_proto::camera::v1 as pb;
use pb::camera_service_client::CameraServiceClient;
use tonic::transport::Channel;

use crate::link::{self, Link, LinkConfig, Outcome};
use crate::switch::Role;
use crate::switch_control::Sent;

/// The name camera-manager logs for these moves.
pub const SOURCE: &str = "power-manager (5-way switch)";

/// Starts the link. `report` is called once per press with what became of
/// it.
pub fn spawn<R>(cfg: &LinkConfig, report: R) -> Result<Link<Sent>, String>
where
    R: FnMut(Sent, Outcome) + Send + 'static,
{
    let client = CameraServiceClient::new(link::channel(cfg, "--camera-manager")?);
    Ok(Link::spawn(
        cfg,
        move |sent: Sent| {
            let mut client = client.clone();
            async move { call(&mut client, sent.role).await }
        },
        report,
    ))
}

/// The camera move a role's long press makes: Up is the switch's old
/// Forward, Down its Back.
pub fn switch_move(role: Role) -> pb::SwitchMove {
    match role {
        Role::Left => pb::SwitchMove::Left,
        Role::Right => pb::SwitchMove::Right,
        Role::Down => pb::SwitchMove::Back,
        Role::Up => pb::SwitchMove::Forward,
        Role::Press => pb::SwitchMove::Press,
    }
}

/// A short description of a view for the log: `rear camera (live)`,
/// `dashboard`, `left camera (unavailable: no left camera configured)`.
pub fn describe_view(view: &pb::View) -> String {
    let camera = match pb::Camera::try_from(view.camera) {
        Ok(pb::Camera::Left) => "left camera",
        Ok(pb::Camera::Right) => "right camera",
        Ok(pb::Camera::Rear) => "rear camera",
        Ok(pb::Camera::Front) => "front camera",
        _ => return "dashboard".to_string(),
    };
    let feed = match pb::FeedState::try_from(view.feed) {
        Ok(pb::FeedState::Starting) => "starting".to_string(),
        Ok(pb::FeedState::Live) => "live".to_string(),
        Ok(pb::FeedState::Unavailable) if view.feed_detail.is_empty() => "unavailable".to_string(),
        Ok(pb::FeedState::Unavailable) => format!("unavailable: {}", view.feed_detail),
        _ => "feed unknown".to_string(),
    };
    format!("{camera} ({feed})")
}

async fn call(client: &mut CameraServiceClient<Channel>, role: Role) -> Outcome {
    let request = pb::MoveRequest {
        r#move: switch_move(role) as i32,
        source: SOURCE.to_string(),
    };
    match client.r#move(request).await {
        Err(status) => Outcome::Failed(link::status_text(&status)),
        Ok(response) => match response.into_inner().view {
            Some(view) => Outcome::Delivered(describe_view(&view)),
            None => Outcome::Failed("camera-manager answered without a view".to_string()),
        },
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn every_role_maps_to_its_move() {
        let moves: Vec<pb::SwitchMove> = Role::ALL.into_iter().map(switch_move).collect();
        assert_eq!(
            moves,
            [
                pb::SwitchMove::Forward,
                pb::SwitchMove::Back,
                pb::SwitchMove::Left,
                pb::SwitchMove::Right,
                pb::SwitchMove::Press,
            ]
        );
    }

    #[test]
    fn views_read_plainly_in_the_log() {
        let mut v = pb::View::default();
        assert_eq!(describe_view(&v), "dashboard");
        v.camera = pb::Camera::Rear as i32;
        v.feed = pb::FeedState::Live as i32;
        assert_eq!(describe_view(&v), "rear camera (live)");
        v.camera = pb::Camera::Left as i32;
        v.feed = pb::FeedState::Unavailable as i32;
        v.feed_detail = "no left camera configured".into();
        assert_eq!(
            describe_view(&v),
            "left camera (unavailable: no left camera configured)"
        );
    }
}
