//! What audio-manager knows about Bluetooth, independent of how it learnt
//! it: BlueZ over D-Bus on the Pi (`bluez.rs`) or the simulated phone
//! (`sim.rs`).

use tokio::time::Instant;

/// The phone's player state (BlueZ `MediaPlayer1.Status`).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum PlayState {
    Stopped,
    Playing,
    Paused,
    ForwardSeek,
    ReverseSeek,
    Error,
    /// A value BlueZ's documentation doesn't list, or none.
    Unknown,
}

impl PlayState {
    /// The position moves on by itself in this state.
    pub fn advancing(self) -> bool {
        self == PlayState::Playing
    }
}

/// Track metadata (BlueZ `MediaPlayer1.Track`). Empty strings: the phone
/// didn't say.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct Track {
    pub title: String,
    pub artist: String,
    pub album: String,
    /// Milliseconds; None when the phone doesn't say (or says 0).
    pub duration_ms: Option<u32>,
}

/// The connected phone's player, as last reported.
#[derive(Debug, Clone, PartialEq)]
pub struct Player {
    /// BlueZ's object path (or the simulation's name for it).
    pub path: String,
    /// The device the player belongs to (its address).
    pub address: String,
    /// The app's name, when the phone gives one.
    pub name: String,
    pub state: PlayState,
    pub track: Track,
    /// Milliseconds into the track when it was read; None: unknown.
    pub position_ms: Option<u32>,
    /// When `position_ms` was read.
    pub read_at: Instant,
}

impl Player {
    /// The position now: counted on from the last report while playing,
    /// never past the track's end. BlueZ sends no periodic position
    /// updates (only on status changes), so this is how the screen moves.
    pub fn position_at(&self, now: Instant) -> Option<u32> {
        let p = self.position_ms?;
        let p = if self.state.advancing() {
            let gone = now.saturating_duration_since(self.read_at).as_millis();
            u32::try_from(u128::from(p) + gone).unwrap_or(u32::MAX)
        } else {
            p
        };
        Some(match self.track.duration_ms {
            Some(d) => p.min(d),
            None => p,
        })
    }
}

/// A phone: a paired or connected Bluetooth device that can send audio
/// (it lists the A2DP Source profile).
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Phone {
    pub address: String,
    pub name: String,
    pub connected: bool,
    pub paired: bool,
}

/// The adapter (BlueZ `Adapter1`).
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Adapter {
    /// Powered and answering.
    Ready { discoverable: bool, pairable: bool },
    /// No D-Bus, no BlueZ, no adapter, or not powered: why, for the screen.
    Unavailable(String),
}

/// Everything the backend knows, replaced as a whole on each change.
#[derive(Debug, Clone, PartialEq)]
pub struct Snapshot {
    pub adapter: Adapter,
    /// Paired or connected phones, connected first.
    pub phones: Vec<Phone>,
    /// The connected phone's player, if it has one. Never a player of a
    /// phone that isn't connected.
    pub player: Option<Player>,
    /// Audio is arriving from a phone (a `MediaTransport1` is active).
    pub streaming: bool,
}

impl Snapshot {
    pub fn unavailable(why: impl Into<String>) -> Snapshot {
        Snapshot {
            adapter: Adapter::Unavailable(why.into()),
            phones: Vec::new(),
            player: None,
            streaming: false,
        }
    }

    pub fn connected_phone(&self) -> Option<&Phone> {
        self.phones.iter().find(|p| p.connected)
    }
}

/// A transport command for the phone's player (AVRCP passthrough through
/// BlueZ `MediaPlayer1`).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Command {
    Play,
    Pause,
    Next,
    Previous,
}

impl Command {
    /// The `MediaPlayer1` method.
    pub fn method(self) -> &'static str {
        match self {
            Command::Play => "Play",
            Command::Pause => "Pause",
            Command::Next => "Next",
            Command::Previous => "Previous",
        }
    }
}

/// What a phone asks of the pairing agent (BlueZ `Agent1`).
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum AgentAsk {
    /// `RequestConfirmation`: the phone shows this six-digit code.
    Confirm { passkey: u32 },
    /// `RequestAuthorization`: an incoming pairing with no code.
    Authorize,
}

/// A request from a phone to pair, waiting for an answer. The backend
/// rejects it if `reply` is dropped.
#[derive(Debug)]
pub struct AgentRequest {
    pub address: String,
    pub name: String,
    pub ask: AgentAsk,
    pub reply: tokio::sync::oneshot::Sender<bool>,
}
