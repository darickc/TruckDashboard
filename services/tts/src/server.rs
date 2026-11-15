//! The socket protocol: text in, a WAV out (see the crate's docs).
//!
//! One request at a time: the engine isn't shared, and a prompt takes well
//! under 2 s. A client that hangs up (audio-manager cut the prompt off) is
//! noticed between Piper's sentences, and the rest isn't synthesised.

use std::io::{self, Read, Write};
use std::os::unix::net::{UnixListener, UnixStream};
use std::path::Path;
use std::time::Duration;

use crate::wav;

/// The longest text accepted, in bytes. A spoken direction is a sentence or
/// two; this only bounds what a confused client can make the server do.
pub const MAX_TEXT: usize = 2000;

/// How long a client gets to send its text, and to take the answer.
pub const IO_TIMEOUT: Duration = Duration::from_secs(5);

/// Speech: mono float samples at a rate.
#[derive(Debug, Clone, PartialEq)]
pub struct Speech {
    pub sample_rate: u32,
    pub samples: Vec<f32>,
}

/// A synthesiser kept loaded between prompts.
pub trait Engine {
    /// Says `text`. `keep_going` is asked between chunks (Piper's sentences);
    /// when it says no, stop and return what there is.
    fn synthesize(
        &mut self,
        text: &str,
        keep_going: &mut dyn FnMut() -> bool,
    ) -> Result<Speech, String>;
}

/// Why a request got no WAV.
#[derive(Debug, PartialEq, Eq)]
pub enum Refused {
    Empty,
    TooLong,
    NotUtf8,
    HungUp,
    Engine(String),
}

impl std::fmt::Display for Refused {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Refused::Empty => write!(f, "no text"),
            Refused::TooLong => write!(f, "text longer than {MAX_TEXT} bytes"),
            Refused::NotUtf8 => write!(f, "text isn't UTF-8"),
            Refused::HungUp => write!(f, "the client hung up"),
            Refused::Engine(e) => write!(f, "{e}"),
        }
    }
}

/// The text a client sent, checked.
pub fn parse_text(bytes: &[u8]) -> Result<String, Refused> {
    if bytes.len() > MAX_TEXT {
        return Err(Refused::TooLong);
    }
    let s = std::str::from_utf8(bytes).map_err(|_| Refused::NotUtf8)?;
    // One line for Piper: newlines and other control characters become
    // spaces.
    let s: String = s
        .chars()
        .map(|c| if c.is_control() { ' ' } else { c })
        .collect();
    let s = s.split_whitespace().collect::<Vec<_>>().join(" ");
    if s.is_empty() {
        return Err(Refused::Empty);
    }
    Ok(s)
}

/// Answers one connection. Ok: the WAV went out.
pub fn handle(stream: &mut UnixStream, engine: &mut dyn Engine) -> Result<usize, Refused> {
    let _ = stream.set_read_timeout(Some(IO_TIMEOUT));
    let _ = stream.set_write_timeout(Some(IO_TIMEOUT));
    let mut buf = Vec::new();
    stream
        .take(MAX_TEXT as u64 + 1)
        .read_to_end(&mut buf)
        .map_err(|_| Refused::HungUp)?;
    let text = parse_text(&buf)?;
    let mut hung_up = false;
    let probe = stream.try_clone().ok();
    let speech = engine
        .synthesize(&text, &mut || {
            let gone = probe.as_ref().is_some_and(peer_gone);
            hung_up |= gone;
            !gone
        })
        .map_err(Refused::Engine)?;
    if hung_up {
        return Err(Refused::HungUp);
    }
    let bytes = wav::mono_i16(speech.sample_rate, &speech.samples);
    stream.write_all(&bytes).map_err(|_| Refused::HungUp)?;
    Ok(bytes.len())
}

/// Whether the client has closed its end. It shut down its write side after
/// the text, so reading EOF can't tell; a socket whose peer has gone reports
/// POLLHUP, which a zero-timeout poll sees.
fn peer_gone(s: &UnixStream) -> bool {
    use std::os::fd::AsRawFd;
    let mut p = libc::pollfd {
        fd: s.as_raw_fd(),
        events: libc::POLLOUT,
        revents: 0,
    };
    poll_now(&mut p) && (p.revents & (libc::POLLHUP | libc::POLLERR)) != 0
}

/// poll(2) with no wait. std has no poll, hence this one unsafe call outside
/// src/piper.rs (ADR-0048).
#[allow(unsafe_code)]
fn poll_now(p: &mut libc::pollfd) -> bool {
    // SAFETY: one valid pollfd, owned by the caller for the call's duration;
    // timeout 0, so it never blocks.
    unsafe { libc::poll(p, 1, 0) >= 0 }
}

/// Serves until the listener fails. `log` gets one line a request.
pub fn serve(
    listener: &UnixListener,
    engine: &mut dyn Engine,
    log: &mut dyn FnMut(&str),
) -> io::Result<()> {
    for conn in listener.incoming() {
        let mut stream = match conn {
            Ok(s) => s,
            Err(e) => {
                log(&format!("tts: accept: {e}"));
                continue;
            }
        };
        let t = std::time::Instant::now();
        match handle(&mut stream, engine) {
            Ok(n) => log(&format!(
                "tts: said a prompt ({n} bytes) in {} ms",
                t.elapsed().as_millis()
            )),
            Err(Refused::HungUp) => log("tts: the prompt was cut off"),
            Err(e) => log(&format!("tts: no prompt: {e}")),
        }
    }
    Ok(())
}

/// The client: asks `socket` to say `text`, and writes the WAV to `out`
/// (through a temporary file beside it, so a half-written file is never
/// played).
pub fn say(socket: &Path, text: &str, out: &Path) -> Result<(), String> {
    let mut s = UnixStream::connect(socket).map_err(|e| format!("{}: {e}", socket.display()))?;
    let _ = s.set_write_timeout(Some(IO_TIMEOUT));
    // Synthesis is the slow part: up to about a second a sentence on the Pi.
    let _ = s.set_read_timeout(Some(IO_TIMEOUT * 4));
    s.write_all(text.as_bytes())
        .and_then(|()| s.shutdown(std::net::Shutdown::Write))
        .map_err(|e| format!("sending the text: {e}"))?;
    let mut bytes = Vec::new();
    s.read_to_end(&mut bytes)
        .map_err(|e| format!("reading the answer: {e}"))?;
    if !wav::looks_valid(&bytes) {
        return Err("no speech came back (see the f250-tts log)".into());
    }
    let mut tmp = out.as_os_str().to_owned();
    tmp.push(".part");
    let tmp = std::path::PathBuf::from(tmp);
    std::fs::write(&tmp, &bytes)
        .and_then(|()| std::fs::rename(&tmp, out))
        .map_err(|e| {
            let _ = std::fs::remove_file(&tmp);
            format!("{}: {e}", out.display())
        })
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::{Arc, Mutex};

    /// One sample a character, per "sentence" (split at '.'), asking
    /// `keep_going` between sentences like Piper's chunks.
    struct Fake {
        seen: Arc<Mutex<Vec<String>>>,
        fail: bool,
        sentences_said: Arc<Mutex<usize>>,
        delay: Duration,
    }

    impl Fake {
        fn new() -> Fake {
            Fake {
                seen: Arc::default(),
                fail: false,
                sentences_said: Arc::default(),
                delay: Duration::ZERO,
            }
        }
    }

    impl Engine for Fake {
        fn synthesize(
            &mut self,
            text: &str,
            keep_going: &mut dyn FnMut() -> bool,
        ) -> Result<Speech, String> {
            self.seen
                .lock()
                .map_err(|e| e.to_string())?
                .push(text.into());
            if self.fail {
                return Err("voice broken".into());
            }
            let mut samples = Vec::new();
            for (i, s) in text.split_inclusive('.').enumerate() {
                if i > 0 && !keep_going() {
                    break;
                }
                std::thread::sleep(self.delay);
                samples.extend(s.chars().map(|_| 0.25f32));
                *self.sentences_said.lock().map_err(|e| e.to_string())? += 1;
            }
            Ok(Speech {
                sample_rate: 22050,
                samples,
            })
        }
    }

    fn pair() -> (UnixStream, UnixStream) {
        UnixStream::pair().expect("socketpair")
    }

    #[test]
    fn text_is_one_trimmed_line() {
        assert_eq!(
            parse_text(b"  Turn left.\nThen\tright. ").as_deref(),
            Ok("Turn left. Then right.")
        );
        assert_eq!(parse_text(b" \n "), Err(Refused::Empty));
        assert_eq!(parse_text(b""), Err(Refused::Empty));
        assert_eq!(parse_text(&[0xff, 0xfe]), Err(Refused::NotUtf8));
        assert_eq!(parse_text(&[b'a'; MAX_TEXT + 1]), Err(Refused::TooLong));
        assert!(parse_text(&[b'a'; MAX_TEXT]).is_ok());
    }

    #[test]
    fn a_request_gets_a_wav_of_the_speech() {
        let (mut client, mut server) = pair();
        client.write_all(b"Turn left.").expect("write");
        client
            .shutdown(std::net::Shutdown::Write)
            .expect("shutdown");
        let mut fake = Fake::new();
        let n = handle(&mut server, &mut fake).expect("handled");
        drop(server);
        let mut got = Vec::new();
        client.read_to_end(&mut got).expect("read");
        assert_eq!(n, got.len());
        assert!(wav::looks_valid(&got));
        assert_eq!(got.len(), 44 + 2 * "Turn left.".len());
        assert_eq!(*fake.seen.lock().expect("lock"), vec!["Turn left."]);
    }

    #[test]
    fn empty_too_long_and_engine_errors_send_nothing() {
        for (input, fail, want) in [
            (b"   ".to_vec(), false, Refused::Empty),
            (vec![b'x'; MAX_TEXT + 10], false, Refused::TooLong),
            (
                b"Turn left.".to_vec(),
                true,
                Refused::Engine("voice broken".into()),
            ),
        ] {
            let (mut client, mut server) = pair();
            client.write_all(&input).expect("write");
            client
                .shutdown(std::net::Shutdown::Write)
                .expect("shutdown");
            let mut fake = Fake::new();
            fake.fail = fail;
            assert_eq!(handle(&mut server, &mut fake), Err(want));
            drop(server);
            let mut got = Vec::new();
            client.read_to_end(&mut got).expect("read");
            assert!(got.is_empty());
        }
    }

    #[test]
    fn a_client_that_hangs_up_stops_the_synthesis_between_sentences() {
        let (mut client, mut server) = pair();
        client.write_all(b"One. Two. Three. Four.").expect("write");
        client
            .shutdown(std::net::Shutdown::Write)
            .expect("shutdown");
        drop(client);
        let mut fake = Fake::new();
        let said = fake.sentences_said.clone();
        assert_eq!(handle(&mut server, &mut fake), Err(Refused::HungUp));
        assert_eq!(*said.lock().expect("lock"), 1, "only the first sentence");
    }

    #[test]
    fn the_client_writes_the_wav_and_the_server_keeps_serving() {
        let dir = std::env::temp_dir().join(format!("f250-tts-test-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).expect("dir");
        let sock = dir.join("tts.sock");
        let listener = UnixListener::bind(&sock).expect("bind");
        let mut fake = Fake::new();
        fake.delay = Duration::from_millis(5);
        let seen = fake.seen.clone();
        let server = std::thread::spawn(move || {
            for _ in 0..3 {
                let (mut s, _) = listener.accept().expect("accept");
                let _ = handle(&mut s, &mut fake);
            }
        });
        let out = dir.join("prompt.wav");
        say(&sock, "Turn left.", &out).expect("first");
        assert!(wav::looks_valid(&std::fs::read(&out).expect("read")));
        let err = say(&sock, "  ", &dir.join("none.wav")).expect_err("empty");
        assert!(err.contains("no speech"), "{err}");
        assert!(!dir.join("none.wav").exists());
        assert!(!dir.join("none.wav.part").exists());
        say(&sock, "In half a mile, turn right.", &out).expect("third");
        server.join().expect("server");
        assert_eq!(
            *seen.lock().expect("lock"),
            vec!["Turn left.", "In half a mile, turn right."]
        );
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn no_server_is_an_error_naming_the_socket() {
        let err = say(
            Path::new("/nonexistent/f250-tts.sock"),
            "Hi.",
            Path::new("/nonexistent/out.wav"),
        )
        .expect_err("no server");
        assert!(err.contains("/nonexistent/f250-tts.sock"), "{err}");
    }
}
