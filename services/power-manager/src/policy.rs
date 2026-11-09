//! The power-key state machine (power-states.md, pulse-only).
//!
//! Pure logic: every input comes with the time since the kernel booted, so the
//! tests drive it without a clock.

use std::time::Duration;

/// Where the head unit is in its power cycle.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum State {
    /// Inside the boot window: the power key is ignored.
    Starting,
    /// The power key shuts down.
    Running,
    /// No power-key device can be read. The key still shuts down if one
    /// comes back; HARDOFF still cuts power either way.
    Fault,
    /// A press was accepted. Nothing changes it now.
    ShuttingDown,
}

/// What happened.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Input {
    /// Time passed.
    Tick,
    /// A power-key press: the PSW pulse, or someone pressed the button.
    Key,
    /// No power-key device is open any more.
    KeyDeviceLost,
    /// A power-key device is open again.
    KeyDeviceBack,
}

/// What the caller does about it.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Action {
    /// Nothing to do.
    None,
    /// The boot window ended.
    EnteredRunning,
    /// The boot window ended, or the last key device went away, with no key
    /// device open.
    EnteredFault,
    /// A key device came back.
    LeftFault,
    /// A press inside the boot window: the supply's ON pulse. Log it.
    IgnoredInBootWindow,
    /// A press while already shutting down.
    IgnoredWhileShuttingDown,
    /// Shut the Pi down.
    PowerOff,
}

/// The state machine.
#[derive(Debug, Clone)]
pub struct Policy {
    state: State,
    boot_window: Duration,
    key_device_open: bool,
}

impl Policy {
    /// `boot_window`: how long after the kernel started a press is ignored
    /// (`boot_key_ignore_s`). It must be shorter than the supply's OFFDELAY,
    /// or a quick key cycle's off-pulse would be ignored.
    pub fn new(boot_window: Duration) -> Self {
        Self {
            state: State::Starting,
            boot_window,
            key_device_open: true,
        }
    }

    pub fn state(&self) -> State {
        self.state
    }

    pub fn boot_window(&self) -> Duration {
        self.boot_window
    }

    /// Feed one input. `since_boot` is the time since the kernel started.
    pub fn handle(&mut self, input: Input, since_boot: Duration) -> Action {
        // Leaving the boot window depends only on time, and is checked first,
        // so a press that comes just after the window is not ignored because
        // no tick has run yet.
        let entered = self.leave_boot_window(since_boot);

        let action = match (self.state, input) {
            (State::Starting, Input::Key) => Action::IgnoredInBootWindow,
            (State::Running | State::Fault, Input::Key) => {
                self.state = State::ShuttingDown;
                Action::PowerOff
            }
            (State::ShuttingDown, Input::Key) => Action::IgnoredWhileShuttingDown,

            (_, Input::KeyDeviceLost) => {
                self.key_device_open = false;
                if self.state == State::Running {
                    self.state = State::Fault;
                    Action::EnteredFault
                } else {
                    Action::None
                }
            }
            (_, Input::KeyDeviceBack) => {
                self.key_device_open = true;
                if self.state == State::Fault {
                    self.state = State::Running;
                    Action::LeftFault
                } else {
                    Action::None
                }
            }
            (_, Input::Tick) => Action::None,
        };

        if !entered || action == Action::PowerOff {
            return action;
        }
        // The window ended under this input: report where the two together
        // left us.
        match self.state {
            State::Running => Action::EnteredRunning,
            State::Fault => Action::EnteredFault,
            State::Starting | State::ShuttingDown => action,
        }
    }

    /// Leave `Starting` once the window is over. True if it happened now.
    fn leave_boot_window(&mut self, since_boot: Duration) -> bool {
        if self.state != State::Starting || since_boot < self.boot_window {
            return false;
        }
        self.state = if self.key_device_open {
            State::Running
        } else {
            State::Fault
        };
        true
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const WINDOW: Duration = Duration::from_secs(30);
    fn s(secs: u64) -> Duration {
        Duration::from_secs(secs)
    }
    fn running() -> Policy {
        let mut p = Policy::new(WINDOW);
        assert_eq!(p.handle(Input::Tick, s(30)), Action::EnteredRunning);
        p
    }

    #[test]
    fn starts_in_the_boot_window() {
        assert_eq!(Policy::new(WINDOW).state(), State::Starting);
    }

    #[test]
    fn on_pulse_in_the_boot_window_is_ignored() {
        let mut p = Policy::new(WINDOW);
        assert_eq!(p.handle(Input::Key, s(4)), Action::IgnoredInBootWindow);
        assert_eq!(p.state(), State::Starting);
        // The last moment of the window still ignores.
        assert_eq!(
            p.handle(Input::Key, s(30) - Duration::from_millis(1)),
            Action::IgnoredInBootWindow
        );
        assert_eq!(p.state(), State::Starting);
    }

    #[test]
    fn window_ends_on_time_alone() {
        let mut p = Policy::new(WINDOW);
        assert_eq!(p.handle(Input::Tick, s(29)), Action::None);
        assert_eq!(p.state(), State::Starting);
        assert_eq!(p.handle(Input::Tick, s(30)), Action::EnteredRunning);
        assert_eq!(p.state(), State::Running);
        assert_eq!(p.handle(Input::Tick, s(31)), Action::None);
    }

    #[test]
    fn press_after_the_window_powers_off_even_before_a_tick() {
        let mut p = Policy::new(WINDOW);
        assert_eq!(p.handle(Input::Key, s(31)), Action::PowerOff);
        assert_eq!(p.state(), State::ShuttingDown);
    }

    #[test]
    fn press_while_running_powers_off() {
        let mut p = running();
        assert_eq!(p.handle(Input::Key, s(600)), Action::PowerOff);
        assert_eq!(p.state(), State::ShuttingDown);
    }

    #[test]
    fn shutting_down_ignores_everything() {
        let mut p = running();
        p.handle(Input::Key, s(600));
        assert_eq!(
            p.handle(Input::Key, s(601)),
            Action::IgnoredWhileShuttingDown
        );
        assert_eq!(p.handle(Input::KeyDeviceLost, s(602)), Action::None);
        assert_eq!(p.handle(Input::KeyDeviceBack, s(603)), Action::None);
        assert_eq!(p.handle(Input::Tick, s(604)), Action::None);
        assert_eq!(p.state(), State::ShuttingDown);
    }

    #[test]
    fn losing_the_key_device_while_running_is_a_fault() {
        let mut p = running();
        assert_eq!(p.handle(Input::KeyDeviceLost, s(100)), Action::EnteredFault);
        assert_eq!(p.state(), State::Fault);
        assert_eq!(p.handle(Input::KeyDeviceLost, s(101)), Action::None);
        assert_eq!(p.handle(Input::KeyDeviceBack, s(110)), Action::LeftFault);
        assert_eq!(p.state(), State::Running);
    }

    #[test]
    fn a_press_in_fault_still_powers_off() {
        let mut p = running();
        p.handle(Input::KeyDeviceLost, s(100));
        // A second device (a keyboard) can still deliver a press.
        assert_eq!(p.handle(Input::Key, s(120)), Action::PowerOff);
        assert_eq!(p.state(), State::ShuttingDown);
    }

    #[test]
    fn no_key_device_through_the_window_ends_in_fault() {
        let mut p = Policy::new(WINDOW);
        assert_eq!(p.handle(Input::KeyDeviceLost, s(2)), Action::None);
        assert_eq!(p.state(), State::Starting);
        assert_eq!(p.handle(Input::Tick, s(30)), Action::EnteredFault);
        assert_eq!(p.state(), State::Fault);
    }

    #[test]
    fn key_device_back_in_the_window_stays_starting() {
        let mut p = Policy::new(WINDOW);
        p.handle(Input::KeyDeviceLost, s(2));
        assert_eq!(p.handle(Input::KeyDeviceBack, s(5)), Action::None);
        assert_eq!(p.state(), State::Starting);
        assert_eq!(p.handle(Input::Tick, s(30)), Action::EnteredRunning);
    }

    #[test]
    fn window_ending_with_a_device_change_reports_the_resulting_state() {
        // Lost exactly as the window ends: Starting → Running → Fault.
        let mut p = Policy::new(WINDOW);
        assert_eq!(p.handle(Input::KeyDeviceLost, s(30)), Action::EnteredFault);
        assert_eq!(p.state(), State::Fault);
        // Back exactly as the window ends, after being lost in it.
        let mut p = Policy::new(WINDOW);
        p.handle(Input::KeyDeviceLost, s(2));
        assert_eq!(
            p.handle(Input::KeyDeviceBack, s(30)),
            Action::EnteredRunning
        );
        assert_eq!(p.state(), State::Running);
    }

    #[test]
    fn zero_window_accepts_the_first_press() {
        let mut p = Policy::new(Duration::ZERO);
        assert_eq!(p.handle(Input::Key, Duration::ZERO), Action::PowerOff);
    }

    #[test]
    fn a_service_restart_late_in_the_drive_does_not_reopen_the_window() {
        // A new Policy after a restart still measures from the kernel's boot.
        let mut p = Policy::new(WINDOW);
        assert_eq!(p.handle(Input::Key, s(3600)), Action::PowerOff);
    }
}
