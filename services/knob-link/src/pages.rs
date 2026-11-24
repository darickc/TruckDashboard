//! The dial's navigation and media pages (ADR-0044 decision 9): `N1` from
//! navigation's guidance and route, `M1` from audio-manager; and `P1`, a
//! phone call, which takes over the dial (ADR-0045 decision 6). The dial parses
//! them in `firmware/knob-display/lib/KnobCore/src/Frame.cpp`; the golden
//! lines below are parsed there too (`test_frame`).
//!
//!   N1 go <turn> <dist> <dunit> <left> <lunit> <min> [<street>]
//!   N1 none | N1 route | N1 wait | N1 arr [<destination>]
//!   M1 <play|pause|stop> <vol> <pos_s|-> <dur_s|-> <title>\t<artist>\t<source>
//!   M1 none <vol>
//!   P1 <ring|wait|dial|call|hold> <active_s> <caller>\t<number>
//!   P1 none

use f250_proto::audio::v1 as audio;
use f250_proto::nav::v1 as nav;

use crate::frame::{CallRequest, Units, with_checksum};

/// Valhalla's maneuver type (odin's DirectionsLeg_Maneuver_Type) as the
/// dial's arrow, the same grouping as the dashboard's icons
/// (navigation_screen.dart `maneuverIcon`).
pub fn turn_name(valhalla_type: u32) -> &'static str {
    match valhalla_type {
        1..=3 => "start",
        4..=6 => "dest",
        7 | 8 | 17 | 22 => "straight",
        9 => "slight-right",
        10 => "right",
        11 => "sharp-right",
        12 => "uturn-right",
        13 => "uturn-left",
        14 => "sharp-left",
        15 => "left",
        16 => "slight-left",
        18 | 20 => "ramp-right",
        19 | 21 => "ramp-left",
        23 => "fork-right",
        24 => "fork-left",
        25 | 37 | 38 => "merge",
        26 | 27 => "roundabout",
        28 | 29 => "ferry",
        _ => "other",
    }
}

/// A distance as the dial shows it: feet under a tenth of a mile (to 50 ft),
/// then miles (one decimal under 10); metres (to 10 m) under 1 km, then km.
pub fn distance(m: f64, units: Units) -> (String, &'static str) {
    let m = m.max(0.0);
    match units {
        Units::Imperial => {
            let mi = m / 1609.344;
            if mi < 0.1 {
                let ft = (m / 0.3048 / 50.0).round() * 50.0;
                (format!("{ft:.0}"), "ft")
            } else if mi < 10.0 {
                (format!("{mi:.1}"), "mi")
            } else {
                (format!("{mi:.0}"), "mi")
            }
        }
        Units::Metric => {
            if m < 1000.0 {
                (format!("{:.0}", (m / 10.0).round() * 10.0), "m")
            } else if m < 10_000.0 {
                (format!("{:.1}", m / 1000.0), "km")
            } else {
                (format!("{:.0}", m / 1000.0), "km")
            }
        }
    }
}

/// Text for the dial: no tabs, stars, line ends or other control characters,
/// at most `max` bytes, cut at a character boundary.
pub fn clean(s: &str, max: usize) -> String {
    let mut out = String::new();
    for c in s.chars() {
        let c = if c.is_control() || c == '*' { ' ' } else { c };
        if out.len() + c.len_utf8() > max {
            break;
        }
        out.push(c);
    }
    out.trim().to_string()
}

/// The navigation page. `route` is the guidance's route when it has been
/// fetched (GetRoute); without it there is no turn to show yet.
pub fn nav_line(g: &nav::Guidance, route: Option<&nav::Route>, units: Units) -> String {
    let body = match nav::RouteState::try_from(g.state) {
        Ok(nav::RouteState::Routing) => "N1 route".to_string(),
        Ok(nav::RouteState::Arrived) => {
            let name = clean(&g.destination_name, 80);
            if name.is_empty() {
                "N1 arr".to_string()
            } else {
                format!("N1 arr {name}")
            }
        }
        Ok(nav::RouteState::Active) => {
            // Progress only comes with a current position (navigation never
            // sends a stale one): without it, no distance.
            let next = g.progress.as_ref().and_then(|p| {
                let r = route.filter(|r| r.id == g.route_id)?;
                Some((p, r.maneuvers.get(p.maneuver_index as usize)?))
            });
            match next {
                None => "N1 wait".to_string(),
                Some((p, m)) => {
                    let (d, du) = distance(p.to_maneuver_m, units);
                    let (l, lu) = distance(p.remaining_m, units);
                    let min = (p.remaining_s.max(0.0) / 60.0).ceil() as u64;
                    let street = clean(m.street_names.first().map_or("", String::as_str), 80);
                    let mut b = format!("N1 go {} {d} {du} {l} {lu} {min}", turn_name(m.r#type));
                    if !street.is_empty() {
                        b.push(' ');
                        b.push_str(&street);
                    }
                    b
                }
            }
        }
        // Idle, unavailable, failed: nothing to follow.
        _ => "N1 none".to_string(),
    };
    with_checksum(&body)
}

fn volume_token(v: Option<&audio::Volume>) -> String {
    match v {
        Some(v) if v.steps > 0 && v.level <= v.steps => {
            format!("{}{}/{}", if v.muted { "m" } else { "" }, v.level, v.steps)
        }
        _ => "-".to_string(),
    }
}

/// The media page, from audio-manager's update.
pub fn media_line(a: &audio::WatchAudioResponse) -> String {
    let vol = volume_token(a.volume.as_ref());
    let body = match (&a.phone, &a.now_playing) {
        (Some(phone), Some(np)) => {
            let state = match audio::PlayState::try_from(np.state) {
                Ok(
                    audio::PlayState::Playing
                    | audio::PlayState::ForwardSeek
                    | audio::PlayState::ReverseSeek,
                ) => "play",
                Ok(audio::PlayState::Paused) => "pause",
                _ => "stop",
            };
            let pos = if np.has_position {
                (np.position_ms / 1000).to_string()
            } else {
                "-".to_string()
            };
            let dur = if np.duration_ms > 0 {
                (np.duration_ms / 1000).to_string()
            } else {
                "-".to_string()
            };
            format!(
                "M1 {state} {vol} {pos} {dur} {}\t{}\t{}",
                clean(&np.title, 60),
                clean(&np.artist, 44),
                clean(&phone.name, 28)
            )
        }
        _ => format!("M1 none {vol}"),
    };
    with_checksum(&body)
}

/// The phone call, from audio-manager's update (ADR-0045): `P1 none`
/// without one, or from an audio-manager without calls.
pub fn call_line(a: &audio::WatchAudioResponse) -> String {
    let call = a
        .calls
        .as_ref()
        .and_then(|c| c.call.as_ref())
        .filter(|_| a.phone.is_some());
    let state = call.and_then(|c| match audio::CallState::try_from(c.state) {
        Ok(audio::CallState::Incoming) => Some("ring"),
        Ok(audio::CallState::Waiting) => Some("wait"),
        Ok(audio::CallState::Dialing | audio::CallState::Alerting) => Some("dial"),
        Ok(audio::CallState::Active) => Some("call"),
        Ok(audio::CallState::Held) => Some("hold"),
        _ => None,
    });
    let body = match (call, state) {
        (Some(c), Some(state)) => {
            // The same words as the dashboard's call bar.
            let caller = if !c.name.is_empty() {
                clean(&c.name, 44)
            } else if !c.number.is_empty() {
                clean(&c.number, 44)
            } else if c.withheld {
                "Number withheld".to_string()
            } else {
                "Unknown caller".to_string()
            };
            let number = if c.name.is_empty() {
                String::new()
            } else {
                clean(&c.number, 24)
            };
            format!("P1 {state} {} {caller}\t{number}", c.active_s)
        }
        _ => "P1 none".to_string(),
    };
    with_checksum(&body)
}

/// What to ask audio-manager for a call button.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum CallCommand {
    Answer(u64),
    HangUp(u64),
}

/// The command for a call button pressed on the dial, against the call
/// audio-manager shows now (the one `call_line` sends): only if that call is
/// still in a state the button was for — Answer a ringing call, Decline a
/// ringing or waiting one, End one active, held or being dialled — so a
/// Decline that crosses an answer on the phone never ends the call. Why not,
/// otherwise.
pub fn call_command(
    req: CallRequest,
    a: Option<&audio::WatchAudioResponse>,
) -> Result<CallCommand, String> {
    let call = a
        .filter(|a| a.phone.is_some())
        .and_then(|a| a.calls.as_ref())
        .and_then(|c| c.call.as_ref())
        .ok_or_else(|| "no call".to_string())?;
    let state = audio::CallState::try_from(call.state).unwrap_or(audio::CallState::Unspecified);
    use audio::CallState as S;
    let ok = match req {
        CallRequest::Answer => matches!(state, S::Incoming),
        CallRequest::Decline => matches!(state, S::Incoming | S::Waiting),
        CallRequest::End => matches!(state, S::Dialing | S::Alerting | S::Active | S::Held),
    };
    if !ok {
        return Err(format!("the call is {}", state.as_str_name()));
    }
    Ok(match req {
        CallRequest::Answer => CallCommand::Answer(call.id),
        CallRequest::Decline | CallRequest::End => CallCommand::HangUp(call.id),
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    fn route(id: u64) -> nav::Route {
        nav::Route {
            id,
            maneuvers: vec![
                nav::Maneuver {
                    r#type: 1,
                    ..Default::default()
                },
                nav::Maneuver {
                    r#type: 10,
                    street_names: vec!["Main Street".into(), "US 36".into()],
                    ..Default::default()
                },
            ],
            ..Default::default()
        }
    }

    fn active(route_id: u64, progress: Option<nav::Progress>) -> nav::Guidance {
        nav::Guidance {
            state: nav::RouteState::Active.into(),
            route_id,
            progress,
            ..Default::default()
        }
    }

    fn progress() -> nav::Progress {
        nav::Progress {
            maneuver_index: 1,
            to_maneuver_m: 640.0,
            remaining_m: 19_400.0,
            remaining_s: 1061.0,
            ..Default::default()
        }
    }

    #[test]
    fn the_next_turn() {
        let line = nav_line(
            &active(7, Some(progress())),
            Some(&route(7)),
            Units::Imperial,
        );
        // Golden: firmware test_frame parses this exact line.
        assert_eq!(line, "N1 go right 0.4 mi 12 mi 18 Main Street*1D");
        let metric = nav_line(&active(7, Some(progress())), Some(&route(7)), Units::Metric);
        assert!(
            metric.starts_with("N1 go right 640 m 19 km 18 Main Street*"),
            "{metric}"
        );
    }

    #[test]
    fn no_distance_without_a_position_or_the_route() {
        assert!(
            nav_line(&active(7, None), Some(&route(7)), Units::Imperial).starts_with("N1 wait*")
        );
        assert!(
            nav_line(&active(7, Some(progress())), None, Units::Imperial).starts_with("N1 wait*")
        );
        // The route fetched is an older one.
        assert!(
            nav_line(
                &active(8, Some(progress())),
                Some(&route(7)),
                Units::Imperial
            )
            .starts_with("N1 wait*")
        );
        let mut p = progress();
        p.maneuver_index = 9;
        assert!(
            nav_line(&active(7, Some(p)), Some(&route(7)), Units::Imperial).starts_with("N1 wait*")
        );
    }

    #[test]
    fn other_states() {
        let g = |s: nav::RouteState, name: &str| nav::Guidance {
            state: s.into(),
            destination_name: name.into(),
            ..Default::default()
        };
        assert!(
            nav_line(&g(nav::RouteState::Idle, ""), None, Units::Metric).starts_with("N1 none*")
        );
        assert!(
            nav_line(&g(nav::RouteState::Unavailable, ""), None, Units::Metric)
                .starts_with("N1 none*")
        );
        assert!(
            nav_line(&g(nav::RouteState::Failed, ""), None, Units::Metric).starts_with("N1 none*")
        );
        assert!(
            nav_line(&g(nav::RouteState::Routing, ""), None, Units::Metric)
                .starts_with("N1 route*")
        );
        assert!(
            nav_line(&g(nav::RouteState::Arrived, "Home"), None, Units::Metric)
                .starts_with("N1 arr Home*")
        );
        assert!(
            nav_line(&g(nav::RouteState::Arrived, ""), None, Units::Metric).starts_with("N1 arr*")
        );
    }

    #[test]
    fn distances() {
        assert_eq!(distance(100.0, Units::Imperial), ("350".into(), "ft"));
        assert_eq!(distance(161.0, Units::Imperial), ("0.1".into(), "mi"));
        assert_eq!(distance(20_000.0, Units::Imperial), ("12".into(), "mi"));
        assert_eq!(distance(-5.0, Units::Imperial), ("0".into(), "ft"));
        assert_eq!(distance(644.0, Units::Metric), ("640".into(), "m"));
        assert_eq!(distance(1500.0, Units::Metric), ("1.5".into(), "km"));
        assert_eq!(distance(25_400.0, Units::Metric), ("25".into(), "km"));
    }

    #[test]
    fn every_maneuver_type_has_a_name_the_dial_knows() {
        // The dial's list (Frame.cpp kTurns).
        let dial = [
            "other",
            "start",
            "dest",
            "straight",
            "slight-right",
            "right",
            "sharp-right",
            "uturn-right",
            "uturn-left",
            "sharp-left",
            "left",
            "slight-left",
            "ramp-right",
            "ramp-left",
            "fork-right",
            "fork-left",
            "merge",
            "roundabout",
            "ferry",
        ];
        for t in 0..64 {
            assert!(dial.contains(&turn_name(t)), "{t}");
        }
    }

    fn playing() -> audio::WatchAudioResponse {
        audio::WatchAudioResponse {
            phone: Some(audio::Phone {
                name: "Pixel 8".into(),
                connected: true,
                ..Default::default()
            }),
            now_playing: Some(audio::NowPlaying {
                title: "Second Simulated Song".into(),
                artist: "The Test Tones".into(),
                state: audio::PlayState::Playing.into(),
                duration_ms: 242_000,
                has_position: true,
                position_ms: 94_500,
                ..Default::default()
            }),
            volume: Some(audio::Volume {
                level: 18,
                max: 30,
                steps: 30,
                ..Default::default()
            }),
            ..Default::default()
        }
    }

    #[test]
    fn whats_playing() {
        // Golden: firmware test_frame parses this exact line.
        assert_eq!(
            media_line(&playing()),
            "M1 play 18/30 94 242 Second Simulated Song\tThe Test Tones\tPixel 8*67"
        );
        let mut a = playing();
        if let Some(np) = a.now_playing.as_mut() {
            np.state = audio::PlayState::Paused.into();
            np.has_position = false;
            np.duration_ms = 0;
            np.title = "Tab\there *star*\nnewline".into();
        }
        if let Some(v) = a.volume.as_mut() {
            v.muted = true;
        }
        let line = media_line(&a);
        assert!(
            line.starts_with("M1 pause m18/30 - - Tab here  star  newline\t"),
            "{line}"
        );
    }

    #[test]
    fn no_phone_or_no_player() {
        let mut a = playing();
        a.now_playing = None;
        assert!(media_line(&a).starts_with("M1 none 18/30*"));
        a.phone = None;
        a.volume = None;
        assert!(media_line(&a).starts_with("M1 none -*"));
    }

    fn with_call(state: audio::CallState) -> audio::WatchAudioResponse {
        let mut a = playing();
        a.calls = Some(audio::Calls {
            available: true,
            call: Some(audio::Call {
                id: 3,
                state: state.into(),
                number: "+15550100".into(),
                name: "Test Caller".into(),
                active_s: 65,
                ..Default::default()
            }),
            ..Default::default()
        });
        a
    }

    #[test]
    fn call_buttons_act_only_on_the_call_they_were_for() {
        use audio::CallState as S;
        let r = |req, st| call_command(req, Some(&with_call(st)));
        assert_eq!(
            r(CallRequest::Answer, S::Incoming),
            Ok(CallCommand::Answer(3))
        );
        assert_eq!(
            r(CallRequest::Decline, S::Incoming),
            Ok(CallCommand::HangUp(3))
        );
        assert_eq!(
            r(CallRequest::Decline, S::Waiting),
            Ok(CallCommand::HangUp(3))
        );
        for st in [S::Dialing, S::Alerting, S::Active, S::Held] {
            assert_eq!(r(CallRequest::End, st), Ok(CallCommand::HangUp(3)));
        }
        // A Decline that crosses an answer on the phone ends nothing.
        assert!(r(CallRequest::Decline, S::Active).is_err());
        // Answering a waiting call is the phone's (it would end or hold the
        // first); End on a ringing call is a Decline the dial didn't show.
        assert!(r(CallRequest::Answer, S::Waiting).is_err());
        assert!(r(CallRequest::End, S::Incoming).is_err());
        assert!(r(CallRequest::Answer, S::Active).is_err());
        // No call, no phone, nothing from audio-manager.
        assert_eq!(
            call_command(CallRequest::End, Some(&playing())),
            Err("no call".into())
        );
        let mut no_phone = with_call(S::Incoming);
        no_phone.phone = None;
        assert!(call_command(CallRequest::Answer, Some(&no_phone)).is_err());
        assert!(call_command(CallRequest::Answer, None).is_err());
    }

    #[test]
    #[allow(clippy::unwrap_used)]
    fn a_call() {
        // Golden: firmware test_frame parses this exact line.
        assert_eq!(
            call_line(&with_call(audio::CallState::Active)),
            "P1 call 65 Test Caller\t+15550100*44"
        );
        for (st, token) in [
            (audio::CallState::Incoming, "ring"),
            (audio::CallState::Waiting, "wait"),
            (audio::CallState::Dialing, "dial"),
            (audio::CallState::Alerting, "dial"),
            (audio::CallState::Held, "hold"),
        ] {
            let line = call_line(&with_call(st));
            assert!(
                line.starts_with(&format!("P1 {token} 65 Test Caller\t")),
                "{line}"
            );
        }
        // Less from the phone: the number alone, then the reason.
        let mut a = with_call(audio::CallState::Incoming);
        let c = a.calls.as_mut().and_then(|c| c.call.as_mut()).unwrap();
        c.name.clear();
        c.active_s = 0;
        assert!(
            call_line(&a).starts_with("P1 ring 0 +15550100\t*"),
            "{}",
            call_line(&a)
        );
        let c = a.calls.as_mut().and_then(|c| c.call.as_mut()).unwrap();
        c.number.clear();
        c.withheld = true;
        assert!(call_line(&a).starts_with("P1 ring 0 Number withheld\t*"));
        let c = a.calls.as_mut().and_then(|c| c.call.as_mut()).unwrap();
        c.withheld = false;
        c.name = "Tab\there *star*".into();
        assert!(
            call_line(&a).starts_with("P1 ring 0 Tab here  star\t*"),
            "{}",
            call_line(&a)
        );
    }

    #[test]
    fn no_call() {
        assert!(
            call_line(&playing()).starts_with("P1 none*"),
            "no calls at all"
        );
        let mut a = with_call(audio::CallState::Active);
        a.phone = None;
        assert!(call_line(&a).starts_with("P1 none*"), "a gone phone's call");
        let a = with_call(audio::CallState::Unspecified);
        assert!(call_line(&a).starts_with("P1 none*"));
    }

    #[test]
    fn long_text_is_cut_on_a_character() {
        assert_eq!(clean("ééé", 5), "éé");
        assert_eq!(clean(&"x".repeat(100), 60).len(), 60);
        let mut a = playing();
        if let Some(np) = a.now_playing.as_mut() {
            np.title = "é".repeat(200);
            np.artist = "a".repeat(200);
        }
        if let Some(p) = a.phone.as_mut() {
            p.name = "p".repeat(200);
        }
        assert!(media_line(&a).len() <= 255);
    }
}
