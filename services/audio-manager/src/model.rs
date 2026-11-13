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
    /// The track's picture on the phone (`ImgHandle`, AVRCP 1.6 cover art):
    /// valid only while audio-manager has a BIP session open to the phone.
    pub image_handle: Option<String>,
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
    /// The L2CAP PSM of the phone's cover art server (`ObexPort`, BlueZ
    /// experimental); None: the phone doesn't offer cover art, or bluetoothd
    /// runs without `--experimental`.
    pub obex_port: Option<u16>,
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

/// A picture of a track, fetched from the phone.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Picture {
    /// The phone and the track's image handle it was fetched for.
    pub address: String,
    pub handle: String,
    /// Different for every picture fetched, so the dashboard knows when to
    /// fetch again.
    pub id: u64,
    pub bytes: std::sync::Arc<Vec<u8>>,
    pub mime: &'static str,
}

/// The connected phone's cover art (ADR-0042): the picture fetched last, or
/// why there is none. Shown only for the track it was fetched for.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct CoverArt {
    pub picture: Option<Picture>,
    /// Why there is no picture (for the screen and the log); empty: nothing
    /// to say.
    pub detail: String,
}

impl CoverArt {
    pub fn none(detail: impl Into<String>) -> CoverArt {
        CoverArt {
            picture: None,
            detail: detail.into(),
        }
    }

    /// The picture, if it is the one for `player`'s current track.
    pub fn for_player(&self, player: &Player) -> Option<&Picture> {
        self.picture.as_ref().filter(|p| {
            p.address == player.address && player.track.image_handle.as_deref() == Some(&p.handle)
        })
    }
}

/// The type of a picture from its first bytes: JPEG, PNG or BMP; None for
/// anything else (refused).
pub fn image_mime(bytes: &[u8]) -> Option<&'static str> {
    if bytes.starts_with(&[0xFF, 0xD8, 0xFF]) {
        Some("image/jpeg")
    } else if bytes.starts_with(b"\x89PNG\r\n\x1a\n") {
        Some("image/png")
    } else if bytes.starts_with(b"BM") && bytes.len() > 54 {
        Some("image/bmp")
    } else {
        None
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
