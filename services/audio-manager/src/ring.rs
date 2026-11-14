//! The ring tone for a phone that doesn't send its own (ADR-0045 decision 7).
//!
//! A phone that rings in-band sends its ring tone over the call audio link;
//! PipeWire's gateway then reports its transport "active" while the call
//! rings (the owner's Z Fold8 does, bench-log 2026-11-14). For one that
//! doesn't, audio-manager rings through the speakers: a short two-tone
//! burst, repeated until the call is answered, declined, stops ringing, or
//! the phone's own ring tone starts.
//!
//! - [`CommandRinger`]: writes the tone as a WAV once ([`ring_wav`]) and has
//!   a program play it, one cycle per run (`afplay` on the Mac; on the Pi a
//!   player script, packaged with the rest of calls). Stopping the ring is
//!   dropping its future: the program is killed.
//! - [`SimRinger`]: nothing is heard; it counts cycles (simulation, tests).
//! - [`NoRinger`]: none configured; a phone without in-band ringing rings
//!   only on the phone, and the screen still shows the call.
//!
//! The tone's pitches, timing and level are examples (CLAUDE.md rule 10).

use std::path::PathBuf;
use std::process::Stdio;
use std::sync::atomic::{AtomicU64, Ordering};
use std::time::Duration;

use tokio::process::Command;

/// The ring tone (examples): two pitches together, in bursts, then a pause.
#[derive(Debug, Clone, PartialEq)]
pub struct Tone {
    pub sample_rate: u32,
    pub pitches_hz: [f32; 2],
    /// (on, off) pairs, played in order: one cycle.
    pub bursts: Vec<(Duration, Duration)>,
    /// The tone's peak, in dB below full scale.
    pub level_db: f32,
    /// Each burst fades in and out this long (no clicks).
    pub fade: Duration,
}

impl Default for Tone {
    fn default() -> Tone {
        Tone {
            sample_rate: 16_000,
            pitches_hz: [660.0, 880.0],
            bursts: vec![
                (Duration::from_millis(400), Duration::from_millis(200)),
                (Duration::from_millis(400), Duration::from_millis(2000)),
            ],
            level_db: -12.0,
            fade: Duration::from_millis(10),
        }
    }
}

impl Tone {
    pub fn cycle(&self) -> Duration {
        self.bursts.iter().map(|(on, off)| *on + *off).sum()
    }
}

fn samples(d: Duration, rate: u32) -> usize {
    usize::try_from(d.as_micros() * u128::from(rate) / 1_000_000).unwrap_or(0)
}

/// One cycle of `tone`, as a 16-bit mono PCM WAV file.
pub fn ring_wav(tone: &Tone) -> Vec<u8> {
    let rate = tone.sample_rate;
    let peak = 10f32.powf(tone.level_db / 20.0) * f32::from(i16::MAX);
    let fade = samples(tone.fade, rate).max(1);
    let mut pcm: Vec<i16> = Vec::new();
    for (on, off) in &tone.bursts {
        let n = samples(*on, rate);
        for i in 0..n {
            let t = i as f32 / rate as f32;
            let env = (i.min(n - 1 - i) as f32 / fade as f32).min(1.0);
            let v: f32 = tone
                .pitches_hz
                .iter()
                .map(|f| (2.0 * std::f32::consts::PI * f * t).sin())
                .sum::<f32>()
                / tone.pitches_hz.len() as f32;
            pcm.push((v * env * peak).round() as i16);
        }
        pcm.extend(std::iter::repeat_n(0, samples(*off, rate)));
    }
    let data_len = u32::try_from(pcm.len() * 2).unwrap_or(u32::MAX);
    let mut w = Vec::with_capacity(44 + pcm.len() * 2);
    w.extend_from_slice(b"RIFF");
    w.extend_from_slice(&(36 + data_len).to_le_bytes());
    w.extend_from_slice(b"WAVEfmt ");
    w.extend_from_slice(&16u32.to_le_bytes());
    w.extend_from_slice(&1u16.to_le_bytes()); // PCM
    w.extend_from_slice(&1u16.to_le_bytes()); // mono
    w.extend_from_slice(&rate.to_le_bytes());
    w.extend_from_slice(&(rate * 2).to_le_bytes());
    w.extend_from_slice(&2u16.to_le_bytes());
    w.extend_from_slice(&16u16.to_le_bytes());
    w.extend_from_slice(b"data");
    w.extend_from_slice(&data_len.to_le_bytes());
    for s in pcm {
        w.extend_from_slice(&s.to_le_bytes());
    }
    w
}

#[tonic::async_trait]
pub trait Ringer: Send + Sync {
    /// Ok when a ring can be heard (how); else why not.
    fn available(&self) -> Result<String, String>;
    /// Plays one cycle of the ring tone, returning when it is over.
    async fn ring_once(&self) -> Result<(), String>;
}

pub struct NoRinger(pub String);

#[tonic::async_trait]
impl Ringer for NoRinger {
    fn available(&self) -> Result<String, String> {
        Err(self.0.clone())
    }
    async fn ring_once(&self) -> Result<(), String> {
        Err(self.0.clone())
    }
}

/// Simulated: silent, a cycle takes `cycle`; counts the cycles started.
pub struct SimRinger {
    pub cycle: Duration,
    started: AtomicU64,
}

impl SimRinger {
    pub fn new(cycle: Duration) -> SimRinger {
        SimRinger {
            cycle,
            started: AtomicU64::new(0),
        }
    }

    /// Cycles started so far.
    pub fn rings(&self) -> u64 {
        self.started.load(Ordering::Relaxed)
    }
}

#[tonic::async_trait]
impl Ringer for SimRinger {
    fn available(&self) -> Result<String, String> {
        Ok("simulated: nothing is heard".into())
    }
    async fn ring_once(&self) -> Result<(), String> {
        self.started.fetch_add(1, Ordering::Relaxed);
        tokio::time::sleep(self.cycle).await;
        Ok(())
    }
}

/// A program that plays the WAV file named by its last argument and exits.
pub struct CommandRinger {
    pub program: PathBuf,
    /// Where the tone is written (the runtime directory).
    pub file: PathBuf,
    pub tone: Tone,
}

impl CommandRinger {
    /// Writes the tone if it isn't there yet (atomically: a player never
    /// reads half a file).
    fn ensure_file(&self) -> Result<(), String> {
        if self.file.exists() {
            return Ok(());
        }
        if let Some(dir) = self.file.parent() {
            std::fs::create_dir_all(dir).map_err(|e| format!("{}: {e}", dir.display()))?;
        }
        let tmp = self.file.with_extension("wav.new");
        std::fs::write(&tmp, ring_wav(&self.tone))
            .and_then(|()| std::fs::rename(&tmp, &self.file))
            .map_err(|e| format!("{}: {e}", self.file.display()))
    }
}

#[tonic::async_trait]
impl Ringer for CommandRinger {
    fn available(&self) -> Result<String, String> {
        Ok(format!("rung by {}", self.program.display()))
    }

    async fn ring_once(&self) -> Result<(), String> {
        self.ensure_file()?;
        let mut child = Command::new(&self.program)
            .arg(&self.file)
            .stdin(Stdio::null())
            .stdout(Stdio::null())
            .kill_on_drop(true)
            .spawn()
            .map_err(|e| format!("{} can't start: {e}", self.program.display()))?;
        // A player that hangs is cut off after a few cycles' time.
        let limit = self.tone.cycle() * 3 + Duration::from_secs(2);
        match tokio::time::timeout(limit, child.wait()).await {
            Ok(Ok(st)) if st.success() => Ok(()),
            Ok(Ok(st)) => Err(format!("{} failed ({st})", self.program.display())),
            Ok(Err(e)) => Err(format!("{}: {e}", self.program.display())),
            Err(_) => {
                let _ = child.kill().await;
                Err(format!("{} didn't finish", self.program.display()))
            }
        }
    }
}

#[cfg(test)]
#[allow(clippy::unwrap_used)]
mod tests {
    use super::*;

    fn u16_at(w: &[u8], i: usize) -> u16 {
        u16::from_le_bytes([w[i], w[i + 1]])
    }
    fn u32_at(w: &[u8], i: usize) -> u32 {
        u32::from_le_bytes([w[i], w[i + 1], w[i + 2], w[i + 3]])
    }

    #[test]
    fn the_tone_is_a_valid_wav_of_one_cycle() {
        let tone = Tone::default();
        assert_eq!(tone.cycle(), Duration::from_millis(3000));
        let w = ring_wav(&tone);
        assert_eq!(&w[0..4], b"RIFF");
        assert_eq!(&w[8..16], b"WAVEfmt ");
        assert_eq!(u16_at(&w, 20), 1, "PCM");
        assert_eq!(u16_at(&w, 22), 1, "mono");
        assert_eq!(u32_at(&w, 24), 16_000);
        assert_eq!(u16_at(&w, 34), 16);
        assert_eq!(&w[36..40], b"data");
        let n = u32_at(&w, 40) as usize;
        assert_eq!(n, 3 * 16_000 * 2, "3 s of samples");
        assert_eq!(w.len(), 44 + n);
        assert_eq!(u32_at(&w, 4) as usize, w.len() - 8);
        let pcm: Vec<i16> = w[44..]
            .chunks(2)
            .map(|c| i16::from_le_bytes([c[0], c[1]]))
            .collect();
        // Bursts at the level asked for, no louder; fades at the edges;
        // silence between and after.
        let limit = (10f32.powf(-12.0 / 20.0) * 32767.0).round() as i16;
        let peak = pcm.iter().map(|s| s.unsigned_abs()).max().unwrap();
        assert!(
            peak <= limit.unsigned_abs() && peak > limit.unsigned_abs() / 2,
            "{peak}"
        );
        assert_eq!(pcm[0], 0, "fades in");
        assert!(pcm[6400..9600].iter().all(|s| *s == 0), "the gap");
        assert!(pcm[9600..16000].iter().any(|s| *s != 0), "the second burst");
        assert!(pcm[16000..].iter().all(|s| *s == 0), "the pause");
    }

    #[tokio::test]
    async fn a_command_plays_the_file_and_can_be_cut_off() {
        let dir = std::env::temp_dir().join(format!("f250-audio-ring-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).unwrap();
        let log = dir.join("played");
        let player = dir.join("player");
        std::fs::write(
            &player,
            format!(
                "#!/bin/sh\necho \"$1\" >> {}\nhead -c 4 \"$1\" >> {}\n",
                log.display(),
                log.display()
            ),
        )
        .unwrap();
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            std::fs::set_permissions(&player, std::fs::Permissions::from_mode(0o755)).unwrap();
        }
        let file = dir.join("run").join("ring.wav");
        let r = CommandRinger {
            program: player.clone(),
            file: file.clone(),
            tone: Tone::default(),
        };
        r.ring_once().await.unwrap();
        assert_eq!(
            std::fs::read_to_string(&log).unwrap(),
            format!("{}\nRIFF", file.display())
        );
        assert_eq!(std::fs::read(&file).unwrap(), ring_wav(&Tone::default()));
        // A player that never ends is killed when the ring stops.
        std::fs::write(&player, "#!/bin/sh\nexec sleep 30\n").unwrap();
        let t = tokio::time::timeout(Duration::from_millis(300), r.ring_once()).await;
        assert!(t.is_err(), "dropped");
        let bad = CommandRinger {
            program: dir.join("missing"),
            file,
            tone: Tone::default(),
        };
        assert!(bad.ring_once().await.unwrap_err().contains("can't start"));
        let _ = std::fs::remove_dir_all(&dir);
    }
}
