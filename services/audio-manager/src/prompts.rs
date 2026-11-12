//! Pausing the music for spoken prompts (ADR-0039 decision 9, owner
//! 2026-11-12: "paused while directions are spoken, not ducked").
//!
//! The prompt itself silences the music at once: it plays with
//! `media.role = "Speech-High"`, which AGL's role policy gives "cork" over
//! Multimedia. So that none of the song is missed, the phone is also paused
//! (AVRCP), and played again `hold` after the last prompt, so prompts close
//! together don't let the music back in between. It is played again only if
//! audio-manager paused it and it is still paused: the driver's own pause,
//! or play, wins.
//!
//! Pure and time-injected; the manager carries out the [`Act`]s.

use std::time::Duration;

use tokio::time::Instant;

/// What to send the phone's player.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Act {
    Pause,
    Play,
}

#[derive(Debug)]
pub struct PromptPause {
    hold: Duration,
    speaking: bool,
    /// audio-manager paused the phone and hasn't resumed it.
    paused_by_us: bool,
    /// When to resume, once nothing is being said.
    resume_at: Option<Instant>,
}

impl PromptPause {
    /// `hold`: how long after the last prompt the music resumes (an example,
    /// 1 s, the owner's choice).
    pub fn new(hold: Duration) -> PromptPause {
        PromptPause {
            hold,
            speaking: false,
            paused_by_us: false,
            resume_at: None,
        }
    }

    pub fn speaking(&self) -> bool {
        self.speaking
    }

    /// audio-manager has paused the music for prompts.
    pub fn music_paused(&self) -> bool {
        self.paused_by_us
    }

    /// A prompt starts (also one cutting off another). `playing`: the
    /// phone's player is playing now.
    pub fn start(&mut self, playing: bool) -> Option<Act> {
        self.speaking = true;
        self.resume_at = None;
        if !self.paused_by_us && playing {
            self.paused_by_us = true;
            return Some(Act::Pause);
        }
        None
    }

    /// The prompt ended (said, failed, or stopped).
    pub fn finished(&mut self, now: Instant) {
        self.speaking = false;
        if self.paused_by_us {
            self.resume_at = Some(now + self.hold);
        }
    }

    /// Time passes. `still_paused`: the player is paused now.
    pub fn tick(&mut self, now: Instant, still_paused: bool) -> Option<Act> {
        if self.speaking || !self.paused_by_us || self.resume_at.is_none_or(|t| now < t) {
            return None;
        }
        self.paused_by_us = false;
        self.resume_at = None;
        still_paused.then_some(Act::Play)
    }

    /// The driver pressed Play or Pause, or the phone went away: audio-manager
    /// won't resume it.
    pub fn forget(&mut self) {
        self.paused_by_us = false;
        self.resume_at = None;
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// The default (owner, 2026-11-12).
    const HOLD: Duration = Duration::from_secs(1);

    fn ms(n: u64) -> Duration {
        Duration::from_millis(n)
    }

    #[test]
    fn pauses_playing_music_and_resumes_after_the_hold() {
        let mut p = PromptPause::new(HOLD);
        let t = Instant::now();
        assert_eq!(p.start(true), Some(Act::Pause));
        assert!(p.speaking() && p.music_paused());
        assert_eq!(p.tick(t + ms(10_000), true), None, "not while speaking");
        p.finished(t + ms(2000));
        assert!(!p.speaking());
        assert_eq!(p.tick(t + ms(2500), true), None, "held");
        assert_eq!(p.tick(t + ms(3000), true), Some(Act::Play));
        assert!(!p.music_paused());
        assert_eq!(p.tick(t + ms(4000), true), None, "once");
    }

    #[test]
    fn music_that_wasnt_playing_is_left_alone() {
        let mut p = PromptPause::new(HOLD);
        let t = Instant::now();
        assert_eq!(p.start(false), None);
        p.finished(t);
        assert_eq!(p.tick(t + ms(10_000), true), None);
        assert!(!p.music_paused());
    }

    #[test]
    fn close_prompts_keep_it_paused() {
        let mut p = PromptPause::new(HOLD);
        let t = Instant::now();
        assert_eq!(p.start(true), Some(Act::Pause));
        p.finished(t + ms(1000));
        assert_eq!(p.tick(t + ms(1500), true), None);
        // A second prompt inside the hold: no second Pause (the phone says
        // paused now), and the hold starts again after it.
        assert_eq!(p.start(false), None);
        assert_eq!(p.tick(t + ms(5000), true), None);
        p.finished(t + ms(6000));
        assert_eq!(p.tick(t + ms(6500), true), None);
        assert_eq!(p.tick(t + ms(7000), true), Some(Act::Play));
    }

    #[test]
    fn a_prompt_cutting_off_another_pauses_once() {
        let mut p = PromptPause::new(HOLD);
        assert_eq!(p.start(true), Some(Act::Pause));
        // The phone may still report playing a moment after the Pause.
        assert_eq!(p.start(true), None);
    }

    #[test]
    fn the_drivers_play_wins() {
        let mut p = PromptPause::new(HOLD);
        let t = Instant::now();
        p.start(true);
        p.finished(t);
        // Pressed Play (or the phone did): the player isn't paused.
        assert_eq!(p.tick(t + HOLD, false), None);
        assert!(!p.music_paused());
    }

    #[test]
    fn the_drivers_pause_wins() {
        let mut p = PromptPause::new(HOLD);
        let t = Instant::now();
        p.start(true);
        p.forget(); // Pause pressed on the screen during the prompt.
        p.finished(t);
        assert_eq!(p.tick(t + HOLD, true), None, "stays paused");
    }

    #[test]
    fn a_stopped_prompt_resumes_too() {
        let mut p = PromptPause::new(HOLD);
        let t = Instant::now();
        p.start(true);
        p.finished(t); // StopSpeaking
        assert_eq!(p.tick(t + HOLD, true), Some(Act::Play));
    }
}
