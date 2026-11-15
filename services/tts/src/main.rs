//! `tts`: the spoken directions' voice (ADR-0048).
//!
//!   tts serve --prefix /opt/f250/piper --voice /opt/f250/piper/voices/en_US-ljspeech-medium.onnx \
//!             --listen /run/f250-tts/tts.sock
//!   tts say --socket /run/f250-tts/tts.sock --out /run/f250-audio/prompt-1.wav "Turn left."
//!
//! `serve` binds its socket only once the voice is loaded, so a socket that
//! exists answers at once; `speak-prompt` uses Flite while it doesn't.

use std::os::unix::net::UnixListener;
use std::path::PathBuf;
use std::process::ExitCode;

use clap::{Parser, Subcommand};
use tts::piper::{Paths, Piper};

#[derive(Debug, Parser)]
#[command(about = "The spoken directions' voice: Piper kept loaded, a WAV for each prompt")]
struct Args {
    #[command(subcommand)]
    cmd: Cmd,
}

#[derive(Debug, Subcommand)]
enum Cmd {
    /// Load the voice and answer prompts on a unix socket.
    Serve {
        /// libpiper's install prefix (lib/, share/espeak-ng-data).
        #[arg(long, default_value = "/opt/f250/piper")]
        prefix: PathBuf,
        /// The voice's .onnx (its .onnx.json beside it).
        #[arg(long)]
        voice: PathBuf,
        /// The socket to create (an old one there is replaced).
        #[arg(long, default_value = "/run/f250-tts/tts.sock")]
        listen: PathBuf,
    },
    /// Ask the service for a prompt and write it as a WAV.
    Say {
        #[arg(long, default_value = "/run/f250-tts/tts.sock")]
        socket: PathBuf,
        #[arg(long)]
        out: PathBuf,
        /// What to say.
        text: String,
    },
}

fn main() -> ExitCode {
    match Args::parse().cmd {
        Cmd::Say { socket, out, text } => match tts::server::say(&socket, &text, &out) {
            Ok(()) => ExitCode::SUCCESS,
            Err(e) => {
                eprintln!("tts say: {e}");
                ExitCode::FAILURE
            }
        },
        Cmd::Serve {
            prefix,
            voice,
            listen,
        } => {
            let t = std::time::Instant::now();
            let mut piper = match Piper::load(&Paths {
                prefix,
                voice: voice.clone(),
            }) {
                Ok(p) => p,
                Err(e) => {
                    eprintln!("tts: can't load Piper: {e}");
                    return ExitCode::FAILURE;
                }
            };
            let _ = std::fs::remove_file(&listen);
            let listener = match UnixListener::bind(&listen) {
                Ok(l) => l,
                Err(e) => {
                    eprintln!("tts: {}: {e}", listen.display());
                    return ExitCode::FAILURE;
                }
            };
            eprintln!(
                "tts: Piper {} with {} loaded in {} ms; listening on {}",
                piper.version,
                voice.display(),
                t.elapsed().as_millis(),
                listen.display()
            );
            let mut log = |line: &str| eprintln!("{line}");
            if let Err(e) = tts::server::serve(&listener, &mut piper, &mut log) {
                eprintln!("tts: {e}");
                return ExitCode::FAILURE;
            }
            ExitCode::SUCCESS
        }
    }
}
