//! Which camera the head unit shows
//! ([camera-policy.md](../../../docs/architecture/camera-policy.md),
//! [ADR-0024](../../../docs/architecture/adr/0024-camera-selection-switch-and-can-reverse.md)).
//!
//! Priority, highest first:
//!
//! 1. **Reverse** shows the rear camera, from the gateway's reverse signal
//!    (HS-CAN broadcast `230`, a candidate decoder). It counts once reverse
//!    has been reported for `rev_debounce`, and the rear view stays for
//!    `rev_hold` after reverse clears. Automatic reverse is **off by default**
//!    until the decoder is verified on the truck ([`Config::auto_reverse`]).
//! 2. **The switch's choice**, latched until the next move. Moves during
//!    reverse are recorded and shown when reverse ends.
//!
//! With neither, there is no camera: the UI goes back to the screen that was
//! showing before.
//!
//! Stale data is never shown as current (CLAUDE.md rule 4):
//!
//! - A reverse signal that is stale (no sample for `rev_stale`) or reported
//!   invalid is **unknown**, never "not in reverse". It never starts the rear
//!   view, and [`View::reverse`] says it is unknown so the UI can show it.
//! - If reverse goes unknown **while the rear view is up** (the last thing
//!   known is that the truck is in reverse), the rear view stays, with the
//!   unknown warning, until the signal comes back or the driver moves the
//!   switch. Dropping the rear camera mid-reverse because of a CAN glitch
//!   would be worse than keeping it; the switch is the way out.
//! - A camera with no recent frames is reported down by its pipeline; the
//!   view still selects it and [`View::camera_unavailable`] makes the UI show
//!   "Camera unavailable" in its place, never a frozen frame.
//!
//! The switch's moves arrive already debounced, from power-manager
//! ([ADR-0025](../../../docs/architecture/adr/0025-camera-switch-through-gpio-key.md)).
//!
//! Pure logic: every input comes with a monotonic time, so the tests drive it
//! without a clock. [`Policy::deadline`] says when to call again if nothing
//! else happens.
//!
//! Status: `[SIM]`, unit tests only. No camera, pipeline or verified reverse
//! decoder exists yet.

use std::time::Duration;

/// A camera.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Camera {
    Left,
    Right,
    Rear,
}

impl Camera {
    pub const ALL: [Camera; 3] = [Camera::Left, Camera::Right, Camera::Rear];

    const fn bit(self) -> u8 {
        1 << self as u8
    }
}

/// One debounced move of the 5-way switch.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Move {
    Left,
    Right,
    Back,
    Forward,
    Press,
}

/// What a move picks.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Choice {
    Camera(Camera),
    /// No camera: back to the screen that was showing before.
    Off,
}

/// The settings. Every time and the speed limit are **examples**, to be tuned
/// on the truck.
#[derive(Debug, Clone, PartialEq)]
pub struct Config {
    /// Show the rear camera automatically in reverse. Off until the `230`
    /// decoder has its VERIFICATION_LOG entry (ADR-0024 decision 4); until
    /// then the switch's Back is the way to see the rear camera.
    pub auto_reverse: bool,
    /// How long reverse must be reported before the rear view comes up.
    pub rev_debounce: Duration,
    /// How long the rear view stays after reverse clears.
    pub rev_hold: Duration,
    /// How long without a reverse sample before it is unknown. The candidate
    /// broadcast arrives about 31 times a second (CAN_CENSUS).
    pub rev_stale: Duration,
    /// Manual selection is allowed only at or below this speed. `None` (the
    /// default): any speed (owner, ADR-0024 decision 6).
    pub manual_max_speed_kph: Option<f64>,
    pub left: Choice,
    pub right: Choice,
    pub back: Choice,
    pub forward: Choice,
    pub press: Choice,
}

impl Default for Config {
    fn default() -> Self {
        Self {
            auto_reverse: false,
            rev_debounce: Duration::from_millis(150),
            rev_hold: Duration::from_millis(2000),
            rev_stale: Duration::from_millis(500),
            manual_max_speed_kph: None,
            left: Choice::Camera(Camera::Left),
            right: Choice::Camera(Camera::Right),
            back: Choice::Camera(Camera::Rear),
            forward: Choice::Off,
            press: Choice::Off,
        }
    }
}

impl Config {
    pub fn choice(&self, m: Move) -> Choice {
        match m {
            Move::Left => self.left,
            Move::Right => self.right,
            Move::Back => self.back,
            Move::Forward => self.forward,
            Move::Press => self.press,
        }
    }
}

/// What happened.
#[derive(Debug, Clone, Copy, PartialEq)]
pub enum Input {
    /// Time passed.
    Tick,
    /// A fresh reverse sample from the gateway: in reverse or not.
    Reverse(bool),
    /// The gateway reports the reverse signal invalid or unavailable now.
    ReverseInvalid,
    /// A debounced switch move.
    Switch(Move),
    /// Vehicle speed in km/h, or `None` when it is stale or unknown. Only
    /// used with [`Config::manual_max_speed_kph`].
    Speed(Option<f64>),
    /// A camera's pipeline is delivering frames.
    CameraUp(Camera),
    /// A camera is missing, failed, or its frames are stale.
    CameraDown(Camera),
}

/// The reverse signal as the UI should show it.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ReverseStatus {
    /// Automatic reverse is switched off in the configuration.
    Off,
    /// Stale, invalid, or never received.
    Unknown,
    NotEngaged,
    Engaged,
}

/// Why a camera is showing.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Why {
    Reverse,
    Switch,
}

/// What the UI shows.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct View {
    /// The camera to show; `None` means the screen that was showing before.
    pub camera: Option<Camera>,
    pub why: Option<Why>,
    /// The selected camera has no live frames: show "Camera unavailable".
    pub camera_unavailable: bool,
    /// For the reverse indicator. `Unknown` must be visible.
    pub reverse: ReverseStatus,
    /// A camera is chosen but the speed limit (or an unknown speed) hides it.
    pub blocked_by_speed: bool,
}

/// The state machine.
#[derive(Debug, Clone)]
pub struct Policy {
    config: Config,
    /// The last reverse sample and when it came.
    sample: Option<(bool, Duration)>,
    /// The gateway said the signal is invalid, after the last sample.
    invalid: bool,
    /// Since when reverse has been reported without a break.
    engaged_since: Option<Duration>,
    /// The rear view is up because of reverse.
    rear_active: bool,
    /// When reverse cleared, while the rear view is held.
    cleared_at: Option<Duration>,
    latched: Choice,
    speed_kph: Option<f64>,
    cameras_up: u8,
    /// The time of the last input.
    now: Duration,
    view: View,
}

impl Policy {
    pub fn new(config: Config) -> Self {
        let mut p = Self {
            config,
            sample: None,
            invalid: false,
            engaged_since: None,
            rear_active: false,
            cleared_at: None,
            latched: Choice::Off,
            speed_kph: None,
            cameras_up: 0,
            now: Duration::ZERO,
            view: View {
                camera: None,
                why: None,
                camera_unavailable: false,
                reverse: ReverseStatus::Unknown,
                blocked_by_speed: false,
            },
        };
        p.view = p.compute(Duration::ZERO);
        p
    }

    pub fn config(&self) -> &Config {
        &self.config
    }

    /// The view after the last input.
    pub fn view(&self) -> View {
        self.view
    }

    /// Feed one input at `now` (monotonic) and get the view.
    pub fn handle(&mut self, input: Input, now: Duration) -> View {
        self.now = now;
        match input {
            Input::Tick => {}
            Input::Reverse(engaged) => {
                self.sample = Some((engaged, now));
                self.invalid = false;
            }
            Input::ReverseInvalid => self.invalid = true,
            Input::Switch(m) => {
                self.latched = self.config.choice(m);
                // With reverse unknown, the driver's move ends a rear view
                // left up from before: nothing else can.
                if self.rear_active && self.reverse_status(now) == ReverseStatus::Unknown {
                    self.end_rear();
                }
            }
            Input::Speed(kph) => self.speed_kph = kph,
            Input::CameraUp(c) => self.cameras_up |= c.bit(),
            Input::CameraDown(c) => self.cameras_up &= !c.bit(),
        }
        self.update_reverse(now);
        self.view = self.compute(now);
        self.view
    }

    /// When the view may change with no new input: the time to send the
    /// next [`Input::Tick`], always after the last input's. `None` when only
    /// an input can change it.
    pub fn deadline(&self) -> Option<Duration> {
        if !self.config.auto_reverse {
            return None;
        }
        let mut next: Option<Duration> = None;
        let after = self.now;
        let mut consider = |t: Duration| {
            if t > after {
                next = Some(next.map_or(t, |n| n.min(t)));
            }
        };
        if let Some((_, at)) = self.sample
            && !self.invalid
        {
            consider(at + self.config.rev_stale);
        }
        if let Some(since) = self.engaged_since
            && !self.rear_active
        {
            consider(since + self.config.rev_debounce);
        }
        if let Some(at) = self.cleared_at {
            consider(at + self.config.rev_hold);
        }
        next
    }

    fn reverse_status(&self, now: Duration) -> ReverseStatus {
        if !self.config.auto_reverse {
            return ReverseStatus::Off;
        }
        match self.sample {
            Some((engaged, at))
                if !self.invalid && now.saturating_sub(at) < self.config.rev_stale =>
            {
                if engaged {
                    ReverseStatus::Engaged
                } else {
                    ReverseStatus::NotEngaged
                }
            }
            _ => ReverseStatus::Unknown,
        }
    }

    fn end_rear(&mut self) {
        self.rear_active = false;
        self.cleared_at = None;
    }

    fn update_reverse(&mut self, now: Duration) {
        match self.reverse_status(now) {
            ReverseStatus::Off => {
                self.engaged_since = None;
                self.end_rear();
            }
            ReverseStatus::Engaged => {
                // Reverse again during the hold: keep the rear view.
                self.cleared_at = None;
                let since = *self
                    .engaged_since
                    .get_or_insert(self.sample.map_or(now, |(_, at)| at));
                if now.saturating_sub(since) >= self.config.rev_debounce {
                    self.rear_active = true;
                }
            }
            ReverseStatus::NotEngaged => {
                self.engaged_since = None;
                if self.rear_active {
                    let at = *self
                        .cleared_at
                        .get_or_insert(self.sample.map_or(now, |(_, at)| at));
                    if now.saturating_sub(at) >= self.config.rev_hold {
                        self.end_rear();
                    }
                }
            }
            ReverseStatus::Unknown => {
                self.engaged_since = None;
                // Known to have left reverse: the hold still runs out. Last
                // known in reverse: the rear view stays (see the module docs).
                if let Some(at) = self.cleared_at
                    && now.saturating_sub(at) >= self.config.rev_hold
                {
                    self.end_rear();
                }
            }
        }
    }

    fn manual_allowed(&self) -> bool {
        match self.config.manual_max_speed_kph {
            None => true,
            Some(max) => self.speed_kph.is_some_and(|v| v <= max),
        }
    }

    fn compute(&self, now: Duration) -> View {
        let reverse = self.reverse_status(now);
        let (camera, why, blocked_by_speed) = if self.rear_active {
            (Some(Camera::Rear), Some(Why::Reverse), false)
        } else {
            match self.latched {
                Choice::Off => (None, None, false),
                Choice::Camera(c) if self.manual_allowed() => (Some(c), Some(Why::Switch), false),
                Choice::Camera(_) => (None, None, true),
            }
        };
        View {
            camera,
            why,
            camera_unavailable: camera.is_some_and(|c| self.cameras_up & c.bit() == 0),
            reverse,
            blocked_by_speed,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn ms(n: u64) -> Duration {
        Duration::from_millis(n)
    }

    fn auto() -> Policy {
        let mut p = Policy::new(Config {
            auto_reverse: true,
            ..Config::default()
        });
        for c in Camera::ALL {
            p.handle(Input::CameraUp(c), ms(0));
        }
        p
    }

    /// Report reverse every 32 ms (about the broadcast's rate) from `from`
    /// until `to`, inclusive of `from`.
    fn reverse(p: &mut Policy, engaged: bool, from: u64, to: u64) -> View {
        let mut t = from;
        let mut v = p.view();
        while t <= to {
            v = p.handle(Input::Reverse(engaged), ms(t));
            t += 32;
        }
        v
    }

    /// In reverse long enough for the rear view.
    fn reversing() -> Policy {
        let mut p = auto();
        let v = reverse(&mut p, true, 1000, 1200);
        assert_eq!(v.camera, Some(Camera::Rear));
        p
    }

    // --- defaults and start-up --------------------------------------------

    #[test]
    fn starts_with_no_camera_and_reverse_unknown() {
        let p = Policy::new(Config {
            auto_reverse: true,
            ..Config::default()
        });
        let v = p.view();
        assert_eq!(v.camera, None);
        assert_eq!(v.reverse, ReverseStatus::Unknown);
        assert!(!v.camera_unavailable);
        assert_eq!(p.deadline(), None);
    }

    #[test]
    fn auto_reverse_is_off_by_default_and_ignores_reverse() {
        let mut p = Policy::new(Config::default());
        let v = reverse(&mut p, true, 0, 3000);
        assert_eq!(v.camera, None);
        assert_eq!(v.reverse, ReverseStatus::Off);
        assert_eq!(p.deadline(), None);
        // Back is the way to see the rear camera.
        let v = p.handle(Input::Switch(Move::Back), ms(3100));
        assert_eq!(v.camera, Some(Camera::Rear));
        assert_eq!(v.why, Some(Why::Switch));
    }

    #[test]
    fn default_examples_are_as_documented() {
        let c = Config::default();
        assert!(!c.auto_reverse);
        assert_eq!(c.rev_debounce, ms(150));
        assert_eq!(c.rev_hold, ms(2000));
        assert_eq!(c.rev_stale, ms(500));
        assert_eq!(c.manual_max_speed_kph, None);
    }

    // --- reverse priority -------------------------------------------------

    #[test]
    fn reverse_shows_rear_after_the_debounce() {
        let mut p = auto();
        let v = p.handle(Input::Reverse(true), ms(1000));
        assert_eq!(v.camera, None);
        assert_eq!(v.reverse, ReverseStatus::Engaged);
        assert_eq!(p.deadline(), Some(ms(1150)));
        let v = p.handle(Input::Reverse(true), ms(1149));
        assert_eq!(v.camera, None);
        let v = p.handle(Input::Tick, ms(1150));
        assert_eq!(v.camera, Some(Camera::Rear));
        assert_eq!(v.why, Some(Why::Reverse));
    }

    #[test]
    fn a_reverse_blip_shorter_than_the_debounce_shows_nothing() {
        let mut p = auto();
        reverse(&mut p, true, 1000, 1100);
        let v = reverse(&mut p, false, 1132, 3000);
        assert_eq!(v.camera, None);
        assert_eq!(v.reverse, ReverseStatus::NotEngaged);
    }

    #[test]
    fn reverse_beats_the_latched_choice() {
        let mut p = auto();
        p.handle(Input::Switch(Move::Left), ms(500));
        assert_eq!(p.view().camera, Some(Camera::Left));
        let v = reverse(&mut p, true, 1000, 1200);
        assert_eq!(v.camera, Some(Camera::Rear));
        assert_eq!(v.why, Some(Why::Reverse));
    }

    #[test]
    fn rear_view_holds_after_reverse_then_returns_to_the_previous_screen() {
        let mut p = reversing();
        let v = p.handle(Input::Reverse(false), ms(2000));
        assert_eq!(v.camera, Some(Camera::Rear), "held");
        assert_eq!(p.deadline(), Some(ms(2500)), "staleness comes first");
        reverse(&mut p, false, 2032, 3990);
        assert_eq!(p.view().camera, Some(Camera::Rear), "still held");
        let v = p.handle(Input::Reverse(false), ms(4000));
        assert_eq!(v.camera, None, "the screen from before");
        assert_eq!(v.why, None);
    }

    #[test]
    fn reverse_again_during_the_hold_keeps_the_rear_view() {
        let mut p = reversing();
        reverse(&mut p, false, 2000, 3000);
        let v = p.handle(Input::Reverse(true), ms(3100));
        assert_eq!(v.camera, Some(Camera::Rear));
        // The old hold is gone: well past 2000 + 2000 still rear.
        let v = reverse(&mut p, true, 3132, 6000);
        assert_eq!(v.camera, Some(Camera::Rear));
    }

    #[test]
    fn moves_during_reverse_show_when_it_ends() {
        let mut p = reversing();
        let v = p.handle(Input::Switch(Move::Right), ms(1300));
        assert_eq!(v.camera, Some(Camera::Rear), "reverse still wins");
        reverse(&mut p, false, 1400, 3500);
        assert_eq!(p.view().camera, Some(Camera::Right));
        assert_eq!(p.view().why, Some(Why::Switch));
    }

    #[test]
    fn forward_during_reverse_returns_to_the_previous_screen_after_it() {
        let mut p = auto();
        p.handle(Input::Switch(Move::Left), ms(0));
        reverse(&mut p, true, 1000, 1200);
        p.handle(Input::Switch(Move::Forward), ms(1300));
        reverse(&mut p, false, 1400, 3500);
        assert_eq!(p.view().camera, None);
    }

    // --- stale and invalid reverse ----------------------------------------

    #[test]
    fn stale_reverse_is_unknown_not_disengaged() {
        let mut p = auto();
        reverse(&mut p, false, 0, 1000);
        assert_eq!(p.view().reverse, ReverseStatus::NotEngaged);
        assert_eq!(p.deadline(), Some(ms(992 + 500)));
        let v = p.handle(Input::Tick, ms(1491));
        assert_eq!(v.reverse, ReverseStatus::NotEngaged);
        let v = p.handle(Input::Tick, ms(1492));
        assert_eq!(v.reverse, ReverseStatus::Unknown);
        assert_eq!(p.deadline(), None, "nothing left to wait for");
    }

    #[test]
    fn invalid_reverse_is_unknown_at_once() {
        let mut p = auto();
        p.handle(Input::Reverse(true), ms(0));
        let v = p.handle(Input::ReverseInvalid, ms(10));
        assert_eq!(v.reverse, ReverseStatus::Unknown);
        // A stale "engaged" never starts the rear view.
        let v = p.handle(Input::Tick, ms(1000));
        assert_eq!(v.camera, None);
        // A fresh sample makes it known again.
        let v = p.handle(Input::Reverse(false), ms(1100));
        assert_eq!(v.reverse, ReverseStatus::NotEngaged);
    }

    #[test]
    fn engaged_samples_that_go_stale_before_the_debounce_show_nothing() {
        // One "engaged" sample, then silence, with a stale time shorter than
        // the debounce: the sample is stale before the debounce ends.
        let mut p = Policy::new(Config {
            auto_reverse: true,
            rev_stale: ms(100),
            ..Config::default()
        });
        p.handle(Input::Reverse(true), ms(0));
        let v = p.handle(Input::Tick, ms(150));
        assert_eq!(v.reverse, ReverseStatus::Unknown);
        assert_eq!(v.camera, None);
    }

    #[test]
    fn reverse_going_unknown_keeps_the_rear_view_with_a_warning() {
        let mut p = reversing();
        let v = p.handle(Input::Tick, ms(5000));
        assert_eq!(v.reverse, ReverseStatus::Unknown);
        assert_eq!(v.camera, Some(Camera::Rear));
        assert_eq!(v.why, Some(Why::Reverse));
        let v = p.handle(Input::ReverseInvalid, ms(9000));
        assert_eq!(v.camera, Some(Camera::Rear));
    }

    #[test]
    fn a_move_ends_a_rear_view_left_up_by_unknown_reverse() {
        let mut p = reversing();
        p.handle(Input::Tick, ms(5000));
        let v = p.handle(Input::Switch(Move::Press), ms(5100));
        assert_eq!(v.camera, None);
        assert_eq!(v.reverse, ReverseStatus::Unknown);
        // Or straight to another camera.
        let mut p = reversing();
        p.handle(Input::ReverseInvalid, ms(1300));
        let v = p.handle(Input::Switch(Move::Left), ms(1400));
        assert_eq!(v.camera, Some(Camera::Left));
    }

    #[test]
    fn signal_back_after_unknown_resumes_normally() {
        let mut p = reversing();
        p.handle(Input::Tick, ms(5000));
        // Back, not in reverse: the hold runs from this sample.
        let v = p.handle(Input::Reverse(false), ms(6000));
        assert_eq!(v.camera, Some(Camera::Rear));
        reverse(&mut p, false, 6032, 8100);
        assert_eq!(p.view().camera, None);
    }

    #[test]
    fn going_unknown_during_the_hold_still_ends_the_rear_view() {
        let mut p = reversing();
        p.handle(Input::Reverse(false), ms(1300));
        let v = p.handle(Input::ReverseInvalid, ms(1400));
        assert_eq!(v.camera, Some(Camera::Rear));
        assert_eq!(p.deadline(), Some(ms(3300)));
        let v = p.handle(Input::Tick, ms(3300));
        assert_eq!(v.camera, None);
        assert_eq!(v.reverse, ReverseStatus::Unknown);
    }

    // --- the latched choice -----------------------------------------------

    #[test]
    fn the_choice_is_latched_until_the_next_move() {
        let mut p = auto();
        let v = p.handle(Input::Switch(Move::Left), ms(0));
        assert_eq!(v.camera, Some(Camera::Left));
        assert_eq!(v.why, Some(Why::Switch));
        assert_eq!(
            p.handle(Input::Tick, ms(600_000)).camera,
            Some(Camera::Left)
        );
        assert_eq!(
            p.handle(Input::Switch(Move::Back), ms(600_100)).camera,
            Some(Camera::Rear)
        );
        assert_eq!(
            p.handle(Input::Switch(Move::Right), ms(600_200)).camera,
            Some(Camera::Right)
        );
    }

    #[test]
    fn forward_and_press_return_to_the_previous_screen() {
        for m in [Move::Forward, Move::Press] {
            let mut p = auto();
            p.handle(Input::Switch(Move::Right), ms(0));
            let v = p.handle(Input::Switch(m), ms(100));
            assert_eq!(v.camera, None, "{m:?}");
            assert_eq!(v.why, None);
        }
    }

    #[test]
    fn the_mapping_is_configuration() {
        let mut p = Policy::new(Config {
            forward: Choice::Camera(Camera::Rear),
            back: Choice::Off,
            ..Config::default()
        });
        assert_eq!(
            p.handle(Input::Switch(Move::Forward), ms(0)).camera,
            Some(Camera::Rear)
        );
        assert_eq!(p.handle(Input::Switch(Move::Back), ms(10)).camera, None);
    }

    #[test]
    fn manual_selection_works_at_any_speed_by_default() {
        let mut p = auto();
        p.handle(Input::Speed(Some(110.0)), ms(0));
        assert_eq!(
            p.handle(Input::Switch(Move::Left), ms(10)).camera,
            Some(Camera::Left)
        );
        assert_eq!(
            p.handle(Input::Speed(None), ms(20)).camera,
            Some(Camera::Left)
        );
    }

    #[test]
    fn the_optional_speed_limit_hides_manual_views() {
        let mut p = Policy::new(Config {
            manual_max_speed_kph: Some(15.0),
            ..Config::default()
        });
        p.handle(Input::CameraUp(Camera::Left), ms(0));
        p.handle(Input::Speed(Some(10.0)), ms(0));
        let v = p.handle(Input::Switch(Move::Left), ms(10));
        assert_eq!(v.camera, Some(Camera::Left));
        let v = p.handle(Input::Speed(Some(40.0)), ms(20));
        assert_eq!(v.camera, None);
        assert!(v.blocked_by_speed);
        // An unknown speed is not taken as slow.
        let v = p.handle(Input::Speed(None), ms(30));
        assert_eq!(v.camera, None);
        assert!(v.blocked_by_speed);
        let v = p.handle(Input::Speed(Some(15.0)), ms(40));
        assert_eq!(v.camera, Some(Camera::Left));
        assert!(!v.blocked_by_speed);
        // Off is never blocked.
        let v = p.handle(Input::Switch(Move::Press), ms(50));
        assert_eq!(v.camera, None);
        assert!(!v.blocked_by_speed);
    }

    #[test]
    fn the_speed_limit_never_hides_reverse() {
        let mut p = Policy::new(Config {
            auto_reverse: true,
            manual_max_speed_kph: Some(15.0),
            ..Config::default()
        });
        let v = reverse(&mut p, true, 0, 200);
        assert_eq!(v.camera, Some(Camera::Rear));
        assert!(!v.blocked_by_speed);
    }

    // --- missing sources --------------------------------------------------

    #[test]
    fn a_camera_with_no_frames_is_shown_as_unavailable() {
        let mut p = Policy::new(Config::default());
        let v = p.handle(Input::Switch(Move::Left), ms(0));
        assert_eq!(v.camera, Some(Camera::Left));
        assert!(v.camera_unavailable, "no pipeline has reported yet");
        assert!(
            !p.handle(Input::CameraUp(Camera::Left), ms(10))
                .camera_unavailable
        );
        let v = p.handle(Input::CameraDown(Camera::Left), ms(20));
        assert_eq!(v.camera, Some(Camera::Left), "the slot stays");
        assert!(v.camera_unavailable);
        // Another camera's state doesn't matter.
        p.handle(Input::CameraUp(Camera::Right), ms(30));
        assert!(p.view().camera_unavailable);
    }

    #[test]
    fn reverse_with_the_rear_camera_down_shows_unavailable() {
        let mut p = auto();
        p.handle(Input::CameraDown(Camera::Rear), ms(0));
        let v = reverse(&mut p, true, 1000, 1200);
        assert_eq!(v.camera, Some(Camera::Rear));
        assert!(v.camera_unavailable);
    }

    #[test]
    fn no_camera_is_never_unavailable() {
        let p = Policy::new(Config::default());
        assert!(!p.view().camera_unavailable);
    }
}
