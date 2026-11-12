//! How a prompt is said (ADR-0039 decision 9).
//!
//! - [`CommandVoice`]: a program that says its last argument and exits. On
//!   the Pi, `/opt/f250/libexec/speak-prompt`: Flite+hts_engine 1.06 makes a
//!   WAV, `pw-play --media-role Speech-High` plays it (the role corks the
//!   music). On the Mac, `say` works for `make sim`.
//! - [`SimVoice`]: nothing is heard; it takes as long as the text would
//!   (simulation and tests).
//! - [`NoVoice`]: none configured; prompts are refused with the reason.
//!
//! Cutting a prompt off is dropping its future: the program is killed.

use std::path::PathBuf;
use std::process::Stdio;
use std::time::Duration;

use tokio::process::Command;

#[tonic::async_trait]
pub trait Voice: Send + Sync {
    /// Ok when prompts can be said; else why not.
    fn available(&self) -> Result<String, String>;
    /// Says `text`, returning when it has been said.
    async fn say(&self, text: &str) -> Result<(), String>;
}

pub struct NoVoice(pub String);

#[tonic::async_trait]
impl Voice for NoVoice {
    fn available(&self) -> Result<String, String> {
        Err(self.0.clone())
    }
    async fn say(&self, _: &str) -> Result<(), String> {
        Err(self.0.clone())
    }
}

/// Simulated: silent, `per_char` a character (at least `min`).
pub struct SimVoice {
    pub per_char: Duration,
    pub min: Duration,
}

impl Default for SimVoice {
    fn default() -> SimVoice {
        SimVoice {
            per_char: Duration::from_millis(60),
            min: Duration::from_secs(1),
        }
    }
}

#[tonic::async_trait]
impl Voice for SimVoice {
    fn available(&self) -> Result<String, String> {
        Ok("simulated: nothing is heard".into())
    }
    async fn say(&self, text: &str) -> Result<(), String> {
        let n = u32::try_from(text.chars().count()).unwrap_or(u32::MAX);
        tokio::time::sleep((self.per_char * n).max(self.min)).await;
        Ok(())
    }
}

pub struct CommandVoice {
    pub program: PathBuf,
    /// A prompt that takes longer is cut off.
    pub timeout: Duration,
}

#[tonic::async_trait]
impl Voice for CommandVoice {
    fn available(&self) -> Result<String, String> {
        Ok(format!("spoken by {}", self.program.display()))
    }

    async fn say(&self, text: &str) -> Result<(), String> {
        let mut child = Command::new(&self.program)
            .arg(text)
            .stdin(Stdio::null())
            .stdout(Stdio::null())
            .kill_on_drop(true)
            .spawn()
            .map_err(|e| format!("{} can't start: {e}", self.program.display()))?;
        match tokio::time::timeout(self.timeout, child.wait()).await {
            Ok(Ok(st)) if st.success() => Ok(()),
            Ok(Ok(st)) => Err(format!("{} failed ({st})", self.program.display())),
            Ok(Err(e)) => Err(format!("{}: {e}", self.program.display())),
            Err(_) => {
                let _ = child.kill().await;
                Err(format!(
                    "{} took over {} s",
                    self.program.display(),
                    self.timeout.as_secs()
                ))
            }
        }
    }
}

/// A prompt's text, for the voice: control characters dropped, whitespace
/// folded, at most 500 characters. Empty: nothing to say.
pub fn clean_prompt(text: &str) -> String {
    let no_controls: String = text
        .chars()
        .map(|c| if c.is_control() { ' ' } else { c })
        .collect();
    no_controls
        .split_whitespace()
        .collect::<Vec<_>>()
        .join(" ")
        .chars()
        .take(500)
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn prompts_are_cleaned() {
        assert_eq!(
            clean_prompt("  In half a mile,\n turn\tright. \u{7}"),
            "In half a mile, turn right."
        );
        assert_eq!(clean_prompt(" \n "), "");
        assert_eq!(clean_prompt(&"x".repeat(900)).len(), 500);
    }
}
